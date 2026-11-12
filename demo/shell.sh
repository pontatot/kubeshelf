#!/usr/bin/env bash
#
# shell.sh - Interactive zsh with kubeshelf loaded and fake clusters, used to record the demo
#
# Nothing touches your real kubeconfigs or clusters: everything lives in a temporary
# directory, kubectl answers come from tests/fakebin/kubectl and k9s is a stand-in.
#
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEMO="$(mktemp -d)"
export HOME="$DEMO"   # paths are displayed as ~/.kube/...

REAL_KUBECTL="$(command -v kubectl)" || { echo "kubectl is required" >&2; exit 1; }
export REAL_KUBECTL
export KUBESHELF_CONFIG_DIR="$DEMO/.kube" KUBESHELF_CACHE_DIR="$DEMO/cache" FAKE_CLUSTERS="$DEMO/clusters"
export PATH="$ROOT/demo/bin:$ROOT/tests/fakebin:$PATH"
unset KUBECONFIG
mkdir -p "$KUBESHELF_CONFIG_DIR" "$FAKE_CLUSTERS"

# shellcheck source=../tests/fixtures.sh
. "$ROOT/tests/fixtures.sh"
make_cluster prod    ok          default kube-system argocd monitoring payments
make_cluster staging ok          default kube-system argocd monitoring payments-staging
make_cluster dev     ok          default kube-system monitoring sandbox
make_cluster legacy  unreachable
ln -s "$KUBESHELF_CONFIG_DIR/prod.config" "$KUBESHELF_CONFIG_DIR/config"

# Warm the namespace cache used by completion
"$ROOT/bin/kwhere" -q default >/dev/null 2>&1 || true

cat > "$DEMO/.zshrc" <<ZSHRC
autoload -Uz compinit && compinit -u -d "$DEMO/.zcompdump"
source "$ROOT/kubeshelf.plugin.zsh"
zstyle ':completion:*' menu select
PROMPT='%F{cyan}❯%f '
zshexit() { rm -rf "$DEMO" }
ZSHRC

ZDOTDIR="$DEMO" exec zsh -i
