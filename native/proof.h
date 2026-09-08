#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Stage 00 only. All functions are constant-time, nonblocking, noexcept;
 * no pointers or ownership cross this ABI. */
uint32_t aphid_abi_version(void);
int64_t aphid_proof_add(int32_t a, int32_t b);
#ifdef __cplusplus
}
#endif
