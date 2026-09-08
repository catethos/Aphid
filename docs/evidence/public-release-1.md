# Authorized experimental prerelease publication

2026-09-08. Working directory: `/Users/catethos/workspace/ladybugex/zig_library`.
Starting signed source: `060c5622cc6eb8a4e3acd983d149d117d5c71546`.
The owner explicitly authorized publication of the existing reviewed release,
its unchanged thirteen assets, and the exact prepared public notes; source
commits/pushes were also authorized. The earlier publication holds are superseded
only for this exact experimental native asset set.

[Public release](https://github.com/catethos/Aphid/releases/tag/v0.1.0-dev):
ID **384589981**, `draft=false`, `prerelease=true`. The only release mutation was
PATCH to `repos/catethos/Aphid/releases/384589981` with `draft=false`,
`prerelease=true`, `make_latest="false"`, and the exact UTF-8 contents of
`docs/releases/v0.1.0-dev-public-body.md`. No release-by-tag lookup or duplicate
creation was used. No asset was added, replaced or removed.

## Identity and publication evidence

- [Source signature](public-release-source-signature-1.log) and
  [tag signature](public-release-tag-signature-1.log): good signatures using
  existing RSA key `F9C8C4619FACD22878C2B41BDF27047769301EAB`.
- [Remote references before](public-release-remote-refs-1.txt) and
  [after](public-release-remote-refs-after-1.txt), plus GitHub
  [tag reference](public-release-tag-ref-1.json) and
  [tag object](public-release-tag-object-1.json): signed tag object
  `7b5dec1620509f33beb8cc99c74661a07f14bbb8` still targets
  `750dc79ec3607893fe53ba84c2cfe45158c49bc3`. Never moved or recreated.
- [Preflight](public-release-preflight-1.json): HEAD matched the authorized
  source; body bytes matched that commit and SHA256
  `be0a8afc33b553c423f78d6576fedc8205645b2e9d0c7e847267f221bcea24ae`
  (4,813 bytes). All thirteen local asset hashes/sizes and GitHub asset
  names/sizes/digests matched the approved manifest; IDs matched historical
  draft metadata. The draft had `published_at=null`.
- [Before metadata](public-release-before-1.json),
  [PATCH response](public-release-published-1.json), and
  [anonymous metadata](public-release-anonymous-metadata-1.json): same release
  ID, exact public body, same thirteen asset IDs/names/sizes/digests after publication.
- [Latest stable check](public-release-latest-check-1.json): anonymous `/releases/latest`
  returned HTTP 404; this prerelease is not designated latest stable.
- [Scope checks](public-release-scope-checks-1.json): catalogs, native lock,
  approved manifest and public notes remain byte-identical to the starting
  commit. Both native catalogs still have no enabled download URL.

The public body retains the Zig MIT notice accompanying the standalone macOS
archive and the instruction to retain `THIRD_PARTY_NOTICES.txt` and release
notices beside downloads and their license trees. The small review found no
bundled Pegasus, ZigParser, NimbleParsec packages or ERTS. Their unresolved
provenance questions were not reinstated as blanket blockers for these assets.

## Independent public downloads

[Download results](public-release-download-checks-1.json) and
[output](public-release-download-1.log): **13/13 passed**, HTTP 200, every byte
count and independently computed SHA256 matched the approved manifest.
The [retained verifier](public-release-verify-1.py) used a fresh standard-library
HTTP opener without authentication, cookies or credential files. It fetched
release metadata by ID anonymously, then streamed each actual public
`browser_download_url` in 1 MiB chunks through SHA256. No native executable ran
and no redundant archive copy was retained. Redirect endpoint paths are recorded;
expiring signed query strings are omitted.

Commands used from the working directory:

```sh
git verify-commit HEAD
git verify-tag v0.1.0-dev
git ls-remote origin refs/heads/main 'refs/tags/v0.1.0-dev*'
gh api repos/catethos/Aphid/releases/384589981
gh api repos/catethos/Aphid/git/ref/tags/v0.1.0-dev
gh api repos/catethos/Aphid/git/tags/7b5dec1620509f33beb8cc99c74661a07f14bbb8
# Temporary JSON contained only the four authorized PATCH fields described above.
gh api --method PATCH repos/catethos/Aphid/releases/384589981 --input /private/tmp/aphid-public-release-patch-1.json
python3 docs/evidence/public-release-verify-1.py
```

All publication/download checks exited 0. There were no asset mismatches or
HTTP download failures. Initial sandboxed signature verification could not
access the existing GPG keybox daemon (`Operation not permitted`, `Can't check
signature: No public key`); it succeeded with authorized broader access and no
signing configuration change. GPG also reported its pre-existing older keyboxd
version warning, without invalidating signatures. An exploratory `priv/native*`
path search had no matches; actual catalogs are `native/local-bundle.json` and
`native/linux-bundles.json`, checked directly. These were tooling/path failures,
not failed artifact checks. PATCH stderr is retained in
[publication log](public-release-publish-1.log).

## Status and next handoff

Public availability and anonymous integrity are now proved for these thirteen
assets. They do **not** establish package-default installation, release support,
or implementation-stage completion. No target is release-supported and no
implementation stage is complete. No Hex publication, maintainer message, native
rebuild, extra release, or catalog activation occurred. Earlier evidence and
sibling projects remain preserved. DuckDB remains 1.4.4.

Next task: prepare the final source package with the retained Zig notice in its
installed supplement and reviewed public catalog URLs, then qualify **that exact
package** against the actual public endpoints on native Linux x86_64, Linux ARM64
and macOS ARM64. Preserve the fixed tag and existing native assets. Record the
new source-package hash and fresh compiler-free/default-selection results on all
three targets; previous 92-test qualifications cover their recorded source
packages only. This publication task deliberately leaves catalog URLs disabled.

Minimum CPU/OS execution, other OTP/binutils, x86_64-to-ARM64 cross-build, fresh
source installation, broader attribution/build/runtime provenance, and remaining
Stage 05/07/08/09 and Sections 8–9 acceptance gates remain open. Linux execution
is established only on Ubuntu 24.04/glibc 2.39 (engine needs GLIBC 2.38 and
GLIBCXX 3.4.32; installer needs GNU objcopy). macOS execution is established only
on 26.6 (13.3 is declared, not execution-qualified; installer needs otool).
Hex publication remains excluded.
