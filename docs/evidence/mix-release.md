# Relocated local Mix release — host proof and limits

2026-09-08. Stages 08/09 remain in progress. No stage/implementation is marked
complete, no target is release-supported, and nothing was uploaded/published.

The embedded-boot failure below is historical; see the subsequent
[embedded startup proof](embedded-startup.md) for the fix and new validation archive.

## What was proved

A genuine Mix release was assembled from the adapter-installed fresh consumer
`/private/tmp/aphid-adapter-consumer-4`, copied into a new build directory. The
consumer's Aphid source and installed native hashes were checked first. No
Aphid, dependency or native source was edited. `mix release --no-compile` reused
the already verified Elixir compilation and exact native candidate; this is a
release-assembly proof, not another fresh installation or source-build proof.

The release uses ordinary Mix options: `include_erts: true`, Unix executables,
`applications: [ex_unit: :load]`, and `steps: [:assemble, :tar]`. Standard overlays
include the unchanged 92-test suite, six examples, the existing DuckDB fixture
executable, and small validation scripts. These test extras make this a
**validation release**, not a production distribution package. Mix generated
its archive; the harness did not substitute an ebin/priv tarball for a release.

The archive was checked, extracted into a fresh directory, then renamed to a
path containing a space and non-ASCII text:
`/private/tmp/aphid-mix-release-4/relocated café release`.
The runtime sandbox denies all networking, native compiler execution, and reads
from the development project, original consumer, release assembly/build tree,
and installed host Elixir/ERTS. Only bundled ERTS and release code run. Mix and
Zigler are absent from the release. The assembly sandbox permits localhost only
for Mix's lock. An intentional negative compiler probe gets `:eperm`; no compiler
process executes. The compiler invocation log is absent and the Zig cache empty.

[Run 4](mix-release-4.log) records five successful watchdog-bounded commands:

| Check | Process time |
|---|---:|
| Mix release assembly and tar generation | 9.494 s |
| Actual network/compiler/source/host-runtime denial probes | 3.337 s |
| Bundled runtime, all 92 BEAM tests including core/FTS/vector/DuckDB | 19.886 s |
| Normal `bin/aphid_consumer start`, both NIFs, persistent write, graceful shutdown | 0.535 s |
| New release VM reopens the persistent database and returns the saved value | 0.431 s |

The `start` proof uses a VM test hook to query and terminate gracefully; it is
not merely an `eval` startup claim. All commands use `scripts/proof.py`
process-group watchdogs (120 s assembly, 180 s suite, 30 s other processes).
The ordinary 92-test suite retains its expected live-upgrade rejection.

[Final checks 2](mix-release-final-checks-2.log) pass: all **821 packaged files**
remain byte-unchanged, including all native libraries, receipt and licenses.
Two ExUnit `:tmp_dir` tests leave local scratch databases under `validation/tmp`;
these are generated test data, not archive contents or changed packaged files.
The separate persisted database is retained as evidence. Both database-close and
cross-VM reopen checks pass; no proof BEAM process remains. No sanitizer suite,
performance work, Linux provisioning/emulation or native rebuild occurred.

## Required runtime setting and discovered limit

Use this standard `rel/env.sh.eex` configuration for this local path:

```sh
export RELEASE_MODE=interactive
export RELEASE_DISTRIBUTION=none
```

Here `interactive` means **on-demand module loading**, not an interactive shell.
Normal `start` still starts the applications and remains running until stopped.
The validation archive already contains these settings.

Default **embedded-mode boot remains unproved and currently fails**. OTP 29's
`init.erl` collects preloaded `on_load` handlers and executes them in reverse
load order. Aphid's integrity loader calls `crypto.hash` before crypto's own NIF
is available during that phase, producing `undef`. Application dependency order
alone does not fix this early boot ordering. The local installed OTP source
`lib/erts-17.0.4/src/init.erl:1884–1921` and generated `start.script` establish the
cause. Mix's generated `env.sh` explicitly documents on-demand loading as the
standard alternative. We used that setting rather than changing crypto,
disabling checksums, rebuilding natives, or rewriting boot scripts. An embedded
boot solution remains a separate engineering gate.

The [full Mach-O audit](mix-release-native-audit-4.json) covers **22 files**:
bundled ERTS executables, OTP crypto NIFs, the four Aphid native libraries and the
DuckDB fixture. All are ARM64. Every non-system dependency is a resolving
`@loader_path` path within the release; only macOS system libraries/frameworks
remain external. This audits declared linkage, not every possible dynamic use.

**Bundled ERTS and crypto declare macOS 15.0.** Aphid's four native files and the
fixture still declare 13.3. Therefore this release cannot be presented as a
macOS 13.3 candidate. Execution was on macOS 26.6 only; neither 15.0 nor 13.3
minimum execution, static CPU floors, SDK symbol availability or other OTP
versions are proved. Do not lower load commands to manufacture compatibility.
A suitable separately built/verified ERTS is needed before pursuing a lower
whole-release OS floor. No installed toolchain was changed.

## Exact identities

Final local Mix release archive:
`artifacts/mix-release-validation-aarch64-macos-4.tar.gz`, **91,405,140 bytes**.
SHA256:
`b82a0a6981f09a0d982ff7700678a1a598134b3b52d70ffba434ec6ec0141fd7`.

Reused native candidate archive:
`artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz`,
**33,608,999 bytes**, SHA256:
`3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
Candidate `_build/nif-macos-13-3-4` used Zigler/Zig 0.16.0 and
`-Dtarget=aarch64-macos.13.3-none -Dcpu=baseline` (Apple M1 NIF baseline).
The native whole-closure CPU floor remains unverified.

| Unchanged native file | SHA256 |
|---|---|
| `Elixir.Aphid.Native.so` | `94b12c614c44b5e695b1233381dc3d4c21bdb21c7fd0287fedf185d4f5f74f77` |
| `Elixir.Aphid.Proof.so` | `ab08db391218885a20f3c35a95625d13f28bde5c6f7e7de5b8c1f946eba1f373` |
| `libaphid_bridge.dylib` | `5dbdd4d341d63da2ba189b908510c1a13ef1f548821a9beaa06ed787e3725110` |
| `liblbug.dylib` | `775f5babbe47f29f004585dd9f108f79a4564a06d4196e8133b4bc74dd193393` |

The normal engine remains
`3a2afd166d9f8854800a2023f73e29b8bb009de23df257180b5dbb95ba5b7a2c`,
and normal bridge remains
`66da4859f901aac548666e496be75c4e0ba34703be02fbc352eb971679f1a06f`.
Native lock remains
`d6c2db650b15ccb9ab77df54fcd9ad96dfc05da24b0104660c06caf9b575f955`,
including DuckDB **1.4.4**. `mix.lock` and all Aphid implementation files are
unchanged by this continuation.

Additional durable evidence:

- [Release identity](mix-release-identity-4.json), SHA256
  `3179c09e5744e0111816bcd2df67ae32d8f89cde49babe705d30c2aaa6fddf2a`.
- [All packaged file hashes](mix-release-files-4.json), SHA256
  `13d0e93b6da800018079c69bbdd98c1a3d6e63083f56cb46905bee7f8657fde8`.
- [Full native load commands/linkage](mix-release-native-audit-4.json), SHA256
  `e90612ef1334d42104a9b1183913dcc2b1692861b823c04760d698d538a9b858`.

## Retained failed attempts

1. [Run 1](mix-release-1.log), archive SHA256
   `7fccb5a415dbf5ffcccd1c81a729472576db464531d82c6df2b982edcc8ddcd9`:
   assembly/audit passed; guard assertion expected `:eacces` but the actual denied
   compiler error is `:eperm`.
2. [Run 2](mix-release-2.log), archive SHA256
   `c8005a43b5d0a3dd872949b5c1fd896ce584c14e8ebdb3f9de0bb74b3ef746b6`:
   guards and 92 tests passed; default embedded `start` hit the crypto boot-order
   failure and the 30-second watchdog killed its process group. The large raw
   early-boot diagnostic is retained.
3. [Run 3](mix-release-3.log), archive SHA256
   `9d7a0b2cf5c568bdf1d70046b7e01ec497820333f32516690b7588260df6e3cc`:
   on-demand loading and 92 tests passed; the proof's quoted VM startup expression
   was stripped by the argument-file parser. The corrected harness uses numeric
   Erlang charlists for that test-only hook. Its crash dump remains in that
   attempt; a separate parser diagnostic/dump remains under `/tmp/aphid-eval-args-check*`.
4. [Run 4](mix-release-4.log): all five watched commands pass. Its original final
   assertion mistakenly counted ExUnit-created scratch databases as changes to
   the package. The harness now checks every original file and allows only
   `validation/tmp` additions. [Final checks 1](mix-release-final-checks-1.log)
   verified identity but the outer sandbox blocked its last process inventory;
   [final checks 2](mix-release-final-checks-2.log) pass the corrected integrity
   checks and process-exit inventory. No passing test suite was rerun for that
   final bookkeeping correction.

All four archives, extracted directories, logs and crash evidence remain. Native
bytes are identical across attempts. Archive bytes differ because these are
separate Mix assembly runs (including generated cookie/metadata), not claimed
bit-reproducible builds. Each release directory occupied about 520 MiB with its
build/assembly/extraction copies; final available disk was about 2.9 GiB. Do not
start a large source build without checking resources; no old evidence was deleted.

## Reproduction and concrete handoff

From `zig_library`, choose unused output/destination names:

```sh
python3 -u scripts/mix_release.py \
  --consumer /tmp/aphid-adapter-consumer-4 \
  --destination /tmp/aphid-mix-release-NEW \
  --output artifacts/mix-release-validation-aarch64-macos-NEW.tar.gz
```

If the prior consumer is unavailable, first reproduce the
[local adapter installation](../local-installation.md) with the exact native
archive/checksum above. The script uses a copy of that consumer and never changes
its original evidence. Installing deps/assembling still needs host Elixir/OTP and
Mix/Hex; relocated runtime uses bundled Elixir/ERTS with no development dependency.
This says nothing about network artifact delivery or a published Hex installation.

Changed files this continuation: new `scripts/mix_release.py`; `README.md`,
`docs/local-installation.md`, `docs/status.md`, `docs/release-checklist.md`; this
handoff, new evidence logs/JSON manifests and four local release archives with
checksum sidecars. Root `library/`, `source/`, and `hex_consumer/` were preserved.
No Aphid loader/NIF/engine/dependency-source changes were needed for the configured
local release path.

Next narrow engineering gate: design and prove embedded-mode startup if it is
required, while retaining checksum verification before any NIF load. Keep the
working interactive-mode archive as the baseline. Separately prove a fresh
source-mode consumer from packaged/verified native inputs when resources permit.
Keep network delivery, production release/package inventory (including bundled
OTP/Elixir notices), actual minimum OS/CPU and other OTP execution, both Linux
targets and outstanding sanitizer mutation/cancellation/GC gates open. No Linux
runner is available; do not provision/emulate one. Keep performance work separate.
Do not mark a stage complete or claim release support based on this host proof.
