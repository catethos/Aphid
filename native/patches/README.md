# Locked native patches

`duckdb-tabular-only.patch` applies to extensions commit
`89fceca9aa0c3d404984b84697a502ac6a088536`. SHA-256 is recorded in `../lock.json`.

Reproduction before patch: `python3 scripts/features.py`, recorded in
`../../docs/evidence/features-run.log`. The create process succeeds. The fresh
reopen process fails on ATTACH with `records already exists in catalog` after a
successful DETACH in the first process. `DuckDBCatalog::createForeignTable`
creates a main-catalog shadow table; `DatabaseManager::detachDatabase` only erases
the attached database. The shadow survives in the persisted main catalog.
The same path also takes `tableEntry.get()` after moving its unique_ptr.

The patch compiles the DuckDB catalog in tabular mode: all attached SQL tables
remain available through `LOAD FROM` and `COPY ... FROM`, including tables whose
names start with `rel_` or `csr_rel_`. It skips direct main-catalog graph
projections entirely. Import into ordinary Ladybug node/relationship tables
before graph traversal. Direct MATCH over external DuckDB tables is not an
Aphid capability. This removes no required table query/import functionality.

This is a build policy around a reproduced upstream defect, not a claim that
the upstream graph-projection lifecycle has been repaired. The disabled source
stays intact so the patch can be removed when upstream fixes and tests its
ownership/detach/checkpoint behavior. There is no runtime option to enable it.

Regression checks include reattach in the same process, fresh-process reopen,
and importing known rows; the identical checks run inside the BEAM. Do not
remove the patch without running these and the later Stage 07 lifecycle tests.

## Promoted from `candidates/` (2026-09-07)

Eight patches promoted after the Apple Clang 21 ASan/UBSan gate passed against
freshly rebuilt sanitizer objects; see `docs/evidence/stage-07.md` and
`docs/evidence/fts-sanitizer-candidate-checks-clt21-1.log` for the verification
runs and `../../docs/evidence/row-alignment.md`, `aggregate-alignment.md`, and
`alp-range.md` for each defect's investigation history.

- `row-value-alignment.patch`, `string-hash-alignment.patch`,
  `join-row-alignment.patch`, `alp-conversion-range.patch`,
  `aggregate-state-alignment.patch`, `sort-key-alignment.patch` fix UBSan
  misaligned-load/out-of-range aborts found while sanitizing packed row,
  string-hash, hash-join, ALP compression, aggregate-state and sort-key code
  paths. Each replaces an unaligned reference/cast with a `memcpy` into an
  aligned local, or (aggregate-state) pads schema offsets to
  `alignof(AggregateState)`. None change on-disk format or externally
  observable results for aligned inputs; each has a focused regression in
  `native/tests/`.
- `node-delete-finalize.patch` guards `SingleLabelNodeDeleteExecutor::finalize`
  with `!batchNodeIDs.empty()` before flushing detach-delete batch storage,
  fixing a UBSan abort on an ordinary `DELETE` with an empty batch (found via
  the public OOM recovery workflow, `native/tests/fts_failure_recovery.cpp`
  `oom` mode).
- `fts-atomic-create.patch` (source: `extensions`) wraps `CREATE_FTS_INDEX`'s
  internal table rewrite in a transaction so a cancelled or late-failing build
  leaves no leftover internal tables and a same-name rebuild succeeds. This is
  the fix for the original cancelled-build failure in
  `docs/evidence/fts-cancel-run-2.log`; `docs/evidence/fts-cancel-run-3.log`
  is the post-promotion production regression (300,000-row cancel/rebuild, in
  memory and on disk).

Promotion required: fresh sanitizer-candidate reconstruction (not trusting
shared upstream extension archive timestamps), apply/reverse round-trip
validation of every patch, a from-scratch normal-engine rebuild with the
shared extension archives removed first (so no sanitizer-flavored object could
be silently reused), and the full Elixir suite plus FTS persistence,
cancellation and OOM recovery against that rebuilt engine.
