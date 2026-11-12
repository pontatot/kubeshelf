# Contributing

Thanks for your interest! Bug reports, ideas and pull requests are welcome.

## Development

```sh
git clone <your fork> ~/.oh-my-zsh/custom/plugins/kubeshelf
cd ~/.oh-my-zsh/custom/plugins/kubeshelf
make lint test
```

- `make lint` runs `bash -n` / `zsh -n` on every file and `shellcheck` when installed.
- `make test` runs `tests/run.sh`. Tests never touch a real cluster: `tests/fakebin/kubectl`
  answers `get namespace(s)` from fixtures and delegates `config ...` to the real kubectl,
  which only reads/writes the temporary kubeconfigs. You need `bash`, `zsh` and `kubectl`.
  Run a subset with `tests/run.sh kswitch`.

## Guidelines

- Linux only (GNU coreutils, bash ≥ 4.4). Commands are bash; completions and the plugin are zsh.
- Shared settings and helpers go in `lib/common.sh`; never hard-code `~/.kube`.
- Errors and warnings go to stderr, results to stdout; exit 1 when nothing is found.
- Every kubectl call that hits a cluster goes through `kt_kubectl` (bounded by a timeout).
- Completions must never call the network: read the namespace cache instead.
- Add or update tests for every behavior change, and a line in `CHANGELOG.md` under *Unreleased*.

## Demo

`demo/demo.gif` comes from a scripted [asciinema](https://asciinema.org) recording: run
`make demo` (needs `asciinema`, and [`agg`](https://github.com/asciinema/agg) for the GIF;
`make demo-gif` only converts the existing recording).
`demo/play.zsh` types the demo with realistic timing (watch it with `zsh demo/play.zsh`,
`DEMO_TYPING_DELAY` changes the speed) into `demo/shell.sh`, an interactive zsh with fake
clusters (the test fixtures) and a k9s stand-in, so nothing real appears in the recording.
Try it by hand with `./demo/shell.sh`. Re-record it when the output of a command changes.

The recording is also published with selectable text on GitHub Pages: `docs/index.html`
(asciinema-player) plays `docs/demo.cast`, a copy that `make demo` / `make demo-gif` keep in
sync (a test checks it). Pages is served from the `/docs` folder of `main`.

## Releasing

1. Bump `KT_VERSION` in `lib/common.sh` (semantic versioning).
2. Move the *Unreleased* entries of `CHANGELOG.md` under a new `## [x.y.z]` section
   (a test checks that the current version has a section).
3. Commit, tag `vx.y.z`, push the tag.

## Adding a command

1. `bin/<cmd>` (executable, sources `lib/common.sh`).
2. `completions/_<cmd>` starting with `#compdef <cmd>`.
3. Register it in `kubeshelf.plugin.zsh` (`autoload` + `compdef`).
4. Tests in `tests/run.sh`, docs in `README.md`.
