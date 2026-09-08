# Explicit macOS NIF candidate and fresh local Mix consumer

2026-09-07. Stages 08/09 remain in progress. No release support, publication,
upload, minimum-OS execution or Linux execution is claimed.

## Pinned build mechanism

Read Zigler **0.16.0** locally: `lib/zig/command.ex:155–188` appends
`module.build_flags` to `zig build`; `templates/build_mod.zig.eex` uses
`b.standardTargetOptions` for the NIF and `b.graph.host` for executable semantic
analysis. `lib/zig/target.ex`'s `TARGET_ARCH/OS/ABI` route cannot express the CPU
model or versioned macOS floor. Zig **0.16.0** `lib/std/Build.zig:1473` accepts
`-Dtarget` and `-Dcpu`. The smallest existing supported interface is:

```elixir
build_flags: ["-Dtarget=aarch64-macos.13.3-none", "-Dcpu=baseline"]
```

Zig 0.16.0 `lib/std/Target.zig:2008` resolves this macOS ARM64 baseline to
**apple_m1**, not generic ARMv8. No installed dependency, SDK or global toolchain
was edited. `scripts/nif_target.py` adds the flags only in its isolated source
copy and reuses the existing compiled build dependencies and normal bridge/engine.
It never configures/rebuilds the engine or consumes shared extension archives.
The normal application/NIF build is not overwritten or promoted.

From `zig_library/`:

```sh
python3 -u scripts/nif_target.py --name nif-macos-13-3-4
```

Use a **new** name on repetition. [Attempt 1](nif-target-build-1.log) failed on
Mix's local TCP lock; [2](nif-target-build-2.log) lacked the staging parent;
[3](nif-target-build-3.log) built both NIFs but lacked telemetry's native lock
input. All attempts remain. [4](nif-target-build-4.log) passes in 10.648 s with
local-socket escalation and `ZIG_GLOBAL_CACHE_DIR=/tmp/aphid-zig-cache`.
The script uses the external `scripts/proof.py` watchdog.

## Exact runtime artifact and closure

Artifact: `artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz`
(33,608,999 bytes), SHA256:
`3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.

```sh
python3 -u scripts/runtime_bundle.py \
  --app-build _build/nif-macos-13-3-4/_build/test/lib/aphid \
  --candidate-identity _build/nif-macos-13-3-4/candidate.json \
  --output artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz
```

[Packaging/runtime log](runtime-bundle-target-1.log) records all seven Mach-O
files as ARM64 with **13.3** deployment load commands: Native, Proof, bridge,
engine, fixture, lifecycle and extension-concurrency. Non-system dependencies
are bundled and loader-relative; old rpaths are removed and changed files
ad-hoc signed. Only macOS system libraries remain external. No sanitizer imports
are present. Native lifecycle passes (2.683 s), then 300 concurrent FTS/vector/
DuckDB reads (0.781 s), then **92 BEAM tests** (16.676 s process time), after
checksum verification, extraction and relocation into a path containing a space
and non-ASCII text. The child sandbox denies networking and development-tree
reads. Unsafe-member and checksum/identity rejection checks also pass.

[Full audit](nif-target-audit-1.log) retains `file`, complete `otool -l/-L`,
undefined symbols, NIF exports, semantic-section presence and generated NIF
entry declarations. [Artifact identity](nif-artifact-identity-3.json) records
source/generated-build/tool hashes and the complete shipped native file hashes.
Both NIFs declare API **2.18**, `min_erts = "erts-17.0.4"`, `beam.vanilla`, and
module identities `Elixir.Aphid.Native` / `Elixir.Aphid.Proof`. Only Elixir 1.20.0 /
OTP 29.0.4 on macOS 26.6 has run them; this is not an older-OTP compatibility claim.

The normal bridge remains SHA256
`66da4859f901aac548666e496be75c4e0ba34703be02fbc352eb971679f1a06f`,
and the normal engine remains
`3a2afd166d9f8854800a2023f73e29b8bb009de23df257180b5dbb95ba5b7a2c`.
Packaging changes loader paths/signatures only in copied binaries. Normal build
commands contain no `-march=native` or `-mcpu=native`; this does **not** prove the
CPU floor of all static objects, runtime dispatch or SDK symbol availability.
The entire closure's actual minimum-OS/CPU execution remains unavailable.

## Actual fresh Mix consumer: local staging contract

`scripts/precompiled_consumer.py` verifies the caller-pinned runtime archive
checksum and manifest before staging its **complete** `priv/lib` into a copied
Aphid source dependency. `APHID_NATIVE_PRECOMPILED` adds the same explicit local
Zigler path selection already used for Proof. These environment paths are trusted
inputs to a local proof, **not checksum-verifying production installer APIs**.

The harness verifies all **13 Hex archive SHA256s** against `mix.lock`, extracts
unmodified source dependencies, and selects them as root Mix path overrides.
There are no reused Aphid/dependency BEAM files or native/Zig build caches. An
installed Hex 2.5.1 tool is copied into a fresh Mix home as a recorded installer
prerequisite. Elixir/OTP and Apple's `otool` remain host prerequisites; Zigler's
macOS precompiled semantic reader requires `otool`. CommandLineTools-free
installation is not proved. There are no reads from the development project or
installed Zig directory during the sandboxed Mix commands.

Failed attempts are preserved:

- [1](fresh-mix-consumer-1.log): wrong expected dependency count in the harness.
- [2](fresh-mix-consumer-2.log): symlinking the OTP launcher broke its path lookup.
- [3](fresh-mix-consumer-3.log): missing Hex installer in the fresh Mix home.
- [4](fresh-mix-consumer-4.log): all 92 tests pass, but the final invocation guard
  correctly fails: Zigler's optional `Zig.Formatter` invokes the Zig sentinel.
- [5](fresh-mix-consumer-5.log): Zig genuinely absent; all 92 tests pass and no
  compiler invocation occurs. Zigler catches discovery failure and warns that
  its optional formatter is inactive. This is retained behavior, not suppressed.
  [Guard attempt 1](fresh-mix-guards-1.log) proves compiler/project/Zig denial,
  but its network timeout **does not prove denial**; its final network assertion
  overstates the evidence and is superseded by the next guard/run.

[Guard 2](fresh-mix-guards-2.log) uses explicit bind/inbound localhost rules and
an outbound remote-localhost rule. An external socket gets `EPERM`; localhost
bind/connect/accept succeeds. The final fresh run uses this corrected policy.

```sh
python3 -u scripts/precompiled_consumer.py \
  --archive artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz \
  --sha256 3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034 \
  --destination /tmp/aphid-fresh-mix-6
```

Use a new destination. [Final run](fresh-mix-consumer-6.log) is the authoritative
fresh-install check. Mix dependency/application compilation and tests use
`proof.py` watchdogs (300/120/180 seconds); C/C++ build tools are guarded,
Zig is absent, the Zig cache stays empty, and installed native file hashes must
exactly equal the verified bundle. This is fresh **Elixir compilation using
precompiled NIFs**, not merely starting previously built ebin files.
Run 6 passes all **92 tests** in 15.977 s process time. The optional formatter
warning is retained. [Final checks](nif-consumer-final-checks-1.log) verify
signatures, ARM64/13.3/no-rpath assertions, unchanged native inputs, identical
installed native hashes, empty Zig cache and absent compiler-invocation log.

Prepared local consumer fixture (sources, pinned extracted dependency sources,
complete native sidecars, tests and input hashes; **not Hex/Mix release**):
`artifacts/fresh-mix-local-aarch64-macos-13.3-1.tar.gz`, 34,024,269 bytes,
SHA256 `c724981605cec376f015b2d0c934b627e5acc20c56959dee2aadb7b5b04f0748`.
Created before compilation in run 5; it contains no compiled BEAM dependencies.
Its source/sidecar identity is compared with final run 6 in the final checks.
The runtime artifact remains an ebin/priv validation bundle.

## Concrete handoff and open gates

Keep using the verified normal engine and candidate artifact above. Do not
rebuild unchanged engines or repeat unchanged sanitizer suites. TSan coverage
and its test-only 1 GiB range remain as recorded in [tsan.md](tsan.md).

1. Exercise this exact candidate on actual covered/minimum macOS and CPU systems;
   inspect SDK import availability and static dependency instruction floors.
   Keep 13.3 as a declaration/build goal until then. Test NIF API/ERTS on each
   proposed supported OTP release; generated `min_erts` is not a tested matrix.
2. Design the minimal production sidecar/checksum adapter around Zigler's
   single-NIF precompiled path. Preserve explicit source selection; do not
   silently fall back. Prove missing/corrupt/unsupported/wrong-architecture/
   incompatible/unloadable installer diagnostics. Address the optional formatter
   discovery warning and Apple `otool` dependency explicitly.
3. Test a genuine source-mode consumer from locked packaged/verified inputs and
   an extracted/relocated offline **Mix release**. Current local path overrides,
   pre-staged archives and host installer tools do not prove a normal Hex install.
4. Obtain real Linux runners separately. No x86_64 Linux runner is available;
   Colima stays stopped. No provisioning, emulation, sanitizer reruns or
   performance optimization was performed in this task.

Native lock SHA256 remains
`d6c2db650b15ccb9ab77df54fcd9ad96dfc05da24b0104660c06caf9b575f955`,
including DuckDB **1.4.4**. Root `library/`, `source/`, and `hex_consumer/` were
preserved. No stage or overall implementation is marked complete.
