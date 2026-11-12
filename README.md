# kubeshelf

[![CI](https://github.com/pontatot/kubeshelf/actions/workflows/ci.yml/badge.svg)](https://github.com/pontatot/kubeshelf/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A small zsh plugin for people who keep **one kubeconfig file per cluster**
(`~/.kube/prod.config`, `~/.kube/staging.config`, ...) and want to move between
them, and their namespaces, without thinking about it.

[![kubeshelf demo: kwhere, kswitch and kopen with namespace completion](demo/demo.gif)](https://pontatot.github.io/kubeshelf/)

<sub>Click the animation to <a href="https://pontatot.github.io/kubeshelf/">watch it with selectable text</a>. Recorded on fake clusters; k9s is shown with a stand-in screen. Source: <a href="demo/">demo/</a>.</sub>

```console
$ kwhere payments
  prod (https://prod.example.com:6443)
  staging (https://staging.example.com:6443)

$ kswitch staging -n payments
Switched default kubeconfig to: staging
  ~/.kube/config -> ~/.kube/staging.config
Default namespace of staging set to: payments

$ kopen -n payments          # k9s on the cluster that has 'payments', pick one if several do
```

| Command | What it does |
|---|---|
| `kswitch <config> [-n ns]` | Make `<config>` the default kubeconfig (`~/.kube/config` becomes a symlink to it), optionally saving its default namespace |
| `kwhere [-p] [-q] <ns>` | List the configs whose cluster has namespace `<ns>`, querying all clusters in parallel |
| `kopen [<config>] [-n ns] [k9s options]` | Open [k9s](https://k9scli.io) on a config and/or namespace. With only `-n`, it finds the cluster first |

Every command has zsh tab-completion, **including the namespaces of the cluster you
typed** after `-n` (`kopen staging -n <TAB>`). Completion is instant: it reads a local
cache and never contacts a cluster.

## Why another kube switcher?

[kubectx/kubens](https://github.com/ahmetb/kubectx), [kubie](https://github.com/sbstp/kubie)
and [kubeswitch](https://github.com/danielfoehrKn/kubeswitch) are great, and you
should probably use them if they fit your setup. kubeshelf fills a narrower niche:

- **One file per cluster, no merging.** Admin kubeconfigs from different providers often
  share the same context names (`kubernetes-admin@kubernetes` everywhere). They clash once
  merged. kubeshelf never merges: it switches which file `~/.kube/config` points to, so
  every tool (kubectl, helm, k9s, Terraform...) follows without any extra setup.
- **"Which cluster is this namespace on?"** `kwhere` answers in about a second across
  every cluster, including the ones where your credentials are limited to a single
  namespace. Results are printed as clusters answer, so an unreachable one doesn't hold
  the others back.
- **Namespace-aware completion per cluster**, from a cache kept up to date as you use the tools.
- **Plain bash scripts.** No daemon, no subshell, no binary to install. Just a
  few hundred lines you can read.

It doesn't try to manage contexts inside one file, spawn isolated shells (use kubie for
that) or support other OSes than Linux.

## Requirements

- Linux, with GNU coreutils
- zsh (for completions) and bash ≥ 4.4 (for the commands)
- `kubectl`, and [`k9s`](https://k9scli.io) for `kopen`

## Install

### oh-my-zsh

```sh
git clone https://github.com/pontatot/kubeshelf.git ~/.oh-my-zsh/custom/plugins/kubeshelf
~/.oh-my-zsh/custom/plugins/kubeshelf/install.sh   # adds kubeshelf to plugins=(...) in ~/.zshrc
rm -f ~/.zcompdump* && exec zsh
```

### Other plugin managers / plain zsh

```zsh
# zinit
zinit light pontatot/kubeshelf
# antidote (.zsh_plugins.txt)
pontatot/kubeshelf
# plain: clone anywhere, then in ~/.zshrc (before or after compinit)
source ~/src/kubeshelf/kubeshelf.plugin.zsh
```

Update with `git pull` in the clone. Check the installed version with `kswitch --version`.

### Uninstall

```sh
# 1. remove kubeshelf from plugins=(...) in ~/.zshrc (and any KUBESHELF_* exports)
# 2. delete the plugin and its cache
rm -rf ~/.oh-my-zsh/custom/plugins/kubeshelf ~/.cache/kubeshelf
rm -f ~/.zcompdump* && exec zsh
```

Your kubeconfig files are never modified on uninstall. `~/.kube/config` stays a symlink
to the last config you switched to: keep it, or replace it with a copy of that file
(`cp --remove-destination "$(readlink ~/.kube/config)" ~/.kube/config`).

## Usage

```sh
kswitch --list                 # available configs
kswitch prod                   # ~/.kube/config -> ~/.kube/prod.config
kswitch staging -n payments    # switch and save 'payments' as default namespace in staging.config
kswitch -n kube-system         # change the namespace of the current config
kswitch --current              # current config and namespace
kswitch --remove               # remove the symlink

kwhere monitoring              # configs whose cluster has 'monitoring'
kwhere -p payments             # substring match, shows the matching namespaces
kwhere -q argocd               # names only, for scripts
kwhere -s payments             # don't contact clusters using a credential plugin (EKS, GKE, OIDC...)

kopen                          # k9s on the default kubeconfig
kopen prod -n monitoring       # k9s on prod, directly in 'monitoring'
kopen -n payments              # find the cluster(s) having 'payments'; numbered list if several
kopen staging -n argocd -c deploy --readonly   # other options are passed to k9s
```

Notes:

- `kswitch -n` saves the namespace **in the kubeconfig file** (like
  `kubectl config set-context --current --namespace`). It checks the namespace exists first.
  If the credentials are limited to one namespace, it refuses to save any other.
- `kswitch` works by changing what `~/.kube/config` points to. If `KUBECONFIG` is set in your
  shell, kubectl ignores that file: `kswitch` warns about it (`unset KUBECONFIG` to fix).
- `kwhere` exits with status 1 when nothing matches, so it can be used in scripts.
  Unreachable clusters are listed on stderr (hidden with `-q`).
- Configs whose credentials cannot list namespaces (namespace-scoped service accounts)
  are matched against the namespace of their context and flagged `(scoped credentials)`.

### Clusters with credential plugins (EKS, GKE, AKS, OIDC...)

Some kubeconfigs get their credentials from a program (`exec:` or `auth-provider:` in the
user section, e.g. `aws eks get-token`, `gke-gcloud-auth-plugin`, `kubelogin`).

- `kwhere` runs them **without a terminal**, so several clusters never prompt at the same
  time. Non-interactive plugins (AWS, GKE) work as usual. One that needs an interactive
  login (an expired OIDC session) fails or times out, and the error names the plugin: log in
  once with `kubectl --kubeconfig ... get ns`, then retry.
- With `kwhere --skip-exec` (or `KUBESHELF_SKIP_EXEC=1`), those clusters are **not contacted**
  and are matched against the namespace cache instead, flagged `(from cache)`. `kopen -n` uses
  the same setting when it searches for a cluster.
- The background cache refresh done by `kswitch` / `kopen` never runs credential plugins, so
  no login pops up behind k9s. Their cache is filled by `kwhere` only.

### Using `k9s` itself

`kopen` is a separate command, so the real `k9s` is never shadowed. If you'd rather
type `k9s prod -n monitoring`, opt in before the plugin is loaded:

```zsh
export KUBESHELF_WRAP_K9S=1      # in ~/.zshrc, before `source $ZSH/oh-my-zsh.sh`
```

`k9s` then behaves like `kopen` (with completion); `command k9s` still runs the real binary.

## Settings

Environment variables: **export** them in `~/.zshrc` before the plugin is loaded (e.g.
`export KUBESHELF_TIMEOUT=10`), so the commands see them too:

| Variable | Default | Meaning |
|---|---|---|
| `KUBESHELF_CONFIG_DIR` | `~/.kube` | Where the kubeconfig files live |
| `KUBESHELF_CONFIG_SUFFIX` | `.config` | Suffix of the kubeconfig files (`prod.config` → `prod`) |
| `KUBESHELF_DEFAULT_LINK` | `$KUBESHELF_CONFIG_DIR/config` | Symlink managed by `kswitch` |
| `KUBESHELF_CACHE_DIR` | `${XDG_CACHE_HOME:-~/.cache}/kubeshelf` | Namespace cache used by completion |
| `KUBESHELF_TIMEOUT` | `5` | Per-cluster request timeout, in seconds |
| `KUBESHELF_SKIP_EXEC` | `0` | `1`: `kwhere` uses the cache for clusters with a credential plugin |
| `KUBESHELF_WRAP_K9S` | `0` | `1` makes `k9s` behave like `kopen` |
| `KUBESHELF_K9S_BIN` | `k9s` in `PATH` | k9s binary used by `kopen` |
| `NO_COLOR` | unset | Disable colors (colors are also off when output is not a terminal) |

## How it works

```
kubeshelf/
├── kubeshelf.plugin.zsh   # adds bin/ to PATH and completions/ to fpath
├── bin/                    # kswitch, kwhere, kopen (bash)
├── lib/common.sh           # shared settings and helpers
├── completions/            # zsh completions (_kswitch, _kwhere, _kopen + helpers)
├── tests/                  # dependency-free test suite with a fake kubectl
└── demo/                   # README demo: scripted asciinema session on fake clusters
```

The namespace cache (`$KUBESHELF_CACHE_DIR/namespaces/<config>`) is refreshed by
`kwhere`, and in the background by `kswitch` / `kopen` each time a config is used.

## Development

```sh
make lint test
```

See [CONTRIBUTING.md](CONTRIBUTING.md). Changes are listed in [CHANGELOG.md](CHANGELOG.md).
To report a vulnerability, see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE)
