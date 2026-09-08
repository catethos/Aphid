# HTTPS adapter proof — 2026-09-08

`APHID_BUNDLE_URL` adds an explicit HTTPS source around the existing pinned local
bundle installer. `Mix.Utils.read_path/2` supplies standard TLS verification and
timeout handling; Aphid checks the independently supplied SHA256 and runs the
same complete archive/identity validation before installing the closure. No
custom downloader, cache, package manager or dependency-source changes were added.
URL/archive selection conflicts and download failures cannot start a source build.
[Actual Mix selection checks](https-selection-1.log) reject URL/archive conflicts,
source-plus-URL and invalid modes before either native module loads.
The existing default source-selection behavior is unchanged; default precompiled
Hex installation remains a separate open gate.

[scripts/https_bundle_checks.py](../../scripts/https_bundle_checks.py) runs a
loopback HTTPS server with a temporary local CA and a signed server certificate.
It exercises actual installer rejection of insecure/credential-bearing URLs,
invalid pins, HTTP 404 and corrupt content, then runs the fresh consumer harness
through the HTTPS option. The certificate/key files remain in `/tmp`; they are
not staged in Git or packaged. The server is stopped in `finally`.

[Attempt 1](https-bundle-1.log) failed because the original self-signed leaf was
rejected by TLS (`selfsigned_peer`). Its missing-file test initially saw a TLS
failure instead of HTTP 404. The corrected test uses a CA and signed leaf and
asserts the actual 404 reason. TLS verification was not weakened.

[Attempt 2](https-bundle-2.log) passes all five installer rejection cases and
all 92 core/FTS/vector/DuckDB tests in a fresh consumer. Native compiler execution
and development-project reads are denied; network access is loopback-only.
Application/dependency build caches start empty, Zig is absent and its cache
stays empty. The complete installed native closure keeps its original hashes.
This is real loopback TLS delivery, not a proof of GitHub CDN delivery or a
published Hex consumer. Dependency sources remain explicitly pinned and staged.

Exact unchanged native archive:
`runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz`, SHA256
`3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
DuckDB remains 1.4.4. No engine/NIF rebuild or native upload occurred.

Source commit `5d771bfb37df091c644ac18604d750135ee53e16` was pushed to the
user-confirmed public `catethos/Aphid` repository with explicit authorization.
[Linux run 34181241317](https://github.com/catethos/Aphid/actions/runs/34181241317)
is the first native Linux qualification attempt; it does not include this
later HTTPS change. Binary uploads, GitHub release creation and Hex publication
remain unauthorized. Linux bundles, audited platform floors/closure, cross-build,
ordinary/default delivery, source installs and final notice gates remain open.

The native GNU recipe now explicitly rejects musl hosts rather than labeling
them glibc. [Routing checks](linux-glibc-routing-1.log) cover both architectures;
these are captured-command checks, not Linux runtime evidence.
