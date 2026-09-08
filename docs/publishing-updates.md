# Publishing future Aphid versions

Aphid publishes **one Hex package version for all included platforms**. Its Mix
installer selects a native archive by OS/architecture and verifies the catalog's
SHA256. GitHub hosts those archives; Hex hosts the Elixir source, installer,
catalogs and notices. Changing the Git repository alone does not update either
published artifact.

This guide describes the release process. It does not run publication or declare
additional platforms supported. See [current status](status.md), the
[release checklist](release-checklist.md) and
[first Hex publication evidence](evidence/hex-published-1.md) for actual results.

## Decide what must change

| Change | Native work |
|---|---|
| Documentation or Elixir-only behavior with an unchanged native interface | Compatible native binary bytes may be reused, after checking the new behavior against them. Versioned archive packaging may still need updating. |
| Zig/NIF interface, C++ bridge, engine, extensions, patches or native dependencies | Rebuild affected bundles from the new locked inputs and qualify each included target. |
| Another Linux distribution with compatible architecture and libraries | First test the existing archive; a separate binary is not automatically needed. |
| Older Linux libraries or an older macOS version | Build against an appropriate minimum baseline and execute on that baseline. Changing a manifest label does not establish compatibility. |
| Different CPU architecture | Build and execute a matching native bundle. Cross-compilation alone is not runtime qualification. |
| Alpine/musl, Windows or Intel macOS | Add target-specific build, packaging, installer and loader handling; the current implementation lacks these targets. |
| Different Elixir/OTP version | Qualify that runtime and update the exact compatibility checks deliberately. |

An OS release and a binary target are different things. Several Linux
distributions may use the same glibc binary if their dependencies are compatible.
The complete dependency closure determines the minimum requirements. Do not
produce a separate Hex package for each distribution.

## Current version coupling

The initial release is not yet a one-command, version-independent pipeline.
Changing only `version` in [mix.exs](../mix.exs) is insufficient:

- [macOS catalog](../native/local-bundle.json) and
  [Linux catalogs](../native/linux-bundles.json) carry `package_version`, target,
  runtime identity, archive name, URL and hashes.
- [The installer](../mix/aphid_bundle.exs) requires the catalog version to match
  the source version. It reads native files from
  `lib/aphid-<package_version>/priv/lib/` inside the archive.
- Build, bundle, qualification and release helpers still contain first-release
  versions, filenames and fixture paths. Inspect relevant occurrences before
  preparing a new release; do not globally replace historical evidence.

A useful future improvement is to derive active release paths and metadata from
one version input. This documentation does not implement that improvement.
Reusing native bytes currently requires matching archive layout/catalog handling;
pointing a bumped package version at an old archive without checking the layout
will fail. Never weaken checks to make a mismatched bundle load.

## Release sequence

1. **Finish and test the change.** Commit source, dependency locks, notices and
   documentation. Include tests for changed behavior. Review the diff and record
   the exact source identity used for each build.
2. **Choose a new version**, such as `0.1.1-dev` for another experimental release.
   Update active version references and catalog/package metadata consistently.
   Follow semantic versioning; do not overwrite an existing release to ship
   ordinary code changes. Keep the published `v0.1.0-dev` tag and assets fixed.
3. **Prepare the native target matrix.** Build or reuse compatible native bytes
   according to the table above. Include the full NIF/bridge/engine closure,
   required ALGO/FTS/vector/DuckDB functionality and all applicable notices. Record
   archive hashes, native-input hashes, runtime versions and system requirements.
4. **Qualify the candidate.** Test on the actual included architectures, with
   fresh installation caches, checksum verification, no native compilation in
   precompiled mode, installed notices, offline runtime and required feature
   suites. Use the current change's tests: the archived first-release 92-test
   suite alone cannot cover newly added behavior.
5. **Publish matching native assets.** Use a new signed release tag and a new
   versioned GitHub release when publishing new versioned bundles. Verify actual
   anonymous downloads against the independently reviewed hashes. Preserve old
   tags and assets; do not reuse a mutable URL for different bytes.
6. **Freeze the final Hex package.** Pin the verified public URLs and hashes,
   build and inspect the source archive, and record its SHA256. Test that exact
   source package with default selection. Source or notice changes after this
   point require a new package hash and appropriate rechecking.
7. **Publish to Hex and verify.** Confirm package/version/owner, run a package-only
   dry run, publish, then anonymously fetch the Hex tarball and compare it with
   the reviewed hash. Perform a fresh registry install using `{:aphid, "== VERSION"}`,
   not a local path dependency. Sign/push final evidence and the next handoff.

For an experimental release, the approved scope may allow publication after a
local package check with additional Linux qualification afterward, as it did for
`0.1.0-dev`. List those checks as pending and report failures. That sequencing
choice does not establish support, close implementation stages, or qualify a
future package using results from an older package.

## Where to publish and which commands to use

Publication can run from a clean, reviewed repository checkout:

```sh
cd /Users/catethos/workspace/ladybugex/zig_library
mix deps.get --check-locked
mix hex.publish package --dry-run
mix hex.publish package
```

These are the final publication commands **after** the preparation above. They
do not build the native platform archives. Verify that the source being packaged
still matches the tested snapshot. Hex's `--dry-run` performs local checks;
`package` selects package-only publication. HexDocs needs a configured docs build
and separate verification. See the [Hex task reference](https://hex.hexdocs.pm/Mix.Tasks.Hex.Publish.html)
and [publishing/version guidance](https://hex.pm/docs/publish).

A dedicated clean checkout or frozen publication copy is optional when normal
work will continue in parallel. The temporary directory used for the first
publication existed to prevent later edits from entering that tested package;
it is not a Hex requirement. Those temporary copies have since been cleared.
Create a fresh directory if isolation is needed, preserve package/evidence hashes,
and clean completed workspaces after verifying required artifacts are retained.

If authentication is missing, run `mix hex.user auth` privately. Enter publishing
2FA codes in the terminal, never in chat, scripts or logs. If a publication command
fails after submission, inspect the registry first to determine whether it
succeeded before retrying. Do not use `--replace` as a routine release workflow.

## Current compatibility baseline

The initial catalogs include Linux x86_64/glibc, Linux ARM64/glibc and macOS ARM64.
The installer currently requires Elixir 1.20.0 / OTP 29.0.4 (ERTS 17.0.4).
Linux needs GNU objcopy; native requirements include GLIBC 2.38 and GLIBCXX 3.4.32.
macOS needs otool. Existing execution evidence is Ubuntu 24.04/glibc 2.39 and
macOS 26.6; the macOS 13.3 binary declaration is not minimum-system execution
proof. Consult the current status before repeating these limits in release notes.

Record build target, execution system, CPU, libc, Elixir/OTP, package/native hashes,
test results and unrun gates for each release. Public availability and a passing
local install do not establish every OS version's compatibility. No target is
currently release-supported and no implementation stage is complete.
