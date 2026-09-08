# Stage 05 cancellation checkpoint

This stage remains incomplete. Core query/transaction deadlines, operation-scoped
cancel and native cleanup are implemented. Forced actual-commit uncertainty,
long FTS/vector/index/DuckDB cancellation and broader timing observations remain
required. Streams will add their own demand/transfer boundaries in Stage 06.

The absolute monotonic deadline starts at public API entry. The coordinator
enforces it through queueing, parameter conversion, native execution, result
conversion and final delivery. Transaction callbacks run in a killable worker;
each query can shorten the overall deadline. Generation-tagged timer messages
cannot expire a replacement phase. A timeout response does not release native
admission: both worker death and native idle must be observed first.

Earlier native tests and Stage 02 source/lifetime analysis establish concurrent
interrupts on retained connections, including the engine's interrupt-reset race.
The fixed controller repeats cancellation until execution ends; the fixed cleanup
service joins workers before destroying connections/database. Exclusive fetch
leases block result destruction while conversion reads it. This is focused
ownership/race evidence, not ASan/TSan coverage of the engine or extensions.

`lifecycle-run-46.log` passes 59 BEAM tests and all native checks. Thirty real
long-running queries are cancelled, cleaned up, and immediately followed by a
parameterized query while another BEAM process issues 100 stale cancels. Every
following result is correct. Maximum observed cancel-to-native-idle time is
91,021 microseconds on this host; this is a sample, not a latency guarantee.

A separate BEAM case submits a 500,000-element result and observes its exclusive
fetch active through an operation-correlated, nonblocking diagnostic snapshot.
It then kills the owner, waits for native idle, verifies the old operation no
longer reports transfer, and successfully executes/collects a following query.
The native deterministic held-fetch tests separately establish close/release
safety during transfer. Previous cases cover death during parameter conversion,
queueing, execution and transaction callback ownership.

The expanded ExUnit suite takes 9.6 seconds (15.537 seconds including recompilation
and Mix). Its ordinary-scheduler heartbeat records 30 samples, maximum gap 6 ms.
Memory/RSS scaling, detailed cancellation observations and the full extension
workload matrix have not yet been measured.

## Long FTS build cancellation — incomplete recovery

`scripts/fts_cancel.py` starts a separate watchdog-bounded BEAM, loads 300,000
documents, observes native execution state, and applies a 100 ms public deadline
to CREATE_FTS_INDEX. [Run 1](fts-cancel-run-1.log) returned timeout at 101 ms and
observed native idle at 105 ms; all source rows remained intact. These are single
host observations during concurrent sanitizer compilation, not latency promises.

The stronger [run 2](fts-cancel-run-2.log) then attempted same-name index creation
and failed: `0_words_appears_info already exists`. Cancellation leaves an internal
FTS table behind. The regression intentionally remains failing until this cleanup
defect is fixed; a prompt timeout/native-idle result alone is not a passing gate.
The fixture also requires successful rebuilt-index querying and drop once the
cleanup problem is resolved. No automatic retry or user-table deletion was added.

Root-cause inspection: `createFTSIndexQuery` emits independently committed
CREATE/COPY statements, with an upstream comment saying COPY cannot run inside
a manual transaction. The selected engine no longer rejects that operation:
`scripts/copy_transaction_probe.exs` verifies a 1,000-row COPY is visible inside
the transaction, disappears after rollback, and persists after commit.
[Probe evidence](copy-transaction-probe-1.log) passes. This establishes a possible
atomic-build prerequisite, not a completed FTS fix. `_CREATE_FTS_INDEX` also
explicitly checkpoints internal tables on persistent databases and registers an
in-memory index; those effects must be audited for rollback before wrapping the
whole build in a transaction. A BEGIN/COMMIT-only patch is not yet justified.

The same leftover-table failure is now reproduced on disk in
[persistent run 2](fts-cancel-persistent-run-2.log), after confirming the source
row count remains 300,000. The fixture accepts an optional database path and
loads ten committed 30,000-row batches. The earlier single-transaction persistent
setup hit the buffer-pool limit before cancellation began
([run 1](fts-cancel-persistent-run-1.log)); it is not cancellation evidence.
The runner now includes both memory and persistent variants, stopping on failure.

## Long vector-index build cancellation

`scripts/vector_cancel.py` runs memory and persistent cases in separate BEAMs
under 120-second external watchdogs. The fixture loads 30,000 three-dimensional
vectors in ten committed batches, observes native execution, and applies a
100 ms public timeout to CREATE_VECTOR_INDEX. It then requires native idle,
checks the intact source count, rebuilds the same index name, verifies the
expected nearest node and zero L2 distance at `efs=200`, and drops the index.
The explicit buffer pool is 1 GiB.

[Run 1](vector-cancel-run-1.log) passes both cases. Timeout response was 101 ms
for each; native idle was observed at 562 ms (memory) and 511 ms (disk). This
distinguishes prompt caller response from later cleanup and session reuse.
Measurements were collected during concurrent sanitizer compilation and are
samples, not deadlines guaranteed for every engine phase or workload.

## Expensive DuckDB execution timeout

The pinned fixture generator's separate `slow` mode creates a view computing
`sum(sin(i::DOUBLE))` over 100 million generated rows. `scripts/duckdb_cancel.py`
attaches that fixture, observes native execution, applies a 100 ms public timeout,
waits for native idle, then verifies query reuse, detach and close. This exercises
execution through the integration, not a paused result cursor.

[Run 2](duckdb-cancel-run-2.log) passes: caller response at 101 ms, native idle at
797 ms. The connector performs a synchronous DuckDB `Connection::Query`; this
test does not establish that Aphid's Ladybug interrupt aborts that embedded
calculation. Native work may finish before the slot can be reused. Preserve this
distinction when describing timeout guarantees. Run 1 was a fixture compilation
error, corrected by using the QueryResult base type for the result chain.

## Actual commit followed by missing completion

`test/commit_outcome_test.exs` deliberately drives the same internal phase/control
boundary used by the transaction worker: after an ordinary transactional insert,
it marks commit in progress, executes native commit and observes its successful
callback, then withholds the worker's committed notification until the public
deadline expires. This uses a real engine commit, not a fabricated result.
The API must return `commit_unknown` with outcome `unknown`; after close and
reopen, the committed row must exist. [Run 66](lifecycle-run-66.log) passes this
case and all 90 BEAM tests plus native lifecycle checks. The test uses internal
controls to hold this otherwise narrow window; it adds no production fault hook
and does not claim coverage of every filesystem/commit failure phase.

## Remaining-boundary assessment and queued write death, 2026-09-07

The early unchecked descriptions above are historical. Later evidence establishes
actual commit-unknown persistence, vector build cancellation, delayed DuckDB
completion and the promoted atomic-FTS fix (Stage 07). Existing native/BEAM tests
cover submission abandonment, execution death, observed transfer death,
transaction callback/lease death and streaming owner death. They do not establish
every instruction-level race window or instrument actual BEAM/Zig GC with TSan.

`test/queued_caller_death_test.exs` closes a specific missing public-query case:
a transaction callback holds the only session behind a message gate; an observed
queued CREATE caller is killed; the queue empties before releasing the callback.
Successful same-name CREATE afterward proves the dead caller's write did not run,
and a following query verifies reuse. No production hook or engine change was
needed. [Focused run 1](queued-caller-death-1.log) passes (one test, seed 0,
2.885 seconds process time); [packaged run 3](runtime-bundle-3.log) includes this
case in all 92 passing tests under offline/development-directory denial.

Combined-feature cancellation, broader mutation/cancellation timing, instrumented
Zig/BEAM boundaries and required-target execution remain acceptance gates. DuckDB
caller timeout must continue to be distinguished from native completion; the
existing slow-query observation does not prove embedded DuckDB interruption.
No Stage 05 checkbox or stage status is marked complete.
