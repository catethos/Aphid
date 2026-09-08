#pragma once
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Stage 01 acceptance proof only. Blocks: dirty CPU scheduler / OS test thread.
 * Input byte views borrowed for the call, copied before engine use, <=4096 bytes,
 * no embedded NUL. Owns and destroys every engine object before returning.
 * Returns 0 on success, 1 on failure (diagnostic on stderr). No cancellation.
 * No handle or borrowed result escapes. Exceptions contained at entry. */
int32_t aphid_features(uint8_t reopen, const uint8_t* graph, size_t graph_len,
                      const uint8_t* fixture, size_t fixture_len);
#ifdef __cplusplus
}
#endif
