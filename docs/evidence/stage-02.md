# Stage 02 — workers, resources, and retirement

Working directory: `/Users/catethos/workspace/ladybugex/zig_library`.
Sources/toolchain: `native/lock.json`; ABI contract: `native/bridge.h`.

Implemented fixed per-session workers, RAII engine ownership, correlated
callbacks using independent BEAM environments, operation-resource retention,
native owner/process monitors, stable operation identities, repeated scoped
interruption, result abandonment, and an intrusive bounded cleanup queue.
Only the cleanup service joins workers/destroys databases. Connections and
results are destroyed on their worker before the parent engine. Open errors
also pass through retirement. Canonical paths stay reserved until destruction.

The fixed runtime has two service threads (cleanup and cancellation controller)
and a single VM-lifetime NIF anchor. Those are the baseline; query workers and
databases must return to zero. No threads are detached. The anchor prevents
callbacks from executing unloaded code. Live NIF upgrades are rejected.

## Commands and results

`ZIG_GLOBAL_CACHE_DIR=/tmp/aphid-zig-cache python3 scripts/lifecycle.py`
builds the bridge and native fault-injection executable, runs the native test
with a 20-second external watchdog, then ExUnit in a sacrificial BEAM using
`+S 1:1 +SDcpu 4` with a 120-second process-group watchdog.

- `lifecycle-run.log`: initial 7 ExUnit tests passed, seed 0, 3.4 s.
- `lifecycle-run-2.log`: 7/8 passed. Native upgrade callback rejected upgrade,
  but Zigler's generated loader returned success after logging the failure.
  This was an actual failed acceptance test, not an expected pass.
- `lifecycle-run-3.log`: corrected loader, all 8 passed, seed 0, 2.8 s.
  The old module/resource remained usable after rejected replacement.
- `lifecycle-run-4.log`: native failed delivery, throwing callback, and injected
  worker failure checks passed (0.839 s); all 8 BEAM tests passed (2.8 s).
- `lifecycle-run-5.log`: native fault checks and all **9 BEAM tests passed**,
  seed 0, ExUnit 3.1 s, command 8.766 s including native/NIF compilation.
  Heartbeat: **30 samples, maximum gap 6 ms**, with one ordinary scheduler.

Checks cover two independent sessions, correlated completion, engine errors,
stale cancellation followed by successful queries, 20 query-caller deaths,
owner death while another process holds the resource, GC, malformed resources,
binary/size/UTF-8 input limits, invalid open, symlink path aliases, duplicate
open, close/reopen, scheduler responsiveness, and rejected upgrade.
Every case verifies closure/native counts or leaves owner monitoring to retire
the database. Native fault hooks are compiled only into the standalone test,
not exported from the production bridge.

## Decisions and remaining gates

Used raw `erl_nif` resource functions through Zigler because its resource helper
has mismatched down/stop signature checks. No Zigler dependency source was
modified. A small before-compile loader override propagates `load_nif` errors.

Session arrays remain stable for the entire resource lifetime, even after heavy
retirement, so close cannot invalidate an in-flight control lookup. Large result
and connection destruction occurs outside control locks. Reporting has a
nonallocating 1023-byte fallback; error text can be truncated, values cannot.
Every bridge entry/thread contains exceptions; unrecoverable service failures
disable admission and quarantine retained owners.

This is an initial lifecycle gate, not sanitizer/race-detector certification.
Stage 04 still owes queue and lease ownership, transaction rollback, and restart
tests. Stage 05 still owes complete deadline accounting and larger cancellation
race/extension-operation coverage. Stage 07 still owes sanitizers. No public
query/result API or faithful value conversion is claimed yet.

Next: freeze `docs/types.md`; implement parameter preparation and bounded result
access without letting a fetch borrow memory that worker retirement can destroy.
