# GitHub release preparation

The repository is `git@github.com:catethos/Aphid.git`
([GitHub](https://github.com/catethos/Aphid)), with this `zig_library` directory
as its root. The prepared workflow is `.github/workflows/linux-native.yml`.
The remote was verified as an empty public repository with default branch `main`.
A local `main` repository and `origin` remote are configured. The package links
to this repository; its version remains `0.1.0-dev`. Nothing has been pushed,
dispatched, uploaded or published.

The workflow is manual and has read-only repository permissions. It uses native
`ubuntu-24.04` x86_64 and `ubuntu-24.04-arm` runners, pinned action revisions,
Elixir 1.20.0, OTP 29.0.4, and SHA256-pinned Zig 0.16.0 archives. Runner labels are
listed in the [GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
Account/repository availability and the pinned BEAM downloads still need an actual
run. OS packages come from the runner's apt repositories; compiler and system
versions are recorded, not yet a reproducible pinned system toolchain.

Each job starts without Aphid/dependency build caches and uses a fresh private
source/output pair. It retrieves locked sources, builds static OpenSSL/DuckDB and
the engine with FTS/vector/DuckDB, builds the bridge, and runs native lifecycle,
concurrent extension, create/reopen feature tests and the BEAM suite under
`scripts/proof.py` watchdogs. The candidate NIFs use explicit target and baseline
CPU flags. No upstream extension archive is shared between jobs. These are source
qualification jobs, not compiler-free consumer or release jobs. No artifacts are
uploaded; GitHub retains job logs under the repository's retention policy.

The Linux C/C++ recipes request x86-64/generic or ARMv8-A and build OpenSSL with
PIC and an explicit `lib` install directory. The host must match the target.
macOS cannot substitute for Linux. Neither an instruction-floor claim nor a
glibc minimum follows from these flags. Native ARM64 qualification does not
fulfil the plan's x86_64-to-ARM64 cross-build gate.

## Before release creation and Hex publication

1. Review and authorize the initial source push to the confirmed public repository.
   Commit/push the reviewed source and execute the Linux qualification jobs
   on actual runners. Investigate retained failures before changing pins. No
   local Linux provisioning or emulation is part of this recipe.
2. Use passing builds to package and relocate the entire ELF closure. Inspect
   ELF architecture, NIF metadata, rpaths, GLIBC/GLIBCXX requirements, exported
   symbols and external libraries. Retain exact binaries and source/toolchain
   hashes. Capture a real linker map and complete final notice review.
3. Add those reviewed identities to the bundle installer; it currently accepts
   only the original macOS candidate. Prove installer failures and a fresh
   compiler-free Linux consumer on both architectures, with development reads
   and compiler execution denied. Zigler 0.16.0 uses `objcopy` on Linux and
   `otool` on macOS, so compiler-free does not mean zero installer prerequisites.
4. Prove HTTPS delivery from the actual repository, trusted package-pinned
   checksums, default precompiled selection without source fallback, offline
   runtime and relocated Mix releases. Run the same artifact on each declared
   minimum system and proposed OTP version. The existing macOS 92-test proof
   does not replace these gates.
5. Only then wire release creation to the passing artifact matrix, create a
   versioned Hex package with the reviewed repository URL and checksums, and
   verify its exact contents in a fresh consumer. The release workflow must use
   narrowly scoped `contents: write` only for its creation job; Hex credentials
   belong only in the separately authorized publication job. There is currently
   no release-creation or Hex-publication workflow.

Linux musl, Windows and macOS x86_64 remain outside the initial matrix. Source
consumer qualification, minimum systems, cross-building, outstanding behavioural
and attribution gates remain open. Preparing this workflow does not make Aphid
ready to publish or establish release support.
