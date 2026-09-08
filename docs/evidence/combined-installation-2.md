# Combined package and Linux embedded release qualification

Run [34199713798](https://github.com/catethos/Aphid/actions/runs/34199713798)
at `608b646d954d9b83128e79f76e46c3e3de63ad41` passed on both native Ubuntu 24.04
architectures. It reused the [reviewed native bundles](linux-qualified-bundles.md)
without rebuilding the engine or NIFs. Elixir 1.20.0, OTP 29.0.4 / ERTS 17.0.4,
glibc 2.39 and GNU binutils 2.42 were used.

## One exact source archive on three targets

`artifacts/aphid-0.1.0-dev-combined-linux-2.tar` is 103,936 bytes, SHA256
`b85967b047662ccdc66851d246a9a7301fe8c797225d7e479948653838dc57df`.
It contains 52 source files, both reviewed Linux identities and the original
macOS identity, with no native binaries or dependency build caches.

Both Linux consumers passed 92 tests (core, FTS, vector and DuckDB), 23 actual
Mix installer rejection cases and missing/corrupt/unloadable NIF loader checks.
The exact retained source archive then passed a fresh macOS ARM64 consumer's
92 tests with the unchanged runtime archive SHA256
`3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
All three used normal locked Hex dependency acquisition, empty application and
dependency build caches, denied development-project reads and native compiler
execution, then isolated compilation/runtime networking. Native hashes stayed
unchanged. Process-group watchdogs were provided by `scripts/proof.py`.

Raw evidence: `combined-linux-{x86_64,aarch64}-consumer-2.log`,
`combined-macos-consumer-2.log`, `combined-linux-run-2.json` and
`combined-source-artifacts-2.json`. Source-only Actions retention was enabled
for seven days after the complete x86_64 job passed. It contains the source
archive, consumer inputs and log; no new native or Mix release archive upload.

The earlier macOS-built archive `4dc6bf1b3083f6ffeb0f177483750723be7c9796d3b391fd749990b2396e7ffe`
has identical compressed source contents and equal parsed metadata; only
metadata field order differs. `combined-package-comparison-2.json` records this.
The retained Linux-built bytes above are the exact three-target review artifact.
Later documentation edits do not retroactively change that archive identity.

## Linux bundled-ERTS releases

Both jobs also assembled, archived and relocated an embedded Mix release from
that source package and ran 92 tests, normal startup, application restart without
NIF reload, graceful shutdown and persisted reopen. Each audited 23 ELF files.
The positive runtime proof hid development/build trees and installed host
Elixir/ERTS, denied native compiler execution, used a network namespace without
routes, and verified native and release-file hashes after execution.

| Target | Ephemeral validation release SHA256 | Bytes |
|---|---|---:|
| x86_64 | `3d1d96b2035e7ee180be29283033c638496912199370c0abbb0306adfead2499` | 140,505,087 |
| ARM64 | `ed894ac886c1ec77a6e614d45b56461d2518b2469b7c0073bf03ca80521e996b` | 129,569,102 |

These release archives were not uploaded or retained locally; their identities,
ELF audits and test results are in the raw CI logs. Separate embedded startup
checks rejected missing, corrupt and unloadable artifacts, including a private
noexec mount, and restored native hashes. Those negative checks do not use the
full positive runtime sandbox. No Mix or Zig installation is needed at runtime.

## Remaining gates and handoff

Actual public GitHub HTTPS delivery/default selection and Hex registry installation
remain unproved. The manual draft workflow has not run. Review final attribution
and linker provenance before authorizing a concrete draft; then verify delivery
of these exact native bytes and rerun the final source package consumers before
any Hex publication. The Hex package API returned 404 for `aphid` on 2026-09-08;
this is not a name reservation.

Minimum OS/CPU execution, other OTP/binutils versions, the required Linux
x86_64-to-ARM64 cross-build, fresh source installation and outstanding plan
behaviour/instrumentation gates remain open. The Linux engine requires GLIBC 2.38
and GLIBCXX 3.4.32; actual execution was glibc 2.39 only. macOS execution remains
26.6 only. DuckDB stays 1.4.4. No target is release-supported, no stage is marked
complete, and no GitHub release or Hex publication occurred.
