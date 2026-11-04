// CD block HLE firmware: what Mednafen's headers provided (types, BCD helpers, the TOC) and the small C runtime.
#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#define INLINE inline
#define MDFN_COLD
#define MDFN_HOT
#define MDFN_UNLIKELY(x) (x)
#define MDFN_LIKELY(x) (x)
#define MDFN_STATIC_ASSERT(a, b) _Static_assert(a, b)
#define assert(x) ((void)0)

void* memset(void* d, int c, size_t n);
void* memcpy(void* d, const void* s, size_t n);
int memcmp(const void* a, const void* b, size_t n);
static inline int abs(int v) { return v < 0 ? -v : v; }

// subcode Q control bits, TOC (Mednafen's CDUtility.h)
enum { SUBQ_CTRLF_PRE = 0x01, SUBQ_CTRLF_DCP = 0x02, SUBQ_CTRLF_DATA = 0x04, SUBQ_CTRLF_4CH = 0x08 };
struct TOC_Track { uint8_t adr, control; uint32_t lba; bool valid; };
typedef struct TOC { uint8_t first_track, last_track, disc_type; struct TOC_Track tracks[100 + 1]; } TOC;

static inline uint8_t BCD_to_U8(uint8_t v) { return ((v >> 4) * 10) + (v & 0xF); }
static inline uint8_t U8_to_BCD(uint8_t v) { return ((v / 10) << 4) + (v % 10); }
static inline int32_t AMSF_to_ABA(int32_t m, int32_t s, int32_t f) { return f + 75 * s + 75 * 60 * m; }
