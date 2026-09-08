# Linux system-loader packaging correction

The passing x86_64 source build in run 34184718955 records direct dependencies
on `ld-linux-x86-64.so.2` in both NIFs and liblbug. See the
[raw log](linux-x86_64-run-2.log) and [parsed identity/ELF record](linux-x86_64-source-identity-2.json).
The draft packager omitted glibc's system loader from its allowlist and would
reject these valid inputs. It now accepts only the loader matching the target:
`ld-linux-x86-64.so.2` or `ld-linux-aarch64.so.1`. Other unknown dependencies still
fail packaging. No native source, lock, compiler flag or macOS artifact changed.

Distribution runs 34185853596 and 34187051003 were cancelled after discovering
this guaranteed packaging rejection, retaining their logs. Neither uploaded an
artifact. The native source-qualification run remains separate and unaffected.
A fresh distribution retry is necessary because earlier jobs did not retain a
complete qualified bundle. Passing CI artifact retention is now explicitly
approved for seven days; GitHub release creation and Hex publication remain
excluded. This correction is not proof of relocation or compiler-free Linux
installation; the retry must exercise those paths.
