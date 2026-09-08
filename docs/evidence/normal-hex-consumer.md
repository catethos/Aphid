# Normal Hex dependency acquisition — 2026-09-08

[Run 1](normal-hex-consumer-1.log) proves the local Aphid Hex source archive with
ordinary Hex dependency acquisition instead of dependency-source path overrides.
The consumer has only the Aphid local path dependency, unpacked from the exact
local Hex archive; its lockfile is seeded from the reviewed package. The Hex
installer itself is an existing prerequisite, copied into a fresh Mix home.
Application/dependency builds and the Hex package cache start empty.

The acquisition phase runs `mix deps.get --check-locked` with external networking
allowed, native compilers blocked and development-project reads denied. All 13
downloaded Hex package archives match the independent SHA256 values in the
reviewed lockfile. Compilation and the 92-test core/FTS/vector/DuckDB run then
use the original loopback-only network sandbox. No dependency path overrides or
native compiler invocation occur, Zig is absent and its cache remains empty.
All four installed native hashes remain identical to the reviewed bundle.

This is not fresh unconstrained dependency resolution: the consumer starts with
a reviewed lockfile. Aphid itself is unpacked from a local Hex archive and the
native bundle is selected explicitly from a local file. The separate HTTPS test
covers loopback TLS delivery. Ordinary Aphid download from Hex, a GitHub-hosted
native release and default precompiled selection remain open.

New local source package, built with standard `mix hex.build --output`:
`artifacts/aphid-0.1.0-dev-https-1.tar`, 98,304 bytes, SHA256
`ff7bb4827808f2daafdbd620d838486728f1ebfe21c5390a70e9161e51995d7a`.
[Build log](https-package-build-1.log). It includes the reviewed GitHub URL and
HTTPS adapter from source commit `253dff3`; the documentation is the snapshot
at package creation. This test's harness is not shipped in the source package.

Unchanged native archive:
`runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz`, SHA256
`3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
No binary artifact or Hex package was uploaded. DuckDB remains 1.4.4; native
engine/NIFs and protected sibling projects were not rebuilt or changed.
