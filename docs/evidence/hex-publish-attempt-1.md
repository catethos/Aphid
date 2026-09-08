# Authenticated Hex publication attempt; 2FA pending

2026-09-08, continuing signed source
`51ee0528e80ffd6e27aa8c8f0c6cd2e9aa314e6b` from
`/Users/catethos/workspace/ladybugex/zig_library`.
The user confirmed completion of Hex authentication. `mix hex.user whoami`
returned `catethos`. Existing experimental publication authorization remains in
force; no new approval was requested.

All 54 frozen source files at `/private/tmp/aphid-hex-publish-1` and the candidate
archive still match the approved inspection. SHA256 remains
`922fdacc2be68fc94f646f6fa281ed10fbf200ca9805b8e34eb169810514ebd7`.
[Prepublication lookup](hex-package-before-2.json) returned HTTP 404.

The first authenticated [dry run](hex-package-dry-run-2.log) stopped because
the frozen publication copy lacked its Elixir dependency sources. Acquiring
them with `mix deps.get --check-locked` succeeded; see
[dependency log](hex-publish-dependencies-1.log). No native build was requested.
The next [dry run](hex-package-dry-run-3.log) exited 0. A fresh
[Hex build](hex-publish-build-check-1.log) compared byte-identically with the
approved archive before the real submission command was invoked.

`mix hex.publish package --yes`, run from the frozen copy, reached Hex's
`Enter your 2FA code:` prompt. The noninteractive input returned `:eof`; the
client raised `FunctionClauseError` in `String.trim/1` and exited 1. The exact
[failure log](hex-publish-1.log) is preserved. It contains no password or 2FA code.
The current client trace identifies Hex 2.4.2; the original preparation used
Hex 2.5.1. The fresh byte comparison proves unchanged package output despite
that client difference.

A subsequent anonymous [registry reconciliation](hex-publish-reconcile-1.json)
returned HTTP 404: no Aphid package had been published. No blind retry,
replacement, version change, tag movement or native asset change occurred.

The user was asked to run this exact command in their own terminal and enter
2FA there, never in chat:

```sh
cd /private/tmp/aphid-hex-publish-1 && mix hex.publish package --yes
```

Next: when the user reports completion, query the public Hex registry before
any further mutation, verify the anonymous tarball against the approved SHA256,
and test a fresh registry installation. Preserve final metadata/results and
sign/push the evidence. Linux final-package/additional-system tests remain
post-publication work; no release-support or stage-completion claim is made.
