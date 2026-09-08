# Authorized private draft, 2026-09-08

The owner explicitly authorized signing `v0.1.0-dev` at
`750dc79ec3607893fe53ba84c2cfe45158c49bc3` and creating the private draft
prerelease with the thirteen reviewed assets. Public publication and Hex were
excluded. The tag was signed with the existing configured key, verified locally
with a good signature, and pushed without moving any existing tag.

[Draft workflow 34209211522](https://github.com/catethos/Aphid/actions/runs/34209211522)
succeeded using native run `34193449987` and source run `34205212486`.
It uploaded nine Linux/notice assets; four locally reviewed macOS assets were
then attached without replacement. Release ID: `384589981`.

[Private draft](https://github.com/catethos/Aphid/releases/tag/untagged-08d7eb9d9a9b931b7919).
The final release metadata records `draft=true`, `prerelease=true`, and
`published_at=null`. All thirteen uploaded names, sizes and GitHub digests match
the approved manifest. Authenticated streaming downloads independently reproduced
every SHA256 without retaining redundant archive copies on disk.

Evidence: [workflow metadata](draft-release-run-1.json),
[workflow log](draft-release-run-1.log), [final release metadata](draft-release-final-1.json),
[download checks](draft-release-download-checks-1.json).
The initial tag-addressed API lookup returned HTTP 404, retained in
[draft-release-before-macos-1.json](draft-release-before-macos-1.json).
Authenticated listing located the draft; no duplicate release was created.
The proposal files remain unchanged historical records.

## Exact identities

The qualified source package remains
`artifacts/notices-source-linux-2/aphid-current-consumer/aphid-0.1.0-dev-combined.tar`,
SHA256 `11ca5ca447a7a93ee6d8e2d79758f3ed67d9ce04d20947a08e82598851152507`.
It is not a release asset. The earlier combined source archive remains preserved
with SHA256 `b85967b047662ccdc66851d246a9a7301fe8c797225d7e479948653838dc57df`.

| Release asset | SHA256 |
|---|---|
| `SHA256SUMS` | `470c877e7c9048abababcf1076eeeef40138745f4a6192080356c6fcd96b74ce` |
| `THIRD_PARTY.md` | `58a0d518a8ec5a1021dfef10380fc08c1eed9b70b54a8f2de18b075f4bbb23ab` |
| `THIRD_PARTY_NOTICES.txt` | `08cc1d20ccb4808537545220152d6aff97701e2c3b0b8597ab2dadaa82a789d1` |
| `aarch64-linux-gnu-elf-audit.json` | `647d7cf9fe2f37e215860fbe1de4530eb2b408d775189d4387137e710cf4739e` |
| `aarch64-linux-gnu-identity.json` | `5e00e063aa7ddb131ff050f267a840d3672d2e74cd26b2ee05068df3716fc6a2` |
| `aphid-0.1.0-dev-aarch64-linux-gnu.tar.gz` | `235ceb0490a1baf64e33fd53f17f683ce263197cf0cac6cf1107275dd94b62af` |
| `aphid-0.1.0-dev-x86_64-linux-gnu.tar.gz` | `fa9535c7e8f3b149658ed0f5f98329f7142cfd21f30f20fef765c74c42b798cc` |
| `x86_64-linux-gnu-elf-audit.json` | `c00a1963031ed4c24d8a72d0030471ff56fa3fad73a02af188dce008dc0f1014` |
| `x86_64-linux-gnu-identity.json` | `5c4643108438c42eb24d9b76f7815b96479939d3be1fc59cd7dc779fb6bc5cb7` |
| `SHA256SUMS-macos` | `e6bd3f83b12e0e0a6a556261b7412386b0c2b8e88f7c704fa941d9a5aa1c6ef2` |
| `aarch64-macos-audit.json` | `6dda9c6cc0118fd9e57d62a57d3bd2c7e41072ed9c930491999583a667355fa7` |
| `aarch64-macos-identity.json` | `b57adb61eba623025de97a8e6e8b4c0f7e3137ad2f1da8995e1d3a86ff9d24a4` |
| `runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz` | `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034` |

## Cleanup and remaining gates

[Cleanup](disk-cleanup-6.md) recovered about 4.2 GiB from 81 verified duplicate
files in older consumer workspaces, leaving 9.6 GiB free. The manifest gives
exact recovery members. Failed attempts, release workspaces, latest qualified
consumer, original artifacts, and sibling projects were preserved.

No native bytes changed or were rebuilt, and no passing qualification/sanitizer
suite was rerun. Existing source qualification remains 92 tests on macOS ARM64
and both native Linux architectures, with the previously documented restrictions.
DuckDB remains 1.4.4. A private draft does not prove anonymous HTTPS delivery.

Next concrete action: resolve the outstanding attribution/shipped-content gates
using existing inventories and review this exact draft for separately authorized
public publication. Version-specific full Pegasus 0.2.6/ZigParser 0.7.0 notices,
final linked/generated/modified-fork attribution, NimbleParsec coverage and
production ERTS/static/build provenance remain open. Do not repeat exhausted
history searches or invent grants; no maintainer messages are authorized.
After public delivery is authorized and available, enable the package-pinned
URLs and qualify the final source package against the actual repository endpoint
on native Linux x86_64/ARM64 and macOS ARM64, reusing these native bytes.
No Hex publication is authorized.

Linux execution remains proved only on Ubuntu 24.04/glibc 2.39; engine requirements
are GLIBC 2.38 and GLIBCXX 3.4.32, and installation requires GNU objcopy.
macOS execution remains proved only on 26.6; declarations of 13.3 do not prove
that minimum, and installation requires otool. Minimum CPU/OS, other OTP/binutils,
x86_64-to-ARM64 cross-build, source installation and outstanding Sections 8–9
and Stage 05/07/08/09 gates remain explicit. No target is release-supported;
no stage or implementation is complete.
