# Stage 07 — feature acceptance and native hardening

In progress on macOS ARM64, 2026-09-07. This is not a release-support claim.

## Full-text search

`test/fts_test.exs` exercises the public query, stream and transaction APIs against
the locked engine's real FTS index. The deterministic corpus verifies two indexed
fields, accented Latin and Japanese/Chinese text, empty text and absent tokens.
Higher term frequency ranks first; equal documents have equal scores, with an
explicit ID sort resolving ties. One-row streaming returns the same ranking.

Committed inserts, updates and deletes maintain the index. Rolling back a
transaction that inserts, updates and deletes restores the prior search results.
Dropping an index inside an explicit transaction returns an engine error and the
wrapper reports `rolled_back`; ordinary auto-transaction drop and rebuild work.
Rebuild is `CALL DROP_FTS_INDEX('Document','words')` followed by
`CALL CREATE_FTS_INDEX('Document','words',['title','body'], stemmer := 'none')`.
Tests deliberately disable stemming to keep token expectations explicit.

`scripts/fts_persistence.py` runs three independent BEAM processes under external
60-second watchdogs, using a database path with spaces and Unicode. Creation
includes a populated index and an index on an empty table. The next process
reopens both, verifies Unicode/search state, updates and deletes populated rows,
and inserts into the formerly empty table. The third process confirms all changes
persisted and both indexes remain searchable.

Evidence:

- [Full regression](lifecycle-run-52.log): 78 BEAM tests and native lifecycle checks pass.
- [Fresh-process persistence](fts-persistence-run-1.log): create, mutate and verify
  all exit successfully.

## Vector index rollback defect (host fix verified)

The initial public vector tests establish empty-index insertion, L2 distances
0/5/12 for deliberately separated neighbors, invalid dimensions, FLOAT overflow
rejection and index reuse afterward. Ordinary insert/update/delete and rollback
of row changes passed in [run 53](lifecycle-run-53.log).

Unlike vector index creation, upstream vector index drop accepts explicit
transactions. [Run 54](lifecycle-run-54.log) demonstrates that dropping and rolling
back leaves search failing with `bad_optional_access`: the catalog rollback does
not restore the removed in-memory index. The suite intentionally failed on this.

`native/patches/vector-drop-auto-transaction.patch` guards only the public
DROP_VECTOR_INDEX binding with the existing `validateAutoTransaction` check.
The internal drop binding remains usable by the automatic transaction rewrite.
This prevents the demonstrated destructive rollback case without implementing
unproven transactional restoration. The patch and combined extension diff are
hashed in `native/lock.json`. [The rebuild](vector-drop-build-1.log) completed,
and [run 55](lifecycle-run-55.log) passed all 80 tests including rejection,
unchanged nearest neighbors, and ordinary drop/rebuild afterward. Applying the
patch independently to the locked source reproduces the working tree byte for
byte; the combined extension diff matches its lock hash. Historical bundle
artifacts predate this patch and still require rebuilding.

## Vector recall and persistence

`scripts/vector_persistence.py` runs three separate BEAMs under 120-second
watchdogs. It generates 1,000 three-dimensional points and 20 probes using
`:exsss` seed `{101,202,303}`. Coordinates are integers from 1 to 10,000 represented
as FLOAT, avoiding input-rounding differences with the brute-force oracle.
The real L2 index uses `efc=200`, and queries use `efs=200`, top-k=10. For this
low-dimensional uniform fixture, the acceptance floor is mean recall >=95% and
each probe >=80%, allowing approximate-search topology variation. Every returned
distance is independently checked against Euclidean distance within 0.01.

[Run 1](vector-persistence-run-1.log) achieved mean/minimum recall **100%/100%**
both before and after reopening in a fresh OS process. A separate empty-table
index also reopened successfully. A subsequent update, deletion and insertion
into the formerly empty table persisted into a third process, with expected
nearest neighbors and zero distances. This is fixture-specific acceptance
evidence, not a general accuracy guarantee or comparative performance benchmark.
This run used the pre-fix native binary while the drop-guard rebuild continued;
the fixture does not exercise index drops and must be rerun on the final artifact.

[Run 2](vector-persistence-run-2.log) on the rebuilt engine retained 100% recall
on the 20 probes but missed the relocated point in the final mutation check,
which had inadvertently used default search breadth. The fixture now directly
checks persisted row contents and uses its declared `efs=200` for that final
query too. [Run 3](vector-persistence-run-3.log) passes all three processes.
This observed default-setting miss is why the tests and documentation must not
promise exact top-k results for arbitrary indexed data, including after mutation.

## DuckDB exact values and repeated imports

`native/tests/fixture.cpp` now creates `exact_values` with the pinned DuckDB
runtime. `test/duckdb_test.exs` verifies both INT64 extrema, DECIMAL(20,4) raw
coefficients (including a coefficient larger than INT64), pre/post-epoch
microsecond timestamps, BLOB bytes including NUL/0xFF and empty BLOB, Unicode,
empty strings and nulls. All arrive through the documented Aphid value types
without test-side casts or rounding.

Three attach/query/stream/import/detach cycles use a path containing spaces and
Unicode. Each COPY imports into a fresh graph node table and compares every
value with the same oracle; each detach makes subsequent source queries fail.
[Run 56](lifecycle-run-56.log) passes all 81 BEAM tests plus native lifecycle
checks.

[Run 57](lifecycle-run-57.log) passes 82 tests, including repeated missing and
invalid file attachment failures followed by successful graph queries. Missing
files are not created, invalid files remain unchanged, and three successful
attach/import/detach cycles leave the complete DuckDB source file byte-identical.
This verifies nonmutation for the exercised read/import workflow; it does not
claim arbitrary cross-engine writes or atomicity.

[Run 58](lifecycle-run-58.log) passes 83 tests. The fixture's `hold` mode opens a
real DuckDB writer in a separate OS process and signals readiness only after
opening. Aphid attachment fails while that lock is held, ordinary queries still
work, and attachment/read/detach succeed after the writer exits. A pipe release
and observed process exit establish ordering without timing guesses. Close
during an active integration query remains acceptance work.

## Combined features and stale default database fix

`test/combined_features_test.exs` imports DuckDB records into graph nodes, adds
vectors and relationships, and builds real FTS/vector indexes. Text and vector
search results feed graph traversal; a third query joins DuckDB source IDs to
that same traversal. Ten rounds launch all three queries concurrently across
two sessions, checking the same expected node/topic pair. After detach, indexed
search and graph traversal must still work from the imported data.

[Run 59](lifecycle-run-59.log) reproduced an engine defect after detach:
`DatabaseManager::detachDatabase` removed the database but retained its name in
`defaultDatabase`. Graph pattern binding then tried to resolve the removed
alias and failed with `No database named localduck`. The narrow locked engine
patch `native/patches/detach-clear-default.patch` clears the default only when
its case-insensitive name matches the database being removed. Other defaults
are preserved; no attachment is silently selected as a replacement.

[The native rebuild](detach-default-build-1.log) and
[independent patch reproduction](detach-patch-check.log) passed.
[Run 60](lifecycle-run-60.log) passes 84 BEAM tests plus native lifecycle checks,
including the combined workload and post-detach traversal. Combined cancellation,
crash/reopen and packaged-target execution remain separate incomplete gates.

The combined crash/reopen case now passes in
[run 1](combined-reopen-run-1.log). `scripts/combined_reopen.py` creates committed
DuckDB-imported graph data with FTS/vector indexes and a relationship. A second
BEAM opens an explicit transaction, inserts a new indexed row and changes an
existing indexed title, then signals readiness while remaining inside the
uncommitted callback. The watchdog runner confirms that process is live, kills
its process group with SIGKILL and reaps it. A third BEAM verifies original
text/vector-to-graph traversal results, absence of the uncommitted row/token,
successful DuckDB reattachment/read/detach, and clean close. This is process-crash
recovery, not power-loss or torn-write testing.

## Shutdown with a DuckDB cursor

[Run 61](lifecycle-run-61.log) passes 85 tests. The DuckDB shutdown regression
suspends a stream after one of two rows, confirms native state 2 (a live result),
then closes the database. Native closure completes, resuming the old stream
raises `closed`, and a replacement database attaches and reads the same file.
This covers cleanup during partial result consumption; it does **not** establish
cancellation latency inside a long-running DuckDB execution or index build.

## Sanitizer build in progress

`scripts/sanitizers.py` builds separately under `_build/sanitizers` and then runs
native lifecycle, fixture, feature-create and fresh-process reopen checks with
external watchdogs. `scripts/build.py --sanitize` explicitly adds ASan and UBSan
to both C and C++ flags, disables sanitizer recovery and preserves frame pointers.
It refuses to overwrite the normal `_build/native` output. The sanitizer choice
is recorded in the build-input fingerprint. Actual generated DuckDB compile
commands include both instruments; instrumented engine/extension compilation
and runtime results remain to be checked.

[Run 1](sanitizers-run-1.log) compiled successfully but its lifecycle process
hit the 120-second watchdog before reaching tests. The first runner covers
C/C++ engine, DuckDB, FTS, vector and bridge/native tests. It reuses uninstrumented
OpenSSL and does not instrument BEAM or Zig. Full public-API execution against
the instrumented library and Zig resource/allocation checks remain additional
work. Any sanitizer diagnostic is a failure, regardless of assertion results.

[A live process sample](sanitizer-lifecycle-sample-1.txt) shows recursive ASan
initialization through the macOS allocator, spinning in `StaticSpinMutex` before
main. [A standalone probe](asan-runtime-probe-1.log) reproduces this with the
Xcode 17 runtime; substituting the newer runtime alone fails its compiler ABI
check. This is not evidence that Aphid passes sanitizers.

The already-installed CLT Clang 21 compiler works with an explicit
`/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` sysroot and its
`usr/include/c++/v1` headers. [Probe 4](asan-runtime-probe-4.log) compiles and
reaches main under ASan+UBSan. The intermediate probes 2/3 failed header discovery.
A full rebuild with this matched toolchain remains necessary; no system developer
selection was changed and no native test pass is claimed from the tiny probe.

[Run 2](sanitizers-run-2.log) now builds separately under
`_build/sanitizers-clt21`, using `native/cmake/sanitizer-clt21.cmake` for every
engine, DuckDB, bridge and native-test configure step. The toolchain path and
file SHA256 are recorded in `inputs.json`. Configuration and initial compilation
succeed; full compile/runtime checks are still in progress. The old run's
artifacts and diagnostic evidence are retained.

## Buffer-pool option validation

[Run 65](lifecycle-run-65.log) passes 89 tests. Public options enforce the
64 MiB–1 GiB range and preserve the 64 MiB default. Direct native calls also
reject zero, below-minimum, above-maximum and UINT64_MAX budgets, with native
resource counters remaining zero after every rejection. A valid minimum-size
open then executes a query and closes cleanly. The configurable bridge and NIF
are now in the working build; the atomic FTS engine patch remains isolated.

The atomic FTS patch still needs native hardening before promotion. Required
packaged targets remain unverified. See the later evidence below for telemetry.

## Telemetry verification (2026-09-07)

Added standard telemetry queue, execute, transfer, cancellation and startup
identity events. Execution and transfer metadata are empty; queue/cancellation
carry only operation kind and lifecycle status. Startup identity contains
observed engine version/extensions and compile-time library version/lock digest.
The exact timing boundaries and limitations are in [telemetry.md](../telemetry.md).

[Lifecycle run 67](lifecycle-run-67.log) passed native lifecycle checks and all
91 Elixir tests. The new test observes a real queued timeout and transaction
cancellation, checks cleanup after native idle, and verifies subsequent session
reuse. [Focused check](telemetry-focused-1.log) also passes with exact empty-map
assertions for execution/transfer metadata after a query containing a secret
parameter. No query text, parameter values, paths or error messages are emitted.

ASan/UBSan run 2 completed using matching Apple Clang 21 and its runtime and
found packed-row alignment errors. Candidate fixes pass the native lifecycle
suite but the feature workload exposed a further string-hash alignment error.
See the [investigation and rechecks](row-alignment.md). The full sanitizer gate
remains incomplete.

## Sanitizer gate completion and atomic-FTS promotion (2026-09-07)

[Sanitizer alignment run 14](sanitizers-alignment-14.log) rebuilt the
`_build/sanitizers-clt21` engine/extension objects from scratch with all seven
alignment/finalize candidate patches applied (row-value, string-hash, join-row,
ALP conversion range, aggregate-state, sort-key, node-delete-finalize) and
passed native lifecycle, the focused hash/ALP/aggregate regressions, and
required-extension create/reopen under ASan/UBSan fatal settings.

The isolated atomic-FTS sanitizer candidate was then reconstructed from those
freshly rebuilt objects with `scripts/fts_candidate.py` into
`_build/fts-candidate-sanitizers-clt21` and `-late`, deliberately not trusting
the previous candidate directories (built 17:35/17:36, before the 18:12
rebuild finished) or the shared upstream extension archives. Against the fresh
candidates, with `ASAN_OPTIONS=halt_on_error=1:abort_on_error=1` and
`UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1`:

- `fts_cancel_capacity` (1 GiB pool, 300,000 rows) passed in memory and persistent modes.
- `fts_failure_recovery oom` (the public OOM workflow that found the
  `SingleLabelNodeDeleteExecutor::finalize` UBSan defect) passed in memory and
  persistent modes — the `node-delete-finalize` fix holds under the same
  300,000-row fixture that previously aborted (compare
  `fts-sanitizer-oom-recovery-native-1.log`, exit -6, pre-fix).
- `fts_failure_recovery late-create` (injected late-registration failure)
  passed in memory and persistent modes against the `-late` candidate.
- `fts_failure_recovery late-verify` passed against the plain sanitizer engine
  build in a fresh process, confirming the rebuilt index persists correctly.

All seven runs are recorded in
[fts-sanitizer-candidate-checks-clt21-1.log](fts-sanitizer-candidate-checks-clt21-1.log).

Each of the eight candidate patches (the seven above plus `fts-atomic-create`)
was verified to reverse-apply cleanly against the then-current source, and a
full revert/reapply round-trip left the working tree byte-identical (`git diff`
before and after matched exactly). `fts-atomic-create.patch` additionally
applied cleanly to the previously untouched extensions checkout.

With sanitizer verification complete, `fts-atomic-create.patch` was applied to
`native/upstream/ladybug/extension/fts/src/function/create_fts_index.cpp` for
real (no injection). All eight patches were promoted from
`native/patches/candidates/` to `native/patches/`, and `native/lock.json` now
records their hashes, reasons, and the recomputed combined
`patched_diff_sha256` for both `engine` and `extensions` (verified by replaying
the exact check `scripts/build.py` performs at fetch time). The DuckDB pin
(`1.4.4`, commit `6ddac802ffa9bcfbcc3f5f0d71de5dff9b0bc250`) is unchanged.

The normal (non-sanitizer) engine was then rebuilt from scratch: the shared
`native/upstream/ladybug/extension/{fts,vector,duckdb}/build` archives (last
written by the sanitizer rebuild) and the stale `_build/native/ladybug` output
(last built before any of today's patches) were removed, then
`scripts/build.py engine --output _build/native` ran with no `--toolchain`
override (plain Apple Clang 17, matching `_build/native/inputs.json`'s prior
toolchain identity). The rebuilt shared extension archives are markedly smaller
than their sanitizer counterparts (e.g. `libfts_static.lbug_extension` 2.4 MiB
vs 7.9 MiB), confirming no ASan/UBSan instrumentation leaked into the normal
engine.

Against the rebuilt normal engine and bridge:

- [`lifecycle-run-68.log`](lifecycle-run-68.log): native lifecycle checks pass;
  91 Elixir tests pass under `scripts/lifecycle.py`'s single-ordinary-scheduler
  configuration.
- [`mix-test-normal-scheduler-1.log`](mix-test-normal-scheduler-1.log): the
  same 91 tests pass under default (unconstrained) scheduler concurrency.
- [`fts-persistence-run-2.log`](fts-persistence-run-2.log): create/mutate/verify
  FTS persistence across three independent BEAM processes passes.
- [`fts-cancel-run-3.log`](fts-cancel-run-3.log): the original public
  cancellation workflow (the defect `fts-atomic-create.patch` was written for)
  now passes in memory and on disk against the production build — cancel
  response ~101-102 ms, native idle ~103-104 ms, source rows intact, same-name
  rebuild/query/drop succeed.
- [`fts-oom-recovery-run-1.log`](fts-oom-recovery-run-1.log): the buffer-pool
  exhaustion workflow that originally found the node-delete-finalize defect
  passes against the production build (no crash on the subsequent ordinary
  `DELETE`).

No separate BEAM-level "late-failure" check was run against production: the
injected fault only ever existed in the isolated sanitizer/candidate builds
(`scripts/fts_candidate.py --late-failure`), never in shipped source, so there
is nothing to inject in the rebuilt normal engine. The production-realistic
analogue — a genuine external interruption of `CREATE_FTS_INDEX` — is exactly
what `fts-cancel-run-3.log` exercises. Native-level injected-failure coverage
of the real defect class remains in the sanitizer evidence above.

**Still outstanding before Stage 07's gate can be marked complete:** TSan race
auditing, Linux ARM64 cross-build/runtime, the required target matrix, and
release packaging (Stage 08/09). This work does not close Stage 07 or the
broader implementation plan.

## Focused TSan host audit, with address-space limit

See [`tsan.md`](tsan.md) for the runtime probes, isolated source/build recipe,
instrumentation checks, exact coverage limits and Linux runner inventory.
Clang 21 runs a clean threaded probe and detects an intentional race;
symbolization requires execution outside the sandbox. The expanded native
lifecycle test passes against the normal engine, including 30 gated
stale-cancel/reuse and simultaneous lease-contention rounds.

The instrumented engine/extension/bridge build succeeded after retaining both
static and shared Ladybug targets. The default 8 TiB mapping fails under this
host's TSan runtime, independently reproduced with a minimal mmap probe.
Using a test-executable-only 1 GiB address range, all native lifecycle checks
passed without TSan diagnostics in 6.677 seconds under a 120-second watchdog
([run 6](tsan-lifecycle-6.log)). Binary hashes, TSan symbol imports and isolated
runtime linkage are recorded in [link checks](tsan-link-checks-1.log).

This covers the selected C++ lifecycle paths, not actual BEAM/Zig GC callbacks,
all extension concurrency, or the production default address range under TSan.
OpenSSL and system libraries are uninstrumented. A later full-runner retry
was interrupted during dependency rebuilding; its objects must not be used
for candidate reconstruction without completing that build. No new engine
patch is promoted, DuckDB remains 1.4.4, and no stage is marked complete.

Final normal regression: [native lifecycle plus all 91 BEAM tests pass](tsan-normal-regression-1.log),
seed 0, under the existing lifecycle watchdog runner. The test address-range
override is absent from the normal build. Linux remains unattempted; runner
discovery found a stopped local ARM64 Colima instance, with no established
x86_64 Linux build host. See the scoped runner requirements in `tsan.md`.

## Continued hardening and host packaging, 2026-09-07

The interrupted isolated build is now resolved by [TSan invocation 8](tsan-run-8.log):
full scheduled dependency/engine/extension work completed and the freshly linked
lifecycle executable passed without diagnostics (11.060 s). A new gated workload
runs 100 reads per connection across FTS, vector and DuckDB on one shared database;
[its TSan run](tsan-extension-concurrency-1.log) passes without diagnostics in
3.389 s. Normal and extracted/offline packaged runs also pass. See [TSan evidence](tsan.md)
for source/flag/binary hashes and the unchanged test-only address-space limit.
This broadens concurrent-read evidence; it does not establish concurrent mutation,
all interrupt timings, actual Zig/BEAM GC instrumentation, or Linux support.

The queued public-query caller-death regression passes, and all **92 BEAM tests**
plus native lifecycle/concurrent-extension reads pass from the current local
runtime bundle with networking and development-directory reads denied
([Stage 08](stage-08.md)). Packaging uncovered a macOS floor mismatch: both NIFs
require 26.6, even though native bridge/engine load commands specify 13.3.
No engine or production behavior changes were made, the native lock is unchanged,
DuckDB remains 1.4.4, and no stage is marked complete.
