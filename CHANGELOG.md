# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0]

### Added
- `kswitch`: switch the default kubeconfig (symlink) and save its default namespace (`-n`),
  validating the namespace exists and respecting namespace-scoped credentials.
- `kwhere`: find the kubeconfigs whose cluster contains a namespace; clusters are queried in
  parallel and printed as soon as they answer; exact or substring (`-p`) match; `-q` for scripts.
- `kopen`: open k9s on a kubeconfig and/or namespace; with only `-n`, finds the cluster that
  has the namespace and offers a numbered list when several do. Extra options go to k9s.
- Optional `KUBESHELF_WRAP_K9S=1` to make `k9s` itself behave like `kopen`.
- zsh completions for all commands, including per-cluster namespace completion after `-n`
  (served from a local cache, never from the network).
- Settings through `KUBESHELF_*` environment variables.
- `-V/--version` on every command.
- Credential plugins (EKS, GKE, OIDC...): `kwhere` runs them without a terminal and names
  them in errors; `--skip-exec` / `KUBESHELF_SKIP_EXEC=1` answers from the cache instead;
  background cache refreshes never run them. Timeouts are reported as such.
- `kswitch` shows paths under `$HOME` as `~`.
- README demo (`make demo`, a scripted asciinema recording on fake clusters) and Dependabot for CI actions.
- `kswitch` warns when `KUBECONFIG` is set, since kubectl then ignores the default symlink.
- Dependency-free test suite and CI (shellcheck, zsh syntax, tests).
