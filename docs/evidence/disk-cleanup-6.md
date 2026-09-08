# Pre-draft disk cleanup, 2026-09-08

Removed 81 duplicate native binary files from older disposable `/private/tmp/aphid-*`
consumer workspaces, totaling 4,464,859,696 logical bytes. Free space increased
from 5.4 GiB to 9.6 GiB. Each removed file was hashed and matched an exact member
of the retained macOS archive before deletion. Paths, hashes and recovery members
are in [disk-cleanup-6.json](disk-cleanup-6.json). These older workspaces now need
those members restored before reuse; their remaining files were retained.

Retained archive: `artifacts/runtime-validation-aarch64-macos-13.3-baseline-3.tar.gz`,
SHA256 `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
Its complete archive hash was checked before deletion. All thirteen files in the
approved release asset manifest also retained their exact sizes and SHA256 values.

Failed-attempt workspaces/archives, Mix release workspaces, the latest qualified
`/private/tmp/aphid-notices-combined-consumer-2`, repository artifacts, and sibling
projects were preserved. No native rebuild or qualification rerun was needed.
