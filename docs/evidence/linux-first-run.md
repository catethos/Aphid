# First real Linux qualification attempt

Run [34181241317](https://github.com/catethos/Aphid/actions/runs/34181241317)
uses source commit `5d771bfb37df091c644ac18604d750135ee53e16` on native GitHub
x86_64 and ARM64 runners. Source publication and these jobs were explicitly
approved; there are no binary-upload, GitHub-release or Hex-publication steps.

The [x86_64 log](linux-x86_64-run-1.log) records Ubuntu 24.04, glibc 2.39,
GCC 13.3.0, CMake 3.31.6, Zig 0.16.0, Elixir 1.20.0 and ERTS 17.0.4.
The runner has four exposed CPUs (AMD EPYC 9V74) and about 16.8 GB RAM.
Locked engine/DuckDB/extension acquisition and compilation pass. The engine step
reports 2467.230 seconds, including its configure/build/bridge work. This is not
an aggregate peak-memory measurement.

Native lifecycle, concurrent FTS/vector/DuckDB, feature creation and fresh-process
reopen checks exit successfully. BEAM qualification does not pass: Mix reaches
Aphid compilation and Zigler rejects the missing staging parent directory. The
optional formatter warning precedes the same fatal problem for Aphid.Native.
The full failed log is retained; no NIF/BEAM success is inferred from native tests.

The narrow harness fix creates the staging parent before compilation. The next
recipe also runs the existing small toolchain proof, with explicit target and
baseline CPU flags, before paying for the engine build. It uses a separate proof
source/staging tree and does not share extension archives. Binary checksums and
ELF header/dependency/version metadata will be printed for inspection once full
NIF compilation succeeds; no binary upload is added.

[Local orchestration checks](linux-staging-fix-2.log) require the staging directory
to exist before commands receive it. Both architecture routes and workflow lint
pass. These checks capture commands and do not substitute for rerunning Linux.
The [ARM64 log](linux-aarch64-run-1.log) confirms the same outcome: locked native build and lifecycle/concurrent-extension/create/reopen checks pass, then Mix fails on the missing staging parent. Neither architecture reached BEAM qualification.

Fix commit `3edd9ba99e3350b98bfa327c0c7f3f6b9b878842` is pushed under the user's approval for source changes and CI iterations.
[Run 34184718955](https://github.com/catethos/Aphid/actions/runs/34184718955)
retries both architectures with the small toolchain preflight first. CPU/glibc floors,
compiler-free Linux consumers, relocatable bundles, source installs, cross-build
and final notice/release gates remain open. No stage is marked complete.
