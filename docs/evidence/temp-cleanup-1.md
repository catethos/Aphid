# Authorized Aphid temporary-file cleanup

2026-09-08. The owner asked to delete Aphid temporary entries to free disk space.
Work was restricted to the 130 inventoried `/private/tmp/aphid*` entries. Sibling
projects, the repository's existing artifacts, published packages and GitHub
assets were not removed or modified.

All 60,418 members were preserved in a local recovery archive before deletion:
`artifacts/temp-cleanup-1.tar.gz`, 2,987,631,108 bytes, SHA256
`6b726c24535577c58d39b9b7a2bcfdf6bc8426907bd1c1694c61c86ecb1905bb`.
Full member metadata and file SHA256 values are retained in
`artifacts/temp-cleanup-1.manifest.json`; the archival script is retained in
`artifacts/temp-cleanup-1.py`. These are local recovery artifacts, not uploads.
The archive preserves old failure workspaces and attribution inputs as well as
successful consumer copies; no unique content was discarded merely because its
path was temporary.

Each archive file was independently read and compared to its original SHA256;
symlink targets and directory/member types were checked without following links.
The member set matched exactly. Immediately before deletion, every original
entry's inode, mode, size and modification time was rechecked for changes.
No mismatch occurred. The [verification log](temp-cleanup-1.log) and
[cleanup result](temp-cleanup-1.json) preserve the entry list, archive identity,
removal outcome and filesystem-space measurements.

Initial sandboxed process inspection was denied. An elevated read-only process
and open-file check found no Aphid runtime; only a zsh current directory at
`/private/tmp/aphid-hex-publish-1` was observed. A subsequent open-file check was
empty before deletion. As announced, the publication directory itself was left
empty. The other 129 entries were removed; all contents of the publication
directory were removed too. There were no deletion failures.

Filesystem available space increased from 10,281,091,072 bytes (9.57 GiB) to
13,458,001,920 bytes (12.53 GiB): **3,176,910,848 bytes / 2.96 GiB net recovered**,
after retaining the 2.78 GiB compressed backup. Disk usage figures include the
filesystem's concurrent activity; the earlier 5.8 GiB entry total was allocated
space reported by du, not a promise of identical net reclamation.

Old temporary consumer and publication paths are no longer usable as prepared
workspaces. The published Hex tar, independent native archives, source commits,
logs and hash records remain available in the repository/artifacts. Recreate
fresh consumer directories for future tests. Recovery, if needed, should extract
the verified backup into a new directory, not overwrite active temporary paths.
No Hex republishing, native build, support claim or implementation-stage change
was involved.
