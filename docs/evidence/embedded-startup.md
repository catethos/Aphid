# Embedded startup continuation

2026-09-08. Stages 08/09 remain in progress. No release support, publication or
implementation completion is claimed. This supersedes the embedded-boot failure
in [the earlier interactive release evidence](mix-release.md).

## Change and boot contract

`lib/aphid/bundle_loader.ex` defers only a bundle-managed early embedded on_load
when crypto is unavailable. It records a pending activation and leaves managed
NIF stubs: no native library is loaded at this point. The new
`lib/aphid/application.ex` callback runs after the declared crypto application
and activates both modules. The existing embedded SHA256 constants verify every
file in the native closure before each actual NIF load. Pending activation is
erased only after success. Application restart therefore does not attempt to
reload an existing NIF. Ordinary on-demand loading retains its previous checks.
An integrity or loader error prevents Aphid application startup; there is no
source fallback. This changes Elixir lifecycle code only, not either NIF.

`mix.exs` declares the callback. `scripts/proof.py` removes that callback only in
its intentional Proof-only staging project, which has no full Aphid application;
no native rebuild was run to repeat that unchanged toolchain proof.
`scripts/mix_release.py` now exercises default embedded boot, pending activation
clearance and application restart. `scripts/embedded_failures.py` exercises real
embedded startup rejection with missing/corrupt sidecars and denied executable
mapping, restoring original bytes in `finally` after each case.

## Proofs and exact identities

The new fresh consumer `/private/tmp/aphid-embedded-consumer-2` starts with empty
application/dependency build caches and unmodified pinned source dependencies.
The real local adapter installs all sidecars. [Consumer 2](embedded-consumer-2.log)
passes all 92 core/FTS/vector/DuckDB tests with no native compiler invocation,
project/toolchain reads denied, localhost-only network, unchanged native hashes,
and the archive moved away before runtime. Consumer attempt 1 is retained: nested
sandbox execution was denied before compilation, so attempt 2 ran the same
restrictive child sandbox with the required outer execution permission.

[Installer/loader regression](embedded-failures-1.log) passes all 23 actual Mix
rejection cases and missing/corrupt/unloadable checks for both NIF modules.
[Release 1](embedded-release-1.log) assembles a genuine Mix release, extracts and
renames it to `/private/tmp/aphid-embedded-release-1/relocated café release`, then
passes denial probes, all 92 tests, embedded `start`, application stop/restart,
persistent write/close, graceful shutdown and reopen in a new VM. Runtime has no
network, compiler execution, development/build-tree or host Elixir/ERTS reads.
It uses bundled ERTS; Mix and Zigler are absent. The suite runs via release eval;
the separate normal start explicitly asserts `:code.get_mode() == :embedded`.

[Embedded rejection proof](embedded-boot-failures-1.log) passes three real `start`
failures: [missing](embedded-boot-missing-1.log),
[corrupt](embedded-boot-corrupt-1.log), and
[unloadable](embedded-boot-unloadable-1.log). Each exits 1 with the appropriate
Aphid diagnostic and application startup failure. Every subprocess uses
`scripts/proof.py` process-group watchdogs. Native fixture originals and damaged
fixtures are retained under `/private/tmp/aphid-embedded-boot-failures-1`.

| Archive | Bytes | SHA256 |
|---|---:|---|
| `artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz` (unchanged input) | 33,608,999 | `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034` |
| `artifacts/mix-release-embedded-aarch64-macos-1.tar.gz` (new validation release) | 91,405,126 | `2ee9d858ec12ab848f083ceb4b1b57d2acf289a40bc94690eaac3991e21a9008` |

[Final checks](embedded-final-checks-1.log) confirm every packaged file remains
unchanged after restoration, no proof VM remains, normal bridge/engine and both
locks are byte-unchanged, and the native closure still matches
`native/local-bundle.json`. The [file manifest](embedded-release-files-1.json)
and [22-file Mach-O audit](embedded-release-native-audit-1.json) are retained.
No shared upstream extension archive was used; no native binary was rebuilt.

## Boundaries and concrete handoff

Use the [local installation recipe](../local-installation.md). The default Mix
embedded mode no longer needs the earlier on-demand workaround. Distribution
remains disabled for these offline proofs. This is a validation release with
ExUnit/examples/DuckDB fixture, not a production package or support claim.
Bundled ERTS/crypto declare macOS 15.0; Aphid binaries declare 13.3. Execution was
only macOS 26.6: neither actual minimum OS nor whole-closure CPU compatibility is
proved. Zigler's installer still needs Apple otool and warns about its optional
formatter without Zig.

Next prepare a local production package/notice inventory from reviewed inputs;
prove a fresh source consumer separately when disk/resources permit. Network
artifact delivery, ordinary Hex distribution, source installation, minimum-system
execution, other OTP versions and both Linux targets remain open. No Linux runner
is available; do not provision or emulate Linux. Preserve native lock DuckDB 1.4.4
and root library/source/hex_consumer. No sanitizer rerun or performance work was
performed. All failed attempts remain; nothing was uploaded or published.
