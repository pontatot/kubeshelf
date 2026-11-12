# shellcheck shell=bash
#
# fixtures.sh - Fake clusters for tests and the demo (used with tests/fakebin/kubectl)
#
# Requires KUBESHELF_CONFIG_DIR (kubeconfig files) and FAKE_CLUSTERS (cluster answers).

# Create a kubeconfig + cluster fixture
#   make_cluster NAME MODE [--ctx-ns NS] [--exec COMMAND] [NAMESPACE...]
#   MODE: ok | forbidden | unreachable | slow | hang | never (fails the test if contacted)
make_cluster() {
  local name="$1" mode="$2" ctx_ns="" exec_cmd="" user; shift 2
  while :; do
    case "${1:-}" in
      --ctx-ns) ctx_ns="$2"; shift 2 ;;
      --exec) exec_cmd="$2"; shift 2 ;;
      *) break ;;
    esac
  done
  if [ -n "$exec_cmd" ]; then
    user="    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      command: $exec_cmd
      args: [get-token]"
  else
    user="    token: fake"
  fi
  cat > "$KUBESHELF_CONFIG_DIR/$name.config" <<EOF
apiVersion: v1
kind: Config
clusters:
- name: $name
  cluster:
    server: https://$name.example.com:6443
users:
- name: $name-admin
  user:
$user
contexts:
- name: $name
  context:
    cluster: $name
    user: $name-admin${ctx_ns:+
    namespace: $ctx_ns}
current-context: $name
EOF
  { echo "$mode"; printf '%s\n' "$@"; } > "$FAKE_CLUSTERS/$name"
}
