# Exact-source notice follow-up

2026-09-08. No stage, implementation, legal inventory or target is marked complete
or supported. This supplements [local package evidence](local-package.md); every
previous archive and failed attempt is retained unchanged.

## Verified findings

The check uses the independent Hex pins from the tested source package and Git
blob comparisons, rather than treating a current upstream license as proof for an
older package. `scripts/notice_sources.py` reproduces the comparisons from retained
sources at `/private/tmp/aphid-notice-sources-2`, and produces a fresh archive.

| Input | Matching evidence | Notice result |
|---|---|---|
| nimble_parsec 1.4.2 | Pinned Hex archive README and metadata | README contains copyright and Apache-2.0 notice; full README retained. Separate license text still requires attribution/coverage review. |
| pegasus 0.2.6 | All 14 packaged files match commit `6f955046465d97fcef3ade6da47e7ed80e6ca3c8` | Metadata declares MIT; historical tree has no LICENSE. The newer upstream LICENSE was not substituted. |
| zig_parser 0.7.0 | All 45 packaged files match commit `3ab4aa2ff10d1886a33a6ea0fc1c908712496360` | Metadata declares MIT; matching upstream tree has no LICENSE. Gap remains. |
| zig_get 0.16.0 | All three packaged files match `installer/` at Zigler commit `afb8a604e278a21717e73151eff078854f4c84ce` | Repository-root MIT license retained with Git blob identity. |
| OTP 29.0.4 / ERTS 17.0.4 | Official tag resolves to commit `1259612946cb36a8bf9614b289090bb32fbcbeb2`; 303 installed source files match Git blobs | 22 top-level/component notice texts fetched at that commit and blob-verified. This is a source-tree superset, not a final shipped-component mapping. |
| OTP crypto OpenSSL 3.5.7 | Existing relocated release reports this version under its network/compiler/source-denial sandbox | Official tag resolves to `8cf17aaeb4599f8af87fefd810b5b5fee90fe69e`; LICENSE.txt retained and blob-verified. Version match does not prove original compiler/build inputs. |

Upstream references: [OTP release](https://github.com/erlang/otp/releases/tag/OTP-29.0.4),
[Pegasus matching source](https://github.com/ityonemo/pegasus/tree/6f955046465d97fcef3ade6da47e7ed80e6ca3c8),
[ZigParser matching source](https://github.com/E-xyza/zig_parser/tree/3ab4aa2ff10d1886a33a6ea0fc1c908712496360),
[ZigGet parent license](https://github.com/E-xyza/zigler/blob/afb8a604e278a21717e73151eff078854f4c84ce/LICENSE),
[OpenSSL license](https://github.com/openssl/openssl/blob/8cf17aaeb4599f8af87fefd810b5b5fee90fe69e/LICENSE.txt).
The native engine remains pinned to its separate OpenSSL 3.6.4 input; nothing was
rebuilt, and the OTP runtime was not relinked or upgraded.

The six installed OTP source files absent from the Git tree are retained as
explicit exceptions: compiler `core_parse.erl`, `beam_opcodes.erl`,
`beam_opcodes.hrl`; kernel `inet_dns_record_adts.hrl`; stdlib `unicode_util.erl`
and `erl_parse.erl`. Their build-generation provenance was not proved. The 303
matches cover installed compiler/crypto/kernel/sasl/stdlib sources; they do not
establish complete ERTS native build provenance or static dependency attribution.

## Artifact and verification

New supplemental archive: `artifacts/notice-review-5.tar.gz`, 684,017 bytes,
SHA256 `281df6b5fba8bb07bf06b2b27c9f238fad7979573460188f0c4f8bb504d94810`.
It retains the previous notice texts and prior inventory, supplemental texts,
matched-file identities, tag/tree provenance, raw runtime identity log, and a new
content SHA256 manifest. The sidecar `notice-review-5.tar.json` is the same report.

[Source checks](notice-source-review-1.log) pass.
[Runtime identity](notice-runtime-1.log) runs through `scripts/proof.py`'s 30-second
process-group watchdog and finishes successfully. The release still runs bundled
ERTS with external networking/compiler/development/host-runtime reads denied.
[Final checks](notice-final-checks-1.log) verify the archive's complete manifest,
unchanged prior archives, normal native engine/bridge, locks, and all 822 packaged
release files. Python syntax checks pass. The unchanged 92-test suites were not
rerun for a notice-only change; their previous passing evidence remains scoped to
the exact unchanged package/native/release artifacts.

Initial tag retrieval under the ordinary outer sandbox failed DNS resolution;
logs remain in `/private/tmp/aphid-notice-sources-1`. Read-only public-source
retrieval then succeeded with outer execution permission. No external messages,
publication, uploads, dependency-source edits or global toolchain changes occurred.
Local clones and retrieval logs remain at `/private/tmp/aphid-notice-sources-2`.

## Handoff and open gates

Next obtain version-appropriate full MIT copyright/permission notices for Pegasus
and ZigParser without borrowing another project's attribution, and map actual
linked/shipped components to notices (including ERTS/OpenSSL and native libraries).
The retained upstream source snapshots and matched hashes are the starting point.
NimbleParsec's README and the ZigGet root license narrow the earlier gaps; they do
not constitute final distribution clearance. No maintainer was contacted.

A fresh source-mode consumer, normal Hex/network delivery, minimum OS/CPU
execution, other OTP versions and both Linux targets remain open. No Linux runner
is available; do not provision or emulate one. macOS execution remains 26.6 only;
Aphid native files declare 13.3 and bundled ERTS/crypto declare 15.0. Root library/,
source/ and hex_consumer/ were preserved, as was DuckDB 1.4.4. Do not repeat passing
sanitizers or performance work for these documentation/inventory changes.
