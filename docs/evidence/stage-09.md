# Stage 09 — local host comparison baseline

In progress, 2026-09-07; no stage or release completion is claimed.

`scripts/benchmark.py --output docs/evidence/benchmark-host-N` runs standalone
C++ followed by Aphid with the same generated setup statements and case file.
Both use an in-memory database, a 64 MiB buffer pool, two engine threads and one
connection/session. Aphid uses one ordinary and one dirty CPU scheduler. The
fixture is created by the normal pinned DuckDB 1.4.4 executable.

Cases: scalar RETURN; 1,000 two-column rows; a 10,000-integer list; FTS top ten
from 1,000 identical documents with explicit ID sorting and no stemmer; vector
top ten over `[i,i,i]` with L2 and `efc=efs=200`; and a two-row DuckDB read.
Each case gets 20 warmups and 100 measured calls. Returned row counts are checked.
The setup and exact queries, raw microsecond samples and summary are retained.
This is a small baseline fixture, not the larger scan/recall/mixed workload gate.

C++ copies each returned typed value (including child values) into owned storage
through the end of collection. Aphid materializes its public BEAM result. Those
representations and their allocation costs differ by design. Measurements include
query execution and eager collection, excluding setup/warmups. Reported throughput
is `1e6 / mean(service time in microseconds)`, not an arrival-driven concurrent
load measurement. Percentiles use nearest rank (50th/95th/99th of 100 samples).

`/usr/bin/time -l` records process high-water RSS, including setup and runtime
startup; Aphid also records total BEAM memory after each case, not peak BEAM
memory. Aphid runs with `mix run --no-compile`, so process memory includes Mix.
The benchmark does not separate engine RSS from allocator/VM overhead.

[Build attempt 1](benchmark-build-1.log) compiled the harness but macOS resource
inspection by `time -l` was denied; exit 1 is not successful measurement evidence.
[Build attempt 2](benchmark-build-2.log) repeats outside the sandbox and succeeds
in 1.604 seconds using Apple Clang 17, C++20, `-O3 -DNDEBUG`, ARM64 and deployment
target 13.3. This measures only the harness compile/link, **not** a clean native
engine build. Normal engine input/flags remain those of Stage 07's verified
production build. The NIF load-command floor is 26.6 (Stage 08).

Results below were collected after the independent TSan compilation finished.
They are baseline observations, not a performance acceptance pass. Remaining benchmark gates include
mixed concurrency, larger/nested transfer scaling, larger DuckDB scans,
vector recall with latency, cancellation response/completion distributions,
run-order effects and complete clean build costs. The [release checklist](../release-checklist.md)
tracks local packaging, licensing and target-support gates.

## First host measurements

[Run 1](benchmark-host-1.log) completed after the isolated TSan build and runtime checks stopped.
Host: Apple M2 (Mac14,15), eight CPUs, 8 GiB RAM, macOS 26.6, Elixir 1.20.0 / OTP 29.0.4.
[Host identity and input hashes](benchmark-host-identity-1.log) and
[machine-readable summary](benchmark-host-1/summary.json) are retained alongside
[C++ raw samples/RSS](benchmark-host-1/cpp.log) and [Aphid raw samples/RSS](benchmark-host-1/aphid.log).
The CMake-managed harness build succeeded in 1.547 s before sampling. No instrumented binary is used.

| Case | Runtime | p50 µs | p95 µs | p99 µs | Service-time QPS |
|---|---|---:|---:|---:|---:|
| small | cpp | 42.5 | 51.9 | 63.8 | 22563.8 |
| small | aphid | 5999.1 | 6555.7 | 6740.9 | 166.6 |
| rows | cpp | 328.5 | 367.1 | 381.7 | 2991.3 |
| rows | aphid | 6002.5 | 6358.5 | 6457.1 | 166.7 |
| nested | cpp | 3307.7 | 3418.1 | 3435.8 | 300.7 |
| nested | aphid | 11974.5 | 12702.0 | 25364.2 | 79.4 |
| fts | cpp | 955.0 | 1005.2 | 1049.2 | 1040.1 |
| fts | aphid | 5991.0 | 6520.9 | 6715.0 | 166.5 |
| vector | cpp | 604.2 | 662.6 | 687.5 | 1626.9 |
| vector | aphid | 5955.1 | 6707.7 | 6977.1 | 166.9 |
| duckdb | cpp | 220.0 | 266.8 | 288.5 | 4393.1 |
| duckdb | aphid | 5967.0 | 7174.7 | 7823.5 | 166.7 |

Process peak RSS: C++ **139,755,520 bytes** (133.3 MiB); Aphid **229,654,528 bytes** (219.0 MiB).
Aphid post-case total BEAM memory ranged from 60,217,082 to 63,464,997 bytes.
The direct harness build measured 227,442,688 bytes maximum resident set size;
none of these numbers establishes clean engine-build peak memory.

The approximately 6 ms Aphid median on five small cases is an observed overhead,
not a performance pass. Code inspection finds a 5 ms coordinator cleanup poll
in `lib/aphid/database.ex` (`schedule/1` and `handle_info(:poll, ...)`), which may
delay session reuse between sequential calls. This is a hypothesis, not a
measured causal attribution; no production timing/lifecycle behavior was changed.
Before optimizing, isolate queue/reuse time from execute/transfer telemetry and
preserve the quarantine/actual-completion safety requirements.

These are one host/run, fixed C++-first order and only 100 samples per case.
The machine was not a dedicated idle performance runner. Vector topology is
approximate, and row-count assertions do not measure recall. No cross-target,
general latency guarantee, mixed-concurrency throughput or complete Stage 09
claim follows from these observations.
