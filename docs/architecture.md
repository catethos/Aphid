# Native ownership and coordination

One database owns a fixed number of sessions; each session has one worker and
one connection. Queries never create threads. A session keeps its result until
it is explicitly released. The result is destroyed before the connection, and
all connections are destroyed before the database.

The bridge's process-wide runtime has a bounded intrusive retirement queue and
one cleanup thread. Resource destructors only request retirement and drop a
reference. The cleanup thread interrupts and joins workers, destroys the engine,
then releases the canonical path reservation. A timed-out close leaves the
native object quarantined; it is never freed while executing.

A second fixed controller thread repeats requested interrupts every millisecond
until the operation completes. This covers cancellation arriving just before
the engine resets its per-query interrupt flag. Neither service creates a
thread per operation. The runtime admits at most 64 databases, each with 1–64
sessions; these are explicit native resource ceilings. Native SQL inputs are
UTF-8 binaries limited to 1 MiB and paths to 4096 bytes, checked before copying.

Completion callbacks allocate an independent BEAM environment and send a
correlated operation-resource message. Each pending callback retains its
operation resource, which retains its database resource. Failed delivery still
releases these references and abandons the result. Native process monitors
cover owner death; ordinary OTP monitoring additionally covers queue/lease
ownership.

Zigler 0.16.0's resource helper has mismatched down/stop callback signature
checks in its source. Aphid uses the underlying `erl_nif` resource functions
through Zigler's raw-term support so ownership callbacks can follow the actual
OTP API without patching the dependency.

NIF live upgrade/unload is unsupported. An explicitly retained, fixed-size
anchor resource pins the callback code for the VM lifetime; it is part of the
runtime baseline, not a per-query allocation. Upgrade callbacks reject loading
replacement code. The fixed cleanup service may remain idle for the VM lifetime;
session workers are always joined. No detached query/cleanup threads are used.

The generated Zigler 0.16.0 loader logs a failed load but returns the logger's
`:ok`. Aphid replaces just that load function with a direct `load_nif` return,
so failed ABI/load/upgrade results fail the module's on-load callback.

Stage 02's isolated native and BEAM tests establish the initial lifecycle
contracts; sanitizer and full transactional races remain later gates.
Stage 01's dirty-CPU scoped feature proof is only an
acceptance harness and will not become a second public execution backend.

Stage 03 fetches take an exclusive native lease that retains the database and
prevents the worker from destroying the result/connection until conversion
ends. Finish, caller death and close can request cleanup concurrently; cleanup
waits for that lease. Heavy metadata/row release happens on the dirty caller
before the worker resumes. Values are inspected through opaque C views and
copied directly into BEAM terms. Recursive Zig conversion uses a finite error
set: Zigler 0.16.0 panics when its error handling inspects unrestricted anyerror.

Parameterized queries prepare and execute on the session worker. Parameter Values move into
preparation; the engine keeps the bound values. The result is destroyed before
its prepared statement, and both precede the connection. Native input factories
consume nested values and submission consumes its parameter collection even on
rejection, keeping partial-conversion cleanup explicit.

No-parameter queries use the engine's query API so internal expansions such as
FTS index creation can run. Single-user-statement validation happens before
either engine call; no failed query is retried. Parameter conversion starts only
after a native session reservation. Reservation IDs prevent a cancelled converter
from dispatching into a reused session, and the session count bounds concurrent
native input builds.

The public database GenServer owns the native database resource. A FIFO admission
queue holds at most the configured waiting request count; admitted queries use
one monitored BEAM runner per native session. The server monitors original
callers separately. Native work remains on fixed session threads. Absolute
deadlines start at API entry and govern queue wait, conversion, execution and
the final reply. On timeout/death the server kills the runner, whose resource-down
callback requests native cancellation. A slot is reusable only after both the
runner exits and the native session reports idle. Query arguments are dropped
from the coordinator once dispatched. This bounds admission count, not arbitrary
BEAM mailbox memory or the engine's materialized results.

Close disables admission and requests retirement immediately. Its successful
reply waits for native destruction and all runners to leave. The closed OTP
process remains under its supervisor. Native worker failure retires the database
instead of returning a dead session to the pool.

Native open distinguishes an active path reservation (code 2) from one belonging
to a retiring owner (code 6). The coordinator retries only the latter, with a
30-second bound and yielding sleeps. The reservation stays held through worker
joins and engine destruction; a fetch lease can delay that destruction. Canonical
path aliases participate in the same reservation. This is startup admission,
not a retry of any database query or write.

Transactions use the same admission queue and one callback runner per leased
session. A process-owned Zig resource retains the database and carries a fresh
native lease generation. Ordinary operations cannot reserve a leased session;
leased operations must match its generation. The callback runs in that runner,
so ordinary Erlang code, input conversion and result transfer share the same
killable execution scope. One additional BEAM monitor per transaction kills the
runner if the coordinator dies, even if callback code traps exits. The monitor
exits with the runner; native thread counts remain fixed.

Begin/commit/rollback execute on the native session worker. The pinned engine
returns to autocommit after a query error, so Aphid marks the lease failed and
rejects later reservations. Public query errors also mark callback scope failed,
preventing commit even if ignored. Lease release/down/GC requests cancellation
and worker-side rollback before clearing the generation. Fetch retention delays
that cleanup safely. Public exceptions are re-raised only after confirmed cleanup.

Before each transaction query, the runner synchronously registers the smaller
of its query deadline and overall transaction deadline with the coordinator.
Completion restores the overall deadline only if the previous phase has not
expired. Timer generations discard stale expiry messages. A pending commit has
an unknown outcome until acknowledged; timeout/close/worker failure cannot
silently label that outcome rolled back. The coordinator still waits for runner
exit and native idle before returning the session to admission.

Streams use the eager converter's fetch/metadata/value path. A native operation
keeps its result across demands; each NIF fetch obtains and releases an exclusive
cursor, encodes at most one row/byte-bounded batch, and preserves absolute row
positions. If the next row exceeds the remaining payload, one unread native row
is retained without copying it and replayed on the next demand. Partial BEAM
conversion remains bounded by that call's remaining payload. A row too large for
a fresh batch fails once; no retry loop can spin on it. Unread rows are destroyed
before result/statement/connection parents during finish, close or worker failure.

A regular stream's monitored worker waits between demands; it never prepares a
future BEAM batch. The coordinator monitors the enumerator, checks ownership and
keeps the session out of admission until worker exit/native idle. Early-release
acknowledgement waits for that state, including with queue capacity zero. Paused
workers also have the coordinator-death monitor used by transaction callbacks.
Transaction streams run directly in their callback process using its existing
lease, with the stream deadline registered as a transaction phase. Overlapping
work is rejected before it can replace that phase's deadline.

Logical payload is not total memory. Engine materialization and a current/unread
native row can exceed it. BEAM heap overhead, transient IPC copies, binary
references and GC behavior are measured separately in the Stage 06 evidence.
