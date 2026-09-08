# Local precompiled bundle installation

This is Aphid's opt-in local archive adapter, exercised on macOS ARM64 26.6
and native Ubuntu 24.04 x86_64/ARM64 with Elixir 1.20.0 / OTP 29.0.4
(ERTS 17.0.4). **No target is release-supported.**
The adapter currently accepts the reviewed native identity in
`native/local-bundle.json` and `native/linux-bundles.json`, not arbitrary Aphid builds. The unchanged candidate's
seven Mach-O load commands declare 13.3; actual minimum OS/CPU execution remains
unproved. The NIF CPU baseline resolves to Apple M1; the whole-closure CPU floor
is still unverified.

## Recipe

Use a self-contained copy of the Aphid source package as your consumer's
`vendor/aphid` dependency:

```elixir
{:aphid, path: "vendor/aphid"}
```

A locally built Hex source archive is now available for review:
`artifacts/aphid-0.1.0-dev-local-2.tar`, SHA256
`921d21ece8c5a96bb3cdc5ab60b6932e73dd4471b2f9382d446d9f182bd8d7e3`.
Its metadata version is `0.1.0-dev`; the filename suffix identifies this local
attempt. It contains MIT-licensed Aphid source and no native/dependency binaries.
This is an unpublished Hex archive, not registry delivery or source-build proof.

To stage that exact archive using standard tar tools, verify the SHA256 against
the independently recorded value above, unpack the outer tar into a new temporary
directory, then unpack its `contents.tar.gz` into a new `vendor/aphid` directory.
Treat other archives as untrusted; the proof harness checks the pinned outer
checksum and rejects links/unsafe inner members before extraction. Continue with
the native archive recipe below. [Package evidence](evidence/local-package.md)
records the fresh consumer built exclusively from those package files.

The copy must contain `mix.exs`, `mix.lock`, `mix/`, `lib/`, and these native inputs:
`native/{lock.json,local-bundle.json,linux-bundles.json,aphid_nif.zig,bridge.h,bridge.cpp,proof.zig,proof.h,proof.cpp}` for the current source. Historical package proofs retain their original file lists.
Do not copy `_build`, `deps`, or `priv` from a development installation. The
runtime archive's BEAM files are not installed: Mix compiles the Elixir sources.

Have the locked Elixir dependency sources available first, including Zigler
**0.16.0**. The reproducible offline proof below supplies verified Hex source
archives as consumer-level path overrides, plus an installed Hex tool in a fresh
Mix home. Ordinary network dependency resolution/Hex delivery is not proved by
that fixture. Dependencies themselves are unmodified. Host Elixir/OTP, Hex and
Apple `otool` are installation prerequisites. No Zig or native compiler is
needed for this path. Zigler's optional formatter warns when Zig is absent;
that warning does not select source compilation. CommandLineTools-free
installation has not been established.

In the consumer directory, choose an **unused absolute build directory** and
an explicit local archive. Pin the SHA256 independently of the archive (for
this candidate, use the recorded value below, not a freshly calculated checksum
of an untrusted download):

```sh
export MIX_ENV=prod
export MIX_BUILD_PATH="$PWD/_build/local-bundle-1"
export APHID_INSTALL=precompiled
export APHID_BUNDLE_ARCHIVE=/absolute/path/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz
export APHID_BUNDLE_SHA256=3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034
mix deps.compile
mix compile
mix run --no-compile -e 'IO.inspect(Aphid.Native.stats())'
```

Keep archive/checksum selection for subsequent compilation. To change bundles,
use a new build directory and a reviewed matching package identity. Do not set
Zigler's force-recompile/force-reload switches in bundle mode. The adapter rejects
these switches, incomplete selection, and attempts to reuse another installation.
An existing bundle build cannot silently become a source build when selection is
omitted. Runtime with `--no-compile` needs only the installed application; the
archive and installation environment variables are unnecessary after compilation.
The proof moves the archive away before its runtime tests.

`APHID_NATIVE_PRECOMPILED` and `APHID_PROOF_PRECOMPILED` remain legacy development
proof inputs. They do not constitute the checksum-verifying local installation
API. The adapter supplies them internally after validation. Explicit
`APHID_INSTALL=source` uses the existing development compilation route in a
separate build directory; a fresh source installation remains an open gate. Run the standalone
[source preflight](source-installation.md) before attempting it: the current Hex
older archive lacks 15 native build inputs. The newer source-input review package
contains them, but source selection still does not build the engine.

## Validation and failures

The Mix compiler runs before Aphid Elixir compilation. It reads the local archive
once, verifies the caller's SHA256, and uses OTP's tar reader to inspect members
and extract into memory. It rejects absolute/traversal/dot paths, links, special
files, duplicates, case collisions and file/directory conflicts. This narrow
format accepts ASCII member paths only. It verifies the complete content
manifest, target/CPU selection, runtime, native lock, native interface source
hashes and all four reviewed native binary hashes. Package version and NIF
API/ERTS identity are tied to those reviewed binaries.

Only the complete `priv/lib` closure and bundled licenses are written into a
fresh sibling staging directory and renamed into the application's build `priv`.
No archive BEAM files or test programs are installed. A receipt records the
archive checksum, native hashes and reviewed identity. Both NIF loaders embed
the expected closure hashes into the newly compiled BEAM code and check all four
files before every load; deleting the receipt later does not disable checks.
The adapter never downloads, edits dependency sources, or starts a source build.

| Diagnostic | Action |
|---|---|
| `[missing]` | Supply the local archive or reinstall the complete closure into a new build directory. |
| `[corrupt]` | Restore the independently pinned archive/content; do not replace the expected checksum to hide damage. |
| `[unsupported-target]` | Use the reviewed macOS candidate and exact currently checked Elixir/ERTS runtime. Other platforms/runtime versions require proof. |
| `[wrong-architecture]` | Use an ARM64 BEAM and ARM64 Mach-O closure. |
| `[incompatible-engine]` | Use the bundle matching the native lock, interface sources and reviewed binary fingerprint; changed native inputs need a new reviewed identity. |
| `[unloadable]` | Inspect the included loader reason; restore the complete matching bundle and resolve host loader restrictions. No compiler fallback occurs. |
| `[unsafe]` / `[selection]` | Replace an unsafe archive or use consistent bundle selection with an empty build directory. |

Installation failures raise `Mix.Error`. Runtime failures log the actionable
category and cause NIF module loading to fail (`:on_load_failure` to callers),
or fail Aphid application startup when activation was deferred during embedded boot.
The native live-upgrade rejection remains intentional and is exercised by the
existing lifecycle test. Build/staging directories are locally owned; concurrent
hostile mutation of an installation by another writer is outside this contract.

## Reproduce the local proof

From `zig_library`, use **new** destinations/evidence filenames on repetition:

```sh
python3 -u scripts/precompiled_consumer.py \
  --archive artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz \
  --sha256 3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034 \
  --destination /tmp/aphid-local-consumer-NEW
python3 -u scripts/local_bundle_failures.py \
  --destination /tmp/aphid-local-failures-NEW \
  --consumer /tmp/aphid-local-consumer-NEW
```

The consumer harness uses `scripts/proof.py` process-group watchdogs, empty
application/dependency build caches, source-only pinned dependencies, absent Zig,
compiler execution denial, denied development-project reads and localhost-only
networking for Mix's lock. It compares the installed native closure to the exact
archive and runs all 92 BEAM tests, including core/FTS/vector/DuckDB. The Python
extractor stages test fixtures and supplies an independent expected hash oracle;
it does **not** stage Aphid's `priv`. The Mix adapter performs that installation.
The failure harness invokes the real Mix compiler task with hostile archives and
loads both installed NIF modules in isolated BEAM processes. A sandbox denial of
executable mapping reaches the real `dlopen` failure with unchanged native bytes.

Network artifact delivery, a normal published Hex package, a fresh source-mode
consumer, actual minimum OS/CPU execution,
other OTP versions remained open at this historical checkpoint. Current Linux
results are linked below. No local Linux system was
provisioned/emulated, no sanitizer suite was rerun, and no performance work was
done. See [current evidence and handoff](evidence/local-bundle-installation.md).

## Local Mix release validation

[The embedded Mix release proof](evidence/embedded-startup.md) now passes all 92 tests,
normal `start`, graceful shutdown and persistent reopen, using bundled ERTS with
network/compiler/development/host-runtime reads denied. It uses a newly compiled fresh adapter consumer; native binaries are reused unchanged.

For this local route, use Mix's standard `rel/env.sh.eex` settings:

```sh
export RELEASE_DISTRIBUTION=none
```

Default embedded boot is now exercised. Early boot defers the NIF load until
Aphid application startup, after crypto is available; full SHA256 checks still
precede each native load. Application restart does not reload already-loaded NIFs.
The validation release includes ExUnit, examples and the existing DuckDB fixture.
Its bundled ERTS/crypto declare macOS **15.0**, while Aphid's native files remain
13.3 declarations; actual minimum-system execution is still unproved.

```sh
python3 -u scripts/mix_release.py \
  --consumer /tmp/aphid-embedded-consumer-2 \
  --destination /tmp/aphid-mix-release-NEW \
  --output artifacts/mix-release-validation-aarch64-macos-NEW.tar.gz
```

Use new paths and retain attempts. This is a genuine, configured local Mix release
validation path, not release support or a production package. Public
network delivery, source installs and minimum OS/CPU/other OTP execution
remain open; see the linked evidence for exact archive hashes and boundaries.

The expanded local source-input archive is
`aphid-0.1.0-dev-source-inputs-1.tar`, SHA256
`f216f32977d5339a0bdd0a242754498458684c3e7245ee8044f855a76a48d90e`.
Its precompiled route passes the same fresh-consumer tests with the unchanged
native candidate. See [source-input evidence](evidence/source-inputs.md); this is
not a source-installation or platform-support claim.

## Explicit HTTPS bundle delivery

The adapter also accepts `APHID_BUNDLE_URL` instead of `APHID_BUNDLE_ARCHIVE`.
Set only one; keep `APHID_INSTALL=precompiled` and an independently trusted
`APHID_BUNDLE_SHA256`. The URL must use HTTPS without embedded credentials or a
fragment. Mix's existing TLS client validates the certificate/hostname, honors
its standard `HEX_CACERTS_PATH` setting for managed networks, and has a 60-second
request deadline. The downloaded bytes go through the same checksum, identity,
archive-member and complete-sidecar checks as local archives. Download failures
report `[download]` and never trigger source compilation.

This route is proved with a private loopback HTTPS server and the unchanged
reviewed macOS archive, including a fresh 92-test compiler-free consumer. The
first invalid self-signed test-certificate attempt is retained. No native archive
was uploaded. There is no usable Aphid GitHub release download URL yet, no default
network selection. The current catalog also accepts the reviewed Linux identities below.
See [HTTPS evidence](evidence/https-bundle.md).

The local source package also passes a fresh consumer using normal Hex dependency
acquisition with the reviewed lockfile, without dependency-source path overrides.
External networking is allowed only for that acquisition phase; native compilers
and development-project reads stay denied, and compilation/runtime revert to
loopback-only networking. All 13 Hex archives match the lock and 92 tests pass.
See [normal Hex dependency evidence](evidence/normal-hex-consumer.md). This does
not publish Aphid to Hex or establish an available GitHub native release.

With no artifact inputs and no `APHID_INSTALL` setting, the current development
version now reports `[missing]` instead of selecting a source build. Set
`APHID_INSTALL=source` deliberately when following the source prerequisites.
[Selection checks](evidence/explicit-selection-1.log) exercise the actual compiler
task and verify rejection occurs before either native module loads.

## Reviewed Linux local archives

Use the current source package with the reviewed Linux catalog, not an older
macOS-only source archive. The same explicit archive/SHA256 recipe above applies.
The exact Linux filenames and independent pins are in
[reviewed Linux bundles](evidence/linux-qualified-bundles.md). Retrieve the
matching architecture from the passing run's Actions artifact before its
seven-day expiry, or use the verified local review copy. Actions retention is
not a durable public installer URL. Keep the pin from source/evidence independent
of the downloaded archive.

The proved Linux hosts are Ubuntu 24.04 with glibc 2.39 and GNU binutils 2.42.
Zigler needs GNU `objcopy` to read NIF metadata. Producers normalize that operation
before pinning; the real consumer proves unchanged hashes afterward. No Zig,
C/C++ compiler, CMake or patchelf is required by the Linux consumer adapter.
Older glibc/CPU systems, musl and different binutils/runtime versions are not
proved by this result. The ELF engine requires GLIBC 2.38 and GLIBCXX 3.4.32;
those symbol requirements are not minimum-system execution evidence.

Both native Linux jobs passed the fresh local Hex-source-package consumer's
92 tests with normal locked Hex dependency acquisition, then offline compilation
and runtime. Real installer/loader failures also passed. The [exact combined source archive](evidence/combined-installation-2.md)
now passes on both Linux architectures and macOS ARM64. Bundled-ERTS Linux
Mix releases also pass startup, restart, shutdown/reopen and failure checks.
Hex registry installation and default public release download remain unproved.
