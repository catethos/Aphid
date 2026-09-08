# Platform adapter local Hex package

`aphid-0.1.0-dev-platform-1.tar` is a locally built, unpublished Hex source archive.
SHA256: `cdea357299b6e92d27e3132772dd246e604ef01ff563d3d25b9f4f60de9e2b23`.
The [identity record](platform-package-1.json) records size and native input.
[Build log](platform-package-build-1.log); [fresh consumer log](platform-hex-consumer-1.log).

The source package includes the fail-closed empty Linux catalog and explicit
source/precompiled selection. Its macOS path reuses the exact original runtime
archive, SHA256 `3125907a738162c55ba8f68874c861c767bc7a5f17e9b23c69f028df192e3034`.
A fresh consumer downloaded normal Hex dependencies against the reviewed lock
(13 archive hashes checked), then compiled and passed 92 tests with native
compiler execution and development reads denied. Compilation/runtime allow only
loopback networking. The installed four native hashes are unchanged.

Aphid itself is unpacked from this pinned local Hex archive into a path dependency;
it is not fetched from the Hex registry. Linux installation remains disabled in
this source package. Actual GitHub binary delivery, minimum systems/CPU, other
OTP versions, final notices and publication gates remain open. No native rebuild,
binary upload, GitHub release or Hex publication occurred in this local proof.
