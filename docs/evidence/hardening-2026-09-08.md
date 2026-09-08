# Combined lifecycle and public-API sanitizer hardening

2026-09-08; work in `zig_library/`. This is local hardening work, not release
qualification. Existing release assets are unchanged.

Outcome: **99 public tests pass** with fatal ASan/UBSan and with the normal
engine. Five narrow engine fixes are promoted into `native/lock.json` (SHA256
`09b8618810c5788237ebec1c8164c9322d0d65f4d312c41e4908687394647aba`).
The patched engine diff is
`da2eb083347d666a63aa27db0e4440eb78e70b3278875acf7e64f1b45589e277`.
No exploit or data exposure has been demonstrated; the findings are native
undefined behavior and crash/correctness defects. This is not a security audit.

## New behavioral coverage

`test/combined_hardening_test.exs` adds three persistent-database cases: query
timeout, transaction caller death, and database close. An explicit transaction
updates an indexed document's text/vector, deletes another document and inserts
an uncommitted document. Three other sessions each retain a real FTS, vector or
DuckDB cursor after transferring one row. Only then does the writer start an
expensive FTS-derived computation; the test observes native state 1
(accepted/executing) before interrupting it. This is not a barrier at a specific
instruction inside the engine.

The non-close cases require native idle and verified rollback while the reader
results are still held. Both indexes are dropped and rebuilt before those readers
resume; their complete results must still match the committed snapshot. The close
case requires native destruction, and each old cursor must report `closed` on
resumption. Every case reopens the persistent database, checks indexed results and
absence of the uncommitted data, reattaches DuckDB and returns native counters to
zero. Reopen here is within one BEAM; the existing fresh-process/crash fixture is
separate coverage. These are controlled lifecycle overlaps, not precise barriers
inside every engine instruction or simultaneous index writers.

[Normal run 3](combined-hardening-3.log): three cases pass in 1.8 seconds, seed 0.
The initial sandbox attempt failed before tests because Mix's local TCP lock was
denied; run 2 passed before the stronger retained-cursor rebuild assertions were
added. None of those attempts is sanitizer evidence.

## Real NIF execution under ASan/UBSan

`scripts/candidate_beam.py` accepts `APHID_ASAN_RUNTIME`. It asks erlexec for its
expanded emulator arguments and launches `beam.smp` directly with ASan preloaded,
`ASAN_OPTIONS=halt_on_error=1:abort_on_error=1` and
`UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1`. Its existing 120-second process-group
watchdog kills and reaps an overrun. No diagnostic suppression or recovery
mode is enabled.

[Attempt 1](asan-public-combined-1.log) failed before tests: preloading erlexec did
not preserve the interceptor initialization through the BEAM exec. Direct BEAM
launch in [attempt 2](asan-public-combined-2.log) loaded the real Zig NIF, the
instrumented bridge and the instrumented engine, then found an engine defect.
Loader paths are retained in each log. The BEAM and Zig themselves are not
compiler-instrumented; the public API, resource callbacks and GC execute against
instrumented C++ code. OpenSSL/system code is also uninstrumented. ASan on this
host is not a proof of leak-free BEAM allocations.

The initial engine was the retained, previously verified atomic-FTS sanitizer
candidate, not the stale pre-promotion library under `_build/sanitizers-clt21`.
The current bridge was freshly compiled with Clang 21. The input audit records
hashes and confirms all 4,387 tracked source files match the retained TSan source
snapshot. The full builds use private copies with the first three candidate patches
and their own extension archives; the later two C++ fixes were rebuilt incrementally.
The sanitizer build reuses the unchanged instrumented DuckDB static
build and uninstrumented OpenSSL. See [input audit](hardening-input-audit-1.json)
and [fresh build recipe](hardening-asan-rebuild-1.py).

## Defects reproduced

1. FLOAT/DOUBLE sorting: `OrderByKeyEncoder::encodeData` dereferences the packed
   output buffer as a `uint32_t*`/`uint64_t*`. The null marker makes the address
   unaligned. The full combined workload aborts in double-distance sorting, and
   [the minimal value reproducer](asan-sort-reproducer-1.log) independently aborts
   at the same access. The candidate swaps/complements aligned local bits and
   copies the result into byte storage, preserving ordering.
2. INT128 addition: the existing minimum-value cast test aborts in
   `addInPlace` at `lhs.high + rhs.high + carry`, where the intermediate sum
   overflows although the carry brings the result into range. The negative-rhs
   branch now groups `rhs.high + carry` first. [First follow-up](asan-sort-candidate-1.log).
3. INT128 negation: extending the regression to minimum-plus-one exposed
   `-input.high - 1` overflowing before borrow handling. The candidate uses
   bitwise complement plus carry; the existing rejection of INT128_MIN remains.
   [Second follow-up](asan-hardening-candidate-1.log).
4. ALTER defaults: initializing the default evaluator dereferences a null
   `ResultSet*` for an operator with no input. The first rebuilt full suite
   [aborts here](asan-public-full-1.log); a new explicit/null-default regression
   [reproduces independently](asan-alter-reproducer-1.log). The fix supplies an
   empty result set, matching existing evaluator initialization elsewhere.
5. Graph path properties: the existing multi-edge graph-value regression
   [aborts](asan-public-full-2.log) on a packed tuple's `internalID_t` comparison
   in `PathPropertyProbe::probe`. The fix copies that ID into an aligned local,
   completing an access missed by the earlier join-row alignment patch.

A focused instrumented arithmetic executable checks 441 additions and 21
negations against compiler 128-bit arithmetic, including rejected overflow.
[Candidate arithmetic check](int128-boundaries-candidate-1.log) passes. This
links the changed implementation directly. The final executable uses the exported
addition/negation operators from the rebuilt shared library and passes in
[native run 2](asan-native-full-2.log). Run 1 failed to link private helper symbols;
the test was corrected to use the exported API. Both engine builds were rebuilt
from scratch after the inline negation-header change.

The existing native lifecycle and concurrent FTS/vector/DuckDB read checks also
pass under ASan/UBSan using the freshly instrumented bridge/test build:
[native run](asan-native-concurrency-1.log). This closes the previously unrun ASan
concurrent-read check for that retained engine only.

## Validation and remaining gates

| Check | Result and evidence |
|---|---|
| Full real-NIF ASan/UBSan suite | [99 passed, seed 0, 55.7 s](asan-public-full-3.log); no sanitizer diagnostic |
| Normal candidate suite | [99 passed, seed 0, 16.8 s](normal-public-full-1.log) |
| Source NIF compiled against promoted normal engine | [Compile passed](hardening-source-nif-1.log); [99 passed, seed 0, 16.5 s](normal-public-promoted-1.log) |
| Native normal suite | [Passed](normal-native-full-1.log): lifecycle, 441 additions/21 negations, hash/ALP/aggregate checks, concurrent extension reads, create and separate-process reopen |
| Native promoted ASan/UBSan suite | [Passed](asan-native-promoted-2.log), same native coverage with fatal diagnostics; DuckDB fixture creation uses the normal helper |
| Patch integrity | [All five apply/reverse exactly](hardening-patch-roundtrip-2.json); both private source trees match patched bytes |
| Final inputs | [4,387 tracked source files match both builds](hardening-final-inputs-1.json); all 1,157 engine/extension compile commands instrumented in ASan build, none in normal build; binary hashes retained |
| Linux command routing | [Passed](hardening-linux-routing-2.log); command capture only, no Linux runtime or sanitizer claim |

The failed second full ASan run also exposed fixture contamination after a prior
fatal VM exit, and a 15-second whole-test budget was too short for the existing
30-round stale-cancel stress test under instrumentation and concurrent compilation.
The runner now gives each VM a fresh temporary root, and that test alone has a
60-second wall-clock budget. Its per-operation assertions and product deadlines
are unchanged. Run 3 completes all 30 rounds; its maximum cancel-to-idle sample is
758,908 microseconds and scheduler heartbeat maximum gap is 6 ms. These are local
samples, not timing guarantees. The logged NIF upgrade rejection is an expected
test of the unloadable/upgrade boundary, not a sanitizer failure.

The first promoted native rerun passed lifecycle/arithmetic/alignment checks but
stopped because its fixture executable had not been built in that private output.
Run 2 uses the existing normal fixture creator, as the earlier native run did;
the engine, concurrency and feature tests remain instrumented.

Reproduce against the retained builds from `zig_library/`:

```sh
APHID_INSTALL=source MIX_BUILD_PATH=_build/hardening-beam \
APHID_CANDIDATE_DIR="$PWD/_build/hardening-asan/bridge:$PWD/_build/hardening-asan/ladybug/src" \
APHID_ASAN_RUNTIME=/Library/Developer/CommandLineTools/usr/lib/clang/21/lib/darwin/libclang_rt.asan_osx_dynamic.dylib \
python3 scripts/candidate_beam.py test --no-compile --no-deps-check --seed 0

APHID_INSTALL=source APHID_NATIVE_BUILD_ROOT="$PWD/_build/hardening-normal" \
MIX_BUILD_PATH=_build/hardening-beam MIX_ENV=test mix compile --force

APHID_INSTALL=source MIX_BUILD_PATH=_build/hardening-beam \
APHID_CANDIDATE_DIR="$PWD/_build/hardening-normal/bridge:$PWD/_build/hardening-normal/ladybug/src" \
python3 scripts/candidate_beam.py test --no-compile --no-deps-check --seed 0
```

Historical full rebuild recipes and logs are retained for
[ASan](hardening-asan-rebuild-1.py) and [normal](hardening-normal-rebuild-1.py).
They describe the then-candidate directory and baseline lock; after promotion,
use the locked [source installation workflow](../source-installation.md) for a
new build instead of replaying their old baseline assertion. The shared
`_build/native` engine was not overwritten. Published catalogs still identify
older immutable bundles, and cannot satisfy the new source lock by changing only
their checksum metadata. Rebuild and qualify new bundles before distributing
these fixes; no publishing or asset replacement was performed here.

No whole Stage 05/07 gate is closed. Linux sanitizers, TSan mutation/GC
coverage, instrumented Zig allocations, other targets and full release
qualification remain separate work. DuckDB's timeout still does not prove
cooperative interruption of its synchronous execution.
