# Stage 06 host stream and memory gate

`lifecycle-run-51.log` passes all native checks and 76 BEAM tests. ExUnit takes
10.0 seconds (10.412 seconds including Mix). This establishes the host core
stream gate; it does not establish sanitizer coverage, the complete extension
matrix or release support on any target.

## Behavior and ownership

`Aphid.stream/4` builds a lazy standard Elixir Stream. It validates options at
construction and acquires/executes at enumeration. The absolute timeout starts
at API entry, including time before enumeration. Batches default to 256 rows and
1 MiB of defined logical payload. Empty results produce one empty batch retaining
metadata. Stream enumeration raises structured `Aphid.Error` failures.

Native batch and eager conversion share cursor, metadata and value encoding.
Tests cover ordered row boundaries, byte boundaries, typed empty results,
oversized-row rejection with absolute row context, foreign fetch rejection,
early release and partial nested-row conversion. A candidate row that does not
fit is retained once natively and replayed whole on the next call; tests prove
no lost/duplicated rows or partially delivered nested values. Other conversion
errors reject the current batch. Eager total payload overflow remains explicit.

Public cases prove construction performs no query, early halt permits an
immediate following query even with queue capacity zero, and a suspended worker
waits without producing another BEAM batch. Foreign continuation use fails
without advancing/releasing the owner's result. Completion, halt, consumer
exceptions, caller death, database close and paused expiry release native work.
Transaction streams reuse their lease, permit another query after halt, roll
back after caught conversion errors, and abort consumer code on deadline.
An overlap cannot replace the active stream's deadline. `examples/stream.exs`
executes as part of the suite.

## Isolated memory measurements

`python3 scripts/stream_memory.py` runs eight fresh BEAM processes, each under a
120-second process-group watchdog. Raw output is in `stream-memory-1.log` through
`stream-memory-8.log`; structured results are in `stream-memory.json`.
The workload emits INT64 plus a 128-byte string, counts/discards streamed rows,
and compares eager collection of the same values. It warms a small stream and
collects garbage before establishing each BEAM baseline. A BEAM sampler observes
total/process/binary/caller memory about every 10 ms; a separate Python process
samples RSS and `/usr/bin/time` reports whole-process peak RSS.

Host: Apple M2, Mac14,15, 8 GiB RAM, macOS 26.6 ARM64. Engine 0.20.2, Release
native build, one session, two engine execution threads, one online ordinary
and one online dirty CPU scheduler. The original requested `+SDcpu 4` is clamped
to one by `+S 1:1`; actual counts are recorded in each case and in
`scheduler-check.log`. Runners now request the effective `+SDcpu 1:1` explicitly.

| Mode | Rows | Batch rows | Batch byte cap | Peak BEAM growth over baseline | Whole-process peak RSS |
|---|---:|---:|---:|---:|---:|
| Stream | 10,000 | 256 | 1 MiB | 0.935 MiB | 107.91 MiB |
| Stream | 100,000 | 256 | 1 MiB | 0.989 MiB | 109.34 MiB |
| Stream | 500,000 | 256 | 1 MiB | 1.058 MiB | 117.17 MiB |
| Stream | 100,000 | 32 | 1 MiB | 0.250 MiB | 108.98 MiB |
| Stream | 100,000 | 2,048 | 1 MiB | 5.245 MiB | 111.88 MiB |
| Stream | 100,000 | 4,096 | 8 KiB | 0.310 MiB | 108.81 MiB |
| Stream | 100,000 | 4,096 | 64 KiB | 1.607 MiB | 109.41 MiB |
| Eager | 100,000 | — | 64 MiB eager cap | 50.289 MiB | 185.20 MiB |

At fixed batch size, a 50-fold row-count increase does not produce corresponding
BEAM growth. Increasing row/byte batch limits increases observed BEAM overhead;
eager collection retains substantially more. RSS grows independently because
the engine may materialize the full result. These are measured samples for this
row shape and runtime, not exact heap bounds or performance guarantees.

The 10,000-row case lasts only 18 ms and has two RSS samples; sampled peaks may
miss short transients. OS-reported peak RSS includes VM startup and warm-up,
while reported BEAM growth uses the post-warm-up baseline. Current/unread native
rows and engine materialization are outside the logical transfer cap. Larger
or differently nested rows can change overhead. Every case verifies all rows
were consumed and native database/worker counts return to zero on close.
