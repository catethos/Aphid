# Aphid value and result contract

Frozen for Stage 03 on 2026-09-07. This is the implementation contract;
`status.md` records which gates have actually passed.

## Public calls

`Aphid.start_link(options)`, `query(database_or_transaction, cypher, params \\ %{},
options \\ [])`, `transaction(database, callback, options \\ [])`,
`rollback(transaction, reason)`, `stream(database_or_transaction, cypher,
params \\ %{}, options \\ [])`, and `close(database, options \\ [])` form the
public API. Query returns `{:ok, %Aphid.Result{}}` or `{:error, %Aphid.Error{}}`.
Stream enumeration yields bounded `%Aphid.Result{}` batches and raises
`Aphid.Error` on failure. Construction is lazy. The process enumerating a stream
owns it until release. A transaction callback returns `{:ok, callback_result}`
after confirmed commit, or `{:error, error_or_rollback_reason}`. Nesting is an
error. Transaction tokens are opaque, process-owned, and expire on release.
The callback executes in a monitored worker process. This lets the coordinator
enforce its deadline during callback code as well as native calls. Callback
exceptions are re-raised in the original caller after rollback; explicit rollback
returns its reason unchanged. Every query error prevents a later commit, even
if ignored. Returning an error tuple as an ordinary callback value still commits.
The executable transaction example covers the intended commit/abort distinction.

Streams validate options at construction but execute only at enumeration. Their
absolute timeout still starts at public API entry. Empty results yield one empty
batch with metadata. Suspension keeps the session; resume/halt must use the same
enumerating process. Early halt waits for native release within the deadline.
Inside a transaction, finish or halt its active stream before another operation;
an overlap returns `:busy_transaction` and cannot replace the stream's deadline.

One call accepts exactly one engine-parsed statement. Manual transaction
statements, including under EXPLAIN/PROFILE, are rejected before execution.
Parameters have UTF-8 binary names without a leading `$`; no dynamic atoms are
created. Unknown options fail before admission; malformed values fail before
native execution. A session reservation bounds native parameter conversion.
`Aphid.info/1` returns the engine version and extension registration snapshot
actually observed at startup.

## Results and types

`%Aphid.Result{columns: [{name, type}, ...], rows: [[value, ...], ...],
statistics: nil}` preserves column order and duplicate names, including metadata
for zero rows. Names are binaries. `Aphid.Result.to_maps/1` returns
`{:ok, maps}` or a duplicate-column error; it never drops a column. Statistics
may later contain measured engine timings; absent statistics remain `nil`.

Types are static atoms or the recursive tuples below. `%Aphid.Value{type: type,
value: value}` supplies explicit input types. Null is `nil` at every level;
typed null input uses the wrapper. Result metadata carries the null's type.

| Engine type | Type descriptor | Value representation |
|---|---|---|
| BOOL | `:bool` | Boolean |
| INT8/16/32/64/128, UINT8/16/32/64/128 | corresponding lowercase atom | Exact Elixir integer |
| SERIAL | `:serial` | Signed 64-bit integer; output only |
| FLOAT, DOUBLE | `:float`, `:double` | Finite float; FLOAT rounds once to IEEE binary32 |
| DECIMAL | `{:decimal, precision, scale}` | Tagged value with exact signed integer coefficient; mathematical value is coefficient × 10^-scale |
| STRING | `:string` | UTF-8 binary, preserving embedded NUL |
| BLOB | `:blob` | Tagged value with arbitrary binary bytes |
| DATE | `:date` | Tagged signed 32-bit days since 1970-01-01 |
| TIMESTAMP/SEC/MS/NS/TZ | `:timestamp`, `:timestamp_sec`, `:timestamp_ms`, `:timestamp_ns`, `:timestamp_tz` | Tagged signed 64-bit count; units respectively microseconds, seconds, milliseconds, nanoseconds, microseconds |
| INTERVAL | `:interval` | Tagged `{months, days, microseconds}`; signed 32/32/64-bit fields |
| UUID | `:uuid` | Tagged canonical lowercase hyphenated ASCII string |
| JSON | `:json` | Tagged UTF-8 JSON text; no numeric decoding |
| LIST | `{:list, child_type}` | Ordered list |
| ARRAY | `{:array, child_type, length}` | Ordered list of exactly `length` elements |
| STRUCT | `{:struct, [{field_name, field_type}, ...]}` | Ordered `{field_name, value}` pairs |
| MAP | `{:map, key_type, value_type}` | Tagged ordered `{key, value}` pairs; never an Elixir map |
| INTERNAL_ID | `:internal_id` | Tagged `{table_id, offset}`, both unsigned 64-bit; output only |
| NODE/REL/RECURSIVE_REL | `{:node, fields}`, `{:rel, fields}`, `{:recursive_rel, fields}` | Tagged ordered `{field_name, value}` pairs, preserving every engine-supplied field and recursive type; output only |

`fields` uses the STRUCT field descriptor. Graph reserved fields retain the
engine names, IDs, labels and endpoints. Recursive paths retain the node and
relationship list order supplied by the engine; the wrapper does not infer
extra nodes or traversal direction. Timestamp without TZ retains its raw
wall-clock count; TZ represents an instant and does not retain an original
timezone name. No calendar range narrowing occurs. Calendar helpers are outside
the initial API.

Measured engine details: a recursive relationship's `_NODES` list contains
intermediate nodes only, excluding endpoints; `_RELS` contains the ordered
edges. Query endpoints separately when needed. The pinned string-to-TIMESTAMP_NS
cast first parses microseconds, then multiplies by 1000: fractional nanoseconds
are truncated by the engine. Raw typed timestamp input must bypass that cast.

Bare inputs infer only boolean, signed INT64, finite DOUBLE and UTF-8 STRING.
A bare list infers one identical non-null child type recursively; mixed widths,
mixed numeric families, empty lists and all-null lists require an explicit
type. Bare `nil` is rejected because it has no type. Bare maps/tuples/calendar
structs are not inferred. Explicit composite wrappers contain raw child values
according to their complete descriptor; nested wrappers must match that type.
Struct fields must match descriptor order and names. Map keys may not be null
or duplicated; key equality uses the declared engine type. Precision is 1..38,
scale is 0..precision, and `abs(coefficient) < 10^precision`. Integer overflow,
FLOAT overflow, nonfinite input/output, invalid UTF-8, and type mismatches are
errors, not coercions. JSON is syntactically checked by the engine's JSON type;
its stored text is returned unchanged when the engine preserves it.

UNION is explicitly unsupported, even for null columns. In the pinned engine,
`Value::copyFromUnion` retains only the selected child value, discarding the
active field index. Inferring a tag from its type would lose information when
two variants share a type. POINTER, unresolved ANY, and unknown future type IDs
also produce `:unsupported_type`. Errors include the descriptor or native tag
and row/column or parameter path; unsupported values are never stringified.

DuckDB output is described by the actual Ladybug logical type after the
extension's conversion. Aphid cannot restore precision the extension has
already discarded. The feature fixture must document such conversions before
claiming support; explicit Cypher casts are part of the query, not hidden
wrapper coercion.

## Bounds and errors

Public option names are fixed as follows. Start accepts `path` (required;
`:memory` or a nonempty UTF-8 path), `sessions`, `threads`, `queue_capacity`, and
the standard OTP `name` forms. Query accepts `timeout`, `max_rows`, `max_bytes`.
Close and transaction accept `timeout`. Stream accepts `timeout`, `batch_rows`
and `batch_bytes`, with the same positive row/byte integer ceilings as eager
limits. Unknown or duplicate options are errors. Session/thread counts are
1..64; queue capacity is 0..65,536; finite timeouts are 0..2^32-1 ms;
row limits are 1..2^32-1 and byte limits 1..2^64-1. These integer ceilings are
validation boundaries, not safe memory-sizing recommendations. Zero timeout
means an already-expired deadline; `:infinity` applies only to timeout.

Defaults: query text 1 MiB, parameter payload 1 MiB, nesting depth 32, eager
10,000 rows / 8 MiB, batch 256 rows / 1 MiB. Row/payload budgets are positive;
timeouts default to 30,000 ms and explicitly accept `:infinity`. Queue capacity
defaults to 64, sessions to 1, engine threads per query to 2. Database paths
are at most 4096 bytes and contain no NUL.

Logical payload accounting is identical on input/output: 8 bytes per value
(including null and each container), plus 16 for an integer/float/raw temporal
scalar, 24 for interval, 16 for internal ID, or the byte length for text/blob/
UUID/JSON; plus recursively counted children. Struct/map pairs cost 8 bytes
each in addition to their names/keys and values. Metadata is charged as 8 bytes
per descriptor plus UTF-8 name bytes, recursively, once per batch/result;
each row costs 8 bytes. Boolean adds no scalar payload. This is a conservative
logical transfer measure, not exact BEAM heap or engine RSS.

Check before allocating/copying large payloads. A streaming row that cannot fit
a fresh batch fails with `:row_too_large`; total eager payload overflow remains
`:payload_limit`. A failed conversion rejects the whole batch or eager
result with zero-based row/column and nested path context. Database writes may
already have happened when transfer fails. The engine may materialize its
whole result independently of these transfer bounds. Only one fetch may be
active for an operation. Its result and parent statement/connection stay alive
until encoding finishes, including during caller death and close.

`%Aphid.Error{code, message, context}` is also an exception for stream errors.
Codes distinguish invalid input, engine errors, unsupported types, limits,
closed/busy/stale/foreign ownership, timeout/cancellation, and uncertain commit.
Native diagnostics are bounded byte strings; public messages replace invalid
UTF-8 for display without pretending the engine returned valid text.
