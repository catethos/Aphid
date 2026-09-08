# Published experimental Hex prerelease and registry verification

2026-09-08. Working directory: `/Users/catethos/workspace/ladybugex/zig_library`.
Source preparation commit: `51ee0528e80ffd6e27aa8c8f0c6cd2e9aa314e6b`.
The owner authorized experimental Hex publication, with Linux package and
additional-system qualification allowed after publication. The owner completed
the interactive publication command after Hex required a private 2FA entry.
No code or credential was supplied in chat or retained in evidence.

## Public package identity

[aphid 0.1.0-dev](https://hex.pm/packages/aphid/0.1.0-dev) is published under
`catethos`. [Package metadata](hex-published-package-1.json) and
[release metadata](hex-published-release-1.json) were retrieved anonymously.
The release is not retired. This is an experimental prerelease, with no target
release-supported and no implementation stage complete. HexDocs was not published.

The [anonymous archive download](hex-public-download-1.json) returned HTTP 200:
115,712 bytes, SHA256
`922fdacc2be68fc94f646f6fa281ed10fbf200ca9805b8e34eb169810514ebd7`.
That is byte-identical to the 54-file reviewed candidate and the checksum in
Hex release metadata. The public copy is retained locally at
`artifacts/hex-publication-1/aphid-0.1.0-dev-public.tar`.

The published package includes the three approved public archive URLs and the
23,288-byte notice supplement, SHA256
`a9380f27e98b9ee7180560a31c99994cdfcbb2b8efae4b526e5225b14c56e992`.
The supplement preserves all prior texts and the exact Zig MIT notice for macOS.
It is installed beside the archive license tree. No native asset was rebuilt,
replaced or added. [GitHub metadata](hex-github-release-check-1.json) confirms
same release ID 384589981, published prerelease state, identical body and thirteen
asset IDs/names/sizes/digests. [Remote tag](hex-fixed-tag-check-1.txt) remains
signed tag object `7b5dec1620509f33beb8cc99c74661a07f14bbb8`, targeting
`750dc79ec3607893fe53ba84c2cfe45158c49bc3`.

## Fresh installation from Hex

[Registry consumer log](hex-registry-macos-1.log): **92 tests passed**, seed 0,
15.6-second suite; runtime command exited 0 after 18.942 seconds. The host is
native macOS ARM64 26.6, Elixir 1.20.0, OTP 29.0.4 / ERTS 17.0.4.

The existing consumer proof now has a small `--hex-registry` option. It declares
`{:aphid, "== 0.1.0-dev"}` in the fresh consumer, acquires Aphid itself through
Hex, and verifies the downloaded tar against the independently reviewed package
pin. All 54 extracted source files are checked against the oracle; the unused
local oracle is then removed before compilation, ruling out its use as a path
dependency. This helper is not in the published package and does not alter it.

Dependency and application build caches are fresh. Dependency versions start
from the reviewed source lock; this proves registry acquisition with those pins,
not every future unconstrained dependency resolution. The new Aphid lock entry,
all downloaded dependency archive hashes and all extracted package bytes are
checked. See [consumer project](hex-registry-macos-project-1.exs),
[resolved lock](hex-registry-macos-lock-1.txt), and
[input identities](hex-registry-macos-inputs-1.json).

Default native download uses the package catalog, with no APHID installation
inputs. Public HTTPS is allowed for acquisition/compilation; native compiler
execution and development-tree reads are denied. Runtime networking is denied.
All four installed native files and all 68 installed license files match the
independent archive/source identities. No native compiler invocation occurred;
the Zig cache stays empty. [Final checks](hex-registry-final-checks-1.json)
record those hashes and the absence of a local Aphid path dependency.

Exact command:

```sh
python3 -u scripts/precompiled_consumer.py --archive artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz --sha256 3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034 --package artifacts/hex-publication-1/aphid-0.1.0-dev-public.tar --package-sha256 922fdacc2be68fc94f646f6fa281ed10fbf200ca9805b8e34eb169810514ebd7 --destination /private/tmp/aphid-hex-registry-macos-1 --hex-dependencies --package-default --hex-registry
```

The retained proof uses external process-group watchdogs. The registry option's
argument guard rejects a missing `--package-default` before creating a workspace
(exit 2), and existing URL-selection checks pass; see
[guard output](hex-registry-guard-1.log) and
[selection output](hex-registry-selection-checks-1.log). Python syntax and
source/documentation whitespace checks pass. Raw tool logs retain their original
trailing whitespace. Expected Zig formatter-unavailable warnings and the native
live-upgrade rejection in the suite are preserved; they are not test failures.

## Attempts, scope and handoff

Earlier missing authentication, absent snapshot dependencies and the CLI's
`:eof` failure at the 2FA prompt are retained in
[authenticated attempt evidence](hex-publish-attempt-1.md) and its linked logs.
The registry returned 404 after the failed attempt, before the owner completed
the interactive command. Publication was not blindly retried or overwritten.
The authenticated client was Hex 2.4.2; the original preparation used 2.5.1.
Byte-identical rebuilding and the final public hash resolve package identity
across those tool versions. The browser authentication and mandatory 2FA behavior
are documented in [Hex 2.4 notes](https://hex.pm/blog/hex-v24-released).

The README, status and handoff now reflect publication. These subsequent source
and evidence edits do not retroactively change the published tar, and that tar
must not be rebuilt/replaced merely to include the later status wording.

Next: fresh installs **from Hex** on native Linux x86_64 and ARM64, then additional
Linux distributions/minimum-system environments as available. Use the published
package pin above with `--hex-registry`, new work/evidence destinations and the
matching unchanged native oracle. The older public-consumer workflow uses a local
source dependency; extend its invocation to registry mode when scheduling that
follow-up, rather than claiming it already establishes Hex installation.
No Linux workflow was dispatched during this publication verification.

Linux execution evidence still covers Ubuntu 24.04/glibc 2.39 only; engine
requirements are GLIBC 2.38 and GLIBCXX 3.4.32, with GNU objcopy needed to install.
macOS requires otool; declared 13.3 is not minimum execution proof. Exact runtime
catalog checks, source-installation, cross-build, broader attribution/production
ERTS provenance, native hardening, performance and remaining Stage 05/07/08/09
and Sections 8–9 gates remain open. No maintainer message, extra GitHub release,
native rebuild, support claim or stage completion occurred.
