#!/usr/bin/env bash
#
# run.sh - Dependency-free test runner for kubeshelf
#
# Usage: tests/run.sh [PATTERN]     (runs test_* functions whose name matches PATTERN)
#
# Every test runs in a fresh temporary directory with fake clusters:
# a fake kubectl (tests/fakebin) answers "get namespace(s)" from fixtures and delegates
# "config ..." to the real kubectl, which only touches local files.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TESTS="$ROOT/tests"
REAL_KUBECTL="$(command -v kubectl || true)"
if [ -z "$REAL_KUBECTL" ]; then
  echo "kubectl is required to run the tests (only 'kubectl config' is used, offline)" >&2
  exit 2
fi
export REAL_KUBECTL NO_COLOR=1

# --- helpers -------------------------------------------------------------------

# shellcheck source=fixtures.sh
. "$TESTS/fixtures.sh"

# run CMD... : sets $status, $out (stdout), $err (stderr)
run() {
  local o e
  o=$(mktemp) e=$(mktemp)
  "$@" >"$o" 2>"$e" </dev/null
  status=$?
  out=$(cat "$o") err=$(cat "$e")
  rm -f "$o" "$e"
}

fail() { echo "    $*"; FAILED=1; }
assert_status()    { [ "$status" -eq "$1" ] || fail "expected status $1, got $status (stderr: $err)"; }
assert_out_eq()    { [ "$out" = "$1" ] || fail "expected stdout [$1], got [$out]"; }
assert_out_has()   { grep -qF -- "$1" <<< "$out" || fail "stdout lacks [$1]: [$out]"; }
assert_out_lacks() { ! grep -qF -- "$1" <<< "$out" || fail "stdout should not contain [$1]: [$out]"; }
assert_err_has()   { grep -qF -- "$1" <<< "$err" || fail "stderr lacks [$1]: [$err]"; }
ctx_namespace()    { "$REAL_KUBECTL" --kubeconfig "$KUBESHELF_CONFIG_DIR/$1.config" config view --minify -o jsonpath='{.contexts[0].context.namespace}'; }
wait_for_file()    { local _; for _ in $(seq 1 50); do [ -s "$1" ] && return 0; sleep 0.1; done; return 1; }

# --- kwhere --------------------------------------------------------------------

test_kwhere_exact_match() {
  make_cluster prod ok default monitoring payments
  make_cluster staging ok default payments-staging
  run kwhere -q payments
  assert_status 0
  assert_out_eq "prod"
}

test_kwhere_partial_match_lists_namespaces() {
  make_cluster prod ok default payments
  make_cluster staging ok default payments-staging
  run kwhere -p payments
  assert_status 0
  assert_out_has "prod (https://prod.example.com:6443) [payments]"
  assert_out_has "staging (https://staging.example.com:6443) [payments-staging]"
}

test_kwhere_not_found_exits_1() {
  make_cluster prod ok default
  run kwhere nope
  assert_status 1
  assert_out_eq ""
  assert_err_has "namespace 'nope' not found"
}

test_kwhere_scoped_credentials_use_context_namespace() {
  make_cluster team forbidden --ctx-ns team-a
  make_cluster other forbidden --ctx-ns team-b
  run kwhere team-a
  assert_status 0
  assert_out_has "team (https://team.example.com:6443) (scoped credentials)"
  assert_out_lacks "other"
}

test_kwhere_reports_unreachable_on_stderr() {
  make_cluster prod ok monitoring
  make_cluster lab unreachable
  run kwhere monitoring
  assert_status 0
  assert_out_has "prod"
  assert_err_has "lab: unreachable - Unable to connect to the server"
  grep -q memcache <<< "$err" && fail "klog noise should be stripped: $err"
}

test_kwhere_quiet_hides_errors() {
  make_cluster lab unreachable
  run kwhere -q monitoring
  assert_status 1
  [ -z "$err" ] || fail "expected no stderr with -q, got [$err]"
}

test_kwhere_prints_fast_clusters_first() {
  make_cluster aaa-slow slow monitoring
  make_cluster zzz-fast ok monitoring
  run kwhere -q monitoring
  assert_status 0
  assert_out_eq $'zzz-fast\naaa-slow'
}

test_kwhere_fills_namespace_cache() {
  make_cluster prod ok default monitoring
  make_cluster team forbidden --ctx-ns team-a
  run kwhere monitoring
  [ "$(cat "$KUBESHELF_CACHE_DIR/namespaces/prod" 2>/dev/null)" = $'default\nmonitoring' ] || fail "bad prod cache"
  [ "$(cat "$KUBESHELF_CACHE_DIR/namespaces/team" 2>/dev/null)" = "team-a" ] || fail "bad team cache"
}

test_kwhere_runs_credential_plugins_without_terminal() {
  make_cluster eks ok --exec aws default payments
  run kwhere -q payments
  assert_status 0
  assert_out_eq "eks"
}

test_kwhere_credential_plugin_failure_is_explained() {
  make_cluster oidc unreachable --exec kubelogin
  run kwhere payments
  assert_status 1
  assert_err_has "oidc: unreachable"
  assert_err_has "credential plugin: kubelogin"
}

test_kwhere_timeout_is_reported() {
  make_cluster stuck hang default
  KUBESHELF_TIMEOUT=1 run kwhere default
  assert_status 1
  assert_err_has "stuck: unreachable - timed out after 1s"
}

test_kwhere_skip_exec_uses_cache() {
  make_cluster oidc never --exec kubelogin
  make_cluster gke never --exec gke-gcloud-auth-plugin
  make_cluster prod ok default payments
  mkdir -p "$KUBESHELF_CACHE_DIR/namespaces"
  printf 'default\npayments\n' > "$KUBESHELF_CACHE_DIR/namespaces/oidc"
  run kwhere --skip-exec payments
  assert_status 0
  assert_out_has "oidc (https://oidc.example.com:6443) (from cache)"
  assert_out_has "prod (https://prod.example.com:6443)"
  assert_out_lacks "gke"
  KUBESHELF_SKIP_EXEC=1 run kwhere -q payments
  [ "$(sort <<< "$out")" = $'oidc\nprod' ] || fail "KUBESHELF_SKIP_EXEC=1 not honored: [$out]"
  [ -e "$FAKE_CLUSTERS/.contacted" ] && fail "a credential-plugin cluster was contacted: $(cat "$FAKE_CLUSTERS/.contacted")"
}

test_background_refresh_skips_credential_plugins() {
  make_cluster oidc never --exec kubelogin
  run kswitch oidc
  assert_status 0
  sleep 1
  [ -e "$FAKE_CLUSTERS/.contacted" ] && fail "background refresh ran a credential plugin"
  [ -e "$KUBESHELF_CACHE_DIR/namespaces/oidc" ] && fail "cache should not be written"
}

test_kwhere_custom_suffix_and_dir() {
  mkdir -p "$TMP/other"
  KUBESHELF_CONFIG_DIR="$TMP/other" make_cluster prod ok monitoring
  mv "$TMP/other/prod.config" "$TMP/other/prod.yaml"
  KUBESHELF_CONFIG_DIR="$TMP/other" KUBESHELF_CONFIG_SUFFIX=.yaml run kwhere -q monitoring
  assert_status 0
  assert_out_eq "prod"
}

test_kwhere_usage_errors() {
  run kwhere
  assert_status 1
  assert_err_has "missing NAMESPACE"
  run kwhere --bogus x
  assert_status 1
  run kwhere -t abc x
  assert_status 1
}

# --- kswitch -------------------------------------------------------------------

test_kswitch_switches_symlink() {
  make_cluster prod ok default
  make_cluster staging ok default
  run kswitch staging
  assert_status 0
  [ "$(readlink "$KUBESHELF_CONFIG_DIR/config")" = "$KUBESHELF_CONFIG_DIR/staging.config" ] || fail "symlink not updated"
  run kswitch prod
  [ "$(readlink "$KUBESHELF_CONFIG_DIR/config")" = "$KUBESHELF_CONFIG_DIR/prod.config" ] || fail "symlink not switched"
}

test_kswitch_unknown_config() {
  make_cluster prod ok default
  run kswitch nope
  assert_status 1
  assert_err_has "not found"
  [ -e "$KUBESHELF_CONFIG_DIR/config" ] && fail "no symlink should be created"
}

test_kswitch_refuses_to_replace_regular_file() {
  make_cluster prod ok default
  echo "hand-made" > "$KUBESHELF_CONFIG_DIR/config"
  run kswitch prod
  assert_status 1
  [ "$(cat "$KUBESHELF_CONFIG_DIR/config")" = "hand-made" ] || fail "regular file was modified"
}

test_kswitch_with_namespace() {
  make_cluster prod ok default monitoring
  run kswitch prod -n monitoring
  assert_status 0
  assert_out_has "Default namespace of prod set to: monitoring"
  [ "$(ctx_namespace prod)" = "monitoring" ] || fail "namespace not saved in prod.config"
}

test_kswitch_namespace_alone_changes_current() {
  make_cluster prod ok default monitoring
  run kswitch prod
  run kswitch -n monitoring
  assert_status 0
  [ "$(ctx_namespace prod)" = "monitoring" ] || fail "namespace not saved"
}

test_kswitch_rejects_missing_namespace() {
  make_cluster prod ok default
  run kswitch prod -n nope
  assert_status 1
  assert_err_has "namespace 'nope' does not exist in prod"
  [ -z "$(ctx_namespace prod)" ] || fail "namespace should not be saved"
}

test_kswitch_scoped_credentials_refuse_other_namespace() {
  make_cluster team forbidden --ctx-ns team-a
  run kswitch team -n team-b
  assert_status 1
  assert_err_has "limited to namespace 'team-a'"
  run kswitch -n team-a
  assert_status 0
}

test_kswitch_unreachable_saves_with_warning() {
  make_cluster lab unreachable
  run kswitch lab -n monitoring
  assert_status 0
  assert_err_has "cannot verify namespace"
  [ "$(ctx_namespace lab)" = "monitoring" ] || fail "namespace not saved"
}

test_kswitch_namespace_without_current() {
  make_cluster prod ok default
  run kswitch -n default
  assert_status 1
  assert_err_has "no current config"
}

test_kswitch_list_current_remove() {
  make_cluster prod ok default monitoring
  make_cluster staging ok default
  run kswitch prod -n monitoring
  run kswitch --list
  assert_status 0
  assert_out_has "prod (current default)"
  assert_out_has "staging"
  run kswitch --current
  assert_out_has "Current default config: prod"
  assert_out_has "Namespace: monitoring"
  run kswitch --remove
  assert_status 0
  [ -e "$KUBESHELF_CONFIG_DIR/config" ] && fail "symlink not removed"
  run kswitch
  assert_status 1
  assert_out_has "Available kubeconfig files"
}

test_kswitch_refreshes_cache_in_background() {
  make_cluster prod ok default monitoring
  run kswitch prod
  wait_for_file "$KUBESHELF_CACHE_DIR/namespaces/prod" || fail "cache not written"
}

test_kswitch_warns_when_kubeconfig_is_set() {
  make_cluster prod ok default monitoring
  KUBECONFIG=/somewhere/else run kswitch prod
  assert_status 0
  assert_err_has "KUBECONFIG is set (/somewhere/else)"
  KUBECONFIG=/somewhere/else run kswitch -c
  assert_err_has "KUBECONFIG is set"
  KUBECONFIG="$KUBESHELF_CONFIG_DIR/config" run kswitch prod -n monitoring
  [ -z "$err" ] || fail "no warning expected when KUBECONFIG is the symlink itself: [$err]"
  run kswitch prod
  [ -z "$err" ] || fail "no warning expected without KUBECONFIG: [$err]"
}

test_version_flags() {
  local cmd
  for cmd in kswitch kwhere kopen; do
    run "$cmd" --version
    assert_status 0
    [[ "$out" =~ ^$cmd\ \(kubeshelf\)\ [0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "bad $cmd --version: [$out]"
    run "$cmd" -V
    assert_status 0
  done
}

test_version_matches_changelog() {
  local v
  v=$(sed -n 's/^KT_VERSION="\(.*\)"/\1/p' "$ROOT/lib/common.sh")
  grep -q "^## \[$v\]" "$ROOT/CHANGELOG.md" || fail "CHANGELOG.md has no section for version $v"
}

# --- kopen ---------------------------------------------------------------------

test_kopen_config_and_namespace() {
  make_cluster prod ok monitoring
  run kopen prod -n monitoring
  assert_status 0
  assert_out_eq "k9s args=[-n monitoring] KUBECONFIG=$KUBESHELF_CONFIG_DIR/prod.config"
}

test_kopen_passes_k9s_options() {
  make_cluster prod ok argocd
  run kopen prod -n argocd -c deploy --readonly
  assert_out_eq "k9s args=[-n argocd -c deploy --readonly] KUBECONFIG=$KUBESHELF_CONFIG_DIR/prod.config"
}

test_kopen_without_args_uses_default() {
  run kopen
  assert_status 0
  assert_out_eq "k9s args=[] KUBECONFIG="
}

test_kopen_subcommands_pass_through() {
  make_cluster version ok default   # a config named like a subcommand must not shadow it
  run kopen version
  assert_out_eq "k9s args=[version] KUBECONFIG="
}

test_kopen_unknown_config() {
  run kopen nope
  assert_status 1
  assert_err_has "config file $KUBESHELF_CONFIG_DIR/nope.config not found"
}

test_kopen_finds_single_cluster() {
  make_cluster prod ok payments
  make_cluster staging ok default
  run kopen -n payments
  assert_status 0
  assert_out_eq "k9s args=[-n payments] KUBECONFIG=$KUBESHELF_CONFIG_DIR/prod.config"
  assert_err_has "Found in prod"
}

test_kopen_namespace_not_found() {
  make_cluster prod ok default
  run kopen -n nope
  assert_status 1
  assert_err_has "namespace 'nope' not found"
}

test_kopen_picker_for_several_clusters() {
  make_cluster prod ok monitoring
  make_cluster staging ok monitoring
  local o e
  o=$(mktemp) e=$(mktemp)
  printf '9\n2\n' | kopen -n monitoring >"$o" 2>"$e"
  status=$? out=$(cat "$o") err=$(cat "$e")
  assert_status 0
  assert_err_has "Invalid choice"
  assert_out_eq "k9s args=[-n monitoring] KUBECONFIG=$KUBESHELF_CONFIG_DIR/staging.config"
}

test_kopen_without_k9s() {
  KUBESHELF_K9S_BIN=/nonexistent/k9s run kopen
  # an explicit but missing binary fails at exec
  [ "$status" -ne 0 ] || fail "expected failure"
}

# --- zsh plugin & completions --------------------------------------------------

zsh_run() {
  local script="$1"
  ZDOTDIR="$TMP" zsh -f -c "
    fpath=($ROOT/completions \$fpath)
    autoload -Uz compinit && compinit -u -d $TMP/.zcompdump
    source $ROOT/kubeshelf.plugin.zsh
    # stub with the real calling convention: _describe [-t tag] descr array [compadd options...]
    _describe() { [[ \$1 == -t ]] && shift 2; shift; local -a arr; arr=(\"\${(@P)1}\"); print -l -- \${arr%%:*}; }
    _message() { print -r -- \"MSG: \$*\"; }
    $script"
}

test_zsh_syntax() {
  local f
  for f in "$ROOT"/kubeshelf.plugin.zsh "$ROOT"/completions/*; do
    zsh -n "$f" || fail "zsh syntax error in $f"
  done
}

test_plugin_registers_commands_and_completions() {
  # shellcheck disable=SC2016  # zsh code, expanded by zsh
  run zsh_run 'whence -p kswitch kwhere kopen; print ${_comps[kswitch]} ${_comps[kwhere]} ${_comps[kopen]} ${_comps[k9s]:-none}; whence -w k9s'
  assert_out_has "$ROOT/bin/kswitch"
  assert_out_has "_kswitch _kwhere _kopen none"
  assert_out_lacks "k9s: function"
}

test_plugin_optional_k9s_wrapper() {
  # shellcheck disable=SC2016  # zsh code, expanded by zsh
  KUBESHELF_WRAP_K9S=1 run zsh_run 'whence -w k9s; print ${_comps[k9s]}'
  assert_out_has "k9s: function"
  assert_out_has "_kopen"
}

test_completion_configs() {
  make_cluster prod ok default
  make_cluster staging ok default
  run kswitch prod
  run zsh_run '_kubeshelf_configs'
  assert_out_eq $'prod\nstaging'
}

test_completion_namespaces_per_config() {
  mkdir -p "$KUBESHELF_CACHE_DIR/namespaces"
  printf 'default\nmonitoring\n' > "$KUBESHELF_CACHE_DIR/namespaces/prod"
  printf 'default\npayments\n' > "$KUBESHELF_CACHE_DIR/namespaces/staging"
  run zsh_run '_kt_config=prod _kubeshelf_ns'
  assert_out_eq $'default\nmonitoring'
  run zsh_run '_kubeshelf_ns | sort'
  assert_out_eq $'default\nmonitoring\npayments'
  run zsh_run '_kt_config=unknown _kubeshelf_ns'
  assert_out_has "MSG: no cached namespaces for unknown"
}

test_completion_helpers_accept_compadd_options() {
  # _arguments calls actions with compadd options (-J, -M...): they must not be taken as a config
  make_cluster prod ok default
  mkdir -p "$KUBESHELF_CACHE_DIR/namespaces"
  printf 'default\nmonitoring\n' > "$KUBESHELF_CACHE_DIR/namespaces/prod"
  run zsh_run "_kt_config=prod _kubeshelf_ns -J namespaces -M 'r:|.=* r:|=*'"
  assert_out_eq $'default\nmonitoring'
  run zsh_run "_kubeshelf_configs -J configs -M 'r:|.=* r:|=*'"
  assert_out_eq "prod"
}

test_completion_through_arguments() {
  # Real compsys run of the completion functions, capturing what reaches compadd
  make_cluster prod ok default
  make_cluster staging ok default
  mkdir -p "$KUBESHELF_CACHE_DIR/namespaces"
  printf 'default\nmonitoring\n' > "$KUBESHELF_CACHE_DIR/namespaces/prod"
  printf 'default\npayments\n' > "$KUBESHELF_CACHE_DIR/namespaces/staging"
  local script
  script=$(cat <<'EOF'
zmodload zsh/zpty
zpty -b z "zsh -f"
zpty -w z "PS1='> '; fpath=($ROOT/completions \$fpath); autoload -Uz compinit; compinit -u -d $TMP/.zcd; source $ROOT/kubeshelf.plugin.zsh; zstyle ':completion:*' list-max 0; LISTMAX=1000"
sleep 1; while zpty -r -t z o 2>/dev/null; do :; done
for line in "kopen staging -n " "kwhere mon"; do
  zpty -w -n z "$line"$'\t'; sleep 1
  out=""; while zpty -r -t z o 2>/dev/null; do out+=$o; done
  print -r -- "[$line] ${${out//$'\e'\[[0-9;?]#[a-zA-Z]/}//$'\r'/}"
  zpty -w -n z $'\C-u'; sleep 0.3; while zpty -r -t z o 2>/dev/null; do :; done
done
zpty -d z
EOF
)
  script=${script//\$ROOT/$ROOT}; script=${script//\$TMP/$TMP}
  run zsh -f -c "$script"
  out=$(tr '\n' ' ' <<< "$out" | sed 's/\[kwhere/\n[kwhere/')   # one line per tested command line
  grep -q 'kopen staging -n .*payments' <<< "$out" || fail "kopen -n did not complete staging namespaces: [$out]"
  grep -q 'kopen staging -n .*monitoring' <<< "$out" && fail "kopen -n completed namespaces of another config: [$out]"
  grep -q 'kwhere monitoring' <<< "$out" || fail "kwhere did not complete 'mon' to 'monitoring': [$out]"
}

test_completion_config_in_words() {
  make_cluster staging ok default
  run zsh_run 'words=(kopen -n x staging ""); CURRENT=5; _kubeshelf_config_in_words'
  assert_out_eq "staging"
}

test_pages_recording_in_sync() {
  cmp -s "$ROOT/demo/demo.cast" "$ROOT/docs/demo.cast" || fail "docs/demo.cast differs from demo/demo.cast: run make demo-gif"
  grep -q 'AsciinemaPlayer.create("demo.cast"' "$ROOT/docs/index.html" || fail "docs/index.html does not play demo.cast"
}

# --- runner --------------------------------------------------------------------

pattern="${1:-}"
passed=0 failed=0
for t in $(declare -F | awk '{print $3}' | grep '^test_' | grep -- "$pattern"); do
  TMP=$(mktemp -d)
  export KUBESHELF_CONFIG_DIR="$TMP/kube" KUBESHELF_CACHE_DIR="$TMP/cache" FAKE_CLUSTERS="$TMP/clusters"
  export KUBESHELF_TIMEOUT=5 HOME="$TMP" PATH="$TESTS/fakebin:$ROOT/bin:$PATH"
  unset KUBECONFIG KUBESHELF_DEFAULT_LINK KUBESHELF_CONFIG_SUFFIX KUBESHELF_WRAP_K9S KUBESHELF_K9S_BIN
  mkdir -p "$KUBESHELF_CONFIG_DIR" "$FAKE_CLUSTERS"
  FAILED=0
  if ( FAILED=0; "$t"; exit "$FAILED" ) > "$TMP/.log" 2>&1; then
    passed=$((passed + 1)); echo "ok   $t"
  else
    failed=$((failed + 1)); echo "FAIL $t"; cat "$TMP/.log"
  fi
  sleep 0.2   # let background cache refreshes finish before cleanup
  rm -rf "$TMP"
done

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
