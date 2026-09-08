# Experimental Hex publication scope

For subsequent versions, see [publishing updates and platform changes](publishing-updates.md).

## 0.1.1-dev

The owner authorized a follow-up stability/correctness prerelease, including new
native bundles for macOS ARM64 and both Linux architectures. This version requires
the new three-target qualification and final package checks before publication;
the first release's sequencing exception below does not apply. See
[0.1.1-dev evidence](evidence/release-011.md) for results and artifact identities.
The existing `0.1.0-dev` package, signed tag and assets stay unchanged.

## First release history

Published: [aphid 0.1.0-dev](https://hex.pm/packages/aphid/0.1.0-dev).
The anonymous archive matches the approved package SHA256
`922fdacc2be68fc94f646f6fa281ed10fbf200ca9805b8e34eb169810514ebd7`.
See [final publication evidence](evidence/hex-published-1.md). The preparation
sequence below records the authorized scope; Linux follow-up remains open.

The owner has authorized publishing `aphid` version `0.1.0-dev` to Hex after
preparing the final package and checking it locally on macOS ARM64. Linux
installation checks and tests on additional Linux systems may follow publication.
This supersedes the earlier requirement to qualify the final package on all
three native targets before publishing. It does not waive failures discovered
during preparation or authorize a stable/support claim.

The package uses the three reviewed public native URLs at
`https://github.com/catethos/Aphid/releases/download/v0.1.0-dev/`, with the
existing independent SHA256 pins. The source supplement includes the Zig MIT
notice missing from the standalone macOS archive and is installed alongside
archive notices. The thirteen GitHub assets and signed tag remain unchanged.
The Hex source package is a new artifact, not GitHub's automatic tag snapshot.

## Publication sequence

1. Build and inspect the exact source package: metadata, file list, notices,
   catalog URLs and hashes. Use a package-only Hex dry run; HexDocs is separate.
2. Run a fresh macOS ARM64 consumer of those exact source bytes through default
   public downloads, with normal Hex dependencies and native compilers denied.
   Verify the installed native/license hashes and the existing 92-test suite.
3. Publish that reviewed package using the authenticated owner's Hex account.
   Verify the published package's identity and fresh registry installation.
4. Follow with fresh native Linux x86_64/ARM64 installs from Hex, then additional
   distributions/older systems as available. Preserve failures and report limits.

## Compatibility and open gates

Use Elixir 1.20.0 / OTP 29.0.4 (ERTS 17.0.4); the native catalog enforces this
runtime identity. Linux installation needs GNU objcopy. Its engine requires
GLIBC 2.38 and GLIBCXX 3.4.32; existing execution evidence is Ubuntu 24.04/glibc
2.39 only. macOS requires otool, with execution evidence on 26.6 only. A declared
13.3 minimum does not prove execution there. musl, Windows and macOS x86_64 have
no catalog entry. Default installation never silently falls back to compilation.

No target is release-supported and no implementation stage is complete.
Final-package Linux results, additional-system/CPU/OTP compatibility, fresh source
builds, cross-compilation, broader provenance, native hardening and performance
acceptance remain visible follow-up work. Prior source packages' test results do
not automatically qualify this package. Production bundled-ERTS review is a
separate distribution scope. No native rebuild, extra GitHub release or maintainer
message is included in this task.

The current outcome and exact source hash are recorded in the repository's
`docs/evidence/hex-publication-1.md`; that evidence is not part of the Hex payload.
