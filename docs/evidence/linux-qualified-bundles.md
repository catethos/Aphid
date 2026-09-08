# Reviewed Linux validation bundles

[Qualification run 34193449987](https://github.com/catethos/Aphid/actions/runs/34193449987)
passed both native architectures at source
`c37c458211d0bff7e4054f90bf5d429f29ece2ef`, attempt 1. Execution was on native
Ubuntu 24.04 runners with glibc 2.39, Elixir 1.20.0, OTP 29.0.4 / ERTS 17.0.4,
NIF API 2.18, Zig/Zigler 0.16.0 and GNU binutils 2.42-4ubuntu2.10.
These are validation bundles; no target is release-supported or stage complete.

| Target | Runtime archive | SHA256 | Bytes |
|---|---|---|---:|
| x86_64 glibc | `aphid-0.1.0-dev-x86_64-linux-gnu.tar.gz` | `fa9535c7e8f3b149658ed0f5f98329f7142cfd21f30f20fef765c74c42b798cc` | 49,965,445 |
| ARM64 glibc | `aphid-0.1.0-dev-aarch64-linux-gnu.tar.gz` | `235ceb0490a1baf64e33fd53f17f683ce263197cf0cac6cf1107275dd94b62af` | 46,275,962 |

Each job passed the locked native build, native lifecycle/concurrent extensions
and feature create/reopen checks, then three 92-test BEAM runs: source candidate,
relocated archive, and fresh Mix consumer. The fresh consumer used an isolated
local Hex source package and 13 normally acquired, checksum-verified Hex
dependencies. Application/dependency caches started empty; development/build
trees were hidden, native compilers masked, and compilation/runtime had no
external networking. Native hashes stayed unchanged. The real Mix adapter passed
23 rejection cases; both NIF loaders rejected missing/corrupt engines and a
byte-unchanged noexec mount. This is not registry installation or a Linux Mix release.

The two job-local Hex source package hashes were respectively
`f70fcdf0894eda5211521e0765d8bc9e2cd0f57f9d0330e3c9f37823a729b7d8` and
`5c17089fdcec618061bc0e1401534706c5d14c19819b65e477fc53b4d40f5a8c`.
They contain target-specific validation catalogs. A separate [combined source archive](combined-installation-2.md) now passes
on all three targets; the two older target-specific archives remain distinct.

The owner-approved Actions uploads contain seven allowlisted files per target.
Their outer artifact IDs/digests and expiry times are in `linux-artifacts-11.json`;
expiry is 2026-09-15 around 07:03 UTC. These outer digests differ from the native
archive SHA256 values above. Exact local downloads are retained under
`artifacts/linux-validation-11/`; no native binary is committed to Git.

Independent local review matched the archive identity to the CI log, verified
the archive checksum, all 135 regular members, complete content manifests,
four native library hashes/ELF architectures, the ELF audit and the retained
source package checksum. Each archive contains 73 license files; that count is
not final attribution clearance. `linux-bundle-review-11.json` retains native
identities and ELF requirements; `linux-bundle-review-11.log` records successful
release-asset staging against the actual downloads. `native/linux-bundles.json`
now pins these reviewed identities and qualification provenance.

The engine requires GLIBC 2.38 and GLIBCXX 3.4.32. Older-system execution and the
whole CPU floor are unproved; requested baseline flags do not close them.
Native ARM64 builds do not satisfy the x86_64-to-ARM64 cross-build gate. Minimum
systems, other OTP versions, public release HTTPS/default selection, ordinary Hex
registry delivery, source installation, final notices and
remaining behavioural/instrumentation gates remain open. GitHub release creation
and Hex publication are still excluded from the current approval.

The manual draft workflow is prepared and its offline verifier passes the actual
qualified assets; it has not been executed. The [combined consumer run](combined-installation-2.md)
reused these exact native archives and passed fresh consumers, failures and
Linux Mix releases without another engine build. Only the passing source package,
inputs and log were retained by that run.
The original macOS candidate and DuckDB 1.4.4 lock remain unchanged.
