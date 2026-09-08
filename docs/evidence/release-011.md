# Aphid 0.1.1-dev release qualification

The owner authorized a new prerelease after the stability/correctness fixes,
including rebuilding and checking all three native targets before publication.
Existing `v0.1.0-dev` assets and tag must remain unchanged. This authorization
includes the new GitHub prerelease and package-only Hex publication, not a
stable-release or platform-support claim.

## Source and native inputs

- Hardening commit: `b3cb35e`.
- Signed release build commit: `f3043c6698c32e0478ed0da83ee907d5bfc09b4d`.
- Native lock SHA256: `09b8618810c5788237ebec1c8164c9322d0d65f4d312c41e4908687394647aba`.
- [Native Linux workflow](https://github.com/catethos/Aphid/actions/runs/34236085662)
  builds both architectures natively from the signed commit, with seven-day
  retention of passing bundles. Results are pending.
- The [prior release metadata](release-011-prior-release.json) records the old
  release before any new publication. [Hex version lookup](release-011-hex-availability.json)
  returned 404 for `0.1.1-dev` before preparation.

## macOS ARM64

The [verified hardened normal engine](hardening-2026-09-08.md) is reused from
`_build/hardening-normal`, with an explicitly rebuilt target NIF in
`_build/release-011-macos`. No stale `_build/native` engine was substituted.
The helper now accepts the explicit native output directory for both linking
and bundle assembly. NIFs use `aarch64-macos.13.3-none` / baseline CPU flags;
execution remains macOS 26.6 only.

| Check | Result |
|---|---|
| [Target NIF build](release-011-macos-nif-1.log) | Pass |
| [Relocated archive](release-011-macos-bundle-1.log) | 99 tests pass, plus native lifecycle and concurrent extension reads; network/development reads denied |
| [Fresh package consumer](release-011-macos-consumer-1.log) | 99 tests pass with normal locked Hex dependencies; no native compiler invocation; native and installed notice hashes match |
| [Installer/loader failures](release-011-macos-failures-1.log) | Missing, corrupt, unsafe and incompatible bundles rejected |
| [Bundled-ERTS Mix release](release-011-macos-embedded-1.log) | 99 tests pass; offline embedded startup, restart, shutdown and separate-VM persistence pass |
| [Embedded failures](release-011-macos-embedded-failures-1.log) | Missing/corrupt/unloadable startup rejected; native closure restored |
| [Source preflight](release-011-source-preflight.json) | All required inputs present, patch checksums match; structural check only |

Archive: `artifacts/aphid-0.1.1-dev-aarch64-macos.tar.gz`, 33,620,177 bytes,
SHA256 `d026518323a5448f2705b126584b2b3b225188c0c599e831b4947a44442c0637`.
The intermediate macOS-only source package is SHA256
`2483abe10ec4e73eeb363019fbe579f71fb18e93920c02646c5356542f8f783d`.
It retains the earlier Linux catalogs and is **not** the final publication
package. A final combined-catalog source package must be qualified separately.

## Remaining release steps

Finish both Linux native builds and packaged checks; pin their identities;
qualify one final combined source package on all three targets; stage and
publish immutable versioned native assets; verify anonymous downloads; freeze,
dry-run and publish the exact Hex package, then verify registry installation.
If Hex requires private 2FA, the owner must enter it directly in the terminal.
No code or credential should enter chat or evidence logs.

Minimum-system/CPU, other OTP versions, Linux sanitizers, broader TSan/Zig
allocation coverage and remaining implementation stages stay open. None of
these results establishes a confirmed security vulnerability or production support.
