# Local package review: third-party inputs and open notices

This source package is a local precompiled-installation review candidate at
0.1.0-dev. It is not published, release-supported, or a proved source installer.
Aphid's own source is MIT-licensed (see LICENSE), as selected by the owner.
Dependencies retain their own licenses; this does not relicense their contents.

The source package contains Aphid Elixir/Zig/C++ interface code, Mix adapter,
locked dependency/native identities and documentation. It includes no dependency
source distributions, engine libraries, NIF binaries, bundled Erlang runtime,
build caches or upstream engine trees. Dependencies resolve separately; the
local runtime archive is separately selected and independently SHA256-pinned.

Zigler 0.16.0 and its transitive dependencies are compile-time inputs. Telemetry
is a runtime dependency. Exact versions and Hex checksums are in mix.lock.
The native archive includes its existing license tree; the installer preserves
those texts unchanged. native/local-bundle.json and native/lock.json identify
the exact native closure (including DuckDB 1.4.4).

The local evidence inventory records available license/notice files and hashes
from pinned source archives, the native bundle and the installed Elixir runtime.
File discovery is not a determination that every embedded component or required
notice has been covered. The installed OTP/ERTS runtime lacks named notice files, but a separate local
follow-up now retains 22 notices from the exact official OTP source commit plus
the version-matched OTP OpenSSL 3.5.7 license. Exact build/static-component
provenance remains open. NimbleParsec's pinned README contains its notice, and
ZigGet's files match a repository commit with a root license. Pegasus and
ZigParser still lack full notice texts at their matching source commits.
Native inventory coverage, final shipped-content review,
and notices for a production Mix release remain open. No legal approval or
redistribution clearance is claimed.

See docs/local-installation.md for the local adapter recipe and boundaries.
The source archive is a standard locally built Hex tar, consumed by extracting
its contents into vendor/aphid. Network Hex installation remains unproved.

A further local build-record map retains embedded notices from CRoaring,
fast_float, glob, httplib and pyparse. The httplib header has an abbreviated MIT notice; a follow-up verified that the
full upstream 0.14.2 text matches an already retained notice and associated it
with this modified header. Direct link/header-dependency records are candidate associations, not
proof of final linked-object retention or complete attribution. See
`docs/evidence/native-notice-map.md` in the development evidence tree.

## Installed supplemental notices

`THIRD_PARTY_NOTICES.txt` now ships with this source package. It preserves ten
retained texts: seven embedded native preambles (CRoaring's three amalgamated
files, fast_float, glob, httplib and pyparse), the verified full httplib 0.14.2
notice, NimbleParsec 1.4.2's complete README notice source, and ZigGet 0.16.0's
content-matched parent license. Each section names its retained member and SHA256.
The pinned source is `notice-review-8.tar.gz`, SHA256
`56647f85783f8d15301176b53f860baaabdc04b73ea694bcc161415a99293471`.
The native preambles are associated with the retained engine/header records;
they do not prove final linked-object retention or historical build provenance.

The precompiled installer copies this file to
`priv/licenses/aphid-supplemental.txt` alongside the unchanged native archive's
license tree. Its receipt records all installed license hashes and rejects
missing or changed license files on repeat installation. Standard Mix releases
carry that application priv directory. This does not change native archive
bytes or introduce a separate notice download.

Httplib's modified Ladybug header matches the pinned engine commit; its full
upstream notice is associated with that fork, without claiming formatting-only
changes. NimbleParsec's README declares Apache-2.0; preserving it is not a final
coverage determination. ZigGet's license comes from Zigler commit
`afb8a604e278a21717e73151eff078854f4c84ce`, whose installer files match the pinned
package. Pegasus 0.2.6 and ZigParser 0.7.0 still lack authoritative full notices
for their matched versions; no later or other-project grant is substituted.
OTP/build/static-component provenance and final redistribution review remain
open. The supplemental file contains no bundled ERTS notices and is not a
production Mix-release attribution inventory.
