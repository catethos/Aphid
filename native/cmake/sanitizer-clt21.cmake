# Host-only sanitizer toolchain proved by asan-runtime-probe-4.log.
# Explicit paths avoid changing xcode-select or the ordinary Release build.
set(CMAKE_C_COMPILER "/Library/Developer/CommandLineTools/usr/bin/clang")
set(CMAKE_CXX_COMPILER "/Library/Developer/CommandLineTools/usr/bin/clang++")
set(CMAKE_OSX_SYSROOT "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk")
set(CMAKE_CXX_STANDARD_INCLUDE_DIRECTORIES
    "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk/usr/include/c++/v1")
