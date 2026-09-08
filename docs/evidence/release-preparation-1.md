# Default delivery preparation and shipped-content review

2026-09-08. Source checkpoint was `7df4cb8`. No release, tag or Hex publication
is authorized by this work. No target is release-supported; no stage is complete.

## Shipped content and attribution

The retained inventories and `notice-review-8.tar.gz` were reused. No Pegasus or
ZigParser history search or maintainer contact was repeated. The new
`shipped-content-review-2.json` rehashes the exact four requested archives and
compares notice-text hashes against that supplement. The first report is also
retained; its source-package count covered only outer Hex members, so the second
report additionally records LICENSE and THIRD_PARTY.md inside contents.tar.gz.

The native archives contain 67 (macOS) or 73 (each Linux) notice-named regular
members. Seven separately retained embedded preambles (CRoaring's three files,
fast_float, glob, httplib and pyparse) have no byte-identical notice member in
any of the three bundles. The full httplib text is already retained in the
native notice tree, but this does not close modified-fork review. Comparing
whole-file hashes does not establish absence of equivalent text inside a longer
file, or which texts are required for a final distribution. The supplement is a
superset that includes build dependencies and OTP; its 38/36 unmatched named
members are not a count of missing legal obligations.

The draft's seven-asset allowlist does not include this supplement. Installing a
native archive copies its own license tree; it does not fetch the separate
supplement. Before public distribution, determine and deliver the necessary
notices with installed contents (for example in the source package, preserving
qualified native bytes). Do not imply a separate review archive already solves
that distribution gap. Authoritative version-appropriate full Pegasus 0.2.6
and ZigParser 0.7.0 notices remain unavailable. NimbleParsec's README needs final
coverage review; ZigGet's matched parent notice is retained. Native generated
code, modified httplib and final linked/header-derived component mapping remain
open. Existing build records are not a final linker map. No rebuild is justified
merely to repeat these records; capture the map at the next necessary isolated
source build. OTP's six generated-source exceptions, static/build provenance
and production runtime notice mapping remain open; bundled ERTS is excluded
from this native draft, but remains relevant to production Mix releases.

## Small default installer path

The existing identity catalogs now serve as the default selection source too.
No `url` is enabled. A package identity can supply its exact HTTPS `url` and
`sha256`; the package version must match before selection. The macOS catalog now
records the existing archive name, size and SHA256 without changing native bytes.
Linux defaults accept the qualified BEAM architecture strings
`x86_64-pc-linux-gnu` and `aarch64-unknown-linux-gnu`; macOS requires ARM64.
Other targets/libcs fail explicitly. This narrow initial selection is not a
claim about other OTP builds or minimum systems.

With no selection inputs, either unset APHID_INSTALL or explicit `precompiled`
uses this path. While URLs are absent both fail `[missing]`. An explicit URL or
archive still requires its own independent SHA256; partial/conflicting selections
cannot silently use the default pin. Source mode remains explicit. Enabled
selection calls the same HTTPS client, checksum verification, safe extraction,
full native sidecars, notices and loader receipt path. Repeat default installation
is permitted only when the existing receipt and native hashes match. A forgotten
explicit selection currently reports `[missing]`, including with an existing
bundle; it does not load native modules or fall back to source.

The concrete proposed URL prefix is
`https://github.com/catethos/Aphid/releases/download/v0.1.0-dev/`.
Append the exact archive names below; these are proposed paths, not available
or tested public endpoints. Enabling URL fields requires authorized delivery
and a new source package/proof. No checksum is obtained from the download server.

| Retained artifact | SHA256 |
|---|---|
| `aphid-0.1.0-dev-combined-linux-2.tar` | `b85967b047662ccdc66851d246a9a7301fe8c797225d7e479948653838dc57df` |
| `aphid-0.1.0-dev-x86_64-linux-gnu.tar.gz` | `fa9535c7e8f3b149658ed0f5f98329f7142cfd21f30f20fef765c74c42b798cc` |
| `aphid-0.1.0-dev-aarch64-linux-gnu.tar.gz` | `235ceb0490a1baf64e33fd53f17f683ce263197cf0cac6cf1107275dd94b62af` |
| `runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz` | `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034` |
| `notice-review-8.tar.gz` | `56647f85783f8d15301176b53f860baaabdc04b73ea694bcc161415a99293471` |

## Draft review and concrete remaining gates

The current workflow still stages exactly two Linux archives, two identity JSON
files, two ELF audit JSON files and SHA256SUMS. Its creation job alone grants
contents:write; it requires an existing version tag, explicit reviewed input and
a successful source-pinned native qualification. It does not create a tag,
overwrite assets, include macOS/ERTS, or publish Hex. Version-specific notes
accurately limit the native evidence to Ubuntu 24.04/glibc 2.39.

The verifier still rejects changed Mix/Elixir source against run 34193449987's
consumer inputs. That is intentional: this installer change is not qualified by
that older run. Before draft creation, preserve native provenance from run
34193449987 while separately verifying fresh consumer provenance for the final
source package; do not weaken or remove the source comparison, and do not rebuild
unchanged natives to refresh wrapper evidence. The consumer workflow already
supports rerunning the current source with those archives.

A draft is private and does not prove anonymous public HTTPS delivery. A Linux-only
draft also cannot satisfy the three-target endpoint gate. Before requesting a
concrete draft authorization, finish the notice/shipped-content decision, decide
the macOS asset delivery scope, tie final source consumer evidence into promotion,
and identify the exact signed source tag and final asset matrix. Public
publication needs its own explicit authorization too. No approval is requested
prematurely here. Preserve local verified copies: Actions copies expire around
2026-09-15 07:03 UTC; ephemeral Linux Mix releases cannot be recovered from them.

After authorized public delivery, enable package-pinned URLs, build one final
source archive, and prove actual repository downloads and fresh compiler-free
consumers on both native Linux architectures and macOS with that exact archive.
Retain independent pins, empty caches, normal locked dependency acquisition,
compiler/development-read denial and unchanged native hashes. The existing
explicit URL test is not an actual endpoint or no-input consumer proof.

Minimum OS/CPU execution, other OTP/binutils versions, x86_64-to-ARM64 cross-build,
fresh source installation and outstanding Stage 05/07/08/09 plan gates remain.
Linux execution is Ubuntu 24.04/glibc 2.39 only, engine symbols require GLIBC 2.38
and GLIBCXX 3.4.32, and installation needs GNU objcopy. macOS execution is 26.6
only; 13.3 declarations do not prove that minimum and installation needs otool.
DuckDB remains 1.4.4. Sibling projects, configured signing and qualified native
bytes are preserved; no native rebuild, sanitizer rerun or performance work.
