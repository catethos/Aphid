# Installed notice supplement preparation

2026-09-08, continuing source `6fa5afa`. No target is release-supported and no
stage is complete. Release creation/public delivery and Hex publication remain
unauthorized; no external maintainer message was sent.

The source package now includes `THIRD_PARTY_NOTICES.txt`: 21,862 bytes, SHA256
`08cc1d20ccb4808537545220152d6aff97701e2c3b0b8597ab2dadaa82a789d1`.
It preserves ten retained notice texts from the checksum-pinned supplement
`notice-review-8.tar.gz` (SHA256
`56647f85783f8d15301176b53f860baaabdc04b73ea694bcc161415a99293471`).
Seven native preambles and the full verified httplib text supplement the native
archives' existing notice trees. NimbleParsec's full README and ZigGet's matched
parent license preserve the known build-dependency notices too. The generator
reads only ten fixed regular members and checks the archive pin before reading;
`--check` reproduces the shipped bytes exactly. Every retained section includes
its original bytes, member name and content hash.

The installer copies the single file into `priv/licenses/aphid-supplemental.txt`.
All archive license texts stay unchanged. The receipt now hashes all licenses as
well as native libraries; repeat installation verifies missing/corrupt notices
and native files before writing a staging tree. Missing source notice content is
an actionable `[missing]` failure, and an archive collision with the reserved
supplement filename is rejected. No native input, binary or archive is rebuilt
or repacked. The consumer proof checks exact installed notice hashes, and the
Mix-release proof checks that the relocated application carries the same file.
The release verifier includes the notice file in its tested-source comparison.

This closes the concrete omission of these retained texts from installed
contents; it does not close final attribution. No source-history search was
repeated. Version-appropriate full Pegasus/ZigParser grants, final linked/generated
component mapping, NimbleParsec coverage and production runtime provenance/notices
remain open. The upstream-to-Ladybug httplib difference remains a modified fork,
not merely formatting. No license grant or copyright holder was invented.

Qualified runtime archive SHA256 values remain:
- Linux x86_64: `fa9535c7e8f3b149658ed0f5f98329f7142cfd21f30f20fef765c74c42b798cc`.
- Linux ARM64: `235ceb0490a1baf64e33fd53f17f683ce263197cf0cac6cf1107275dd94b62af`.
- macOS ARM64: `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.

DuckDB stays 1.4.4. Ubuntu 24.04/glibc 2.39 and macOS 26.6 are the only proved
execution systems. GLIBC 2.38/GLIBCXX 3.4.32 requirements and macOS 13.3
load-command declarations do not prove minimum-system/CPU execution. GNU objcopy
and otool remain installer prerequisites. Other OTP/binutils, cross-build from
x86_64 to ARM64, source installation and outstanding plan gates remain open.
