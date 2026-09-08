# Release preparation checklist — release publication not authorized

No target is release-supported and no stage is closed. The local runtime
validation archives are test bundles, not Hex packages or release candidates.

| Required target | Build / runtime evidence | Remaining blocker |
|---|---|---|
| Linux x86_64 glibc | Native GitHub runner: locked builds, relocated suites, compiler-free 92-test consumer and failure checks pass | Prove declared glibc/CPU baseline, public delivery and Linux Mix release |
| Linux ARM64 glibc | Native GitHub runner: locked builds, relocated suites, compiler-free 92-test consumer and failure checks pass | Cross-build on x86_64 Linux, then execute that exact artifact on native ARM64 Linux |
| macOS ARM64 | Host-only extracted runtime validation; see Stage 08 evidence | Explicit-target candidate declares 13.3; local checksum/sidecar adapter and fresh consumer pass; embedded-mode Mix release passes; actual minimum OS/CPU and network delivery remain |

## Historical local-host inventory

Inventory evidence: `docs/evidence/continuation-inventory-1.log`. The Mac has
8 GiB RAM and eight CPUs. Available disk was initially 5.1 GiB; the isolated
TSan build alone occupied 7.5 GiB. Colima is configured for aarch64, two CPUs,
2 GiB RAM and a 100 GiB virtual disk. A configured virtual disk does not establish
available physical storage. No VM was started or resized. No remote machine
was contacted. The user confirmed that no x86_64 Linux runner is available.

Obtain an actual x86_64 Linux build host before attempting the required
cross-build. On that host and the ARM64 runtime, record `uname -a`, `lscpu`,
`getconf GNU_LIBC_VERSION`, memory/disk availability, compiler/linker versions,
CMake/Ninja/Zig versions, and Elixir/OTP versions. Establish native ARM64
execution, the VM's guest distribution/libc and mounts before using Colima as a
runtime. Record virtualization/emulation explicitly; x86_64 emulation on this
Mac cannot fulfill the required x86_64 Linux build-host proof.

The native GitHub qualification workflow has now run on both architectures.
Both native/NIF builds and 92 BEAM tests passed in run 34184718955 after the
retained first-attempt staging error. Full bundle qualification is running. Local Linux provisioning and
emulation remain excluded.
See [CI preparation](evidence/linux-ci-preparation.md). Qualification must build locked OpenSSL/DuckDB/engine inputs
for the target, separate host generators from target binaries, and remove
Darwin-specific assumptions. Do not substitute a Mac artifact. Estimate storage
from actual normal/instrumented build trees before allocating a new environment;
there is no measured Linux peak-memory/build-space budget yet.

## Acceptance still required

- Complete remaining Stage 05/07 boundary and extension coverage, including
  cancellation of combined workloads, actual Zig/BEAM resource boundaries under
  suitable instrumentation, and mutation races. Keep TSan's 1 GiB test-only
  mapping limitation visible; never generalize it to the production 8 TiB range.
- Build immutable artifacts for all three required targets from locked inputs.
  DuckDB remains 1.4.4. Build extension archives in isolated source trees;
  upstream writes them into source directories regardless of output directory.
- Verify each artifact's entire dependency closure, CPU baseline, minimum OS or
  glibc, NIF API/OTP compatibility, loader paths, symbols and observed extensions.
  Explicit-target candidate load commands now declare 13.3; actual minimum-system
  execution and static dependency CPU/SDK availability remain unproved.
- Extend distribution beyond the proved opt-in local Mix adapter: trusted pinned
  checksum, safe extraction, full sidecars and distinct failure diagnostics now
  pass actual installer/loader checks for the reviewed macOS candidate. Network
  artifact delivery and ordinary Hex distribution remain open; no platform or
  stage gate is closed by this local proof.
- Exercise fresh precompiled and source consumers with empty caches; precompiled
  mode must not invoke compilers (local adapter with pinned dependency sources
  passes; network delivery/normal Hex installation remain open), and source mode must use only packaged or
  verified source inputs. No developer-directory dependency is acceptable.
- Run core, FTS, vector and DuckDB suites from the extracted artifact on every
  actual target. Prove offline startup and a relocated **Mix release**, including
  native dependency discovery and cleanup. The embedded-mode local Mix release passes host startup/restart checks.
  Its bundled ERTS declares 15.0, so it cannot establish a 13.3 release floor.
- Measure complete clean build time/peak memory and archive size. The benchmark
  harness's small incremental build cost does not establish engine build cost.
- Complete comparative benchmark coverage: mixed concurrency, larger DuckDB
  scans, vector recall with latency, and cancellation response versus completion.
  Retain raw samples, settings, hardware, build flags and memory measurements.
- Review notices against final shipped contents, including BEAM dependencies and
  any bundled runtime. Native license hashes are checked when building local
  validation bundles; this is not a completed release legal inventory.
- Prepare a local versioned package, complete manifests and checksums, support
  matrix and reproducible consumer instructions. Obtain separate explicit
  authorization before GitHub release creation or Hex publication. Seven-day
  Actions retention of passing Linux validation artifacts is already approved.

## Latest local distribution evidence

See [source inputs/private routing](evidence/source-inputs.md),
[source preflight evidence](evidence/source-preflight.md),
[attribution follow-up](evidence/attribution-followup.md),
[native notice mapping](evidence/native-notice-map.md),
[notice-source evidence](evidence/notice-sources.md),
[local package evidence](evidence/local-package.md),
[embedded startup evidence](evidence/embedded-startup.md) and
[installation recipe](local-installation.md). The fresh adapter consumer and
relocated bundled-ERTS release each pass 92 tests. Default embedded start,
application restart, shutdown and persistent reopen pass offline with compiler,
development/build and host-runtime reads denied. Missing/corrupt/unloadable
native files fail real embedded startup before application success. All packaged
files and native closure hashes remain unchanged after restoring negative fixtures.

Bundled ERTS/crypto declare macOS 15.0; native candidate files declare 13.3.
Actual minimum-system/CPU execution remains unproved. Validation-only ExUnit,
examples and fixture are not a production package decision. Production notices,
normal Hex/network delivery, source installs, other OTP versions and all required
platforms remain open. No stage or target is marked complete/supported. No native
rebuild, Linux provisioning/emulation, sanitizer rerun, publication or upload occurred.

A local Hex archive with explicit file allowlist and owner-selected MIT license
now installs into a fresh consumer and passes all 92 tests with the unchanged
native bundle. The notice-review archive retains 67 native-bundle texts, ten
Hex dependency texts and Elixir's license. Named notice files are absent from
nimble_parsec, pegasus, zig_get and zig_parser source archives; the inspected
OTP/ERTS installation also lacks named notice files. Exact-source notice and
linked-component review remain required; no inventory or stage is marked complete.

The source follow-up now retains NimbleParsec's README notice, ZigGet's
content-matched parent license, 22 OTP notice texts and OTP OpenSSL 3.5.7's license.
Full version-appropriate Pegasus/ZigParser notices, six unmatched installed OTP
source files, runtime/native build provenance and shipped-component mapping remain
open. See notice-source evidence for exact commits and manifest identities.

The retained native link/header records now associate 57 component groups with
candidate notice texts and preserve seven embedded preambles. httplib's abbreviated
header still needs its full notice. These records do not prove linker retention or
historical header bytes; a fresh source build should capture a real linker map
with isolated extension inputs. Existing runtime artifacts remain unchanged.

Httplib's full upstream 0.14.2 notice now has a verified association with the
retained modified header. Pegasus/ZigParser history checks remain inconclusive
for full pinned-version attribution; do not substitute a later/other-project
license. Prepare a source-installation preflight before allocating a fresh build.

A standalone source preflight now reports the current package's 15 missing native
build inputs and checks lock/patch identities without extracting or building.
Its five isolated tests pass; source compilation remains unproved. Package inputs,
private extension source trees, Mix/native output wiring, SDK/tool versions and
clean-build peak resource measurement remain required.

The new source-input archive includes the 15 previously missing files and preflight;
structural checks and a fresh 92-test precompiled consumer pass. Private source-root
ownership/routing and explicit native output options are checked without a source
build. Locked acquisition, actual source compilation/linking/relocation, resource
measurement and automatic Mix source orchestration remain open.

Current source changes and CI iterations are authorized. Binary artifact uploads,
GitHub release creation and Hex publication remain excluded. The Linux catalog
is empty pending reviewed artifacts; see [distribution preparation](evidence/linux-distribution-preparation.md).

[Run 34193449987](evidence/linux-qualified-bundles.md) now passes both Linux
bundle qualification jobs. Reviewed identities are pinned; approved seven-day
Actions retention succeeded. The manual draft release workflow is prepared and
local verification of its actual assets passes. Actual draft creation, public
release delivery and Hex publication remain unexecuted and unauthorized.
