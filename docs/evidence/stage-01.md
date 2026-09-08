# Stage 01 — complete engine bundle (in progress)

Working directory: `/Users/catethos/workspace/ladybugex/zig_library`.
Exact source/toolchain identities: `native/lock.json`.

1. `python3 scripts/build.py engine --jobs 3`: DuckDB 1.4.4 static build
   succeeded (348 build steps). Ladybug failed while compiling DuckDB connector
   sources because SDK floating-point formatting requires macOS >=13.3.
   See `engine-build.log`. No runtime check passed in this attempt.
2. `python3 scripts/build.py openssl --jobs 2`: fixed OpenSSL source built and
   installed under `_build/native/install`, exit 0 (`openssl-build.log`).
3. `python3 scripts/build.py engine --jobs 4`: retry uses macOS 13.3 and explicit
   static OpenSSL archives, not Homebrew search results (`engine-build-2.log`).

DuckDB's newer generated-loader warning is preserved. In 1.4.4,
`DuckDBExports.cmake` puts core_functions/parquet on `duckdb_static`'s interface;
there is no separately named generated loader target. Build only the targets
that exist in the pinned source. Actual linkage and feature results remain the gate.

Native tests under `native/tests` were authored independently of the old
Elixir/Rust libraries. They create a three-document FTS/vector fixture, an empty
FTS index, and a separate DuckDB file with Unicode and null values. The runner
executes create and reopen in separate OS processes, then repeats through a dirty
CPU Zigler NIF. This narrow Stage 01 proof intentionally owns open/query/close in
one C++ scope; it is not the eventual public API or asynchronous worker design.

Pending: run `python3 scripts/features.py`, diagnose all failures, package and
relocate the dependency closure, run offline, inspect symbols/dependencies.

## Target-runner inventory

`docker info --format '{{.OSType}} {{.Architecture}}'` failed: no daemon at
`~/.colima/default/docker.sock`. `limactl list` reported no instance. Podman
inventory attempted to create its home directory and was denied by the sandbox;
no VM was created. Linux x86_64 -> ARM64 cross-build/execution remains unrun.
macOS host compilation does not satisfy the Linux cross-build requirement.

## Host gate results

`engine-build-2.log`: DuckDB build exit 0 (220.549 s); Ladybug build exit 0
(456.040 s). All three extensions are statically registered. The shared engine
depends only on system `libSystem.B.dylib` and `libc++.1.dylib` according to
`otool -L`; OpenSSL and DuckDB are inside the library. Duplicate static-library
link arguments produced linker warnings, not duplicate definitions. The Ladybug
database constructor is defined in the engine image; the NIF and C bridge do
not contain another engine archive.

`features-run.log` reproduced a real attachment bug: create passed, fresh reopen
failed with `records already exists in catalog`. See
`native/patches/README.md` for root cause and the locked tabular-only correction.
This does not repair or expose upstream direct DuckDB graph projections.

`features-run-2.log`: standalone create/reopen passed; Zig semantic-analysis
executable failed to locate its bridge dylib. Added explicit build-time rpaths.

`features-run-3.log`: all four feature invocations passed, exit 0. Each checks
actual registration, expected FTS document, indexed-vector nearest neighbor,
empty-FTS result, DuckDB scan/import, table-name collisions/prefixes, and repeated
attachment. Separate create/reopen OS processes run first in C++, then the BEAM.
Standalone create/reopen: 1.155 / 0.130 s;
BEAM create/reopen including compilation: 10.375 / 1.157 s. These are acceptance
durations, not benchmarks. The C++ proof uses explicit exceptions, not assertions
disabled by release flags.

`bundle-run.log`: relocation initially failed because Zig's Mach-O had no spare
load-command space. Removing the build rpaths before replacing dependencies
fixed it; no source or engine behavior changed.

`bundle-run-2.log`: offline, relocated artifact checks passed, exit 0:
fixture generation 1.039 s, native create/reopen 2.016 / 0.128 s, BEAM
create/reopen 2.473 / 0.349 s. Each runs under macOS sandbox-exec with
`(deny network*)`. BEAM loads only the packaged Aphid module and verifies Zigler
is absent. Sidecar references use `@loader_path`; build rpaths are removed,
copied binaries are ad-hoc signed, and unexpected external dependencies fail.
66 license/notice files and cppjieba dictionaries are included.

Local archive: `artifacts/engine-proof-aarch64-macos.tar.gz`, 37,554,347 bytes,
SHA-256 `896cb0d1625d0a425f32dc798126ef9a8e7301b6d5fcf1e253af299345182ffe`.
It contains a test-only NIF, bridge, engine, fixture executables, notices, lock,
and per-file checksum manifest. It is not a public API/release artifact.

`otool -l` reports engine minos 13.3 but NIF minos **26.6** (Zig's native-host
default), SDK 26.1. Consequently the bundle's tested OS is 26.6 only. Setting a
lower engine floor alone does not establish compatibility for the NIF.

`engine-repeat.log`: supported build entry point reconfigured and found no
remaining compilation work; both native builds exit 0. `fetch-patch-verify.log`
verified source commits, archive checksums, and exact locked patch diff.

The host mandatory-feature gate is passed. Linux cross-build/runtime evidence
remains pending. Next: Stage 02 worker/resource/retirement proofs; retain Linux
and minimum-OS gates as incomplete, not release-supported.
