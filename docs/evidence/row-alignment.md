# Packed-row alignment investigation

Apple Clang 21 ASan/UBSan [run 2](sanitizers-run-2.log) completed compilation
and ran the native lifecycle tests. UBSan aborted in `Value::copyFromRowLayout`
on an INT64 load from an address ending in `...749`, requiring eight-byte
alignment. The reproducer is the existing nested prepared-parameter lifecycle
test. Packed list/struct row layouts place values immediately after null bytes,
so aligned pointer dereferences are invalid even when the hardware tolerates them.

The candidate `native/patches/candidates/row-value-alignment.patch` uses byte
copies into aligned local values in row-layout readers. The first recheck
rebuilt only the static archive and therefore still executed the old shared
library; [alignment run 1](sanitizers-alignment-1.log) is not post-fix evidence.

[Alignment run 2](sanitizers-alignment-2.log) relinked the actual shared library.
It passed the original read location and exposed the same defect in
`ListVector::copyToRowData`: binding a `list_t&` to a packed struct member at an
address ending in `...009`. The candidate now also copies list/string headers
to and from aligned locals in row-layout vector conversion. Column-layout
conversion is unchanged.

The candidate is applied to the local upstream source for sanitizer iteration,
but is not yet in `native/lock.json` and has not been rebuilt into the normal
development engine. A locked-source check intentionally rejects this temporary
state. Promotion requires successful sanitizer and normal regression checks.

## Subsequent checks

[Alignment run 3](sanitizers-alignment-3.log) failed compilation because the
initial edit placed a copy in the wrong string helper; it has no runtime result.
That edit was corrected before [alignment run 4](sanitizers-alignment-4.log).
Run 4 passes the complete native lifecycle suite with ASan/UBSan enabled,
including nested parameters, conversion, failures, concurrent lifecycle actions
and cleanup. Fixture creation also passes.

The same run then aborts in the combined feature create process while hashing
`ocean coral`. `Hash::operation(string_view)` reads eight bytes through a
`uint64_t*` from an address ending in `...404`, requiring eight-byte alignment.
The separate candidate `string-hash-alignment.patch` replaces that load with
`memcpy` into a local `uint64_t`; block boundaries, byte order, hash mixing and
the final partial-block calculation are unchanged. It is also applied only to
the source being used for sanitizer iteration, not promoted into the lock or
normal engine. [Alignment run 5](sanitizers-alignment-5.log) records both
candidate digests and is rebuilding the shared library before rerunning the
native lifecycle and create/reopen feature checks.

## Focused string-hash regression

`native/tests/hash_alignment.cpp` checks lengths 0 through 80, including zero
and high-bit bytes, with each starting offset 1 through 7 compared against the
same aligned input. [Candidate check](hash-alignment-1.log) passes under
ASan/UBSan. [Original-header check](hash-alignment-original-1.log) compiles the
same test with an isolated copy of the pinned original header and fails with
the expected misaligned-load diagnostic (exit -6). That negative check does not
modify the ongoing engine build's source. The sanitizer driver now runs this
regression in addition to its native lifecycle and feature tests.

## Packed hash-join entries

Alignment run 5 passes lifecycle checks and fixture creation, then UBSan aborts
at `JoinHashTable::findHashSlot` reading a hash from a tuple address ending in
`...031`. The separate `join-row-alignment.patch` reads that packed hash with
`memcpy`. The same tuple representation stores a linked-list pointer without
alignment padding; its accessor now returns a copied pointer value instead of
an address that callers dereference. All callers (join matching, intersection
and path-property probing) use that value. Pointer writes already used `memcpy`
and retain that behavior. Hash-slot arrays themselves remain aligned and unchanged.

[Alignment run 6](sanitizers-alignment-6.log) records all three candidate digests
and rebuilds before running lifecycle, the focused hash regression, and feature
create/reopen checks. The alignment candidates remain applied locally but
unpromoted. The FTS cancellation probe also now has a CMake target and compiles
with the sanitizer toolchain ([build evidence](fts-sanitizer-probe-build-1.log));
its execution against the atomic FTS candidate is still pending.

Run 6 passes lifecycle and focused hash checks, then fails in
`BaseHashTable::compareEntry<string_t>` when binding a reference to a packed
string key. The join-row candidate now also copies packed scalar/list keys
before comparison, including factorized-table comparisons and nested list
headers. Aligned vector inputs retain their existing access. The updated patch
digest and rebuild/check results are recorded in
[alignment run 7](sanitizers-alignment-7.log).

Run 7 passes native lifecycle, the focused hash regression and fixture creation.
The feature create workload proceeds beyond the earlier alignment failures and
UBSan reports a separate defect in bundled ALP compression:
`AlpEncode<float>::encode_value` converts `1e+10` to `int`, outside its
representable range (`third_party/alp/include/alp/encode.hpp:53`). This is not
an alignment issue and is not covered by the three alignment patches. The full
sanitizer gate and patch promotion remain pending investigation of that failure.
The [ALP investigation](alp-range.md) records its candidate fix and subsequent
aggregate-state alignment failure.

## Promotion (2026-09-07)

`row-value-alignment.patch`, `string-hash-alignment.patch` and
`join-row-alignment.patch` passed [sanitizer run 14](sanitizers-alignment-14.log)
after rebuilding from scratch, and were promoted into `native/lock.json`; see
[stage-07.md](stage-07.md) for the full promotion record and the
normal-engine production regression that followed.
