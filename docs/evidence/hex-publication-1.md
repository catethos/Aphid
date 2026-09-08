# Experimental Hex package ready; authentication pending

2026-09-08. Working directory: `/Users/catethos/workspace/ladybugex/zig_library`.
Starting signed source: `494310c891cba2873e3dd5b32f4e521874ba1acf`.
[Expanded authorization](hex-authorization-1.md) includes experimental Hex
publication after the local macOS check, with Linux package/additional-system
qualification deferred until after publication. This supersedes earlier Hex
exclusions and the prepublication three-target sequence.

## Exact candidate and preparation

Package: `artifacts/hex-publication-1/aphid-0.1.0-dev.tar`, **115,712 bytes**.
SHA256: `922fdacc2be68fc94f646f6fa281ed10fbf200ca9805b8e34eb169810514ebd7`.
It contains 54 files: Aphid source, installer, pinned catalogs/native inputs,
notices and documentation; no native/BEAM binaries, ERTS, dependency distributions,
development cache or upstream engine tree is bundled. Executable Elixir/Mix
adapter files and native inputs remain unchanged from the starting source.

The only native catalog change is addition of the three already reviewed public
URLs. All binary hashes, native source identities, lock entries, fixed tag and
thirteen GitHub release assets remain unchanged. The source supplement preserves
all previous bytes and appends the exact Zig 0.16.0 MIT notice. It is now 23,288
bytes, SHA256 `a9380f27e98b9ee7180560a31c99994cdfcbb2b8efae4b526e5225b14c56e992`.
The notice generator's pinned-source reproduction passes. Its matching review
text is retained at `docs/releases/v0.1.0-dev-zig-NOTICE.txt`.

README and packaged documentation describe default installation, exact runtime
requirements, experimental scope and superseded historical checkpoints. The URL
selection test now creates disabled catalogs only as fixtures. The existing
lost-selection rejection likewise uses an isolated disabled catalog, preserving
that check without attempting a network download or changing the real catalogs.

[Inspection](hex-package-inspection-1.json) records every member's hash and
metadata. [Build](hex-package-build-1.log) passes. A frozen extracted publication
copy at `/private/tmp/aphid-hex-publish-1` rebuilds byte-identically; see
[snapshot build](hex-package-snapshot-build-1.log). Publish from that copy to
avoid packaging later status/evidence changes. Package-only publication is
selected; this project has no configured HexDocs generator.

## Verification

[Fresh macOS output](hex-package-macos-1.log) and
[inputs](hex-package-macos-inputs-1.json): **92 tests passed**, seed 0,
16.0-second suite (16.699-second runtime command), macOS ARM64 26.6,
Elixir 1.20.0 / OTP 29.0.4 / ERTS 17.0.4. Fresh dependency/build caches and normal
locked Hex dependency acquisition were used. Default installation had no APHID
input overrides and downloaded from the actual public URL. Native compilers and
development-tree reads were denied; runtime networking was denied. All installed
native hashes and license hashes, including the new supplement, match.
No native compiler invocation occurred.

[Installer rejections](hex-package-failures-1.log) pass: the existing 23 selection,
archive and integrity cases, four notice fixtures, installed notice mutation and
receipt checks, and isolated missing/corrupt/unloadable loader probes. Expected
loader errors and the live-upgrade rejection appear in passing logs; they are
intentional negative tests. Fixtures restore the original installed hashes.
[Final checks](hex-package-final-checks-1.json) reverify all native/notice bytes
and unchanged final package inputs after those checks.

[URL fixtures](hex-default-checks-1.log) and
[notice reproduction](hex-notice-check-1.log) pass; changed Python helpers parse,
and source/documentation whitespace checks pass. Raw Hex output logs retain
the tool’s trailing spaces on its `Links:` lines; they are preserved verbatim. No Linux workflow or native rebuild was run.

Exact commands:

```sh
mix hex.build --output artifacts/hex-publication-1/aphid-0.1.0-dev.tar
python3 scripts/supplemental_notices.py --archive artifacts/notice-review-8.tar.gz --output THIRD_PARTY_NOTICES.txt --check
python3 scripts/package_default_checks.py
python3 -u scripts/precompiled_consumer.py --archive artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz --sha256 3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034 --package artifacts/hex-publication-1/aphid-0.1.0-dev.tar --package-sha256 922fdacc2be68fc94f646f6fa281ed10fbf200ca9805b8e34eb169810514ebd7 --destination /private/tmp/aphid-hex-macos-1 --hex-dependencies --package-default
python3 -u scripts/local_bundle_failures.py --destination /private/tmp/aphid-hex-failures-1 --consumer /private/tmp/aphid-hex-macos-1
```

All build, consumer, notice, fixture and rejection commands exited 0. The
consumer/rejection helpers use external process-group watchdogs. Broader runtime,
source-installation and support gates are not closed by these results.

## Publication blocker and next action

Hex is **not published**. The initial [anonymous name lookup](hex-package-before-1.json)
returned 404, so no existing Aphid package was found at that time. However,
`mix hex.user whoami` found no authenticated user. The package-only
[dry run](hex-package-dry-run-1.log) built the expected package, then exited 1 at
the authentication step. This is an account-access blocker, not missing user
publication approval. The user was asked to run `mix hex.user auth` privately in
their terminal; passwords/codes must not be placed in conversation or evidence.
Other exploratory tooling failures are retained in
[attempt notes](hex-preparation-attempts-1.log).

After authentication, confirm the intended publishing account and that no
conflicting `aphid`/`0.1.0-dev` appeared. From `/private/tmp/aphid-hex-publish-1`,
repeat `mix hex.publish package --dry-run --yes`, verify its checksum equals the
candidate above, then run `mix hex.publish package --yes`. Do not use `--replace`
or change the version/tag without a new decision. Record the API response and
an anonymous `https://repo.hex.pm/tarballs/aphid-0.1.0-dev.tar` download hash;
verify exact identity and perform a fresh registry installation. An uncertain
publication result must be reconciled by read-only registry lookup before retry.

Then qualify installation **from Hex** on native Linux x86_64/ARM64 and other
Linux systems as available. Existing local-path/source-package qualification
workflows alone do not establish registry installation. Report the actual
systems and exact published package hash. No target is release-supported and
no implementation stage is complete. Remaining minimum-system/CPU/OTP, source
build, cross-compilation, provenance, hardening and performance gates persist.
