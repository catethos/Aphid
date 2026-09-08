# Aphid

LadybugDB for Elixir, built with Zigler and a small C-compatible C++ bridge.
The name follows Ladybug's insect theme. `:aphid` and `Aphid` are local names;
package-name availability has not been claimed or reserved.

Implementation follows `../ZIG_IMPLEMENTATION_PLAN.md`. This is an early
development library: supervised queries, transactions and batch streams are
available; hardening and release gates are unfinished. See [the status ledger](docs/status.md).

## Query API

```elixir
{:ok, db} = Aphid.start_link(path: :memory)
{:ok, result} = Aphid.query(db, "RETURN $n AS answer", %{"n" => 42})
{:ok, [%{"answer" => 42}]} = Aphid.Result.to_maps(result)
{:ok, info} = Aphid.info(db)
:ok = Aphid.close(db)
```

Under a supervisor, use `{Aphid, path: "/data/graph", name: MyGraph}` as a child.
`close/2` closes native storage and leaves an addressable closed OTP process;
the supervisor still owns that process. Queries against it return `:closed`.
A concurrent close while another close is waiting returns `:closing`.
`info/1` reports the version and extension registrations observed at startup.
After an unexpected process exit, startup waits up to 30 seconds for the previous
native owner of the same canonical path to finish retiring. An active duplicate
owner fails immediately. A retirement timeout leaves the original owner
quarantined and returns `:retiring`; it never opens overlapping database owners.

The default session count is one and the FIFO wait queue holds 64 requests.
Queries default to a 30-second deadline, 10,000 rows and 8 MiB of logical result
payload. `timeout`, `max_rows` and `max_bytes` override those query settings.
`timeout: :infinity` keeps caller-death cleanup active. Timeout and transfer
errors do not imply that writes were rolled back. No query is retried.
The engine may materialize much more data than the transfer payload limit.

Use `%Aphid.Value{type: {:decimal, 38, 2}, value: 1230}` for exact `12.30`,
or a complete collection descriptor for empty/all-null inputs. See
[types.md](docs/types.md) for the full mapping. The runnable
`examples/basic.exs` is included in the test suite.

Indexed search examples are also executable tests:
[full-text search](examples/fts.exs) and [vector search](examples/vector.exs).
They use Cypher directly, including typed vector parameters. L2 returns
Euclidean distance; approximate search recall depends on the data and search
settings. Run index creation and removal outside explicit transactions.

`Aphid.start_link/1` accepts `buffer_pool_bytes` from 67,108,864 (64 MiB, the
default) to 1,073,741,824 (1 GiB). This is the engine buffer pool per database,
not a limit on total process memory or result payloads. Larger index builds can
require a larger explicit pool; choose it alongside the number of database
instances you run. The atomic FTS candidate's 300,000-document recovery fixture
requires 1 GiB on this host; that candidate is still undergoing hardening.

The [DuckDB example](examples/duckdb.exs) attaches a reproducible local fixture,
reads its rows, imports them into graph nodes, and detaches the source. Run
`python3 scripts/lifecycle.py` first to build its development-only fixture
generator; then run `MIX_ENV=test mix run examples/duckdb.exs`. Applications
attaching existing DuckDB files do not need the fixture generator.

## Transactions

```elixir
{:ok, :saved} = Aphid.transaction(db, fn tx ->
  {:ok, _} = Aphid.query(tx, "CREATE (:Item {id: $id})", %{"id" => 1})
  :saved
end)
```

Create the table first, as shown in the tested `examples/transaction.exs`.
The callback runs in a monitored process that owns one exclusive session.
Its mailbox and process dictionary belong to that worker; captured closure data
is available normally. Transaction tokens cannot be used from another process
or after their scope ends. Nested transactions and manual Cypher transaction
control are rejected.

A normal callback return commits and produces `{:ok, callback_result}`. Use
`Aphid.rollback(tx, reason)` to return `{:error, reason}` after rollback.
Returning an error tuple as a callback value still commits; explicit rollback
is the abort operation. A query error prevents commit even when the callback
ignores it. Callback exceptions are re-raised in the original caller after
rollback completes. Rollback covers database changes, not external callback
side effects.

The transaction's `timeout` defaults to 30 seconds and includes admission,
callback execution, every query, commit and cleanup. A query's own deadline can
shorten that budget; expiry aborts the whole callback. Timeout returns promptly
while native cleanup continues, and the session stays unavailable until cleanup
finishes. Error context reports `:pending_rollback` at that point. Query failures
returned after verified cleanup report `:rolled_back`. `:commit_unknown` means a
commit might have taken effect; a known commit followed by a cleanup timeout
reports `outcome: :committed`. Aphid never retries transaction operations.

## Streams

```elixir
total = Aphid.stream(db, "UNWIND range(1,1000) AS n RETURN n", %{}, batch_rows: 64)
|> Enum.reduce(0, fn %Aphid.Result{rows: rows}, total -> total + length(rows) end)
```

Construction validates options but does not acquire a session or execute Cypher.
Enumeration acquires the session and yields `%Aphid.Result{}` batches. Defaults
are `batch_rows: 256`, `batch_bytes: 1_048_576`, and `timeout: 30_000`.
The absolute timeout starts at `Aphid.stream/4` entry, including delay before
enumeration. An empty result yields one empty batch retaining column metadata.

Early halt and consumer exceptions release the result before returning; native
cleanup that exceeds the deadline stays quarantined. A paused continuation holds
its session and must be resumed or halted by its original enumerating process.
Caller death or database shutdown also releases it. Expiry while paused is
reported at the next demand. Each demand produces at most one batch; no later
BEAM batch is prefetched.

Streams inside `Aphid.transaction/3` use its existing lease. Finish or halt one
before issuing another query or stream on that token. Native stream errors
prevent commit even when caught. A transaction stream's deadline can shorten the
transaction budget and abort callback code. See the tested `examples/stream.exs`.

Batch limits measure logical transfer payload, not total memory. When a row
does not fit the remaining budget, one unread native row is retained for the
next demand. A row that cannot fit a fresh batch raises `:row_too_large`.
The engine can materialize the entire query result and use much more memory.
The [streaming measurements](docs/evidence/stage-06.md) report BEAM memory and
process RSS separately, including batch-size variation and eager collection.

## Build proofs

Prerequisites: Elixir 1.20 / OTP 29, Zig 0.16.0, CMake 3.20 or newer,
Ninja, Python 3.12 or newer, Git, and a C++20 compiler/macOS SDK. The currently
tested host is macOS 26.6 ARM64. All Mix dependencies are in `mix.lock`;
native revisions are in `native/lock.json`.

```sh
python3 scripts/build.py fetch
python3 scripts/build.py proof
python3 scripts/build.py openssl --jobs 3
python3 scripts/build.py engine --target aarch64-macos --mode Release --jobs 3
python3 scripts/features.py
python3 scripts/lifecycle.py
```

The proof runs C++ calls through Zigler, checks BEAM resource cleanup, compiles
against a local precompiled NIF with a rejecting Zig executable, and runs a
relocated consumer with no Zigler dependency. It produces a local NIF and checksum
under `artifacts/proof/`. This proof artifact contains no database engine.

For the opt-in checksum-verifying local archive adapter, see
[local precompiled installation](docs/local-installation.md) and its
[consumer/failure evidence](docs/evidence/local-bundle-installation.md). The fresh
consumer passes 92 tests without a native compiler. A configured
[relocated Mix release](docs/evidence/embedded-startup.md) also passes 92 tests and
embedded start/restart/shutdown/reopen with bundled ERTS.
Network delivery, source installation and the platform matrix
remain open. Bundled ERTS declares macOS 15.0; no release support is claimed.

Source builds are explicit. No release artifacts are downloaded or published.
The engine build is not yet an installation/support claim for any target.

The [value contract](docs/types.md) describes the full query/transaction/stream API.
The [telemetry contract](docs/telemetry.md) documents timing events and their privacy boundaries.
The [extension and upgrade guide](docs/extensions.md) covers index maintenance,
cancellation recovery, DuckDB scope, native crashes and reopen compatibility.
Current checks cover native
lifetime, typed inputs/results, required engine features and initial public
admission/transaction/stream/deadline behavior; they are not production certification.

The owner-selected license for Aphid's own source is [MIT](LICENSE). Dependency
licenses remain separate; see [third-party review boundaries](THIRD_PARTY.md).
The [local Hex package proof](docs/evidence/local-package.md) records a fresh
consumer passing all 92 tests from the exact unpublished source archive.
