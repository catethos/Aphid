# Source installation preflight — installation remains unproved

The local Hex package is verified for explicit precompiled installation only.
Setting `APHID_INSTALL=source` currently selects the development Zigler route;
it does not fetch/build the engine or bridge. The new source-input review package
includes the checked build inputs and supports explicit private source/output
paths, but that route has not performed a fresh native build. Do not treat
source selection as an automatic source installer.

Run the standalone preflight **before** attempting source compilation:

```sh
python3 scripts/source_preflight.py \
  --package artifacts/aphid-0.1.0-dev-source-inputs-1.tar \
  --sha256 f216f32977d5339a0bdd0a242754498458684c3e7245ee8044f855a76a48d90e \
  --output /tmp/aphid-source-preflight-NEW.json
```

Use a new output path. The tool reads the pinned Hex archive in memory and writes
only the report. It never extracts, downloads, patches, starts Mix, invokes
compilers or changes toolchains. It is a development inspection tool, not a Mix
compiler hook; the source-input package contains it but does not invoke it automatically.

Exit 2 means invalid input or missing/mismatched required source inputs. Exit 0
means only that the checked file structure is present; it does not prove source
build readiness or platform support. The source-input review archive returns
`inputs_present_not_build_proven`, with zero missing files and zero patch checksum
mismatches. The older `aphid-0.1.0-dev-local-2.tar` remains unchanged and still lacks
15 build inputs. No omitted file is supplied from the development tree by preflight.

## Inputs and prerequisites still to establish

The report records locked engine/extension commits, DuckDB 1.4.4 and OpenSSL 3.6.4
archive checksums, patch identities and the retained toolchain record. A source
package needs its own bridge implementation/CMake recipe, watchdog/build entry
points and exact patch bytes. Third-party trees may come from verified sources;
a current developer checkout or prebuilt bridge is not a substitute for that proof.

The current build recipe requires Python, Git, CMake/Ninja, make, Perl, a C/C++
toolchain and macOS SDK, then the pinned Elixir/OTP/Zigler/Zig pair. Packaging and
relocation also use Apple otool, install_name_tool and codesign. The preflight
reports executable discovery only; it does not execute tools or validate their
versions, SDK availability or functionality. No Linux source recipe is proved.

Source build order is locked source acquisition/patching, OpenSSL, DuckDB with
core_functions/parquet, Ladybug with FTS/vector/DuckDB, the bridge, then Zigler
NIFs. The resulting closure still needs relocation/signing/audit and fresh
core/FTS/vector/DuckDB tests under watchdogs. Appending build files to a package
alone does not wire that sequence into Mix.

A new native output directory is insufficient isolation: upstream extension CMake
writes archive outputs beneath the source tree. Each candidate must own a private
source tree and extension outputs. Never trust shared upstream extension archives.
The explicit `--source-root` option now binds a new empty source directory to one
new empty output directory, native lock identity, target, mode, instrumentation
and optional toolchain-file hash. Begin with `fetch`; later steps must use the
same options. Ownership markers reject shared development paths, overlapping
roots, unowned existing contents and conflicting pair/configuration reuse.
The marker is a local serial-use guard, not a concurrency lock or a proof that
sources/compilers were not externally modified. Do not run concurrent builds in
the same pair or change compiler environment between steps.

From a self-contained extracted package, a future source proof can use:

```sh
python3 scripts/build.py fetch --source-root /absolute/new-sources --output /absolute/new-output
# After acquisition/identity validation, repeat the same options for:
# openssl, engine, bridge (engine already builds the bridge).
export APHID_INSTALL=source
export APHID_NATIVE_BUILD_ROOT=/absolute/new-output
# mix deps.compile and mix compile require the actual native build first.
```

`APHID_NATIVE_BUILD_ROOT` must be absolute; it sets the bridge link path and both
native rpaths for Zigler. Without it, the legacy `_build/native` path remains.
These are inspectable build steps, not a proved installation recipe. The source
routing checks capture commands without executing Git/CMake/compiler builds;
the custom-path check uses a stub Zig module and does not prove source linking.
The independent Stage 00 `proof` command is not a private engine-build step;
its test fixtures are not part of this source-input review package.

The report records free disk, but no clean-build peak memory/disk budget has been
proved. Retained cached build sizes do not establish a fresh-build peak or minimum
requirement. No automatic threshold or sufficiency claim is made. Preserve previous
attempts and measure resource use when a fresh source build is actually performed.

Next prove acquisition/patch validation in a genuinely private tree, then measure
a fresh source build with the locked toolchain and capture a linker map. Keep fresh source installation, network
Hex/artifact delivery, minimum OS/CPU execution, other OTP versions, Linux and final
notice review open. This preflight establishes none of those gates. See
[evidence and exact handoff](evidence/source-inputs.md).

Native Linux source recipes and CI qualification are now prepared separately; see
[GitHub preparation](github-release.md). They require a matching real Linux host
and private source/output trees. They have not established Linux build or install
support, and the local precompiled adapter still accepts only its reviewed macOS
identity.
