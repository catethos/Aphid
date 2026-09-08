# Unverified patch candidates

These files are not part of `native/lock.json` and are not applied by the build.

## Status (2026-09-07): all listed candidates promoted

`fts-atomic-create.patch` and the seven alignment/finalize patches described
below (`row-value-alignment.patch`, `string-hash-alignment.patch`,
`join-row-alignment.patch`, `alp-conversion-range.patch`,
`aggregate-state-alignment.patch`, `sort-key-alignment.patch`,
`node-delete-finalize.patch`) passed the full sanitizer/native/production
verification described in `docs/evidence/stage-07.md` and were moved to
`native/patches/` with entries in `native/lock.json`. This directory currently
holds no pending candidate patches; the narrative below is retained as the
provenance record for how each was found and fixed. A future candidate goes
through the same promotion bar: fresh sanitizer-candidate reconstruction
(never trusting shared upstream extension archive timestamps), apply/reverse
round-trip validation, a from-scratch normal-engine rebuild, and the full
Elixir/native regression suite against that rebuilt engine before the patch
and its `native/lock.json` entry are added.

Remaining release gates are unaffected by this promotion: TSan race auditing,
Linux ARM64 cross-build/runtime, the required target matrix (Stage 08), and
benchmarks/release packaging (Stage 09) are still outstanding. Promoting these
patches does not mark Stage 07 or the overall implementation complete.

`fts-atomic-create.patch` is a candidate for the cancelled-build failure in
`docs/evidence/fts-cancel-run-2.log`. It wraps the rewritten build in a transaction,
retains the public explicit-transaction restriction, adds removal of the in-memory
index on rollback, and relies on post-commit index checkpointing instead of
checkpointing uncommitted internal tables.

Before promotion: compile in isolation, pass same-name cancellation recovery,
all FTS acceptance and fresh-process persistence checks, and verify late-failure
rollback around index registration. Callback allocations now precede `addIndex`,
and a shared registration flag ensures rollback removes only an installed index.
The candidate applies cleanly and compiles in isolation with the current Release
engine command (`docs/evidence/fts-candidate-compile-1.log`). The isolated linker
runner `scripts/fts_candidate.py` substitutes the candidate object in a copied
FTS archive and links a separate library from existing Release objects. Native
feature creation and fresh-process reopening passed in
`docs/evidence/fts-candidate-run-1.log`; loader diagnostics confirm both processes
loaded `_build/fts-candidate/liblbug.0.dylib`. Cancellation recovery and public API
tests are still pending, so this candidate is not a verified fix. Keep source inputs stable
while the current sanitizer build is running.

Public cancellation run 3 (`docs/evidence/fts-candidate-cancel-3.log`) confirms
candidate loading through `scripts/candidate_beam.py`. Cancellation reached idle
and preserved the 300,000 source rows. Same-name recreation advanced beyond the
former leftover-table error but failed with buffer-pool exhaustion under the
bridge's fixed 64 MiB pool. Atomic creation retains more uncommitted data; this
resource requirement must be resolved or explicitly supported before promotion.
The complete recovery assertion remains failing. Runs 1 and 2 were launcher
selection failures, not valid candidate runtime evidence.

`scripts/fts_oom_recovery.exs` separately verifies that buffer exhaustion preserves
all 300,000 source rows and permits a same-name index after intentionally reducing
that fixture to 1,000 rows (`docs/evidence/fts-candidate-oom-1.log`). This checks
cleanup only and does not replace the original large cancellation/rebuild gate.
The complete 88-test public suite also passes against the candidate in
`docs/evidence/fts-candidate-suite-1.log`, with loader identity recorded.

The full-size native capacity probe `native/tests/fts_cancel_capacity.cpp` uses
the same 300,000 documents and verifies engine timeout, same-name rebuild,
300,000 search hits and drop. A 256 MiB pool was insufficient
(`docs/evidence/fts-capacity-run-1.log`). An explicitly configured 1 GiB pool
passes both in-memory and persistent databases
(`docs/evidence/fts-capacity-run-2.log`), with candidate loading confirmed.
This is engine-level timeout evidence; the original public cancellation test
still needs a supported buffer configuration and rerun. The application default
has not been increased. The evidence now justifies exposing a bounded explicit
buffer-pool setting rather than silently enlarging every database instance.

`buffer_pool_bytes` is now exposed through the public API with matching native
validation (64 MiB to 1 GiB, unchanged 64 MiB default). Public cancellation
run 4 (`docs/evidence/fts-candidate-cancel-4.log`) passes the original full-size
workflow in memory and on disk at 1 GiB, with candidate loading confirmed.
Both samples returned at 101 ms and reached native idle at 105 ms, preserved
300,000 source rows, rebuilt the same index, found all expected hits and dropped
the index. These are measured samples, not timing guarantees. The candidate is
still unapplied pending remaining late-failure and sanitizer checks.

Late registration failure is now checked by `scripts/fts_candidate.py --late-failure`:
the isolated source throws once after index registration and callback setup.
The production patch contains no injection. The linker reconstructs extension
archives from Release object lists because upstream archive destinations are
shared with sanitizer builds; it never trusts their current destination contents.
`scripts/fts_late_failure.exs` verifies the injected error, intact source rows,
a subsequent write, same-name rebuild and correct search results. Memory and disk
creation plus a separate disk reopen all pass in
`docs/evidence/fts-late-recovery-1.log`, with the fault-library identity confirmed.
Sanitizer verification remains pending.
