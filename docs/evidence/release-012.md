# Aphid 0.1.2-dev release qualification

The owner authorized publication of new bundles after adding ALGO. This
prerelease rebuilds macOS ARM64 and Linux x86_64/ARM64 with the standard
algorithms bundled and icebug disabled. Existing releases remain unchanged.

Source verification: 101 tests and native create/reopen checks pass on macOS
ARM64. Native platform, fresh-consumer, and publication checks are recorded below.
No new platform-support or minimum-system claim is made.

## Build identity

Signed native build commit: `f9f86eb79198ab944d8f014175d4536979c7523b`.
Linux qualification run: [34249482350](https://github.com/catethos/Aphid/actions/runs/34249482350).

## macOS ARM64

The rebuilt normal engine in `_build/native` contains ALGO and the locked
hardening patches. The release NIF in `_build/release-012-macos` uses the
existing `aarch64-macos.13.3-none` baseline target. Execution remains macOS 26.6.

- Target NIF build passed.
- Relocated archive: 101 tests and native lifecycle/concurrency checks passed
  with networking and development-tree reads denied.
- Fresh package consumer: 101 tests passed with normal locked Hex dependencies,
  native compilers denied, unchanged native files, and verified installed notices.
- Missing/corrupt/incompatible installer and loader rejection checks passed.

The macOS-only intermediate source archive is for local qualification, not the
final combined package. The published catalogs will be pinned to all three new
bundles before the final source package is qualified.

macOS archive SHA256: `f16d35403a13fce83ea0c94ae5caf11aff8de508c50cac3e09bafd517c474ea6` (33681661 bytes).
Native lock SHA256: `80a5763a43cddc17ecade56f34f24d83fc9b1af52158d25a488b68fc9c23514d`.

The bundled-ERTS macOS release passes all 101 tests, offline startup, application
restart, graceful shutdown, and separate-VM persistence/reopen. Native files
remain unchanged and no compiler is invoked.

Embedded missing/corrupt/unloadable startup rejection checks also pass, with
the native files restored unchanged afterward.

## Linux ARM64 and x86_64

[Native qualification run 34249482350](https://github.com/catethos/Aphid/actions/runs/34249482350)
passed on both native architectures. Each passed 101 source-build, 101
relocated-bundle, and 101 fresh precompiled-consumer tests, plus native
lifecycle/concurrency/persistence and installer-rejection checks. Downloaded
archive sizes, hashes, every manifest entry, current test contents, ELF audit
hashes, native source hashes, and the native lock were verified before pinning
the catalogs.

- aarch64-linux-gnu: `773c99a84225dc0486a89bc1d5ef90bf3144223c04222623910b9aff15ad1731` (46396683 bytes).
- x86_64-linux-gnu: `60c3d09f2b6e41248fde52375f5da8ab0cb90b4df3b7dd3f414f820a472e91ae` (50092308 bytes).

## Final combined package

[Combined consumer run 34255516099](https://github.com/catethos/Aphid/actions/runs/34255516099)
passed on both Linux architectures, including 101 fresh-consumer and 101
bundled-ERTS tests per target. The exact retained source archive also passes
all 101 tests in a fresh macOS consumer.

Qualified source archive SHA256: `7236de60e361c8eabe2d4f17973ce6f9e71b247570deb5736553d6f051a037f4`.
The frozen-source package-only Hex dry run passes. Publication uses this exact
retained tarball through Hex 2.5.1's `Hex.API.Release.publish/5`, with the normal
authentication wrapper and `replace=false`, matching the installed CLI flow.

## Public native release

The signed [GitHub prerelease](https://github.com/catethos/Aphid/releases/tag/v0.1.2-dev)
is public with thirteen assets. Every anonymous download matches the staged
SHA256 and size; the prior `v0.1.1-dev` release and all of its assets are unchanged.
Public default installations pass 101 tests each on macOS ARM64 and both Linux
architectures ([public Linux run](https://github.com/catethos/Aphid/actions/runs/34256497743)).
[Aphid 0.1.2-dev is published on Hex](https://hex.pm/packages/aphid/0.1.2-dev).
The publisher exited with status 0. The independently downloaded registry
archive is 123,904 bytes and exactly matches the qualified SHA256 above. No
existing version was replaced. Fresh registry-installation checks pass on all three targets.

## Final registry verification

Fresh Hex-registry installations pass all 101 tests on macOS ARM64 and Linux
x86_64/ARM64. [Linux registry run 34257103251](https://github.com/catethos/Aphid/actions/runs/34257103251)
explicitly enables `HEX_REGISTRY=true`. The macOS registry log and input record
are retained beside this report. Every check acquires Aphid from Hex, verifies
the exact independently pinned source archive, downloads the native bundle
through its public default URL, and runs with native compilers denied. Offline
runtime, unchanged native files, and installed notices pass.

Publication and three-target registry verification are complete. Temporary
local consumer/publisher copies were removed after retaining archives, input
identities, and logs. Existing release assets remain unchanged.
