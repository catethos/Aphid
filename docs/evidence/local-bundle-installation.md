# Local bundle adapter evidence and handoff

2026-09-08. Stages 08/09 remain in progress; no stage or implementation is marked
complete and no target is release-supported. Nothing was published or uploaded.

## Decision and code

Read plan Sections 8–9 and the prior status, target/consumer evidence, artifact
identity 3, consumer 6, final checks 1 and release checklist before implementation.
The applicable user AGENTS instructions require narrow, verified changes. No
additional AGENTS file applies to the edited Aphid paths.

Pinned Zigler 0.16.0 flow: `Zig.Module.normalize_precompiled/2` accepts one local
NIF and can return nil under `ZIGLER_PRECOMPILE_FORCE_RECOMPILE`; its web path also
returns nil for an absent selected checksum. `Zig.Sema` reads a macOS NIF's
`__DATA,__sema` using Apple `otool`. `Zig.Command.compile!/1` skips native
compilation and copies just that NIF, only if missing or force-reloaded. Its
standard loader logs load errors; Aphid's Native loader already overrode loading
to preserve load failure semantics. Python `runtime_bundle.extract` validates
archives for proof tooling but did not provide a Mix installation API.

The adapter is `mix/aphid_bundle.exs`, required by `mix.exs` and placed before
Mix's ordinary compilers. It supplies Zigler's local single-NIF paths only after
verifying the independently supplied archive SHA256, safe member table, content
manifest, target/runtime/native-lock identity, native interface sources and the
reviewed four-file native fingerprint. It installs the entire sidecar closure
plus licenses atomically from a fresh staging directory; it never installs the
archive's BEAM files. Receipt/embedded loader hashes preserve integrity checks
at startup, before either NIF loads. No package manager, network transport,
dependency modification, global toolchain change or native rebuild was added.

The reviewed identity is `native/local-bundle.json`, derived from
[nif-artifact-identity-3.json](nif-artifact-identity-3.json). It is a local allowlist
for this candidate, not a new release matrix or a promise to accept other builds.
NIF API 2.18 and ERTS 17.0.4 are tied to the reviewed binary hashes. The compiler
currently requires Elixir 1.20.0 and ERTS 17.0.4. Native interface input changes
or different native hashes require a matching reviewed build identity. Missing
selection on an existing bundle build is rejected; it cannot silently switch
to source. An empty development/source build retains its existing selector.

## Exact artifacts and native identities

Reused archive, **33,608,999 bytes**:
`artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz`

SHA256: `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
No new runtime archive was created. Candidate `_build/nif-macos-13-3-4`, Zigler /
Zig 0.16.0, flags `-Dtarget=aarch64-macos.13.3-none -Dcpu=baseline`, was reused.

| Installed file | SHA256 |
|---|---|
| `Elixir.Aphid.Native.so` | `94b12c614c44b5e695b1233381dc3d4c21bdb21c7fd0287fedf185d4f5f74f77` |
| `Elixir.Aphid.Proof.so` | `ab08db391218885a20f3c35a95625d13f28bde5c6f7e7de5b8c1f946eba1f373` |
| `libaphid_bridge.dylib` | `5dbdd4d341d63da2ba189b908510c1a13ef1f548821a9beaa06ed787e3725110` |
| `liblbug.dylib` | `775f5babbe47f29f004585dd9f108f79a4564a06d4196e8133b4bc74dd193393` |

Normal bridge remains
`66da4859f901aac548666e496be75c4e0ba34703be02fbc352eb971679f1a06f`;
normal engine remains
`3a2afd166d9f8854800a2023f73e29b8bb009de23df257180b5dbb95ba5b7a2c`.
`native/lock.json` remains
`d6c2db650b15ccb9ab77df54fcd9ad96dfc05da24b0104660c06caf9b575f955`,
with DuckDB **1.4.4**. `mix.lock` is unchanged. The reviewed identity file is
SHA256 `2553be69f0cbb1e161014b0ccd297d1f046b3d9f5edc682644d97d72de0c6d43`.

## Final checks and retained attempts

[Final fresh consumer run 4](local-bundle-consumer-4.log) uses
`/private/tmp/aphid-adapter-consumer-4`. Its source dependency contains no staged
`priv`, compiled BEAM dependencies, or build caches. All 13 dependency source
archives are pinned and source-only. Mix dependency/application compilation
passes in **28.056 / 5.252 seconds** under the compiler-execution/project-read
sandbox and localhost-only network rules. The archive is then renamed away and
all Aphid installation variables are removed for runtime: **92 tests pass**, in
**17.233 seconds** process time, including core/FTS/vector/DuckDB and six examples.
The [fresh input manifest](local-bundle-inputs-4.json) is retained with SHA256
`2d99a8e719b01c0b2be085ac8c167e7a2f483aacf24a5669b1429945299a4805`.
The Zig cache remains empty, the compiler invocation log is absent, and all four
installed native hashes equal the original archive. `proof.py` process-group
watchdogs bound compilation and testing (300/120/180 seconds).

[Final failure run 4](local-bundle-failures-4.log),
`/private/tmp/aphid-adapter-failures-4`, passes **23 actual Mix adapter rejection
cases**. These cover missing archive/pin/sidecar, bad checksum/tar/manifest,
unsupported target, incompatible lock/native fingerprint, wrong architecture,
unloadable header, conflicting/forced/lost selection, traversal, absolute and dot
paths, duplicate/case-colliding members, file/directory conflict, symlink,
hardlink and FIFO members. Each checks the real task's `Mix.Error` category and
no-source-fallback diagnostic. No accepted `priv` or outside file is written.
Hostile fixtures are small synthetic archives, not new runtime candidates.

Three additional sacrificial BEAM processes load **both** actual installed NIF
modules: missing sidecar, corrupt sidecar, and executable-mapping denial. The
first two fail closure checks before load. The last uses unchanged native bytes
and reaches actual `dlopen`, returning `:load_failed` with the sandbox's `mmap`
reason and the `[unloadable]` diagnostic. Both modules return `:on_load_failure`.
These are loader/installer paths, not Python validator-only checks. Actual
wrong-architecture host execution is not claimed; that rejection uses a mutated
Mach-O header fixture.

[Final identity/source checks](local-bundle-final-checks-1.log) verify the normal
engine/bridge/lock, archive identity, installed closure and licenses, absent
compiler log, empty Zig cache, final copied Aphid source equality, and all 13
unmodified dependency source archives. Default development and explicit source
selection remain no-ops in an empty build; no source build was performed. Code
checksums and exact commands are retained there. Python harness syntax and Elixir
formatting were checked; no sanitizer or performance suite was repeated.

All attempts remain:

- [Consumer 1](local-bundle-consumer-1.log) stopped before compilation because the
  outer sandbox denied creation of the nested proof sandbox.
- [Consumer 2](local-bundle-consumer-2.log) passed 92 tests for the initial adapter.
- [Consumer 3](local-bundle-consumer-3.log) passed 92 tests after reviewed identity
  checks and removal of the archive/installer variables at runtime.
- [Consumer 4](local-bundle-consumer-4.log) is authoritative for final code,
  including archive collision checks and the preserved legacy Proof loader path.
- [Failure 1](local-bundle-failures-1.log) passed earlier rejections but its last
  mapping-denial check was blocked by the outer sandbox. [2](local-bundle-failures-2.log)
  proved real `dlopen` denial; [3](local-bundle-failures-3.log) covered both NIF
  loaders and native identity. [4](local-bundle-failures-4.log) covers final code.

The nested sandbox proofs were rerun with the execution permission needed for
`sandbox-exec`; the child compiler/network/project restrictions stayed active.
Zigler's optional absent-Zig formatter warning is retained, as are dependency
compiler warnings and the expected native live-upgrade rejection test.

## Changed files and concrete handoff

Implementation: `mix.exs`, new `mix/aphid_bundle.exs`, new
`lib/aphid/bundle_loader.ex`, `lib/aphid/native.ex`, `lib/aphid/proof.ex`, and new
`native/local-bundle.json`. Proof tooling: `scripts/precompiled_consumer.py`, new
`scripts/local_bundle_failures.py`, and surgical source-copy additions in
`scripts/nif_target.py` / `scripts/proof.py` required by the new Mix helper.
Documentation: `README.md`, `docs/local-installation.md`, `docs/status.md`,
`docs/release-checklist.md`, this handoff and new evidence logs. Root `library/`,
`source/`, and `hex_consumer/` were preserved. Old evidence/artifacts remain.

Use [the local installation recipe](../local-installation.md) and the exact
candidate above. The next locally actionable distribution gate is a genuine
**Mix release** made from this adapter-installed consumer, relocated and started
offline with compiler/development reads denied. Verify both NIFs and the native
closure after relocation; do not label the current ordinary Mix consumer as a
release. A fresh source-mode consumer from packaged/verified sources is separate.

Keep network artifact delivery/normal Hex distribution open. Keep actual minimum
macOS/CPU execution, SDK/static instruction compatibility and other OTP versions
open. All seven packaged Mach-O files declaring 13.3 remains a declaration, not
minimum-system execution evidence. No Linux runner is available; neither Linux
provisioning nor emulation occurred. Preserve the outstanding sanitizer mutation/
cancellation/GC gates and TSan's test-only 1 GiB limitation. Leave performance
investigation separate. Do not rebuild unchanged natives, trust shared extension
archives, publish/upload, or mark any stage/implementation complete.
