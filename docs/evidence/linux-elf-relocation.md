# Linux ELF relocation and metadata extraction

Full [run 34188940428](https://github.com/catethos/Aphid/actions/runs/34188940428)
uses source `d34ea305346442e6fee5b73b403a91e338d501fb`. Both architectures pass
the locked native/NIF build and 92 BEAM tests. Neither job reaches its
success-gated artifact upload. Full raw logs are retained as `linux-*-run-7.log`.

On x86_64, packaging rejects a sanitizer-named symbol in Proof. It also records
an ELF PHDR mapping error after adding `$ORIGIN` with patchelf. Small-NIF
[run 34192327760](https://github.com/catethos/Aphid/actions/runs/34192327760)
(source `6a8d188`) reproduces the actual objcopy rejection of that relocated ELF.
The symbol diagnostic shows defined weak UBSan handlers and no undefined
sanitizer references. The original audit accidentally checked all definitions,
unlike the existing macOS external-runtime audit. The corrected check rejects
undefined sanitizer references; this does not claim absence of built-in handlers
or complete instrumentation coverage.

ARM64 in run 7 packages and safely extracts the bundle into a Unicode path.
The relocated native lifecycle, concurrent extensions, feature create/reopen and
92 BEAM tests pass with development trees hidden, compilers masked and external
networking unavailable. Normal Hex dependency acquisition and offline compilation
then install the full bundle through the adapter. The following consumer compile
rejects a changed Native NIF hash. Runtime consumer and real failure checks do
not run. The ephemeral archive identity is retained in
`linux-aarch64-bundle-identity-7.json`, explicitly unsuitable for promotion.
Its archive SHA256 was
`2e84318365aba54cd9ed115f264248b94d02ab0a77fcba8fe82a8da18b0d614e`;
the local Hex source archive SHA256 was
`43e21046fba325aec14ed766761e27b02761f7bce0ad8c2c358664f38ddf93b9`.
Neither binary archive was retained after the failed job.

Zigler 0.16.0 `lib/zig/sema.ex:710` calls objcopy to dump `.sema` without an output
ELF filename. GNU objcopy documents that omitting the output filename rewrites
the input via a temporary file: [official manual](https://sourceware.org/binutils/docs/binutils/objcopy.html).
The adapter's integrity rejection is therefore useful evidence, not a reason to
accept a changed receipt or disable checksums.

Source `99a43a9` reserves the Linux Proof NIF's `$ORIGIN` at link time through
candidate-only Zigler options. Packaging skips redundant rpath edits, normalizes
the NIF with the same metadata extraction before hashing, and requires a second
extraction to preserve both native and metadata hashes. ELF audit diagnostics now
fail explicitly. No dependency source or global toolchain is changed.
The small-NIF preflight also asserts unchanged hashes after actual Zigler
precompiled compilation. [Run 34192694429](https://github.com/catethos/Aphid/actions/runs/34192694429)
passed native metadata normalization and actual precompiled compilation/tests
on both architectures, then failed the new installed-hash assertion. Zigler skips
copying when a destination NIF already exists; this older small proof had reused
the source-build output. The fixture now removes that destination after preserving
its source artifact, exercising the real copy path. This is a test-harness fix;
the full bundle installer already stages an empty consumer and exact native bytes.
No full engine rebuild was started for these diagnostic iterations.

The public Linux catalog remains empty. These checks do not close minimum-system,
CPU, cross-build, Mix release, network delivery, attribution or publication gates.
The macOS runtime and DuckDB 1.4.4 lock remain unchanged. No stage is complete.
