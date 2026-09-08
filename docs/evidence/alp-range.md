# ALP conversion range

[Sanitizer run 7](sanitizers-alignment-7.log) aborts when bundled ALP compression
converts `1e+10` to `int` while choosing compression settings for FLOAT data.
`FloatingToEncodedType<float>` is `int32_t`, but the existing early check uses
64-bit encoding limits. Its failure sentinel also casts that 64-bit limit to
the narrower destination. The scalar path called with `SAFE=false` bypasses
the early check entirely.

The candidate `native/patches/candidates/alp-conversion-range.patch` uses the
destination integer's maximum as the sentinel and checks the scaled, rounded
value immediately before conversion in both paths. The upper bound is the
exact power of two above the signed maximum; the lower bound is its negative.
The upper comparison is exclusive because converting the integer maximum to a
float can round upward. The compression algorithm's existing decode/exception
comparison remains responsible for retaining values that do not round-trip.

[Focused test](alp-range-1.log) passes under ASan/UBSan for float and double:
upper-bound overflow, larger negative values, finite maxima, infinities, NaNs,
and ordinary exact integers, in both template modes. The regression is in
`native/tests/alp_range.cpp` and is included in the sanitizer driver.

[Sanitizer run 8](sanitizers-alignment-8.log) passes lifecycle, focused string
hashing and fixture creation, then gets past the earlier ALP failure in the
feature create workload. It aborts on a separate `CountState` alignment defect
in aggregation (`function/aggregate/count.h:17`). Aggregate state is stored
inside packed factorized-table rows; this needs an allocation/layout fix because
it contains live C++ objects, not merely serialized scalar bytes.

The ALP candidate is applied locally for hardening but remains outside the lock
and the normal development engine. No full sanitizer or release pass is claimed.

## Promotion (2026-09-07)

`alp-conversion-range.patch` passed [sanitizer run 14](sanitizers-alignment-14.log)
after rebuilding from scratch, and was promoted into `native/lock.json`; see
[stage-07.md](stage-07.md) for the full promotion record and the normal-engine
production regression that followed.
