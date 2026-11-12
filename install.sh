#!/usr/bin/env bash
#
# install.sh - Install kubeshelf as an oh-my-zsh custom plugin
#
# Usage:
#   ./install.sh               # from a clone: link it into oh-my-zsh if needed, enable it
#   ./install.sh REPO_URL      # clone REPO_URL into the oh-my-zsh custom plugins, enable it
#
set -e

if [ "$(uname -s)" != "Linux" ]; then
  echo "Error: kubeshelf only supports Linux" >&2
  exit 1
fi

REPO_URL="${1:-}"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
DEST="$ZSH_CUSTOM/plugins/kubeshelf"
SRC="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "$ZSH_CUSTOM" ]; then
  echo "Error: oh-my-zsh custom directory not found ($ZSH_CUSTOM)." >&2
  echo "Without oh-my-zsh, add this line to ~/.zshrc instead:" >&2
  echo "  source $SRC/kubeshelf.plugin.zsh" >&2
  exit 1
fi

if [ ! -e "$DEST" ]; then
  if [ -n "$REPO_URL" ]; then
    git clone "$REPO_URL" "$DEST"
  elif [ "$SRC" != "$DEST" ]; then
    ln -s "$SRC" "$DEST"
    echo "Linked $DEST -> $SRC"
  fi
fi

# Enable the plugin in ~/.zshrc
if sed -n '/^plugins=(/,/)/p' "$HOME/.zshrc" | grep -qw kubeshelf; then
  echo "kubeshelf already enabled in ~/.zshrc"
elif grep -q '^plugins=(' "$HOME/.zshrc"; then
  if grep -q '^plugins=($' "$HOME/.zshrc"; then
    sed -i '/^plugins=($/a\    kubeshelf' "$HOME/.zshrc"       # multi-line list
  else
    sed -i 's/^plugins=(/plugins=(kubeshelf /' "$HOME/.zshrc"  # one-line list
  fi
  echo "Added kubeshelf to plugins=(...) in ~/.zshrc"
else
  echo "No plugins=(...) line found in ~/.zshrc: add kubeshelf to your plugins manually" >&2
fi

for tool in kubectl k9s; do
  command -v "$tool" >/dev/null || echo "Warning: $tool not found in PATH"
done

echo "Done. Run: rm -f ~/.zcompdump* && exec zsh"
