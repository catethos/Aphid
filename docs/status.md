# Implementation status

Release `0.1.2-dev` qualification (2026-09-09): ALGO is bundled with
FTS/vector/DuckDB on macOS ARM64 and Linux x86_64/ARM64; icebug-backed `GDS_*`
functions are disabled. All 101 tests pass in source, relocated-bundle, and
fresh-consumer checks on each target. The macOS bundled-ERTS release also
passes its startup/shutdown/persistence and failure checks. Combined-package
qualification and publication are tracked in [release evidence](evidence/release-012.md).
ALGO sanitizer and minimum-system qualification remain open.

Published: [aphid 0.1.1-dev on Hex](https://hex.pm/packages/aphid/0.1.1-dev) and
[GitHub](https://github.com/catethos/Aphid/releases/tag/v0.1.1-dev), with rebuilt
native bundles containing the five hardening fixes. The public Hex archive
matches the exact package qualified on all three targets. Fresh Hex registry
installations pass 99 tests each on macOS ARM64 and Linux x86_64/ARM64. See
[release evidence](evidence/release-011.md) for publication and installation checks.
This remains an experimental prerelease; earlier publication checkpoints below
are historical.

Local source hardening checkpoint (2026-09-08): **99 public tests pass** on
macOS ARM64 against normal and fatal ASan/UBSan builds. Five demonstrated native
defects are patched and pinned, with new combined mutation/cancellation/shutdown
coverage. See [hardening evidence](evidence/hardening-2026-09-08.md).
The source lock has advanced. [0.1.1-dev release qualification](evidence/release-011.md)
tracks the rebuilt native bundles; the older `0.1.0-dev` assets do not contain
these fixes and remain unchanged. TSan mutation/GC coverage, Linux
sanitizers, Zig allocation instrumentation and release support remain open.

Temporary cleanup: [130 Aphid temporary entries cleared](evidence/temp-cleanup-1.md),
with a verified local recovery archive retained; 2.96 GiB net space recovered.
Use fresh directories for subsequent registry tests.

Previous release outcome (2026-09-08): [aphid 0.1.0-dev is published on Hex](https://hex.pm/packages/aphid/0.1.0-dev).
The public Hex archive matches the exact reviewed SHA256
`922fdacc2be68fc94f646f6fa281ed10fbf200ca9805b8e34eb169810514ebd7`.
See [publication and registry-installation evidence](evidence/hex-published-1.md).
The GitHub prerelease, thirteen assets and fixed tag remain unchanged.
Linux registry installation and additional-system tests follow publication under
the owner's expanded scope. No target is release-supported and no implementation
stage is complete. Earlier authorization and preparation checkpoints below are historical.

Current scope (2026-09-08): experimental Hex publication is now authorized.
The user accepts publication after a final local macOS package check, with Linux
package installation and additional-system tests following publication.
The three public catalog URLs are enabled in this source revision, and the
source supplement now includes the retained Zig MIT notice. See
[Hex publication scope](hex-publication.md). The GitHub prerelease is already
public; its thirteen assets and fixed tag remain unchanged. No target is
release-supported and no implementation stage is complete.

Earlier checkpoints below are historical and do not override this scope.

Latest scope: [authorized experimental publication](evidence/public-release-1.md).
Release [v0.1.0-dev](https://github.com/catethos/Aphid/releases/tag/v0.1.0-dev)
(ID 384589981) is public with `draft=false`, `prerelease=true`, and is not latest
stable. All thirteen unchanged assets passed anonymous public streaming SHA256
and size verification. The exact reviewed body supplies the Zig MIT notice and
retains the supplemental-notice instructions. Signed tag and native bytes are unchanged.

Current handoff: prepare the final source package with the Zig notice and reviewed
public catalog URLs, then qualify that exact package on native Linux x86_64/ARM64
and macOS ARM64 against the public endpoints. Catalog URLs remain disabled in
this publication-only checkpoint. Public download verification does not establish
package-default installation or release support. No target is release-supported;
no implementation stage is complete. Hex publication remains excluded.

Earlier checkpoints below are historical; their publication holds and proposed
next actions do not supersede the current publication evidence and handoff.

Previous scope: [small review of the thirteen draft assets](evidence/small-release-review-1.md).
The parser packages are not bundled; their missing full notices are not a
demonstrated blocker for this native draft. One concrete notice fix is prepared
in the proposed public body: include Zig’s existing MIT notice for macOS users.
The broader hold below is superseded for this narrow experimental-release review.
No publication is authorized or performed; the fixed tag/assets remain unchanged.

Current review: [public publication decision](releases/v0.1.0-dev-publication-review.md)
and [preparation evidence](evidence/publication-preparation-1.md). Publication is
on hold for attribution review; existing draft 384589981 remains private. A manual
package-default endpoint workflow is prepared and locally checked, not executed.
URLs remain disabled; public publication and Hex remain unauthorized.

Current continuation: [authorized private draft](evidence/draft-release-1.md).
Signed `v0.1.0-dev` remains fixed at `750dc79ec3607893fe53ba84c2cfe45158c49bc3`.
The private draft exists; public publication and Hex remain unauthorized.
Default URLs remain disabled. All attribution, support and plan gates remain open.

Previous continuation: [installed notices and draft proposal](evidence/shipped-notices-1.md).
Known supplemental notices now ship into installed priv and Linux Mix releases.
One exact updated source archive passes 92 tests on all three targets. The
thirteen-asset private-draft proposal is locally verified and awaits separate
explicit authorization. Defaults/public delivery, final attribution and all
previously open support/plan gates remain open. Earlier checkpoints below are
historical and do not supersede this handoff.

Current handoff: [default delivery and shipped-content review](evidence/release-preparation-1.md).
Default selection is prepared but disabled until authorized delivery; the native
bytes are unchanged. Refreshed consumer-to-release verification passes locally.
Notice delivery and macOS/public endpoint scope remain before draft authorization.
Older checkpoints below remain historical, not current gate closures.

Updated 2026-09-08. Library name: **Aphid**. Folder: `zig_library/`.

| Stage | Status | Evidence / next gate |
|---|---|---|
| 00 | Toolchain gate passed | [Evidence](evidence/stage-00.md); compiler-free fresh package install remains a distribution gate |
| 01 | Host gate passed; Linux pending | [Evidence](evidence/stage-01.md); packaged offline C++/BEAM feature proofs passed |
| 02 | Initial lifecycle gate passed | [Evidence](evidence/stage-02.md); 9 BEAM tests and native fault checks pass |
| 03 | Host query/value gate passed | [Evidence](evidence/stage-03.md); 43 BEAM tests plus native checks, including typed/null/empty metadata and required extensions |
| 04 | Host admission/transaction gate passed | [Evidence](evidence/stage-04.md); 57 BEAM tests plus native checks, including persisted transaction recovery |
| 05 | Core deadlines and repeated cancellation races pass | [Evidence](evidence/stage-05.md); queued public-write caller death now checked; actual commit-uncertainty and long FTS/vector/DuckDB workflows retained; broader boundary gates remain |
| 06 | Host stream/memory gate passed | [Evidence](evidence/stage-06.md); 76 BEAM tests plus eight isolated BEAM/RSS cases |
| 07 | In progress; ASan/UBSan and focused host TSan checks passed | [Evidence](evidence/stage-07.md); isolated TSan rebuild now finished, fresh lifecycle and concurrent FTS/vector/DuckDB reads pass; [limits](evidence/tsan.md): test-only 1 GiB range, broader mutation/GC races and Linux remain |
| 08 | In progress; local macOS runtime bundle validated | [Evidence](evidence/stage-08.md); packaged native lifecycle/concurrent-extension reads and 92 BEAM tests pass offline after relocation; explicit-target candidate declares 13.3 and fresh local Mix consumer passes; local checksum/sidecar adapter now passes fresh-consumer/failure checks; embedded relocated Mix release now passes; minimum execution, network delivery and required matrix remain |
| 09 | In progress; examples and six host baseline comparisons recorded | [Evidence](evidence/stage-09.md); latency distributions, service-time throughput and memory retained; ~6 ms small-query Aphid median needs investigation; broader benchmarks and local release candidate remain; [release checklist](release-checklist.md) |

| Required target | State |
|---|---|
| Linux x86_64 glibc | Native GitHub runner: locked native/NIF build and 92 BEAM tests pass; reviewed bundle, relocated suites, compiler-free consumer and failures pass |
| Linux ARM64 glibc | Native GitHub runner: locked native/NIF build and 92 BEAM tests pass; reviewed bundle, relocated suites, compiler-free consumer and failures pass; cross-build unproved |
| macOS ARM64 | Host runtime passed: explicit-target bundle and fresh local Mix consumer pass 92 tests on 26.6; local bundle adapter passes; Mix release passes embedded startup and restart; minimum OS/CPU and network delivery remain |

No target is release-supported. The isolated candidate NIF load commands now declare
macOS 13.3 (normal development NIFs remain 26.6); 13.3 is not a tested whole-bundle minimum. Stage 00's small resource destructor performs
one atomic decrement; it does not prove heavy database retirement.

## Historical handoff from earlier continuation

[Combined package qualification](evidence/combined-installation-2.md) is the current handoff;
[source inputs/private routing](evidence/source-inputs.md) remains valid for the prior package;
[source preflight](evidence/source-preflight.md) remains valid for the older package;
[attribution follow-up](evidence/attribution-followup.md) remains valid;
[native notice mapping](evidence/native-notice-map.md) remains valid;
[notice-source evidence](evidence/notice-sources.md) remains valid;
[local package evidence](evidence/local-package.md) remains valid;
[embedded startup evidence](evidence/embedded-startup.md) remains valid;
[the earlier interactive proof](evidence/mix-release.md) remains historical evidence.
The fresh adapter consumer and relocated bundled-ERTS release each pass 92 tests.
Default embedded startup, application restart without NIF reload, graceful shutdown,
and persistent reopen pass with network/compiler/development/host-runtime reads denied.
Early embedded on_load leaves managed stubs until crypto is ready; application
startup then verifies the complete native closure before loading either NIF.
Real embedded missing/corrupt/unloadable startup failures pass. No checksum bypass.

Validation archive: `mix-release-embedded-aarch64-macos-1.tar.gz`, SHA256
`2ee9d858ec12ab848f083ceb4b1b57d2acf289a40bc94690eaac3991e21a9008`.
The native input archive remains `runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz`,
SHA256 `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
Normal engine/bridge, dependency sources and DuckDB 1.4.4 lock remain unchanged.
Bundled ERTS/crypto declare macOS 15.0; Aphid native files declare 13.3.
Neither declaration proves actual minimum OS/CPU compatibility; execution is macOS 26.6 only.

The local MIT-licensed Hex archive `aphid-0.1.0-dev-local-2.tar` now builds and
installs into a fresh compiler-free consumer, passing all 92 tests. SHA256:
`921d21ece8c5a96bb3cdc5ab60b6932e73dd4471b2f9382d446d9f182bd8d7e3`.
Supplementary notices and the native component map are retained in
`notice-review-8.tar.gz`, SHA256
`56647f85783f8d15301176b53f860baaabdc04b73ea694bcc161415a99293471`.
The follow-up preserves NimbleParsec's README notice, the content-matched ZigGet
parent license, 22 blob-verified OTP notice texts and the version-matched OTP
OpenSSL 3.5.7 license. All Pegasus/ZigParser package files match recorded upstream
commits, but those commits still lack full license texts. 303 installed OTP source
files match the pinned upstream tree; six remain outside that comparison.

The retained native link/header records now map 57 component groups to candidate
notices and preserve seven embedded notice preambles missed by named-file discovery.
All 13 file-backed normal/packaged engine sections match. This is not a final
linker map or a proof of historical header contents/object retention.

Httplib's full upstream 0.14.2 notice is now verified and mapped to the existing
retained text. Its modified Ladybug header matches the pinned engine commit;
source differences are retained. Pegasus/ZigParser's fetched non-shallow histories
do not resolve their pinned-version attribution; authoritative notices remain open.

The new `aphid-0.1.0-dev-source-inputs-1.tar` includes the previously missing build
inputs and all eleven checked patches. SHA256:
`f216f32977d5339a0bdd0a242754498458684c3e7245ee8044f855a76a48d90e`.
Structural preflight passes and a fresh precompiled consumer passes 92 tests.
Private source/output ownership and command routing are checked; the Native module
accepts an absolute APHID_NATIVE_BUILD_ROOT. No source engine/NIF compilation was
performed, and Mix does not automatically orchestrate the source build.

Next prove locked acquisition/patch validation in a private tree, then measure a
fresh source build with a linker map and full consumer/closure tests. Retain unresolved attribution and
OTP/static-component provenance gates; prove a fresh source consumer when
resources permit. Keep network/Hex
delivery, minimum-system/other-OTP execution and both Linux targets open. No Linux
runner is available; do not provision/emulate one. Retain mutation/cancellation/GC
sanitizer gates and TSan's test-only 1 GiB limit; performance is separate.
Root `library/`, `source/`, and `hex_consumer/` were preserved. No native rebuild,
sanitizer rerun, publication/upload, or stage/implementation completion occurred.

The requested Hex/GitHub release preparation now has a manual Linux source
qualification workflow for native x86_64 and ARM64. It has been linted and its
routing checked locally, but no Linux job has run. The public repository is `catethos/Aphid`, with `zig_library` as its root;
the initial source is pushed and Linux qualification run 34181241317 is in progress; release creation and compiler-free Linux installation remain open.
See [GitHub preparation](github-release.md). No stage or target is closed.

Source commit `253dff3` is now pushed with explicit approval. Its HTTPS adapter
passes real loopback TLS delivery, installer failures and 92 fresh-consumer tests.
A subsequent local Hex archive passes ordinary Hex dependency acquisition with
a reviewed lockfile (13 checksum-matching downloads), followed by compiler-denied,
development-read-denied compilation and 92 tests. See
[normal dependency evidence](evidence/normal-hex-consumer.md). Aphid/native binary
publication, actual GitHub delivery and default precompiled selection remain open.

Current Linux checkpoint: both jobs in run 34181241317 passed locked native builds
and feature checks, then failed on the same staging-directory harness error.
Fix `3edd9ba` is pushed; run 34184718955 retries both targets with an early
toolchain preflight. See [retained first-run evidence](evidence/linux-first-run.md).
Source changes and CI iterations are approved; binary uploads, GitHub releases
and Hex publication remain excluded. Earlier no-runner statements above describe
historical checkpoints, not current runner availability.

Run 34184718955 now passes native and all 92 BEAM tests on both Linux
architectures. ELF audits show GLIBC 2.38 and GLIBCXX 3.4.32 requirements;
execution was Ubuntu 24.04 / glibc 2.39, not an older-system proof. The draft
packager omitted the standard glibc loader; runs 34185853596 and 34187051003
were cancelled after this was detected. Their logs are retained. See the
[loader correction](evidence/linux-loader-allowlist-fix.md). Passing CI artifact
retention for seven days is explicitly approved; GitHub releases and Hex
publication remain excluded. No Linux catalog identity is promoted yet.

Linux full run 34188940428 passed both native/NIF builds and 92 BEAM suites.
ARM64 also passed relocated native/92 BEAM tests before consumer integrity
rejected objcopy-modified NIF bytes; x86_64 stopped at ELF packaging. Neither
job uploaded artifacts. [ELF correction and handoff](evidence/linux-elf-relocation.md)
records the real failures and small-NIF prerequisite checks.

[Reviewed Linux bundles](evidence/linux-qualified-bundles.md) now pass both full
qualification jobs in run 34193449987. Seven-day Actions retention is approved
and succeeded. Exact downloads, manifests, native hashes and source-package
checksums were independently checked; the Linux catalog is pinned. A combined
source-package consumer check follows without rebuilding the qualified engine.
GitHub release creation and Hex publication remain excluded; no stage is closed.

[Combined package and embedded release evidence](evidence/combined-installation-2.md)
now records one exact source archive passing all 92 tests on macOS ARM64 and
both Linux architectures, plus Linux bundled-ERTS startup/restart/reopen and
failure checks. Public delivery, final notices and minimum-system gates remain
open; no stage is marked complete.
