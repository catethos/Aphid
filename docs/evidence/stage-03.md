# Stage 03 — partial evidence

2026-09-07, same pinned macOS ARM64 environment as Stage 02. This stage is
**in progress**, not a public API or release gate pass.

The public names, tagged value grammar, ordered result shape and payload
accounting were frozen in [types.md](../types.md) before conversion work.
`Aphid.Value`, `Aphid.Result` and `Aphid.Error` exist; map conversion rejects
duplicate columns (including zero-row results) and malformed row widths.

`Native.submit/3` now uses the exported engine parser to require exactly one
statement and reject transaction control, recursively inspecting EXPLAIN.
Tests cover comments, empty input, PROFILE/EXPLAIN transaction syntax, literal
semicolons/transaction words, and proof that the first CREATE of rejected
multi-statement input did not execute. Parameters and the public coordinator
are not implemented yet.

The bridge provides an exclusive fetch lease. It retains its database itself,
and the session worker cannot destroy its result or connection until fetch end.
The native sacrificial test calls finish during a fetch, closes/releases the
external database reference during a fetch, reads the retained value, rejects
stale/concurrent fetches, then proves workers/database reach zero. Metadata is
copied once per fetch; rows/children/byte views borrow engine storage only for
the lease. One field-name scratch buffer is copied into BEAM before recursion.
No second native result tree or zero-copy BEAM binary is constructed.

`Native.collect/3` is a dirty-CPU eager converter, restricted to the operation
owner. It checks row/payload/depth limits, finite floats, UTF-8 text, and the
operation cancellation flag during conversion. It returns an internal result
struct or structured error with row/column/path/native-tag context and always
ends the fetch/requests result destruction after acquisition. Streams and the
absolute public deadline are later stages. Invalid resource/owner arguments
remain raw NIF errors until the public API wraps them.

## Verified checkpoint

`lifecycle-run-8.log`, produced by `python3 scripts/lifecycle.py`:

- Native failed-delivery/throwing-callback/worker-failure/cleanup tests pass.
- Native fetch ownership tests pass.
- All 20 BEAM tests pass, seed 0, in 3.6 s (whole Mix command 8.294 s).
- One ordinary scheduler; heartbeat 30 samples,
  maximum gap 6 ms.
- Native subprocess watchdog 20 s; whole BEAM process-group watchdog 120 s.

Value tests execute real queries for every signed/unsigned integer width,
including minimum/maximum INT128 and UINT128. 128-bit results use bounded
standard Erlang SMALL_BIG_EXT conversion because Zigler's default large integer
conversion is not an exact Elixir integer. Further cases cover full-precision
decimal coefficients, raw date/nanosecond timestamp values, separate interval
components, canonical UUID, JSON text with a large integer, arbitrary BLOB
bytes, UTF-8 and embedded-NUL text, FLOAT rounding, nonfinite rejection,
typed all-null lists, arrays, structs, maps, empty-result metadata, graph IDs/
endpoints/properties, recursive path order, union rejection and foreign-process
fetch rejection. A one-element list costs exactly 57 logical bytes under the
documented rule: 57 passes, 56 reports row 0/column 0/path [0]/INT64. Depth and
row limit failures release the result; following queries succeed.

## Failed attempts and measured limitations

- `result-run-1..4.log`: development compilation failures (relative module
  import, unavailable C-header module dependency, Zig name shadowing, Elixir
  sigil delimiter). Kept conversion in the existing NIF file to avoid adding
  a dependency-routing workaround.
- `result-run-5.log`: a transfer-limit error exposed a Zigler runtime panic
  in `has_processterminated`, which force-unwraps an unrestricted `anyerror`
  set. Explicit finite conversion errors fix the root cause; subsequent limit
  tests and full-suite watchdog run pass. No dependency source was modified.
- A test generated a not-yet-existing atom before its first native use; replaced
  test inference with a fixed literal type table. Production never creates
  atoms from database names.
- String-to-TIMESTAMP_NS cast truncates to microseconds before scaling.
  Independently confirmed in pinned `cast_string_non_nested_functions.cpp`.
  Typed raw timestamp input must bypass this conversion; it is still pending.
- Recursive relationship `_NODES` contains only intermediate nodes, not both
  endpoints. A two-edge test verifies the intermediate node and edge order.
- UNION materialization discards the active field index in
  `Value::copyFromUnion`; its selected child type cannot distinguish same-type
  variants. Rejected explicitly, including at metadata conversion.

## Remaining Stage 03 gates

Strict public options and bounded parameter conversion; prepared statement
ownership; real input/output round trips for all supported types; raw timestamp
range/precision tests; dynamic-name atom stability; all extension result types
through this converter; complete contextual input errors and public examples.
Do not treat the current result tests as those missing acceptance gates.

## Native parameter checkpoint

`lifecycle-run-11.log` passes the native checks in 1.195 s and all 20 BEAM tests
in 3.3 s (Mix command 4.08 s), using the same watchdog/scheduler settings.
The heartbeat remains 30 samples/max 6 ms.

All submissions now use `prepare`/`prepareWithParams` followed by
`executeWithParams`. The worker retains the prepared statement until after
result destruction, including finish, failed delivery, caller death and close.
The selected engine binds supplied values during prepare, so execution with an
empty update map retains those exact parameters without a second wrapper copy.
Source inspection and real parameter queries verify that behavior.

The C ABI has owned type/value/parameter constructors with explicit consuming
semantics. Scalar bytes are copied, nested child ownership moves into engine
Values, and submission consumes the parameter collection on success or failure.
Native validation rejects integer/decimal overflow, nonfinite floats, array/
struct/type mismatches, null/duplicate map keys and invalid JSON. JSON validation
uses the pinned engine's exported parser; no extra parser dependency was added.
Map duplicate checks hash normalized native values and use null-aware recursive
equality (the engine's scalar equality otherwise reads storage for typed nulls).
The duplicate-key regression includes positive and negative floating zero.

Direct native prepared round trips cover all scalar input types, exact raw
TIMESTAMP_NS value 123456789, embedded-NUL bytes, JSON, decimal metadata, typed
empty/null lists, arrays, structs and maps. Constructors consume and clear child
slots even on duplicate-key failure. These tests are stronger than constructing
a Value alone: each submits `$n`, fetches the engine result, verifies type and
value, and returns the session to idle.

BEAM parameter grammar/validation and the public API are still pending. The
private NIF currently submits without parameters; native constructor tests do
not substitute for that missing end-to-end input path. Input payload/depth and
caller-death checks during conversion must be implemented in Zig before this
stage can pass.

## BEAM scalar parameter checkpoint

`Native.submit/4` now accepts a parameter map; its three-argument helper passes
an empty map. The operation's owner monitor is armed before input conversion.
Zig checks the cancellation flag during conversion, charges the 1 MiB logical
parameter budget, validates binary UTF-8 names/text, requires explicit tags for
ambiguous scalar values, and constructs the native parameter collection before
dispatch. Failure frees partially converted native parameters and releases the
operation/parent references without executing a query.

Large integers are compared against exact 128-bit bounds before calling the
standard ETF serializer, so arbitrary-size BEAM integers cannot trigger a large
temporary serialization. The serialized representation is then at most 20
bytes. Raw timestamps and decimal coefficients never go through strings or
floats. Tagged-value maps must have exactly the struct/type/value fields.

`lifecycle-run-14.log` passes native checks and all 22 BEAM tests under the
watchdogs. New tests cover BEAM INT128 extrema, UINT128 maximum, raw nanoseconds,
decimals, intervals, blobs, JSON, UUID, typed null, inferred scalars and invalid
input cleanup. Overflow beyond signed/unsigned 128-bit bounds, narrow integer
overflow, malformed JSON, invalid UTF-8, atom parameter names, wrong parameter
container, partial-map failure and oversized binary input are rejected before
execution. `lifecycle-run-12.log` records initial compile-time name-shadowing
errors; corrected runs 13 and 14 pass.

Recursive BEAM list/array/struct/map conversion is still pending; the private
NIF explicitly rejects those descriptors for now. This temporary gap does not
change the frozen required type contract or the Stage 03 completion gate.

## Recursive BEAM input and feature checkpoint

Recursive BEAM lists, arrays, ordered structs and ordered maps are now wired
through the native constructors. Types are constructed once per parameter and
child type views are borrowed during conversion. Partial child arrays are freed
on every failure; successful native construction consumes and nulls each slot.
Bare lists infer an identical non-null child type, while empty/all-null or mixed
lists require an explicit descriptor. Nested wrappers must exactly match the
declared type. Input descriptor/value recursion is limited to depth 32; list
scans check cancellation and stop at the remaining payload bound. Errors carry
the parameter and zero-based nested path. Payload and cancellation failures
have distinct codes.

The new reservation precedes parameter conversion. It bounds simultaneous
native input builds by session count. Abandonment may release a reservation
while an old converter is still unwinding; submission checks the original ID
and rejects it if the slot was cancelled/reused. Native tests explicitly prove
that stale conversion cannot dispatch or cancel a following operation.

`lifecycle-run-22.log` passes native scalar/nested inputs, reservation races,
fault injection and fetch ownership, plus all 27 BEAM tests under watchdogs.
Additional BEAM cases cover typed empty/null nested data, list inference,
fixed arrays, maps containing lists/nulls, BLOB children, wrong field/type/
length rejection, FLOAT duplicate keys after normalization, improper lists,
depth rejection, contextual partial-child failure, and five caller kills during
large parameter conversion. After warm-up, 100 fresh parameter/column/struct
names add zero atoms. Sessions remain usable after each failure/death.

All three mandatory extensions now pass through the same NIF input/result
implementation: parameterized document insertion, FTS indexed lookup,
parameterized indexed vector lookup with ARRAY results, and DuckDB attachment,
parameterized scan, import and detach. The fixture build is part of the
watchdog runner, not an optional skipped test.

`lifecycle-run-19.log` found a real engine preparation limitation:
CREATE_FTS_INDEX expands into several internal statements, and the public
prepare API rejects that expansion. The engine's query API already executes
the expansion and hides its internal results. Aphid therefore selects query()
for no-parameter calls and prepareWithParams()/executeWithParams() for bound
parameters, before any execution. Both use the same session worker and the
same engine parser check for exactly one user statement. There is no retry or
fallback after execution. Index-definition calls use literal Cypher arguments;
index lookup parameters are tested. Prepared handles owned by Aphid still
outlive their results; internal statements in query() are managed by the engine.
Runs 20–22 verify the corrected behavior and the single-statement regressions.

Runs 15–16 record an unavailable Zigler `enif_is_list` alias; using the actual
OTP list-cell/empty-list inspection API fixes compilation. The public supervised
API, strict public options, comprehensive remaining boundary cases and executable
public examples still prevent marking Stage 03 complete.

`Aphid.Options` now validates the operation-specific public settings and
documented defaults. Tests reject unknown/duplicate settings, wrong containers,
invalid paths and out-of-range numbers; explicit in-memory startup and infinite
or zero deadlines are represented without coercion. `lifecycle-run-23.log`
passes the native checks and all 28 BEAM tests. The public supervisor/coordinator
is the next required implementation step; this options module alone does not
make the public API available.

## Public API and completed host query/value gate

`lifecycle-run-34.log` passes native lifecycle/fault/parameter/fetch checks and all
43 BEAM tests under the single-ordinary-scheduler watchdog. The BEAM suite takes
4.5 seconds (5.112 seconds including Mix), and the heartbeat records 30 samples
with a maximum 6 ms gap. This establishes the host Stage 03 gate, not release
support, sanitization coverage, or the later transaction/stream/deadline gates.

The public `Aphid` API now supports validated startup, supervisor child specs,
parameterized queries, ordered results, info and close. Startup actually queries
the engine version and verifies FTS, vector and DuckDB registrations. The
quickstart in `examples/basic.exs` executes as part of the suite. Public tests
also cover names (including the valid atom `false`), malformed database handles,
invalid options/parameters, queue overload, deadlines and close semantics.

Runs 29–32 expand the real-engine type matrix: every signed/unsigned width at
both boundaries and overflow, decimal storage widths through precision 38,
full raw temporal ranges and submicrosecond TIMESTAMP_NS, FLOAT rounding and
overflow, empty/arbitrary BLOBs, exact JSON whitespace, UUID normalization,
compound map keys with null children and duplicate rejection. Null values and
zero-row results retain scalar and recursive collection descriptors. SERIAL
storage returns its declared type and generated integer, including zero-row
metadata. Prior tests cover graph IDs/endpoints/path order, duplicate columns,
unsupported UNION, depth/size limits, partial conversion cleanup, dynamic-name
atom stability, and all three extension result paths.

Run 33 deliberately reproduces a public error-formatting defect: bounded native
UUID diagnostics can truncate inside a UTF-8 character. The structured-Error
branch previously returned those bytes unchanged. Public formatting now applies
the same valid-text-or-byte-inspection rule to both native error forms. Run 34
passes the three UTF-8 truncation alignments and the complete regression suite.

Limits remain explicit: UNION cannot be faithfully extracted from the pinned
engine and is rejected. Graph values and SERIAL are output-only. Parameterized
index definitions are constrained by upstream internal statement expansion;
no-parameter definitions and parameterized searches are tested. Queue capacity
bounds request count, not arbitrary mailbox memory; native payload bounds are
logical accounting rather than total process RSS. Streaming and the specific
single-oversized-row error belong to Stage 06 and are not implemented yet.

Scheduler correction from the later runtime inspection: the historical
`+S 1:1 +SDcpu 4` flags are clamped by this OTP build to one normal and one dirty
CPU scheduler, not four dirty schedulers. `scheduler-check.log` records the
actual counts under those exact flags. New runners request `+SDcpu 1:1`
explicitly. Historical heartbeat results remain valid; the earlier scheduler
description was incorrect.
