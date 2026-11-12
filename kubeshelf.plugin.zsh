# kubeshelf - kswitch, kwhere and kopen for one-kubeconfig-per-cluster setups
#
# Settings (export them before this file is loaded, e.g. before `source $ZSH/oh-my-zsh.sh`):
#   KUBESHELF_CONFIG_DIR, KUBESHELF_CONFIG_SUFFIX, KUBESHELF_DEFAULT_LINK,
#   KUBESHELF_CACHE_DIR, KUBESHELF_TIMEOUT   (see README.md)
#   KUBESHELF_WRAP_K9S=1   make `k9s` itself behave like `kopen`

0=${(%):-%N}
KUBESHELF_ROOT=${0:A:h}

# Commands
path=("$KUBESHELF_ROOT/bin" ${path:#$KUBESHELF_ROOT/bin})

# Completions: works whether compinit already ran (oh-my-zsh) or runs later
fpath=("$KUBESHELF_ROOT/completions" ${fpath:#$KUBESHELF_ROOT/completions})
autoload -Uz _kswitch _kwhere _kopen _kubeshelf_configs _kubeshelf_ns _kubeshelf_config_in_words

# Optional: `k9s` -> `kopen` (the real binary stays reachable with `command k9s`)
if [[ ${KUBESHELF_WRAP_K9S:-0} == 1 ]]; then
  k9s() { kopen "$@" }
fi

if (( $+functions[compdef] )); then
  compdef _kswitch kswitch
  compdef _kwhere kwhere
  compdef _kopen kopen
  [[ ${KUBESHELF_WRAP_K9S:-0} == 1 ]] && compdef _kopen k9s
fi
