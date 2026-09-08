# Focused native TSan audit — host result with limits

## Runtime discovery, 2026-09-07

Working directory: `/Users/catethos/workspace/ladybugex/zig_library`.
Apple Clang 21.0.0 (`clang-2100.1.1.101`), CommandLineTools SDK
`MacOSX26.5.sdk`, ARM64 macOS 26.6 (25G72), deployment target 13.3.

[`tsan-runtime-probe-1.log`](tsan-runtime-probe-1.log) records the exact compile
command, runtime dependency inspection and watchdog-controlled clean threaded
probe: exit 0. `native/tests/tsan_probe.cpp race` deliberately performs two
unsynchronized writes. [`tsan-runtime-probe-2.log`](tsan-runtime-probe-2.log)
records a detected race and SIGABRT, with sandbox symbolizer failures.
The same command outside the sandbox produced source locations and no
symbolizer warnings in [`tsan-runtime-probe-3.log`](tsan-runtime-probe-3.log);
it also aborted as required. These intentional failures validate detection;
they are not passing application tests. No diagnostics were suppressed.

The existing Clang/SDK selection supports TSan. `native/cmake/tsan-clt21.cmake`
reuses that selection and adds TSan instrumentation separately from ASan/UBSan.
Run application tests outside the sandbox for symbolization. Every diagnostic
is a failed audit, irrespective of assertions.

## Build and selected coverage

`python3 -u scripts/tsan.py > docs/evidence/tsan-run-N.log 2>&1`
uses `scripts/proof.py` process-group watchdogs and `_build/tsan-clt21`.
It copies Ladybug and extensions without prior build outputs because upstream
places extension archives in its source tree. The production source archives
and `_build/native` are never used as instrumented engine inputs. Only locked
OpenSSL archives are reused uninstrumented. DuckDB stays pinned to 1.4.4.

Run history (all raw output retained):

- [`tsan-run-1.log`](tsan-run-1.log): DuckDB built; Ladybug compilation
  finished but linking failed with `library 'lbug' not found`. The attempted
  static-target omission was incompatible with extension linkage.
- [`tsan-run-2.log`](tsan-run-2.log): enabling both static and shared Ladybug
  targets, as in the working normal/ASan recipe, linked the complete engine and
  bridge. Lifecycle exited 1 before its first case.
- [`tsan-lifecycle-3.log`](tsan-lifecycle-3.log) and
  [`tsan-lifecycle-4.log`](tsan-lifecycle-4.log): source-location and open-error
  reporting isolated the failure to the default 8 TiB virtual address mapping.
  Running outside the sandbox did not remove this failure.
- [`tsan-mapping-probe-1.log`](tsan-mapping-probe-1.log): the standalone
  `tsan_probe.cpp mapping` mode confirms 1 GiB and 8 TiB mappings both succeed
  normally; under TSan, 1 GiB succeeds and 8 TiB fails with `ENOMEM` (exit 1).
- [`tsan-run-5.log`](tsan-run-5.log): full-runner retry unexpectedly scheduled
  a DuckDB rebuild after configuration outside the sandbox. Its build process
  group was explicitly terminated; this is not a pass. The already-linked
  engine from run 2 remained intact. The exact rebuild trigger was not audited.
- [`tsan-lifecycle-6.log`](tsan-lifecycle-6.log): rebuilding only the bridge/test
  with `APHID_TEST_MAX_DB_SIZE=1073741824`, then running outside the sandbox
  with `TSAN_OPTIONS=halt_on_error=1:exitcode=66`, passed all lifecycle cases
  in **6.677 seconds**, exit 0, with no TSan diagnostic. External watchdog: 120 s.

The 1 GiB setting limits the engine's virtual database address range in the
test executable; it does not increase the unchanged 64 MiB buffer pool.
The compile definition is applied only to `lifecycle`, and the bridge hook
also requires `APHID_TEST_FAULTS`. Neither production nor sanitizer shared
bridge libraries use the reduced range. This is a host TSan feasibility
adjustment, not an upstream race fix or proof of the production 8 TiB setting.
No engine patch was added or promoted; `native/lock.json` is unchanged.

Initial test: `native/tests/lifecycle.cpp`, including transaction abandonment
while a long query executes, rollback before reuse, stale reservation/lease
rejection, failed callback delivery, worker failure, and fetch-held retirement
with path reservation and joined cleanup. The execution overlap currently
uses a 10 ms delay and unfinished callback observation, not an engine execution
barrier; do not overstate determinism of the precise interrupt point.

The lifecycle test now additionally performs 30 rounds of 100 stale-cancel
calls from a second thread while the successor is held at its worker
cancellation callback, followed by verifying the successor returns 7. This
deterministically covers the accepted successor generation before engine
execution, not every possible in-engine interrupt timing. Each round also
starts two native lease contenders behind an atomic gate and requires exactly
one winner. [`tsan-controls-normal-1.log`](tsan-controls-normal-1.log) records
the initial expanded lifecycle passing against the normal engine (2.140 s);
[`tsan-controls-normal-2.log`](tsan-controls-normal-2.log) passes after making
the callback's base-pointer conversion explicit (2.010 s).
The existing BEAM tests `native_lifecycle_test.exs` and
`native_transactions_test.exs` additionally cover repeated stale cancellation,
caller death and actual GC, but those are not native TSan coverage.

[`tsan-input-checks-1.log`](tsan-input-checks-1.log) verifies both upstream
commits and patched diffs against the lock, all patch checksums, 4,387 copied
source files, and TSan flags in all 1,157 Ladybug and 390 DuckDB generated
compile commands. [`tsan-link-checks-1.log`](tsan-link-checks-1.log) records
binary hashes, TSan initialization/read/write symbol imports, and the lifecycle
executable's runtime path to the isolated engine. It also verifies both bridge
compile commands are instrumented and only the test has the address-range cap.
FTS, vector and DuckDB are built with instrumentation, but this run exercises
native lifecycle/core queries rather than extension concurrency workloads.
BEAM, Zig NIF code, actual resource GC callbacks, OpenSSL and system libraries
are not instrumented. No general race-freedom, complete extension concurrency,
or release-target claim follows from this focused audit. All stages remain open
where previously open.

[`tsan-normal-regression-1.log`](tsan-normal-regression-1.log) records the final
normal regression command:
`ZIG_GLOBAL_CACHE_DIR=/tmp/aphid-zig-cache python3 -u scripts/lifecycle.py`.
Native lifecycle passes with the production address-range default (2.214 s);
all **91 BEAM tests pass**, seed 0, single ordinary scheduler, 15.3 s ExUnit
time / 16.036 s process time. The normal shared bridge has no TSan imports.
Only test/diagnostic code and the compile-gated test setting changed; no
engine defect or production behavior fix was introduced.

To repeat only the passing test against the existing verified engine without
reconfiguring dependencies, from the working directory above:

```sh
python3 -u - <<'PY' > docs/evidence/tsan-lifecycle-7.log 2>&1
import os, sys
sys.path.insert(0, 'scripts')
from proof import ROOT, run
run([str(ROOT / '_build/tsan-clt21/bridge/lifecycle')],
    env=dict(os.environ, TSAN_OPTIONS='halt_on_error=1:exitcode=66'), timeout=120)
PY
```

Run outside the sandbox for usable diagnostics. Do not treat the interrupted
dependency rebuild as fresh build evidence; complete `scripts/tsan.py` before
reconstructing any new engine/candidate from its object files. Broader
extension concurrency, actual GC/Zig/BEAM boundaries, default-address-range
TSan coverage and Linux targets remain unproved.

## Linux runner scope

[`linux-runner-inventory-1.log`](linux-runner-inventory-1.log) records read-only
host/runner discovery. Docker selects a stopped Colima `aarch64` instance
(2 CPUs, 2 GiB RAM, 100 GiB configured virtual disk); no Lima instance was
listed. Docker daemon access was unavailable in this check. These observations
do not establish a Linux build or execution environment.

The requested x86_64 Linux to ARM64 Linux proof requires an actual x86_64 Linux
build host and subsequent execution on native ARM64 Linux. The local ARM64 VM
could be investigated as a target runtime, but x86_64 emulation on this Mac
would only be supplemental evidence. Provisioning/sizing both runners,
establishing the locked Linux dependency/toolchain recipe, and adapting the
current Darwin-only bridge link path are a separate effort. No VM was started,
no Linux artifact was built, and no Linux runtime was tested in this audit.

## Continuation input audit and added coverage, 2026-09-07

The user confirmed there is no available x86_64 Linux runner. Host resource
scope is retained in [continuation inventory](continuation-inventory-1.log) and
[the release checklist](../release-checklist.md); no VM was started or resized.

[Input audit 2](tsan-input-checks-2.log) confirms all 11 patch hashes, both locked
source diffs/commits, all 4,387 snapshot files, and TSan in all 1,157 Ladybug and
390 DuckDB compile commands. The native lock SHA256 remains
`d6c2db650b15ccb9ab77df54fcd9ad96dfc05da24b0104660c06caf9b575f955`;
DuckDB remains 1.4.4. No engine defect or production fix was introduced.

`native/tests/extension_concurrency.cpp` adds three gated native connections,
each issuing 100 read queries against one shared database: FTS count over 100
matching documents, vector nearest ID 1, and DuckDB sum 42. Connections join
before detach/database destruction. Normal [attempt 1](extension-concurrency-normal-1.log)
passes; [attempt 2](extension-concurrency-normal-2.log) passes after moving the
start gate ahead of connection construction so constructor failure cannot leave
the readiness wait hanging. [Packaged offline run 3](runtime-bundle-3.log) also
passes this executable. The gate synchronizes thread starts, not exact engine
instructions, and there is no concurrent mutation or index create/drop.

Both `lifecycle` and `extension_concurrency` receive the test-only 1 GiB setting
in the isolated TSan bridge configure. The shared production bridge receives
neither override. The extension fixture generator runs normally in a separate
process; the read workload's embedded DuckDB is instrumented. `scripts/tsan.py`
now includes this workload after lifecycle checks for future full invocations.
The already-running invocation 8 loaded the earlier script, so its extension
runtime check is issued separately after the isolated build finishes.

### Completed isolated rebuild and concurrent-read result

[Invocation 8](tsan-run-8.log) finished successfully: DuckDB rebuild 375.419 s,
Ladybug/extension rebuild 972.731 s, bridge/test build 1.376 s, and the freshly
linked lifecycle test **11.060 s**, exit 0 without TSan diagnostics. This resolves
the interrupted dependency-build prerequisite. Unlike invocation 6, this result
does not rely on the previously linked engine from invocation 2. No new candidate
was reconstructed or promoted.

The separately issued [concurrent-extension run 1](tsan-extension-concurrency-1.log)
passes in **3.389 s**, exit 0 without diagnostics, with
`TSAN_OPTIONS=halt_on_error=1:exitcode=66` and the 120-second process-group watchdog.
[Link/input checks 2](tsan-link-checks-2.log) retain all four binary hashes,
TSan init/read/write imports, isolated engine linkage, instrumentation of all
three bridge/test compile commands, and address-cap exclusion from the shared
bridge. The normal bridge has no TSan imports or test address-range definition.

The expanded evidence covers lifecycle controls and concurrent **reads** using
all three extensions. Concurrent index mutation/build/drop, precise in-engine
cancellation windows, actual BEAM/Zig GC, OpenSSL/system internals, the production
8 TiB range under TSan and Linux runtime coverage remain open. Prior ASan/UBSan
results are unchanged; this new concurrent-read workload was not run under ASan.
No sanitizer diagnostic was ignored, suppressed or counted as a pass.
