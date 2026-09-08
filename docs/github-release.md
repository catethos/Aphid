# GitHub release preparation

The public repository is [catethos/Aphid](https://github.com/catethos/Aphid),
with `zig_library` as its root and `git@github.com:catethos/Aphid.git` as its
remote. The package version remains `0.1.0-dev`. The owner has authorized source
pushes, Linux CI iterations, and seven-day retention of passing Linux validation
artifacts in GitHub Actions. **GitHub release creation and Hex publication remain
excluded.** No target is release-supported and no stage is marked complete.

## Current qualification

[Run 34184718955](https://github.com/catethos/Aphid/actions/runs/34184718955),
source `3edd9ba99e3350b98bfa327c0c7f3f6b9b878842`, passed locked native builds,
NIF compilation and all 92 BEAM tests on both native Linux architectures.
This established source qualification, not compiler-free bundle installation.
The source ELF requirements include GLIBC 2.38 and GLIBCXX 3.4.32; execution was
on Ubuntu 24.04 with glibc 2.39. Older-system and CPU-floor execution remain open.

[Run 34188940428](https://github.com/catethos/Aphid/actions/runs/34188940428),
source `d34ea305346442e6fee5b73b403a91e338d501fb`, passed both native/NIF builds and 92 BEAM suites, then failed distribution
qualification. ARM64 passed relocated native/92 BEAM tests before detecting
changed installed NIF bytes. x86_64 stopped during ELF packaging. No artifact
was uploaded. The [ELF correction](evidence/linux-elf-relocation.md) is being
checked in small-NIF preflights before another full build. Earlier attempts
and their cancellations remain in the evidence logs. See the
[loader correction](evidence/linux-loader-allowlist-fix.md) and
[locale preflight](evidence/linux-locale-preflight.md).

The manual `.github/workflows/linux-native.yml` has read-only repository
permissions. It uses native `ubuntu-24.04` and `ubuntu-24.04-arm` runners,
pinned action revisions, Elixir 1.20.0, OTP 29.0.4 and checksum-pinned Zig 0.16.0.
System package/compiler versions are recorded; the system toolchain is not yet
reproducibly pinned. No local Linux provisioning or emulation is used.

Each full job starts with fresh private source/output trees and no application
or dependency build caches. No upstream extension archive is shared between
builds. Watchdogs cover the native lifecycle, concurrent extensions,
FTS/vector/DuckDB create/reopen tests and BEAM suite. The distribution steps then
package the complete ELF closure, relocate it, run offline tests, build a local
Hex source archive, and test a fresh compiler-free consumer plus real installer
and loader failures. The consumer hides development/build trees and masks native
compilers; only dependency acquisition has external networking. Compilation and
runtime use a separate network namespace.

The public Linux identity catalog remains empty until exact passing bundles are
reviewed. CI injects its identity only into an isolated validation source package.
See [distribution preparation](evidence/linux-distribution-preparation.md).

## Approved artifact retention

The `retain_validation` input defaults to false. When explicitly enabled, it
uploads only after the complete job succeeds, using pinned official
`actions/upload-artifact` v4.6.2. Retention is seven days. The allowlist contains
the runtime archive and identity, ELF audit, local Hex source archive and identity,
consumer input hashes and qualification log. It excludes build caches and
upstream extension archives. The owner approved this scope on 2026-09-08;
run 7 enabled it but both jobs failed before upload. A preflight-only run cannot upload artifacts.

Actions retention is for qualification review. It does not provide production
GitHub release delivery. Retrieve passing artifacts before expiry, verify the
inner archive against its independent identity and record run, commit and target
provenance. The outer Actions artifact digest is not the runtime archive SHA256.

## Before release creation and Hex publication

1. Review the passing ELF closure, exact hashes, loader paths, symbols, runtime
   requirements and notices. Capture a linker map and resolve final attribution.
2. Promote only reviewed bundle identities into the installer and prove a fresh
   consumer of that exact source package. Zigler 0.16.0 requires `objcopy` on
   Linux and `otool` on macOS; compiler-free still has installer prerequisites.
3. Prove HTTPS delivery from the actual repository, package-pinned checksums,
   default precompiled selection, offline runtime and relocated Linux Mix releases.
   Execute the same artifacts on every declared minimum system and OTP version.
4. Preserve the plan's separate x86_64-to-ARM64 cross-build gate: a native ARM64
   build does not prove it. Linux musl, Windows and macOS x86_64 remain outside
   the initial matrix. Source-consumer and outstanding behavioural gates remain.
5. Prepare release creation around the reviewed immutable artifact matrix, with
   `contents: write` confined to the creation job. Keep Hex publication separate.
   The prepared manual draft workflow is described below. Actual draft creation
   and Hex publication still require authorization; no Hex publication workflow exists.

The original macOS runtime archive remains unchanged, SHA256
`3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
Its Mach-O declarations are 13.3; actual execution is macOS 26.6 only. DuckDB stays
pinned to 1.4.4. Preparing these workflows does not establish release support.

## Prepared manual Linux draft workflow

`.github/workflows/release-draft.yml` is source preparation only; it has not been
executed. It must be dispatched on an existing version tag with `reviewed=true`
after owner review of the exact assets and notices. Its only creation job has
`contents: write` and `actions: read`; qualification jobs remain read-only.
It uses GitHub's CLI to retrieve the selected run and creates only a draft
prerelease. It does not create a tag, overwrite assets or publish to Hex.

`scripts/release_assets.py` requires both reviewed Linux identities in the tagged
source catalog. Each identity must carry `qualification` with `run_id`, `attempt`
and full `commit`. These must match a successful manual Linux workflow of `main`.
The tag must match the pinned package version. The verifier compares the exact
downloaded identities, archive hashes/sizes, ELF audit hashes, native lock and
interface source hashes before staging any release assets. It retains the native
archive bytes unchanged and generates `SHA256SUMS`. The current empty catalog
rejects promotion, so this workflow is not yet ready to execute.

The verifier has an offline fixture check (`scripts/release_assets_checks.py`)
covering valid staging plus empty catalog, failed run, wrong source commit,
wrong tag, changed lock and changed archive rejection. This does not establish
actual GitHub release upload or public HTTPS delivery. Workflow lint also passes.
The Linux draft omits macOS: the approved seven-day retention scope covers Linux
qualification archives only, and the original macOS archive remains local.
Minimum systems, cross-build, production notices and other release gates above
remain open. Do not dispatch this workflow under the current retention-only
approval; obtain authorization for the concrete reviewed draft first.
