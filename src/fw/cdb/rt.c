// CD block HLE firmware: C runtime for RV32I (no M extension): string functions and the arithmetic helpers the
// compiler calls.
#include "rt.h"

#ifdef SMPC_FW
// the SMPC runs between the CD code's steps: fills and copies longer than 256 bytes let it run every 256 bytes
// (smpc_world.c); up to 256 bytes they are the plain loops (the CD code's own long loops poll themselves)
void smpc_poll(void);
static void* __attribute__((noinline)) memset_long(void* d, int c, size_t n)
{
	uint8_t* p = d;
	while (n) {
		size_t k = n < 256 ? n : 256;
		n -= k;
		while (k--) *p++ = (uint8_t)c;
		smpc_poll();
	}
	return d;
}
static void* __attribute__((noinline)) memcpy_long(void* d, const void* s, size_t n)
{
	uint8_t* p = d; const uint8_t* q = s;
	while (n) {
		size_t k = n < 256 ? n : 256;
		n -= k;
		while (k--) *p++ = *q++;
		smpc_poll();
	}
	return d;
}
void* memset(void* d, int c, size_t n)
{
	if (n > 256) __attribute__((musttail)) return memset_long(d, c, n);
	uint8_t* p = d; while (n--) *p++ = (uint8_t)c; return d;
}
void* memcpy(void* d, const void* s, size_t n)
{
	if (n > 256) __attribute__((musttail)) return memcpy_long(d, s, n);
	uint8_t* p = d; const uint8_t* q = s; while (n--) *p++ = *q++; return d;
}
#else
void* memset(void* d, int c, size_t n) { uint8_t* p = d; while (n--) *p++ = (uint8_t)c; return d; }
void* memcpy(void* d, const void* s, size_t n) { uint8_t* p = d; const uint8_t* q = s; while (n--) *p++ = *q++; return d; }
#endif
int memcmp(const void* a, const void* b, size_t n)
{
	const uint8_t *p = a, *q = b;
	for (; n; n--, p++, q++) if (*p != *q) return *p - *q;
	return 0;
}

uint32_t __mulsi3(uint32_t a, uint32_t b)
{
	uint32_t r = 0;
	while (b) { if (b & 1) r += a; a <<= 1; b >>= 1; }
	return r;
}
uint64_t __muldi3(uint64_t a, uint64_t b)
{
	uint64_t r = 0;
	while (b) { if (b & 1) r += a; a <<= 1; b >>= 1; }
	return r;
}
#ifdef SMPC_FW
// SMPC_FW: the CPU is shared with the SMPC, and the CD code's divisions (MSF / BCD conversions: tens of them per
// sector) made its longest stretches without an SMPC poll: shift-subtract over the quotient's bits only (the
// divisor first aligned under the dividend's top bit). Same results (checked against the loop below on 2e8 random
// and edge-case operands).
static uint32_t udivmod(uint32_t n, uint32_t d, uint32_t* rem)
{
	if (!d) { *rem = n; return 0xFFFFFFFF; }
	if (n < d) { *rem = n; return 0; }
	uint32_t b = 1, q = 0;
	while (!(d & 0x80000000u) && (d << 1) <= n) { d <<= 1; b <<= 1; }
	for (;;) {
		if (n >= d) { n -= d; q |= b; }
		if (b == 1) break;
		d >>= 1; b >>= 1;
	}
	*rem = n;
	return q;
}
#else
static uint32_t udivmod(uint32_t n, uint32_t d, uint32_t* rem)
{
	uint32_t q = 0, r = 0;
	if (!d) { *rem = n; return 0xFFFFFFFF; }
	for (int i = 31; i >= 0; i--) {
		r = (r << 1) | ((n >> i) & 1);
		if (r >= d) { r -= d; q |= 1u << i; }
	}
	*rem = r;
	return q;
}
#endif
uint32_t __udivsi3(uint32_t n, uint32_t d) { uint32_t r; return udivmod(n, d, &r); }
uint32_t __umodsi3(uint32_t n, uint32_t d) { uint32_t r; udivmod(n, d, &r); return r; }
int32_t __divsi3(int32_t n, int32_t d)
{
	uint32_t r, q = udivmod(n < 0 ? -(uint32_t)n : (uint32_t)n, d < 0 ? -(uint32_t)d : (uint32_t)d, &r);
	return ((n < 0) != (d < 0)) ? -(int32_t)q : (int32_t)q;
}
int32_t __modsi3(int32_t n, int32_t d)
{
	uint32_t r;
	udivmod(n < 0 ? -(uint32_t)n : (uint32_t)n, d < 0 ? -(uint32_t)d : (uint32_t)d, &r);
	return n < 0 ? -(int32_t)r : (int32_t)r;
}
