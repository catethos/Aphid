# Stage 04 admission and restart checkpoint

The host admission/transaction gate passed at run 45. Earlier checkpoints below
record implementation order; the final section describes the completed public
surface. Cancellation hardening, streams, sanitizers and release targets remain
separate, incomplete gates.

The public coordinator implements a FIFO wait queue, configured sessions and
queue capacity, caller and runner monitors, and absolute query deadlines. Tests
cover overload, queued expiry, executing expiry, caller death, close during work,
and native retirement disabling admission. Native sessions are not reused until
the runner is down and native cleanup has reached idle.

`lifecycle-run-31.log` passes 40 BEAM tests and native tests. Five forced kills
of a supervised persistent database process each produce a distinct replacement
that reads the previously committed row. Final shutdown reaches zero native
databases and workers. `lifecycle-run-34.log` retains these checks within the
expanded 43-test suite.

The native test deterministically holds an exclusive fetch lease across database
release. Opening the active path first returns code 2; opening an alias while
retirement is held returns code 6. Releasing the fetch permits joined cleanup
and a successful fresh open. This proves path reservations survive real native
retirement rather than relying on a sleep to make cleanup win the race.

Public startup now waits, yielding between attempts, for code 6 only, up to
30 seconds. It does not wait on an active duplicate or erase a reservation on
timeout. The native quarantine remains authoritative. The 30-second exhaustion
branch is not yet exercised with a deliberately stalled engine; this checkpoint
does not prove transactional recovery, crash consistency or all shutdown races.

## Native transaction foundation

`lifecycle-run-35.log` proves the pinned engine's transaction behavior with two
connections: uncommitted writes remain invisible, commit makes them visible,
rollback and connection destruction discard them. A duplicate-key execution
error rolls back earlier writes, and a later ordinary query can autocommit.
This agrees with `ClientContext::TransactionHelper::runFuncInTransaction` and
`TransactionContext`'s documented return to AUTO mode. Aphid must not let an
ignored error silently turn the rest of a transaction callback into autocommits.

`lifecycle-run-36.log` passes the new native lease/control tests and all 43 BEAM
regressions. A fresh generation reserves an idle session exclusively; ordinary
and foreign-generation reservations fail while leased. Begin/commit/rollback
run on the existing session worker through the engine TransactionContext.
An engine error marks the lease failed, and subsequent reservations fail.
Queries after commit/rollback cannot implicitly start an autocommit transaction.
Release requests cancellation and performs rollback on the worker before clearing
the generation and reporting idle. A rollback exception retires that worker.
Stale release cannot affect a newly acquired lease. Tests cover confirmed commit,
explicit rollback, abandonment rollback, duplicate-key failure, nested begin,
post-commit rejection and reuse after cleanup.

These are private C ABI primitives. The Zig lease resource, process ownership,
public callback API, end-to-end transaction deadlines and commit-uncertainty
reporting are not wired yet. The public API still has no transaction call; this
native checkpoint must not be presented as a completed Stage 04 gate.

Run 37 additionally releases a lease during a still-running cross-product query
after an uncommitted insert. Interruption and rollback finish before idle and the
insert remains absent. Another case holds a native fetch while releasing the
lease: a new acquisition is rejected, the old row remains safely readable, and
only fetch-end permits rollback and idle. These deterministic cases exercise the
new lease cleanup path with real native execution and result retention.

## Public transaction gate

Runs 38–45 connect the native lease to a monitored Zig resource and public
`Aphid.transaction/3`, `query/4` and `rollback/2`. Run 45 passes 57 BEAM tests and
the standalone native suite. ExUnit takes 5.9 seconds; the heartbeat remains
30 samples with a maximum 6 ms gap. `examples/transaction.exs` executes in the
suite and demonstrates committed and explicitly rolled-back writes.

Callbacks run in a monitored BEAM worker that owns the native lease. They share
the bounded queue with queries. The original caller and worker are monitored
separately; callback/process-dictionary state does not run in the original
caller. The lease resource monitors its own process, retains its database, and
checks owner identity before query/control/release. Native generations independently
reject stale handles. Tests cover foreign processes, stale generations, owner
death while idle/executing, and resource GC while its owner remains alive.

Public cases prove commit, explicit rollback, exception re-raise after rollback,
query errors that remain fatal even if ignored, manual-control rejection, nested
transaction rejection, and a caught rollback that cannot resume writes. Two
sessions show that unrelated reads cannot see uncommitted data. Single-session
contention covers queue overload, queued expiry/death, and exclusive reservation
between callback queries. Old timer-generation messages cannot cancel a later
phase. Transaction and individual query deadlines abort callbacks and release
sessions only after actual native cleanup.

Run 40 exposes an orphaned callback after its database coordinator is killed.
Run 41 adds one bounded monitor process per transaction; it kills the callback
on coordinator death even when callback code traps exits. A persistent test now
commits id 42 in a transaction, interrupts a second transaction after its insert,
and forces supervisor restart. The replacement reads only id 42. No query,
write or commit is retried.

Run 42's GC fixture dropped its token before its own helper finished waiting for
the leased-idle state, allowing GC to release the lease earlier than the test
expected. The corrected fixture keeps the token live through the query, then
drops it and explicitly collects garbage; run 43 passes. This was a fixture
liveness assumption, not a production cleanup failure.

Explicit rollback returns the supplied reason unchanged. Native query errors
returned after cleanup carry `outcome: :rolled_back`; pending cleanup on timeout
carries `:pending_rollback`. Accepted commit failures remain `:commit_unknown`,
and known commits followed by cleanup failure retain `:committed`. The reporting
paths exist, but forced failures during actual commit and long extension
cancellation are still Stage 05/07 verification work, not proved by this gate.
