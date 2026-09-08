# Small review of the thirteen native draft assets

2026-09-08. Source checkpoint `6e38c8a0e75f413e88db5210635783268adc9c80`.
Working directory: `/Users/catethos/workspace/ladybugex/zig_library`.
The owner requested a narrow prepublication review, with broader verification
allowed to remain follow-up work. This supersedes the earlier blanket attribution
hold for this experimental native draft; it is not publication authorization.

## Recommendation

For this limited review, do not require Pegasus/ZigParser maintainer confirmation
or production ERTS qualification before this native prerelease. Neither parser
package nor ERTS is bundled in the three archives. Their MIT declarations are
retained from the exact published package metadata, rather than treated as absent
license evidence. A missing full package-specific copyright notice remains a
follow-up if a future distribution actually includes those packages.

One concrete notice correction is prepared: include the Zig contributors' MIT
notice in the public release body accompanying the unchanged macOS archive.
It is already present inside both Linux archives, but absent from the macOS
archive and the current supplemental attachment. The native Zig source uses
standard-library implementations, so supplying the known exact notice is simpler
than trying to prove every such implementation was optimized out.

The updated [proposed public body](../releases/v0.1.0-dev-public-body.md) includes
that text and instructs direct archive users to retain the attached supplement
and release notices alongside the archive's license tree. This avoids replacing
qualified binaries, changing any of the thirteen assets, or creating a fourteenth
asset. The [standalone notice copy](../releases/v0.1.0-dev-zig-NOTICE.txt) is local
review material, not an additional upload proposal. Publication of the existing
release with this exact body still needs separate explicit authorization.

This is a bounded engineering review of known retained components and notices,
not a legal opinion or proof that every historical build input was inventoried.
No new concrete omission was found in the retained native component map.
Broader provenance, minimum-system, source-installation, sanitizer, performance
and support gates can remain explicit follow-up work for this experimental release.
No target is release-supported and no implementation stage is complete.

## What actually ships

[Machine-readable review](small-release-review-1.json) lists the exact members,
asset hashes, mapped notice locations and proposed notice identity.

| Content | Result |
|---|---|
| Thirteen approved assets | Every local size/SHA256 still matches the immutable approved matrix. No asset modified. |
| Three native archives | Aphid native closure, Aphid and Telemetry BEAM code, tests/examples and license trees. These are validation archives, not merely four shared libraries. |
| Parser dependencies | No Pegasus, ZigParser or NimbleParsec source/module distributions in the archives. No matching parser atoms in any of the 65 packaged BEAM modules. |
| ERTS | No bundled ERTS runtime. Production runtime provenance is outside this asset set. |
| Native notices | 73 named license members in each Linux archive; 67 in macOS. All 70 distinct retained texts associated with the existing 57-component map are present in each archive's license tree or the supplemental attachment. |
| Telemetry | Its BEAM modules really ship; the complete Apache-2.0 license is included in all three native archives. |
| NimbleParsec | Its README is reproduced in the supplemental attachment, although its executable package is not bundled. The attached archive license trees include the full Apache-2.0 text; preserve those notices with the distribution. |
| Zigler-generated interface code | Zigler's MIT text is in Linux archives. The identical copyright/permission text also appears in the common supplement as the ZigGet parent license; this text therefore accompanies the macOS download when the supplement is retained. |
| Zig standard library/runtime | Exact MIT text in both Linux archives; absent in standalone macOS archive and supplement. Prepared public-body inclusion supplies it as accompanying documentation. |
| OpenSSL, DuckDB, Ladybug and mapped third parties | Existing license texts and seven embedded preambles are retained. Full httplib notice and fork copyright are available; no new fork or changed native code was introduced. |
| Source packages | The qualified Hex source tar is not one of these thirteen assets. GitHub's automatic tag snapshot is also not that qualified source package. This review does not qualify a new Hex package. |

The notice-map comparison retains all candidate notices, including supersets;
it does not rely on presumed dead stripping to discard any credit. The map was
built from retained macOS records; matching Linux texts does not create a fresh
Linux linker map. The review therefore establishes delivery of those known texts,
not complete object-level build provenance on all platforms.

Absence of parser module names alone is not proof about arbitrary copied code.
It is corroborated by the pinned integration path: Zigler calls Zig.Parser to
produce a parsed representation during wrapper compilation; Pegasus/NimbleParsec
generate the parser inside ZigParser itself, not an Aphid parser module. The
packaged modules contain Aphid and Telemetry only. No copied parser implementation
was identified, so the small review finds no basis to make the parser notice
clarifications a prerequisite for these native assets.

## Verification and preserved failures

All checks were read-only with respect to release assets. Python standard-library
`hashlib.file_digest` rechecked the thirteen independent manifest pins; `tarfile`
read members without extracting native executables. Known BEAM bytes alone were
copied to `/private/tmp/aphid-small-review-1/beams/` after archive verification.
The [retained OTP script](small-review-beam-script-1.exs) used
`:beam_lib.chunks(path, [:atoms, :imports])`, invoked as:

```sh
elixir docs/evidence/small-review-beam-script-1.exs
```

It exited 0 and produced [all 65 module records](small-review-beam-modules-1.json).
No packaged BEAM code or native NIF was executed. The initial custom Python
chunk decoder failed and was replaced by OTP's reader; the failure and unsuccessful
version-specific web fetches are preserved in [attempt log](small-review-attempt-1.log).
The exact package MIT declarations remain supported by the prior retained package
metadata and corresponding dependency `mix.exs` files.

The archive notice comparison read the 70 exact texts named in
`artifacts/notice-review-8.tar.json` from pinned `notice-review-8.tar.gz` and checked
whole-text equality against archive license members or byte inclusion in the
attached supplement. All 57 component groups have their mapped texts delivered.
The full supplement remains 21,862 bytes, SHA256
`08cc1d20ccb4808537545220152d6aff97701e2c3b0b8597ab2dadaa82a789d1`.

The newly copied Zig notice is 1,080 bytes, SHA256
`5c537d6853e005298a285d508cff9ac7192cea23576c840d485b2b586a7ff177`.
Source: `licenses/zig-0.16.0/LICENSE` inside approved Linux x86_64 archive SHA256
`fa9535c7e8f3b149658ed0f5f98329f7142cfd21f30f20fef765c74c42b798cc`.
Its original bytes are preserved both in the local notice file and proposed body.
MIT notice-preservation requirement: [official MIT text](https://opensource.org/license/mit).
Apache redistribution conditions: [official Apache-2.0 text, section 4](https://www.apache.org/licenses/LICENSE-2.0).

No dependency history search, native rebuild, sanitizer rerun, remote release
mutation, new asset, maintainer message or publication occurred. Native catalogs,
source supplement and the fixed signed tag remain unchanged. Source commits/pushes
remain authorized; release publication and Hex remain excluded.

## Next concrete action

Review and separately authorize publication of existing release `384589981` as
an unsupported prerelease with the unchanged thirteen assets, fixed signed tag
`v0.1.0-dev` at `750dc79ec3607893fe53ba84c2cfe45158c49bc3`, and the exact updated
public-body file. No duplicate release or additional asset is needed for this
notice correction. This task only prepares that result; it does not publish it.

For eventual compiler-free installation, the final source supplement should also
carry the Zig notice for macOS users, then receive the already-planned final
source-package checks after URL activation. Public availability, no-input endpoint
installation on three native targets and Hex publication remain separate steps.
Broader build/runtime attribution and support verification are deferred, not
claimed complete or silently waived for a future production release.

Final [checks](small-review-final-checks-1.json) verify the pinned notice inventory,
byte-identical Zigler/ZigGet-parent notice, unchanged native lock and disabled
catalog URLs. Proposed public-body SHA256: `be0a8afc33b553c423f78d6576fedc8205645b2e9d0c7e847267f221bcea24ae`.
