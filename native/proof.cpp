#include "proof.h"
extern "C" uint32_t aphid_abi_version(void) { return 1; }
extern "C" int64_t aphid_proof_add(int32_t a, int32_t b) {
    return static_cast<int64_t>(a) + b;
}
