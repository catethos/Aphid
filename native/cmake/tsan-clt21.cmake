# Host-only TSan runtime proved by tsan-runtime-probe-{1,3}.log.
include("${CMAKE_CURRENT_LIST_DIR}/sanitizer-clt21.cmake")
set(CMAKE_C_FLAGS_INIT "-fsanitize=thread -g -fno-omit-frame-pointer")
set(CMAKE_CXX_FLAGS_INIT "-fsanitize=thread -g -fno-omit-frame-pointer")
