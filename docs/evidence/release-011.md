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
  retention of passing bundles. Both jobs passed: each has 99 source-build,
  99 relocated-bundle and 99 fresh precompiled-consumer tests passing, plus
  native arithmetic/lifecycle/concurrency/persistence and installer rejection
  checks. See [run metadata](release-011-linux-run.json) and
  [complete log](release-011-linux-run.log). Downloaded archives, full manifests,
  native interface hashes and all 21 packaged test files were verified before
  pinning `native/linux-bundles.json`.
- The [prior release metadata](release-011-prior-release.json) records the old
  release before any new publication. [Hex version lookup](release-011-hex-availability.json)
  returned 404 for `0.1.1-dev` before preparation.

Linux archive SHA256 pins:

- x86_64: `02cf205c2e3efe510ddd02440eec764c2f3406a6d591de8c65e4e304c45b4f9f`
  (49,969,085 bytes).
- ARM64: `d919aa4165d3fa9bbf673bc3645c33e9389afedf0cdb89f7c8c1d2ff8c19f2d5`
  (46,279,085 bytes).

Both ELF audits retain GLIBC 2.38 / GLIBCXX 3.4.32 requirements. Actual execution
is Ubuntu 24.04/glibc 2.39. The default-selection fixture initially attempted a
download because it assumed published catalog URLs were disabled. The test now
disables URLs only in its copied negative fixtures; production pins are unchanged.
[The corrected offline checks pass](release-011-default-selection-2.log), as do
the existing package-selection and release-asset staging checks.

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

## Final package and publication

The [final Linux consumer run](https://github.com/catethos/Aphid/actions/runs/34242496036)
passed on both architectures, including 99 fresh-consumer and 99 relocated
bundled-ERTS tests per target. [macOS run 2](release-011-final-macos-consumer-2.log)
passes 99 tests on the exact retained archive. Its SHA256 is
`9faa9af3eb1c826446b0bf9473e94632e4fbb9fcb6bfc9d85bae1a90862f2448`.
[Linux](release-011-linux-staging.log) and [macOS](release-011-macos-staging.log)
asset staging pass their source, runtime, notice and consumer identity checks.

The locally built archive `605247b8…` has byte-identical compressed source
contents and semantically identical metadata; only top-level metadata term
ordering differs. [Comparison](release-011-archive-equivalence.json). It is not
the chosen publication archive. To preserve the exact qualified outer bytes,
publication uses `Hex.API.Release.publish` with the retained tarball and
`replace=false`, the same [Hex 2.4.2 publishing API](https://github.com/hexpm/hex/blob/v2.4.2/lib/hex/api/release.ex)
and normal credential/OTP retry flow used by the CLI. The frozen-source
[package-only dry run](release-011-hex-dry-run-2.log) passes after installing
locked publisher dependencies; the first dry run lacked those dependencies.

The signed [GitHub prerelease](https://github.com/catethos/Aphid/releases/tag/v0.1.1-dev)
is public with thirteen assets. [Anonymous download checks](release-011-public-assets.json)
match every independently staged SHA256 and size. The prior release and its
thirteen asset identities remain unchanged. [macOS default installation](release-011-public-macos.log)
passes 99 tests, and [Linux public-consumer run 34243869828](https://github.com/catethos/Aphid/actions/runs/34243869828)
passes 99 tests on both architectures with no native compiler invocation.

[aphid 0.1.1-dev is published on Hex](https://hex.pm/packages/aphid/0.1.1-dev).
The owner completed Hex's normal 2FA privately in Terminal; the publisher exited
with status 0. [Public release metadata](release-011-hex-release.json) and the
[independently downloaded registry archive](release-011-hex-archive.json) match
the exact qualified SHA256 above (121,856 bytes). No existing version was replaced.

The exact-archive [publisher](release-011-publish.exs) used the installed Hex
archive on the normal Elixir code path. Initial `mix run` attempts pruned Hex/SSL
paths and failed before submission; the direct Elixir invocation completed the
standard authentication flow. No code or credential is retained in evidence.

Final fresh **Hex registry** installations pass all 99 tests on each target:

- [macOS ARM64 log](release-011-hex-registry-macos.log) and
  [input identities](release-011-hex-registry-macos-inputs.json).
- [Linux x86_64 and ARM64 run](https://github.com/catethos/Aphid/actions/runs/34245955775),
  [metadata](release-011-hex-registry-linux-run.json) and
  [complete log](release-011-hex-registry-linux-run.log). Both jobs explicitly
  enable `HEX_REGISTRY=true`.

Each check acquires Aphid itself from Hex with normal registry dependencies,
compares it with the independently pinned qualified archive, installs the native
bundle through its public default URL, and runs with native compilers denied.
Offline runtime, unchanged native files and installed notice hashes pass.
Publication and the required three-target registry checks are complete.

Minimum-system/CPU, other OTP versions, Linux sanitizers, broader TSan/Zig
allocation coverage and remaining implementation stages stay open. None of
these results establishes a confirmed security vulnerability or production support.
