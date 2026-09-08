# Linux isolation locale preflight

[Preflight run 34188650346](https://github.com/catethos/Aphid/actions/runs/34188650346)
uses `d10c1a457bff6159ad0a8ed51e395eee8431d0e0`. Both native architectures pass
compiler masking, hidden development trees, privilege dropping and network
isolation. Both then fail the real Elixir check because
`:file.native_name_encoding()` returns `:latin1` after the environment is cleared.
Full logs are retained as `linux-x86_64-run-6.log` and `linux-aarch64-run-6.log`.
No engine is built and no artifact is uploaded in this preflight-only mode.

The sandbox now explicitly sets `LANG=C.UTF-8`. Its real UTF-8 assertion remains
before any engine build. Other environment variables still use the narrow
allowlist, so this does not restore credentials or build-library search paths.
The existing full run 34188260294 was cancelled because its later relocation
checks inherited the same incorrect locale. Its build inputs were not changed.
The next full run must pass the fast prerequisite and all distribution checks
before the approved seven-day artifact retention step can execute.

This is a test-environment correction, not native runtime qualification or a
minimum-system claim. The [Erlang filename documentation](https://www.erlang.org/doc/apps/kernel/file.html)
describes locale-dependent filename mode on Linux. GitHub release creation and
Hex publication remain excluded; no stage is marked complete.
