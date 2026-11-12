# Security policy

kubeshelf reads and edits kubeconfig files, which contain cluster credentials.
Security issues are taken seriously.

## What it does with your credentials

- It only talks to the API servers listed in your own kubeconfig files, through `kubectl`.
- It never sends data anywhere else, and stores nothing but namespace names
  (in `${XDG_CACHE_HOME:-~/.cache}/kubeshelf`).
- It writes to a kubeconfig file only when you run `kswitch -n` (default namespace), and to
  `~/.kube/config` only as a symlink when you run `kswitch`.

## Supported versions

Only the latest release receives security fixes.

## Reporting a vulnerability

Please **do not open a public issue**. Instead, report it privately through
[GitHub private vulnerability reporting](https://github.com/pontatot/kubeshelf/security/advisories/new)
or by email to **pontatot@proton.me**.

Include what you found, how to reproduce it, and its impact. You should get an answer
within a week. Once a fix is released, the advisory is published and you're credited
(unless you prefer otherwise).

Don't include real credentials, tokens or server addresses in a report: redact them.
