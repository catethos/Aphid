# Graph algorithms, indexed search and DuckDB

Source builds bundle `algo`, `fts`, `vector`, and `duckdb` into the engine and check
all four at database startup. The published archives through `0.1.1-dev` still contain
only FTS/vector/DuckDB; ALGO requires the updated source build until new platform
bundles are released.
`Aphid.info/1` reports the observed registration and engine version. Queries use
the engine's Cypher procedures directly; Aphid does not emulate indexed search.

## Graph algorithms

ALGO is statically linked and registered automatically. Use `Aphid.query/3`;
no `INSTALL ALGO` or `LOAD EXTENSION ALGO` is needed.

The bundled procedures are `PAGE_RANK` (`PR`),
`STRONGLY_CONNECTED_COMPONENTS` (`SCC`),
`STRONGLY_CONNECTED_COMPONENTS_KOSARAJU` (`SCC_KO`),
`WEAKLY_CONNECTED_COMPONENTS` (`WCC`), `K_CORE_DECOMPOSITION` (`KCORE`),
`LOUVAIN`, and `SPANNING_FOREST` (`SF`).

Create and populate ordinary graph tables, then project the tables for the
algorithm. For existing `Person` nodes and `Knows` relationships:

```elixir
{:ok, _} = Aphid.query(db, "CALL PROJECT_GRAPH('social', ['Person'], ['Knows'])")
{:ok, result} = Aphid.query(db, """
CALL PAGE_RANK('social')
RETURN node.id, rank
ORDER BY rank DESC, node.id
""")
{:ok, _} = Aphid.query(db, "CALL DROP_PROJECTED_GRAPH('social')")
```

See [the complete executable example](../examples/algo.exs).
`test/algo_test.exs` checks PageRank symmetry and relative ranking, connected
component membership, projection removal, and failure of excluded GDS functions.
The remaining bundled algorithms are not individually qualified by that test.
The macOS ARM64 source build passed all 101 tests and native create/reopen
checks on 2026-09-09. Linux, sanitizer, and new packaged-runtime qualification
for ALGO remain pending.

Builds explicitly set `ICEBUG_ENABLED=OFF`. Icebug-backed `GDS_PAGE_RANK`,
`GDS_NODE2VEC`, `GDS_LOUVAIN`, `GDS_LEIDEN`, and `GDS_PPR` are excluded.
The pinned `algo-optional-openmp.patch` removes an unused OpenMP requirement
from this standard-algorithm build; icebug, Arrow, and OpenMP are not added to
the runtime bundle. Enabling icebug later requires separately locking, packaging,
and testing those dependencies.

For an existing development checkout with the locked sources and OpenSSL already
built, rebuild locally from the `zig_library` directory:

```sh
python3 scripts/build.py configure
python3 scripts/build.py engine
APHID_INSTALL=source MIX_ENV=test mix compile
APHID_INSTALL=source MIX_ENV=test mix test test/algo_test.exs test/examples_test.exs
```

Use a source build path without an installed precompiled bundle. Source builds
require the pinned toolchain and native prerequisites; these commands are not a
fresh-machine installer. Distribution requires new native archives and catalog
checksums for every included target; see [publishing updates](publishing-updates.md).
Existing published archives cannot satisfy the new four-extension startup check.

## Index maintenance

Create and drop FTS/vector indexes outside `Aphid.transaction/3`. Public index
DDL requires engine auto-transaction mode. Wrapping it in a callback transaction
is rejected and prevents that callback from committing.

Committed inserts, updates and deletes maintain the indexes in the tested
configuration. Rolled-back mutations restore the prior search state. Reopening
the same persistent database with the tested build retains index data. These
behaviors are exercised by `test/fts_test.exs`, `test/vector_test.exs`, and the
fresh-process `scripts/fts_persistence.py` and `scripts/vector_persistence.py`
checks. An index created on an empty table is tested after subsequent insertion.

To explicitly rebuild, finish active application work using that index, drop it,
and create it again with the desired configuration. The two public calls are
separate operations; queries between them cannot use the index. Keep creation
settings with application schema code so the rebuild is reproducible. No automatic
index rebuild, repair, or retry is performed by Aphid.

FTS tests cover multiple indexed fields, Unicode, empty text, stemming disabled,
and explicit tie ordering. Add a secondary sort key when deterministic ordering
of equal scores matters. See [the executable FTS example](../examples/fts.exs).

Vector results are approximate. L2 scores in the tested engine are Euclidean
distance. Match the declared vector dimension and element type; use typed
`Aphid.Value` parameters as in [the vector example](../examples/vector.exs).
Search effort affects recall: the seeded persistence probe uses `efc := 200`
when creating the index and `efs := 200` for search. Its measured recall is a
property of that fixture and configuration, not a guarantee for other data.
The default search effort missed a known nearest point in an earlier probe;
see [Stage 07 evidence](evidence/stage-07.md).

## Cancellation and recovery

Deadlines bound the caller's wait. Native cleanup can continue after the response;
the session stays unavailable until cleanup finishes. A timeout after a write
does not prove rollback. For transaction outcome meanings, see the
[transaction contract](../README.md#transactions) and
[telemetry timing boundaries](telemetry.md).

The locked engine includes the atomic FTS creation patch. The original
interruption defect left internal tables behind; cancellation, same-name rebuild,
query and drop now pass in memory and on disk. OOM and injected late-registration
failure recovery also passed the checks recorded in
[Stage 07](evidence/stage-07.md#sanitizer-gate-completion-and-atomic-fts-promotion-2026-09-07).
Wait for native cleanup before an explicit rebuild. Aphid does not automatically
retry writes, and a timeout response alone does not establish recovery.

The 300,000-document cancellation fixture requires an explicit 1 GiB buffer pool
on the tested host. A 64 MiB pool can fail during creation. Pool size is per
database and does not cap total RSS. Larger builds need their own capacity
measurements; [streaming measurements](evidence/stage-06.md) separately report
BEAM memory and process RSS.

The vector cancellation probe rebuilds the same index after cleanup. The DuckDB
probe verifies that the caller times out and the session later becomes reusable.
It does not prove that Ladybug immediately interrupts DuckDB's synchronous work;
that work may finish before cleanup. These observations are recorded in
[Stage 05 evidence](evidence/stage-05.md).

## DuckDB scope

The supported integration under test attaches an existing DuckDB file, scans
tables/views, streams rows, imports rows into graph tables, and detaches it.
Direct graph projection through the connector is excluded by the locked patch.
The [executable example](../examples/duckdb.exs) demonstrates the tabular path.

Tests compare source file bytes before and after repeated read/import cycles,
check exact integer/decimal/timestamp/blob/null values, and verify missing,
invalid and externally locked files fail cleanly. After an external writer
releases its lock, a new explicit attachment succeeds. Attachment aliases are
runtime state: reattach in a fresh process when needed. Detaching does not remove
graph rows previously imported from the source.

## Crash and upgrade policy

The NIF and engine execute inside the BEAM OS process. A native crash can terminate
the VM; an OTP supervisor cannot contain that fault. Sacrificial-process tests
check uncommitted changes after a forced process kill and reopen, including
combined FTS/vector/DuckDB graph workloads. They do not establish power-loss or
hardware-failure guarantees.

Live NIF upgrade is rejected. Stop application work, close databases and shut down
the old VM before loading a different native build. Reopen/persistence evidence
currently covers the pinned engine and applied patch set on the tested host.
No cross-version database migration or downgrade compatibility is claimed.
Preserve a recoverable copy and test a new build's reopen and indexed queries
against a copy before replacing an existing installation. There is no automated
format migration in Aphid.

No release target is supported yet. See the [target/status ledger](status.md)
for the tested host and the outstanding Linux and packaged-runtime gates.
