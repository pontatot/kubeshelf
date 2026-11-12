# shellcheck shell=bash
#
# common.sh - Settings and helpers shared by the kubeshelf commands
#
# Settings (environment variables):
#   KUBESHELF_CONFIG_DIR     directory holding the kubeconfig files   (default: ~/.kube)
#   KUBESHELF_CONFIG_SUFFIX  suffix of kubeconfig files               (default: .config)
#   KUBESHELF_DEFAULT_LINK   symlink managed by kswitch               (default: $KUBESHELF_CONFIG_DIR/config)
#   KUBESHELF_CACHE_DIR      namespace cache for completions          (default: ${XDG_CACHE_HOME:-~/.cache}/kubeshelf)
#   KUBESHELF_TIMEOUT        per-cluster request timeout, in seconds  (default: 5)
#   KUBESHELF_SKIP_EXEC      1: kwhere does not contact clusters whose credentials come from an
#                            exec/auth-provider plugin (EKS, GKE, OIDC...) and uses the cache
#   NO_COLOR                  disable colored output when set

KT_VERSION="0.1.0"

KT_CONFIG_DIR="${KUBESHELF_CONFIG_DIR:-$HOME/.kube}"
KT_SUFFIX="${KUBESHELF_CONFIG_SUFFIX:-.config}"
KT_DEFAULT_LINK="${KUBESHELF_DEFAULT_LINK:-$KT_CONFIG_DIR/config}"
KT_CACHE_DIR="${KUBESHELF_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/kubeshelf}"
KT_NS_CACHE_DIR="$KT_CACHE_DIR/namespaces"
KT_TIMEOUT="${KUBESHELF_TIMEOUT:-5}"
# shellcheck disable=SC2034  # read by bin/kwhere
KT_SKIP_EXEC="${KUBESHELF_SKIP_EXEC:-0}"

# Colors only when writing to a terminal
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[0;31m' GREEN=$'\033[0;32m' YELLOW=$'\033[0;33m'
  BLUE=$'\033[0;34m' CYAN=$'\033[0;36m' BOLD=$'\033[1m' NC=$'\033[0m'
else
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi
export RED GREEN YELLOW BLUE CYAN BOLD NC

kt_error() { printf '%s\n' "${RED}Error: $*${NC}" >&2; }
kt_warn()  { printf '%s\n' "${YELLOW}Warning: $*${NC}" >&2; }

kt_print_version() { printf '%s\n' "${1:-kubeshelf} (kubeshelf) $KT_VERSION"; }

# Warn when KUBECONFIG is set: kubectl then ignores the default symlink in this shell
kt_warn_kubeconfig_override() {
  local v="${KUBECONFIG:-}"
  [ -z "$v" ] && return 0
  [ "$v" = "$KT_DEFAULT_LINK" ] && return 0   # explicitly pointing at the symlink is fine
  kt_warn "KUBECONFIG is set ($v): kubectl ignores $KT_DEFAULT_LINK in this shell. Run 'unset KUBECONFIG' to use it."
}

kt_require_kubectl() {
  command -v kubectl >/dev/null 2>&1 || { kt_error "kubectl not found in PATH"; exit 1; }
}

# Path for display: $HOME shown as ~
kt_pretty_path() { printf '%s\n' "${1/#"$HOME"/\~}"; }

# Path of the kubeconfig file of a config name
kt_config_path() { printf '%s\n' "$KT_CONFIG_DIR/$1$KT_SUFFIX"; }

kt_config_exists() { [ -n "$1" ] && [ -f "$(kt_config_path "$1")" ]; }

# Config names (file names without suffix), one per line, sorted
kt_config_names() {
  local f
  for f in "$KT_CONFIG_DIR"/*"$KT_SUFFIX"; do
    [ -f "$f" ] || continue
    [ "$f" = "$KT_DEFAULT_LINK" ] && continue   # the kswitch symlink itself
    f=${f##*/}
    printf '%s\n' "${f%"$KT_SUFFIX"}"
  done
}

# Config name the default symlink points to (empty if none)
kt_current_default() {
  local target
  [ -L "$KT_DEFAULT_LINK" ] || return 0
  target=$(readlink "$KT_DEFAULT_LINK")
  target=${target##*/}
  printf '%s\n' "${target%"$KT_SUFFIX"}"
}

# Field of the current context of a config, e.g. kt_context_field prod namespace
kt_context_field() {
  kubectl --kubeconfig "$(kt_config_path "$1")" config view --minify \
    -o jsonpath="{.contexts[0].context.$2}" 2>/dev/null
}

# Credential plugin of a config (exec command or auth-provider name), empty for static
# credentials (certificates, tokens). Such plugins may open a browser or prompt for input.
kt_exec_auth() {
  kubectl --kubeconfig "$(kt_config_path "$1")" config view --minify \
    -o jsonpath='{.users[0].user.exec.command}{.users[0].user.auth-provider.name}' 2>/dev/null
}

kt_server() {
  kubectl --kubeconfig "$(kt_config_path "$1")" config view --minify \
    -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null
}

# kubectl against a config, bounded by KUBESHELF_TIMEOUT
kt_kubectl() {
  local name="$1"; shift
  timeout $((KT_TIMEOUT + 2)) kubectl --kubeconfig "$(kt_config_path "$name")" \
    --request-timeout="${KT_TIMEOUT}s" "$@"
}

# Namespaces of a config, one per line (stderr of kubectl kept, for error classification)
kt_list_namespaces() {
  kt_kubectl "$1" get namespaces -o custom-columns=:metadata.name --no-headers
}

# Keep the meaningful line of a kubectl error (drop klog "E1112 ... memcache" noise)
kt_short_error() {
  local msg
  msg=$(grep -E '^(Unable to connect|error:|Error from server)' <<< "$1" | tail -1)
  [ -z "$msg" ] && msg=$(grep -v '^$' <<< "$1" | tail -1)
  printf '%s\n' "${msg:0:140}"
}

# Store the namespaces of a config (stdin) in the completion cache, atomically
kt_cache_namespaces() {
  local name="$1" tmp
  mkdir -p "$KT_NS_CACHE_DIR" || return 0
  tmp=$(mktemp "$KT_NS_CACHE_DIR/.$name.XXXXXX") || return 0
  cat > "$tmp"
  if [ -s "$tmp" ]; then mv "$tmp" "$KT_NS_CACHE_DIR/$name"; else rm -f "$tmp"; fi
}

# Refresh the namespace cache of a config in a detached background job
# (survives an exec into another program and never writes to the terminal)
kt_refresh_ns_cache_bg() {
  local name="$1"
  # never run a credential plugin in the background: it could open a login behind k9s
  [ -n "$(kt_exec_auth "$name")" ] && return 0
  (
    out=$(kt_list_namespaces "$name" 2>/dev/null) && printf '%s\n' "$out" | kt_cache_namespaces "$name"
  ) </dev/null >/dev/null 2>&1 &
  disown 2>/dev/null || true
}
