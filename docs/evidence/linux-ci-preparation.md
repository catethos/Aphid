# Linux CI preparation — 2026-09-08

No Linux job has run. The source recipes now accept native x86_64/ARM64 Linux
with explicit private source/output directories. OpenSSL uses target-specific
configuration, PIC, baseline CPU flags and `--libdir=lib`; CMake uses its platform
shared-library prefix/suffix. An absolute `APHID_NATIVE_BUILD_ROOT` selects the
Linux `.so` bridge. The existing macOS default and reviewed native inputs remain.

Changed implementation files: `scripts/build.py`, `native/CMakeLists.txt`,
`native/tests/CMakeLists.txt`, `lib/aphid/native.ex`,
`scripts/source_routing_checks.py`, `scripts/linux_ci.py`,
`scripts/linux_ci_checks.py`, `.github/workflows/linux-native.yml`.
See [workflow scope and handoff](../github-release.md).

Checks:

- [Routing](linux-routing-1.log): nine ownership/configuration rejections, macOS
  routing, both Linux OpenSSL/CMake routes, baseline flags and wrong-host rejection.
  Commands are captured rather than executed.
- [CI orchestration and actionlint](linux-ci-checks-2.log): both Linux routes,
  candidate source/test/example staging and watchdog test invocation. The commands
  are mocked; this is not Linux execution. The earlier check log is retained;
  its mock-captured success text is not runtime evidence.
- [Native options](linux-native-options-1.log): existing macOS default/custom
  path and relative-path rejection, using the same stub-Zig option test as before.
- [Fresh macOS consumer](linux-prep-consumer-1.log): 92 tests pass after the source
  changes. Empty application/dependency build caches, no native compiler invocation,
  development-project reads denied, localhost-only networking; native hashes unchanged.
- [Final identities](linux-ci-final-checks-1.log): exact original runtime/native
  lock/normal bridge/normal engine hashes, Python syntax and actual Mac rejection
  of the Linux CI entry point before it writes a work directory.

Action references were resolved from the official GitHub tag API and pinned to
commits ([pins](ci-action-pins-1.json)). Zig 0.16.0 Linux archive checksums come
from the official download index ([pins](ci-zig-pins-1.json)). Local actionlint
was downloaded to `/tmp` and checked against its official release checksum
([identity](ci-actionlint-1.json)); no global toolchain was changed.

The exact reused runtime archive is
`artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz`, SHA256
`3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
No new runtime or Hex archive was built in this continuation. The prior Hex
source-input archive remains immutable, but does not contain these new edits.
DuckDB remains 1.4.4. No engine/NIF rebuild, sanitizer/performance rerun, Linux
provisioning/emulation, publication/upload or stage completion occurred.

Next obtain the publishing repository/layout and execute the prepared jobs on
real runners. Retain failures, lock the actual toolchain and produce audited ELF
bundles before extending installer identities and testing Linux consumers. Release
creation, network/default Hex delivery, minimum-system/CPU/OTP execution,
x86_64-to-ARM64 cross-building, source-consumer and attribution gates remain open.
