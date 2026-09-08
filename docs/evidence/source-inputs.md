# Source-package inputs and private directory wiring

2026-09-08. Stages 08/09 remain in progress. No source installation, stage,
implementation or target is marked complete/supported. This follows the
[source preflight](source-preflight.md).

## Changes and scope

The Hex allowlist now includes native/bridge.cpp, native/CMakeLists.txt, the
locked patches, scripts/build.py, scripts/proof.py and scripts/source_preflight.py.
The new local package is still version 0.1.0-dev; it contains no compiled native
libraries or dependency/build caches. Earlier package artifacts remain unchanged.

`scripts/build.py --source-root PATH --output PATH` now routes source acquisition,
OpenSSL Configure, DuckDB/Ladybug CMake sources and bridge LADYBUG_SOURCE to the
explicit private source tree. Bridge CMake sources remain package-local. Begin
with fetch into new empty disjoint directories. Each gets a small ownership
marker binding the canonical source/output paths, normalized native lock identity,
target, mode, instrumentation and optional toolchain-file hash. Later steps reject
conflicting ownership/configuration. Shared development roots, overlap, and
unowned nonempty directories are rejected. The old development defaults remain.

This addresses upstream extension archives being emitted beneath the source tree:
a private output alone was insufficient. No shared extension archive contents
were read/reused for this proof. The markers enforce serial local ownership;
they are not cross-process locks or protection against external source/compiler
mutation. Source-content verification, toolchain environment and actual builds
still require proof. Do not run concurrent builds in a pair or reuse it for a
changed compiler environment. The independent Stage 00 proof is not an engine
step; its test fixtures are not shipped by this source-input package.

`Aphid.Native` accepts absolute `APHID_NATIVE_BUILD_ROOT` for its bridge link path
and bridge/engine rpaths. Relative values are rejected. The legacy path remains
the default. This connects an explicit output path to Zigler options; it does not
make Mix automatically fetch/build the engine. Use a fresh Mix build directory
when changing native outputs. The source preflight now reports whether the
packaged Native module exposes this option.

## Checks

[Routing check 1](source-routing-1.log) passes nine rejection cases (uninitialized,
shared source, normal output, overlap, nonempty unowned directory, changed output,
lock, mode and instrumentation). Fetch/OpenSSL/configure/engine/bridge calls are
captured and checked for private paths. No Git/CMake/compiler build commands run.
The retained command record is `/private/tmp/aphid-source-routing-1/routing.json`.
These are command-routing checks, not a successful native build.

[Native option check 1](source-native-options-1.log) checks legacy defaults,
absolute paths containing spaces, both rpaths, and relative-path rejection. It
uses a stub Zig module to inspect constructed options, not a real source link.
Its retained script is `/private/tmp/aphid-native-options-1.exs`.

[Hex build 1](source-package-build-1.log) succeeds with standard local `mix hex.build`.
[Preflight 1](source-inputs-preflight-1.json) reports zero missing required files and
zero patch mismatches: **inputs present, build unproved**. All eleven locked patch
hashes match. The archive contains the documentation snapshot taken during package
assembly; this subsequent handoff and updated recipe are outside that frozen
snapshot. Use the current [source recipe](../source-installation.md) for new options.

[Fresh consumer 1](source-inputs-consumer-1.log) installs from this exact expanded
Hex archive and the unchanged native runtime archive, then passes all 92
core/FTS/vector/DuckDB tests. Caches start empty; native compilers and development
reads are denied, and networking is localhost-only for Mix locking. No native
compiler invocation occurs and all installed native hashes remain unchanged.
Runtime archive selection is removed before runtime tests, as in the existing
adapter proof. This proves the package's precompiled route, not source mode.

Checks use scripts/proof.py process-group watchdogs. Python syntax checks pass.
[Final checks](source-inputs-final-checks-1.log) verify archive/file/patch identities,
unchanged normal native/lock hashes and no compiler log/remaining proof process.
No native rebuild or sanitizer/performance rerun occurred.

## Exact artifacts and handoff

New Hex archive: `artifacts/aphid-0.1.0-dev-source-inputs-1.tar`, 94,720 bytes,
SHA256 `f216f32977d5339a0bdd0a242754498458684c3e7245ee8044f855a76a48d90e`.
The native archive remains `runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz`,
SHA256 `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
No NIF/engine binary was rebuilt. All prior source/notice/runtime artifacts remain.

Next prove locked acquisition and patch verification in a genuinely private source
tree, then measure a fresh native source build with the pinned toolchain, actual
link map, full closure audit and fresh consumer tests. Plan disk/memory from actual
measurements rather than assuming retained cached sizes are sufficient. Mix source
orchestration, generated build inputs, source-mode runtime relocation and support
remain open. Network/Hex delivery, minimum OS/CPU execution, other OTP versions,
OTP/static provenance, Pegasus/ZigParser and final notice review remain open.
No Linux runner is available; do not provision/emulate one. Protected root
library/source/hex_consumer and DuckDB 1.4.4 remain unchanged. No external messages,
publication/upload or stage/implementation completion occurred.
