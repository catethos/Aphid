# Native build-record notice mapping

2026-09-08. Stages remain in progress; no implementation, notice inventory or
release-support claim is marked complete. This follows [notice-source evidence](notice-sources.md).

`scripts/native_notice_map.py` reads the retained normal Ladybug/DuckDB Ninja
link/dependency records with the read-only `ninja -t deps` tool. It does not build,
relink, read/reuse shared upstream extension archive contents, or modify source.
The engine link paths are evidence only; shared extension archives remain
untrusted across builds. The original normal engine SHA256 is checked before
comparison to the exact adapter-installed packaged engine.

[Map 2](native-notice-map-2.log) records:

- 41 distinct direct engine link inputs, including system flags and static archives.
- 1,163 Ladybug and 333 DuckDB object dependency records.
- 57 component groups with candidate notice associations, covering direct static
  dependencies plus third-party paths in retained header dependency records.
- Seven embedded notice preambles from CRoaring's three amalgamated source/header
  files, fast_float, glob, httplib and pyparse. Source SHA256 and line extents are
  recorded; the texts are preserved byte-for-byte.
- All 13 file-backed Mach-O sections match between the normal and packaged engine.
  Whole-file hashes differ because runtime packaging adjusts load commands and
  signing; this check compares section contents, not minimum-OS compatibility.

The earlier named-file inventory omitted those embedded notices. CRoaring,
fast_float, glob and pyparse contain permission text; httplib's header contains
copyright and an MIT label but no full permission text. That specific gap stays
open. Candidate notice association for generated Cypher parser/extension code
uses the engine license; generated-code and final attribution review remains open.

The dependency records are not a linker map: they do not prove every object or
header-derived implementation survived dead stripping in the binary. Recorded
header paths also do not carry historical content hashes. The embedded notice
preambles are hashed from the currently retained source; this is not a fresh
reproducible source-build proof. Broad third-party inventories include texts for
upstream components/tools which may not ship. No notice text was deleted based
on presumed dead stripping or non-use.

## Exact supplement and checks

New archive: `artifacts/notice-review-7.tar.gz`, 709,776 bytes,
SHA256 `550da48de1d66b4e1205157d9b62a9cfbc2a3a1e0022060a47ca6232a987598d`.
The archive retains all previous notice texts and inventories, seven embedded
notice preambles, the relevant retained link rule and a new manifest/component
mapping. `artifacts/notice-review-7.tar.json` is the same report outside the tar.

[Final checks](native-notice-final-checks-1.log) verify every manifest member,
prior-text preservation, unchanged native/runtime/source package archives,
normal engine/bridge and locks. Python syntax checks pass. This is a read-only
build-evidence comparison, so unchanged runtime tests/sanitizers were not rerun.
The prior 92-test consumer/release evidence remains tied to unchanged artifacts.

[Attempt 1](native-notice-map-1.log) failed while writing because the new script
omitted an `io` import. The partial `notice-review-6.tar.gz` is retained and is
not a usable supplement. The import was corrected and a new archive path used;
no evidence file was overwritten.

## Concrete handoff

Next obtain the full version-appropriate httplib notice and Pegasus/ZigParser
attribution, then review actual linked/shipped component coverage using the
retained map. A fresh source build should capture an actual linker map plus
content-pinned headers/isolated extension inputs; it must not reuse shared
upstream extension archives. OTP/static dependency build provenance remains open.

The native candidate remains `runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz`,
SHA256 `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
The MIT Hex package remains `aphid-0.1.0-dev-local-2.tar`, SHA256
`921d21ece8c5a96bb3cdc5ab60b6932e73dd4471b2f9382d446d9f182bd8d7e3`.
Fresh source installation, normal Hex/network delivery, minimum OS/CPU execution,
other OTP versions and both Linux targets remain open. No Linux runner is
available; do not provision/emulate one. No native rebuild, global toolchain
change, sanitizer/performance work, external messages, publication/upload or
stage completion occurred. Root library/source/hex_consumer and DuckDB 1.4.4
remain unchanged.
