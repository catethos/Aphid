# Httplib notice association and dependency-history limits

2026-09-08. This follows [native notice mapping](native-notice-map.md). No stage,
implementation, legal inventory or target is marked complete or supported.

## Httplib

The official `v0.14.2` tag resolves to
`f14accb7b6ff4499321e14c61497bc7e4b28e49b`. The [upstream LICENSE](https://github.com/yhirose/cpp-httplib/blob/f14accb7b6ff4499321e14c61497bc7e4b28e49b/LICENSE)
and header were downloaded at that commit and verified against their Git blobs.
The full license SHA256 is
`4b45cbe16d7b71b89ae6127e26e0d90a029198ca5e958ad8e3d0b8bbed364d8b`;
it is byte-identical to the already retained
`native/duckdb/third_party/httplib/LICENSE` notice in the supplements.
The map now associates that full text with Ladybug's httplib component too.
No license was invented or substituted from a merely similar project.

The retained Ladybug header advertises 0.14.2, but is a modified fork, not an
exact copy of that upstream header. It matches the pinned Ladybug engine commit
`f150bddf7d01c65e5308384b8a064af1e2347701`. The difference includes formatting,
added status-code definitions and other source changes; it must not be described
as formatting-only. Upstream header, full diff, tag/tree identity and provenance
are retained in `docs/evidence/attribution-1/` and the new supplement.
Final modified-fork/component attribution review remains open.

| File | SHA256 |
|---|---|
| Upstream httplib.h | `646136e93fdec176cc9576b89cf0164eb7ed95d55277747454c4373a26b48349` |
| Retained Ladybug httplib.h | `0ee34d727ac5d751091abaf8ac92ba01eeb95d5979402427b5161b7fc14fd71e` |
| Retained upstream-to-Ladybug diff | `1d65665edb373ff3974b3ae6d694daaf5dd0b2be186d97199de23141b8541cd2` |

## Pegasus and ZigParser

The fetched default-branch histories are no longer shallow: Pegasus has 34
commits through `34828fb48ad80f751ea5be8aca5d5f59673a43c4`; ZigParser has 119 through
`3ab4aa2ff10d1886a33a6ea0fc1c908712496360`. This covers those ancestors only, not
all possible refs, external notices or separate grants.

Pegasus's named license file first appears at
`2528f293b1e7d65898e8a11ad092dc57a297ac53`, after the exact package-matching 0.2.6
commit `6f955046465d97fcef3ade6da47e7ed80e6ca3c8`. That later commit also changes
source and version. ZigParser's fetched history contains no named LICENSE,
LICENCE, COPYING or NOTICE file. Both pinned package metadata records declare
MIT, but these checks do not establish the missing full attribution texts.
The later Pegasus license is not silently applied to the old package, and
ZigGet's parent license is not borrowed for ZigParser. No maintainer was contacted.
Further repeated scans of these same histories would add no evidence; obtaining
authoritative version-appropriate notices remains the concrete unresolved step.

## Artifact, checks and handoff

New `artifacts/notice-review-8.tar.gz`: 851,345 bytes, SHA256
`56647f85783f8d15301176b53f860baaabdc04b73ea694bcc161415a99293471`.
[Map 3](native-notice-map-3.log) passes with the full httplib notice association,
57 component groups, 41 direct link inputs and unchanged matching contents for
all 13 file-backed engine sections. [Final checks](attribution-final-checks-1.log)
verify manifest contents and unchanged runtime/package/normal native/lock hashes.
`native_notice_map.py` now embeds and verifies the attribution evidence. Python
syntax checks pass. Existing artifacts, including incomplete attempt 6, remain.
No unchanged runtime or sanitizer suites were rerun for this notice-only change.

Next prepare the source-installation input/prerequisite preflight against the
local package before attempting an expensive fresh source build. Keep the
Pegasus/ZigParser notices and final linked/shipped attribution review open; they
need evidence beyond the histories already inspected. A fresh build must use
isolated extension inputs and capture an actual linker map and content identities.

The native archive remains `runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz`,
SHA256 `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
The Hex archive remains `aphid-0.1.0-dev-local-2.tar`, SHA256
`921d21ece8c5a96bb3cdc5ab60b6932e73dd4471b2f9382d446d9f182bd8d7e3`.
Fresh source installation, normal Hex/network delivery, minimum OS/CPU execution,
OTP/static dependency build provenance, other OTP versions and both Linux targets
remain open. No Linux runner is available; do not provision/emulate one.
Root library/source/hex_consumer and DuckDB 1.4.4 remain unchanged. No native
rebuild, global toolchain change, performance work, external message,
publication/upload or implementation/stage completion occurred.
