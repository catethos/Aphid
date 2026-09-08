# Public publication review and default-consumer preparation

2026-09-08. Starting source `71f912156fd8b3cd4a24ec9286c98d58d9c46aea`;
working directory `/Users/catethos/workspace/ladybugex/zig_library`.
The tree was clean at entry. No target is release-supported and no stage or
implementation is complete. This continuation prepares a review and validation
path; it does not establish public installation or attribution clearance.

## Outcome

The [publication decision](../releases/v0.1.0-dev-publication-review.md) names the
existing release ID `384589981`, fixed signed tag, thirteen-asset matrix, proposed
public-body file, specific attribution closure requirements and post-authorization
commands. Recommendation is to hold publication while attribution is unresolved.
The proposed body is local only. No release mutation, maintainer message, tag
change, native rebuild, Hex publication or workflow dispatch occurred.

A fresh authenticated release-ID read confirms the private draft state and all
thirteen approved asset names, sizes and server digests. Previous authenticated
streaming download evidence is reused; native archives were not downloaded again.
The first read-only network attempt failed in the outer sandbox; its empty output
and [failure log](publication-draft-state-failure-1.log) remain. The read-only retry
with outer execution permission succeeded in [state 2](publication-draft-state-2.json).
This is distinct from the earlier release-by-tag 404, which remains preserved.

[Content review 2](publication-content-review-2.json) independently rehashes all
thirteen retained assets, both named source packages, the unchanged native lock,
and the qualified source's installed supplement input. It records 73 license
members per Linux archive and 67 for macOS. Attempt 1 incorrectly searched for
installed `/priv/licenses/` paths inside the archives, whose member prefix is
`licenses/`; its zero counts are invalid and superseded by attempt 2. Both reports
are retained. The correction did not alter any asset or notice.

The existing source-matched attribution inventories were read, not regenerated.
Missing authoritative Pegasus 0.2.6/ZigParser 0.7.0 notices, NimbleParsec coverage,
linked/generated/modified-fork attribution, native static/build provenance and
production ERTS coverage remain open. Runtime notices are scoped separately:
ERTS is not a draft asset. No exhausted source-history search was repeated and
no grant was inferred from a different version or project.

## Minimal validation changes

- `scripts/precompiled_consumer.py` adds `--package-default`. It requires an
  independently pinned source package and normal locked Hex acquisition. The
  native archive is an independent content/test oracle; no archive, URL, SHA or
  source-mode override is supplied to the real Mix installer. The helper requires
  the package's exact version/archive repository URL and clears all inherited
  APHID variables plus GitHub token variables. It never enables a URL.
- Public-default compilation uses the existing acquisition sandbox with external
  networking, preserving compiler masks and denied development reads. Runtime
  uses the existing offline sandbox and checks all 92 tests/native/license hashes.
  This describes prepared behavior, not a new test pass. Existing local/loopback
  compile behavior remains selected when the new option is absent.
- `scripts/linux_sandbox.py` changes only the network evidence label to include
  installation; its permissions/masking logic is unchanged.
- `.github/workflows/public-consumer.yml` is manual and read-only. It downloads
  one SHA256-pinned source from a successful manual `linux-consumer.yml` main run
  and uses the same bytes on both native Ubuntu architectures. The independent
  native oracle download and real default installation are unauthenticated.
  It has no release writes, uploads, catalog mutation or native builds.
- `scripts/package_default_checks.py` checks three fixture-enabled targets,
  disabled catalogs, wrong URLs/pins, duplicate pins, inherited override/token
  clearing and required-argument rejection before workspace creation. Fixtures
  do not mutate repository catalogs and do not load native code.

The actual source/native catalogs, installer, shipped notice bytes and native
lock are unchanged. The old qualified source package remains immutable and does
not retroactively include this continuation. New public/default source evidence
is required after actual publication and catalog activation.

## Checks and retained identities

Commands executed from the working directory above:

```sh
python3 scripts/package_default_checks.py
/private/tmp/aphid-actionlint-1/actionlint .github/workflows/public-consumer.yml
python3 scripts/supplemental_notices.py --archive artifacts/notice-review-8.tar.gz --output THIRD_PARTY_NOTICES.txt --check
git diff --check
```

All exit 0. Logs: [selection](public-consumer-selection-1.log),
[workflow lint](public-consumer-workflow-lint-1.log),
[notice reproduction](publication-notices-check-1.log). Python AST parsing passes
for the three touched/new Python files. The notice check reproduces all ten
retained texts, 21,862 bytes, SHA256
`08cc1d20ccb4808537545220152d6aff97701e2c3b0b8597ab2dadaa82a789d1`.
The inline streaming-hash inventory check and release metadata assertions passed;
exact per-asset hashes and sizes are in content review 2 and the unchanged matrix.
Workflow lint and fixture checks do not qualify native targets or public URLs.
No unchanged passing runtime/sanitizer suite was rerun.

| Retained artifact | SHA256 |
|---|---|
| `artifacts/notices-source-linux-2/aphid-current-consumer/aphid-0.1.0-dev-combined.tar` | `11ca5ca447a7a93ee6d8e2d79758f3ed67d9ce04d20947a08e82598851152507` |
| `artifacts/aphid-0.1.0-dev-combined-linux-2.tar` | `b85967b047662ccdc66851d246a9a7301fe8c797225d7e479948653838dc57df` |
| `artifacts/linux-release-review-15/aphid-0.1.0-dev-x86_64-linux-gnu.tar.gz` | `fa9535c7e8f3b149658ed0f5f98329f7142cfd21f30f20fef765c74c42b798cc` |
| `artifacts/linux-release-review-15/aphid-0.1.0-dev-aarch64-linux-gnu.tar.gz` | `235ceb0490a1baf64e33fd53f17f683ce263197cf0cac6cf1107275dd94b62af` |
| `artifacts/macos-release-review-1/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz` | `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034` |

The fixed tag still resolves to `750dc79ec3607893fe53ba84c2cfe45158c49bc3`.
Native lock SHA256 remains
`d6c2db650b15ccb9ab77df54fcd9ad96dfc05da24b0104660c06caf9b575f955`;
DuckDB stays 1.4.4. No cleanup was performed. Sibling projects and retained
failures/recovery manifests remain intact; old cleaned consumers need restoration
before reuse. Passing Actions copies expire around September 15.

## Next action and limits

Obtain authoritative version-specific Pegasus/ZigParser notice evidence for
review (no maintainer contact is authorized), and finish the component/notice
mapping decisions listed in the publication review. Revise the proposed body
when those findings change, then request separate explicit authorization for
publishing this exact existing prerelease and the exact body. Do not request
approval as a substitute for the unresolved review or silently waive its gaps.

After separately authorized public delivery exists, verify anonymous asset
hashes, enable only the reviewed catalog URLs, qualify one final source archive
through the existing local-archive Linux consumer workflow, then run the new
public-default workflow and the same exact package on native macOS. No endpoint
proof or new CI pass is claimed now. No new macOS bundled-ERTS proof was run.

Ubuntu 24.04/glibc 2.39 and macOS 26.6 remain the only proved execution systems.
GLIBC 2.38/GLIBCXX 3.4.32 and macOS 13.3 declarations are not minimum-system/CPU
proof. GNU objcopy and otool remain installer requirements. Other OTP/binutils,
x86_64-to-ARM64 cross-build, fresh source installation, production runtime/static
provenance, remaining Sections 8–9 and Stage 05/07/08/09 gates all remain open.
