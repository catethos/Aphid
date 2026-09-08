# Stage 08 — local host runtime bundle validation

In progress, 2026-09-07. No release support or stage completion is claimed.
Working directory: `/Users/catethos/workspace/ladybugex/zig_library`.

`scripts/runtime_bundle.py --output artifacts/runtime-validation-aarch64-macos-N.tar.gz`
packages the already verified normal engine, bridge, compiled Aphid/telemetry,
required test NIFs, fixture generator, tests/examples and hash-checked native
notices. This is a local validation bundle, not an installer, source fallback,
Hex package or Mix release. Existing outputs are never overwritten.

The script rewrites non-system dependencies to loader-relative paths, removes
old rpaths, re-signs changed Mach-O files, requires ARM64, and checks for NIF
entry points and accidental sanitizer imports. Each archive contains a per-file
SHA256 manifest and locked native manifest; its external SHA256 is recorded in
a sibling file. Extraction verifies the archive digest first, rejects absolute
and parent paths, symlinks, hard links and special files before extracting into
a new directory, then checks lock identity and every extracted file hash.

The first artifact was generated in [run 1](runtime-bundle-1.log); traversal,
absolute path, symbolic/hard link and corrupt checksum rejection checks passed.
The offline subprocess could not start inside the existing sandbox
(`sandbox_apply: Operation not permitted`, exit 71); this attempt is not a pass.
[Run 2](runtime-bundle-2.log) extracts the same artifact and runs outside the
outer sandbox, with a child sandbox denying **all networking and all reads from
the development directory**. All 91 tests pass in 18.603 seconds, including core,
FTS, vector, DuckDB and all six examples. Zig is absent from the runtime code
path. The expected NIF upgrade rejection warning is part of the existing module
lifecycle test; this is a normal-engine run, not a sanitizer result.

Artifact 1: 33,565,504 bytes; SHA256
`730e5cd0d9aef4fbd6f95d5b2edad5725c7bdad82278158b5b6c0059077eeb8d`.
Artifact 2 adds the new queued-caller-death case and packaged native tests;
its results are recorded below.

## Deployment-floor finding

`vtool -show-build` in run 1 reports **26.6** for both Native and Proof NIFs,
but **13.3** for the bridge, engine and fixture executable. Consequently the
whole bundle cannot be represented as a macOS 13.3 artifact. No engine patch or
minimum-OS workaround was applied. Zigler's host-default target selection must
be replaced by a proved explicit target/CPU recipe, then the entire rebuilt
closure inspected and run on the declared covered/minimum systems.

System dependencies remain macOS system libraries. ARM64 architecture checks
and absence of `-march=native` in the inspected normal Ninja files do not prove
a portable CPU instruction floor. There is no Linux artifact or tested glibc
floor. Elixir/OTP on the host remain runtime prerequisites outside this bundle.

Fresh Mix precompiled/source installs, compiler-free empty-cache installation,
real installer error diagnostics (including unloadable or wrong-architecture
payloads), relocated Mix release, minimum OS/CPU and both Linux rows remain
open. See [the release checklist](../release-checklist.md).

## Updated artifact and complete host suite

[Run 3](runtime-bundle-3.log) builds artifact 2 with the queued-caller-death test
and native lifecycle/extension-concurrency executables. Architecture, loader
inspection, NIF exports, sanitizer-import rejection, license hashes, archive
checksum and unsafe extraction checks pass. After extraction and relocation,
with networking and development-tree reads denied, the packaged native lifecycle
and 300-read extension workload pass, followed by **92 BEAM tests**, seed 0,
19.355 seconds process time. No native compilation or Mix invocation occurs in the consumer;
Zig is not loaded. This remains an ebin/priv runtime proof using the installed
Elixir/OTP, not an empty-cache precompiled Mix install.

Artifact 2: `artifacts/runtime-validation-aarch64-macos-2.tar.gz`,
33,612,443 bytes; SHA256
`1d0363f075ec8a484cb75af31e451ff137b3c3345d6bca0b8ab1ec19be905e7a`.
Its native lock remains unchanged and DuckDB is 1.4.4. Normal tests alone do not
prove sanitizer safety. No artifact was published or uploaded.

Additional local-validator failure checks are retained in
[attempt 1](runtime-artifact-failures-1.log) and the checked-in
`rejection_checks()` rerun [attempt 2](runtime-artifact-failures-2.log): missing
artifact, unsupported target, mismatched engine lock, mismatched contents and
unsafe members reject with the expected distinct errors. These are Python
validation checks; actual installer wrong-architecture/unloadable diagnostics
are still unimplemented/unproved. To repeat only these inexpensive checks:

```sh
python3 - <<'PY'
import sys, tempfile
from pathlib import Path
sys.path.insert(0, 'scripts')
from runtime_bundle import rejection_checks
with tempfile.TemporaryDirectory() as temp:
    rejection_checks(Path(temp))
PY
```

## Explicit-target candidate and fresh local Mix continuation

The historical 26.6 NIF finding above still applies to artifacts 1/2 and the
normal development build. New isolated candidate artifact 3 declares 13.3 for
all seven Mach-O files and passes relocated native tests and all 92 BEAM tests.
The final local fresh Mix consumer compiles pinned source dependencies and
Aphid Elixir using the same verified precompiled sidecars; all 92 tests pass
without native compiler invocation or reads from the development project.

See [full evidence, exact checksums, failed attempts and handoff](nif-target-and-consumer.md).
The candidate's whole-closure minimum OS/CPU execution, production installer,
source consumer, Mix release and Linux gates remain open. Zigler's optional
formatter discovery warning and macOS otool requirement remain visible.
No stage or release support is declared complete.
