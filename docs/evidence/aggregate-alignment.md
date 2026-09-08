# Aggregate-state alignment

[Run 8](sanitizers-alignment-8.log) aborts under UBSan while updating `CountState`
inside a factorized-table row. Unlike serialized row values, aggregate states
contain live C++ objects and must be placed at correctly aligned addresses.
Packed key widths can misalign the first state, and a trailing null map can
misalign every subsequent row even when the first state's offset is aligned.

The candidate `aggregate-state-alignment.patch` adds an optional alignment to
schema column insertion. Aggregate columns request `alignof(AggregateState)`;
ordinary columns retain the default packed layout. The schema pads column
offsets and rounds the complete row stride to the required alignment. Schema
copies preserve these offsets, and equality compares the resulting layout.
The aggregate hash table obtains its first state offset from the schema instead
of recomputing an unpadded sum of key widths.

The focused `native/tests/aggregate_alignment.cpp` uses a BOOL grouping key,
COUNT and SUM states, and two output groups. It checks exact results and is
included in the sanitizer driver. The initial before-fix attempt used an
unsupported INT64-to-BOOL cast and did not reach aggregation. The corrected
query uses a boolean comparison; its recheck is recorded in
[before-fix evidence](aggregate-alignment-before-2.log). [Run 9](sanitizers-alignment-9.log)
records all five candidate patch digests and will run lifecycle/hash/ALP and
feature create/reopen checks after relinking. The focused aggregate check must
also be executed against that rebuilt library.

The candidate remains applied to local upstream source only. The lock and normal
development engine have not been updated; no sanitizer gate is marked complete.

## Rechecks

Run 9 completes the rebuild and passes lifecycle/hash/ALP checks. Feature creation
gets past aggregate-state updates but fails on a packed hash read in
`aggregate_hash_table.cpp:getHash`. The candidate now copies that hash into an
aligned local value, and removes the two key-width counters made unused by the
schema offset. [Run 10](sanitizers-alignment-10.log) records the updated digest
and rebuilds before rechecking.

The focused regression now explicitly checks padded offsets, stride, schema
copying, and append-after-copy. [After check 1](aggregate-alignment-after-1.log)
passes these schema checks, then fails in the query's `ORDER BY`:
`OrderByKeyEncoder::encodeFTIdx` stores a `uint32_t` at an address ending in
`...002`. The query remains unchanged to retain this reproducer. This is a
separate packed sort-key defect, so the focused aggregate query does not yet
have a passing result.

The separate `sort-key-alignment.patch` copies the two 32-bit sort-key metadata
fields into/out of byte storage with `memcpy`. The packed field order, 24-bit
offset mask, final one-byte table index, and byte order remain unchanged. Both
encoder writes and decoder reads are covered. [Run 11](sanitizers-alignment-11.log)
records its digest alongside the preceding candidates and reruns the unchanged
aggregate/sort reproducer and native feature suite.

## Promotion (2026-09-07)

`aggregate-state-alignment.patch` and `sort-key-alignment.patch` passed
[sanitizer run 14](sanitizers-alignment-14.log) after rebuilding from scratch,
and were promoted into `native/lock.json`; see [stage-07.md](stage-07.md) for
the full promotion record and the normal-engine production regression that
followed.
