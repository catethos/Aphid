# Local Hex package and available-notice inventory

2026-09-08. Stages 08/09 remain in progress. Nothing is published/uploaded or
release-supported; no implementation or notice inventory is marked complete.

## Package and consumer

The owner selected MIT for Aphid's new source. `LICENSE` records that choice;
`THIRD_PARTY.md` keeps third-party licenses and unfinished notice review separate.
`mix.exs` now defines an explicit package allowlist and MIT metadata. It includes
33 source/interface/documentation files, not compiled BEAM/NIF files, generated
hidden Zig files, native engine trees, dependencies, test fixtures or caches.
Links metadata is empty; no repository URL was invented. Package version remains
0.1.0-dev and native identity/locks remain unchanged.

[Hex build 1](local-package-build-1.log) was rejected for absent licenses/links
metadata before the owner selected MIT. Its listing also exposed hidden generated
Zig files; the allowlist now selects `lib/**/*.ex` instead of the whole directory.
[Hex build 2](local-package-build-2.log) passes with standard `mix hex.build` in
`/private/tmp/aphid-local-package-2`. This command creates a real Hex archive;
there is no custom packaging system, dependency edit or upload. The staged build
is retained. The archive includes the documentation snapshot at packaging time;
subsequent evidence/status updates are not retroactively written into it.

`scripts/precompiled_consumer.py` accepts `--package` and `--package-sha256`.
It verifies the outer pin, safely extracts the Hex contents into vendor/aphid,
and reads dependency pins from the packaged mix.lock. No Aphid source files are
filled in from the development tree on this route. Test fixtures come from the
unchanged native validation archive and dependency sources from pinned Hex caches.
[Fresh consumer 1](local-package-consumer-1.log), at
`/private/tmp/aphid-package-consumer-1`, passes all 92 core/FTS/vector/DuckDB tests.
Application/dependency caches start empty; compilers and development-project reads
are denied; networking is localhost-only for Mix locking. The actual Mix adapter
installs the complete unchanged native closure; the runtime archive is moved away
before tests. Every compilation/test subprocess uses `scripts/proof.py` watchdogs.
No Zig cache or compiler-invocation log is produced.

The earlier [embedded release proof](embedded-startup.md) remains applicable to
unchanged application/loader/native code. It was not rerun for packaging metadata
and documentation changes. This local path still stages the source package as a
path dependency; ordinary Hex registry resolution/delivery remains unproved.

## Exact artifacts

| Local artifact | SHA256 |
|---|---|
| `artifacts/aphid-0.1.0-dev-local-2.tar` | `921d21ece8c5a96bb3cdc5ab60b6932e73dd4471b2f9382d446d9f182bd8d7e3` |
| `artifacts/notice-review-4.tar.gz` | `efc10308f4d00591dd2a8fdaa3a04cdcb2a6aa01100cc0ee5c8bcd18d3673521` |
| Unchanged `artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz` | `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034` |

Sidecar SHA256 files, the notice archive's inventory.json, and
`artifacts/notice-review-4.tar.json` record content identities. The source package
manifest matches all 33 staged consumer files. [Final checks](local-package-final-checks-1.log)
record sizes, native identities and unchanged lock/normal engine/bridge hashes.

Subsequent [notice-source evidence](notice-sources.md) narrows the gaps below;
this package/archive record remains unchanged.

## Notices and limitations

`scripts/package_inventory.py` inventories source metadata/files, all thirteen
pinned Hex dependency archives, native-bundle notices and the exact installed
Elixir/ERTS runtime used by the previous validation release. It preserves available
texts without assigning licenses to third-party code. [Inventory 4](package-notice-inventory-4.log)
records 67 native-bundle texts, ten Hex dependency texts and Elixir's LICENSE.
All native/licenses.json entries match; the additional bundled Telemetry LICENSE
matches the pinned Hex text. Elixir executable module MD5 matches the release
(Mix strips debug chunks, so file SHA differs); bundled ERTS file SHA matches.

Named license/notice files were absent from four compile-time source archives:
`nimble_parsec`, `pegasus`, `zig_get`, and `zig_parser`. The inspected OTP 29.0.4 /
ERTS 17.0.4 installation contains no named license/notice files. These findings
are gaps in this available-file inventory, not statements about license absence.
Obtain the exact-source license/notice texts and inspect embedded component notices
before any final distribution review. Native file discovery is also not a complete
mapping of linked components; some bundled texts cover upstream tools/test data.

Inventory attempts 1–3 are retained: the first did not account for the additional
Telemetry license; the second used the wrong case for an Elixir BEAM manifest key;
the third compared stripped/unstripped file SHA instead of executable module MD5.
No candidate binary was changed to satisfy those checks.

## Concrete handoff

Use [the local installation recipe](../local-installation.md), or reproduce the
proof with a new destination and these exact archive/checksum arguments:

```sh
python3 -u scripts/precompiled_consumer.py \
  --archive artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz \
  --sha256 3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034 \
  --package artifacts/aphid-0.1.0-dev-local-2.tar \
  --package-sha256 921d21ece8c5a96bb3cdc5ab60b6932e73dd4471b2f9382d446d9f182bd8d7e3 \
  --destination /tmp/aphid-package-consumer-NEW
```

Next resolve exact-source notices for the four dependencies and OTP/ERTS, and map
final shipped components. A fresh source consumer remains separate and unproved;
this package intentionally contains only the inputs needed for local precompiled
installation. Network delivery, minimum OS/CPU execution, other OTP versions and
both Linux targets remain open. No Linux runner is available; do not provision or
emulate Linux. Execution is macOS 26.6 only; Aphid native declarations are 13.3,
and the validation release's bundled ERTS/crypto declarations are 15.0.
Root library/source/hex_consumer and DuckDB 1.4.4 are preserved. No native rebuild,
sanitisers, performance work or global toolchain changes occurred.
