# Linux distribution continuation — execution pending

The shared Mix adapter now has a fail-closed Linux identity catalog. The committed
catalog is empty: no Linux bundle is accepted by the production-facing package
until an identity is reviewed. macOS retains the original candidate and hashes.
No-input compilation now requests a pinned bundle or explicit source mode; it
cannot silently invoke a compiler. Selection checks and the fresh macOS consumer
pass; see `platform-consumer-2.log` (92 tests, unchanged native hashes).

The next Linux CI recipe packages the four native libraries and validation
executables from its private locked build, rewrites ELF loader paths with
`patchelf`, records ELF metadata and hashes, verifies notice hashes, and exercises
the extracted archive. It then creates a job-local Hex source archive containing
that build's independently recorded identity and proves a fresh Mix consumer.
Only the isolated validation package receives that identity; the repository's
catalog remains empty. The package and native archive stay inside the job.

Consumer isolation uses a private mount/network namespace, hides the checkout and
private build trees, masks compiler executables, and drops to the runner user
without capabilities. An early probe verifies those properties before the engine
build. This uses [bubblewrap's documented namespace and capability options](https://github.com/containers/bubblewrap/blob/v0.9.0/bwrap.xml),
with privilege dropping through the system `setpriv` utility. No host mount,
compiler installation or global toolchain setting is changed by these probes.
The additional apt tools belong to the disposable authorized CI runner.

The real installer rejection script also routes Linux ELF fixtures and performs
missing/corrupt loader tests. Its unloadable test creates a private noexec mount
of a copied, byte-unchanged native closure so integrity verification can pass
before the actual loader rejects executable mapping.

Local routing/header checks and workflow lint pass. They do not execute Linux.
No Linux archive identity or compiler-free success is claimed yet. Actual Linux
consumer/loader outcomes, minimum glibc/CPU execution, x86_64-to-ARM64 cross-build,
Mix releases, actual GitHub delivery, final notices and publication gates remain
open. Binary uploads, GitHub release creation and Hex publication are excluded.
