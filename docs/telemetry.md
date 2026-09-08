# Telemetry

Aphid emits standard `:telemetry` events. Attach handlers with
`:telemetry.attach/4` or `:telemetry.attach_many/4`. Handlers run synchronously
in the emitting process: keep them short and offload I/O. A failing handler is
detached by telemetry. No handlers are installed by Aphid.

| Event | Measurements | Metadata and boundary |
|---|---|---|
| `[:aphid, :database, :open]` | `count: 1` | Observed `engine_version` and `extensions`; compile-time `library_version` and `lock_sha256`. Emitted after startup feature validation. |
| `[:aphid, :queue, :stop]` | `duration` | `kind: :query / :transaction / :stream`, `status: :dispatched / :cancelled`. From coordinator admission to dispatch or cancellation while queued. |
| `[:aphid, :execute, :stop]` | `duration` | Empty metadata. Time waiting for native query completion after submission, including scheduling delay. Covers eager queries and streams, including queries inside transactions and startup probes. |
| `[:aphid, :transfer, :stop]` | `duration` | Empty metadata. Each eager collect or stream batch fetch, including native conversion and BEAM result construction. |
| `[:aphid, :cancellation, :stop]` | `duration` | `kind`, and `status: :idle / :queued / :retired`. From the coordinator's first cancellation request until the worker has exited and native idle is observed; queued work has no native cleanup. `:retired` means the native session could not be reused and the database is closing. |

Durations use Erlang native time units. Convert with
`System.convert_time_unit(duration, :native, :microsecond)`. Queue timing excludes
time spent in the coordinator mailbox before admission. Execution timing excludes
submission, result transfer, and transaction commit/rollback controls. Transfer
timing excludes consumer processing and waiting between stream batches.

Cancellation timing is distinct from caller response latency. It also covers
owner death, database close, and early stream release. The `:retired` event is an
observation of retirement, not proof that database close has completed. Cancellation
of a transaction-local stream is part of its owning transaction's lifecycle.

Stop events are observations, not guaranteed accounting records: a killed worker
cannot emit its execution/transfer stop event, and a killed coordinator cannot
emit cancellation completion. There are no matching start events. Calls rejected
before admission do not emit a queue event.

Metadata contains no query text, parameters, database paths, result values, or
error messages. The lock digest identifies the declared build inputs compiled
into the Elixir module; it is not a runtime signature of a loaded native library.
Use the packaging manifest and artifact checksums to verify binaries.
