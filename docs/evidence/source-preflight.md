# Standalone source-input preflight

2026-09-08. No stage/implementation is marked complete or release-supported.
This follows the [attribution handoff](attribution-followup.md).

## Findings

The exact 33-file local Hex archive is a precompiled-installation source package,
not a complete native source installer. The preflight finds **15 missing files**:
native/CMakeLists.txt, native/bridge.cpp, scripts/build.py, scripts/proof.py and
all 11 checksum-pinned patches. [Report 1](source-preflight-1.json) includes the
full list, package/dependency/native identities, upstream commits/archive pins,
patch hashes, retained toolchain settings and host tool-path discovery.
[Run 1](source-preflight-1.log) exits 2 as expected; this is an explicit finding,
not a crashed proof or an attempted native build.

The code trace establishes additional boundaries:

- `Mix.Tasks.Compile.AphidBundle.source/0` checks for an existing bundle receipt,
  clears its environment receipt and returns `{:noop, []}`. It does not run the
  native engine build sequence.
- `lib/aphid/native.ex` links `../../_build/native/bridge/libaphid_bridge.dylib`
  and adds fixed development rpaths. Custom native output paths are not passed
  through that module.
- `scripts/build.py` separates fetch/OpenSSL/configure/engine/bridge operations,
  but fetches into ROOT/native/upstream. A separate --output does not isolate
  extension source outputs.
- Upstream extension CMake sets ARCHIVE/LIBRARY/RUNTIME_OUTPUT_DIRECTORY beneath
  `${PROJECT_SOURCE_DIR}/extension/${extension_name}/build`. Shared archives
  must never be trusted across candidate builds.

`scripts/source_preflight.py` is a standalone standard-library inspection tool.
It verifies the independently pinned outer archive, inspects contents in memory,
rejects unsafe/duplicate members, checks the packaged dependency lock against the
native lock, and checks required patch bytes when present. No extraction,
download, compilation, Mix startup or native/toolchain mutation is performed.
It is not automatically invoked by Mix or included in the frozen package.
`inputs_present_not_build_proven` explicitly means structural presence only.

## Verification

[Checks 1](source-preflight-checks-1.log) passes five separate CLI cases through
`scripts/proof.py` 30-second process-group watchdogs. The copied standalone tool
runs outside the development project, with network, native compiler execution
and development-project reads denied:

| Case | Expected result |
|---|---|
| Exact local package | Exit 2, blocked, 15 missing files |
| Incorrect independent SHA256 | Exit 2, invalid input |
| Unsafe ../ archive member | Exit 2, invalid input, no extraction |
| Altered locked patch | Exit 2, blocked, one checksum mismatch |
| Synthetic fixture containing required files | Exit 0, inputs present **but build unproved** |

Fixtures/reports remain at `/private/tmp/aphid-source-preflight-checks-1`.
The synthetic fixture is a test input, not a newly supported source package;
no fixture was compiled. Python syntax checks pass. Existing runtime and sanitizer
suites were not repeated: application/native code and their artifacts are unchanged.
[Final checks](source-preflight-final-checks-1.log) record report identities and
verify the previous package/runtime/native/lock hashes.

## Exact inputs and next step

Hex archive: `artifacts/aphid-0.1.0-dev-local-2.tar`, SHA256
`921d21ece8c5a96bb3cdc5ab60b6932e73dd4471b2f9382d446d9f182bd8d7e3`.
Native archive: `artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz`,
SHA256 `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
No new runtime or Hex archive was created in this continuation.

Next extend the source-package input list and implement private source-root/output
wiring in the existing build entry point before attempting a fresh source install.
Keep tool versions/SDK functionality and clean-build peak memory/disk measurement
explicitly unproved. Free disk is recorded, not treated as proof of sufficiency.
Capture link maps and source identities during a future isolated build. Use
[the preflight recipe](../source-installation.md); do not invoke source compilation
on the current archive expecting automatic engine acquisition/build.

Source installation, network delivery, minimum OS/CPU execution, other OTP versions,
OTP/static build provenance, Pegasus/ZigParser and final notice review remain open.
No Linux runner is available; do not provision or emulate Linux. Protected root
library/source/hex_consumer and DuckDB 1.4.4 are unchanged. No native rebuild,
shared-extension reuse, global toolchain change, sanitizer/performance work,
publication/upload or stage/implementation completion occurred.
