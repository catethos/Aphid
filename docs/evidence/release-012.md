# Aphid 0.1.2-dev release qualification

The owner authorized publication of new bundles after adding ALGO. This
prerelease rebuilds macOS ARM64 and Linux x86_64/ARM64 with the standard
algorithms bundled and icebug disabled. Existing releases remain unchanged.

Source verification: 101 tests and native create/reopen checks pass on macOS
ARM64. Native platform bundles, fresh consumers, and publication checks follow.
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
