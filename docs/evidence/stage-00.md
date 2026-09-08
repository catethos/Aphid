# Stage 00 — toolchain and precompiled proof

2026-09-07 follow-up: `scripts/proof.py` now copies just the toolchain proof
into `_build/toolchain-proof`, keeping it independent of later engine/API code.
`stage-00-run-5.log` passes source compilation, both two-test runs, compilation
with a rejecting Zig executable, and the relocated dependency-free consumer.
The new proof artifact SHA256 is
`ce923e1469d7befde9289464954730d5206bab6a1790d1c87d0c6471dbb5ed76`.
It remains a small toolchain proof, not the packaged database library.

Date: 2026-09-07. Working directory: `/Users/catethos/workspace/ladybugex/zig_library`.

Selected Zig 0.16.0 with Hex Zigler 0.16.0 based on the package's own
`Zigler.MixProject.zig_version/0`, then compiled and executed it. Host:
macOS 26.6 (25G72), ARM64; Elixir 1.20.0, OTP 29.0.4; CMake 4.4.3.
Inputs are recorded in `native/lock.json` and `mix.lock`.

## Successful checks

`ZIG_GLOBAL_CACHE_DIR=/tmp/aphid-zig-cache python3 scripts/proof.py`
completed with exit 0. Full output: `stage-00-run-3.log`.

- Source mode: 2 ExUnit tests, seed 0, 0 failures. Native C++ addition widens
  before adding; out-of-range input is rejected. C ABI version is 1.
- Resource test retains the token in a child process, confirms the live count,
  then observes cleanup after the process exits (bounded wait of 1 second).
- Precompiled mode: `mix compile --force`, exit 0, with `ZIG_EXECUTABLE_PATH`
  pointing to an executable that exits 99 on any invocation. Repeated the 2 tests,
  seed 0, 0 failures. Existing Zigler dependencies were already compiled.
- Fresh relocated runtime: separate OS process with only Aphid's `ebin/priv`;
  asserts Zig is absent, checks ABI, arithmetic and resources, exit 0.
  Consumer elapsed 0.621 seconds. This proves runtime without the compiler;
  it does not yet prove a fresh Hex source installation without compilers.
- Process-group watchdogs: 600 seconds per build command, 30 seconds consumer;
  expiry kills and reaps the group and fails the proof.

Artifact: `artifacts/proof/Elixir.Aphid.Proof.so`, SHA-256
`b793ca76b81864f8d1dd67cc9ee6bc2ef48e6a1ac824f3de92a5cc9f5e0189ad`.
`otool -L` reports only `/usr/lib/libSystem.B.dylib` as a dependency
(the `@rpath/libElixir.Aphid.Proof.dylib` entry is its install name).

## Failed attempts and corrections

Sandbox DNS denied initial source retrieval; approved network execution worked.
Mix's local TCP filesystem lock needed approved execution. Initial `mix test`
subsequently passed 2 tests with seed 90412.

`stage-00-run.log`: explicitly passing `precompiled: nil` is rejected by Zigler.
`stage-00-run-2.log`: a dynamic `use` option expression was invalid. Corrected
by setting Zigler's module options only when the proof environment variable exists.
Both failures occurred before test execution; neither counts as a pass.

## Source and dependency inventory

Ladybug commit `f150bddf7d01c65e5308384b8a064af1e2347701` pins extension
`89fceca9aa0c3d404984b84697a502ac6a088536`. Both are MIT-licensed.
The engine vendors its core libraries; the extension vendors Snowball and uses
the engine's RE2, cppjieba and SimSIMD. DuckDB 1.4.4 (MIT) includes
core_functions/parquet and vendored dependencies. `native/licenses.json`
records paths and SHA-256 for 63 license/notice files. Final packaging must copy
their contents and audit the actual linked closure.

Upstream CMake found Homebrew OpenSSL 3.6.4. That discovery is not a reproducible
bundle: its source revision/build and dependency relocation remain to lock.
DuckDB 1.4.4 exports bundled extension libraries through `duckdb_static`'s
interface, but lacks the separate generated loader target expected by newer
extension recipes. The configure warning is retained; linkage/behavior must
decide compatibility, not the warning alone.

Zigler precompiled mode accepts a single library and extracts semantic metadata
using `otool` on macOS. It does not supply sidecar bundle installation. Zigler's
own dependency compilation builds its formatter NIF, so the clean compiler-free
package path still needs a minimal adapter or packaged BEAM proof.

Next: complete native dependency pins and run `python3 scripts/build.py engine
--jobs 3`; keep all feature and target support claims pending runtime tests.

## Follow-up, same date

Locked OpenSSL 3.6.4 archive SHA-256
`9bffaa1ad1e07b354c21bd3324ec02fa15579f45a7d0494b3e74bc449b7333ef`;
built `darwin64-arm64-cc no-shared no-tests` successfully with `scripts/build.py
openssl --jobs 2` (see `openssl-build.log`). License inventory now contains 66
files. Apple clang 17.0.0 and SDK 26.1 are recorded in the lock manifest.

The engine compile rejected macOS 13.0 because floating `to_chars` is available
starting at macOS 13.3. The candidate engine/DuckDB floor is now 13.3; OpenSSL
builds with its compatible 13.0 floor. No OS-minimum runtime claim is made.

Finalized proof adds an unconditional source `mix compile --force`, preventing
a previous precompiled run from masquerading as a source rebuild. Run 4
(`stage-00-run-4.log`) passed both 2-test runs with seed 0, precompiled
compilation with the rejecting Zig executable, and the relocated consumer
(0.877 seconds). Artifact SHA-256 was unchanged. This is repeatability evidence,
not a general bit-reproducibility claim. Formatting was applied to the new files.

The toolchain gate is passed. Stage 08 still owes a clean-cache compiler-free
package install and the complete sidecar bundle/target tests.
