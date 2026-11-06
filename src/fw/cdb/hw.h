// CD block HLE firmware: the hardware of rtl/Saturn/CD/CDB_HLE.sv as the firmware sees it.
#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#define IO(o)        (*(volatile uint32_t*)(0x20000000u + (o)))
#define IO_FLAGS     IO(0x00)   // R flags (below); W 1 clears CMD_PEND / RES_READ
#define IO_HIRQ      IO(0x04)   // W: HIRQ bits to set (not readable)
#define IO_HMASK     IO(0x08)   // not readable (the host side only)
#define IO_TIMER     IO(0x0C)   // 11.2896 MHz (44100 x 256)
#define IO_CR(i)     IO(0x10 + 4 * (i))
#define IO_RR(i)     IO(0x20 + 4 * (i))   // W only
#define IO_SEC_LBA   IO(0x30)   // W: read this sector (LBA, FAD - 150) into the page of IO_SEC_PAGE
#define IO_SEC_PAGE  IO(0x34)
// 0x38 / 0x3C (sector bytes 12-19) are gone: the firmware reads them from the page (words 6-9)
#define IO_DT_CTRL   IO(0x40)
#define IO_DT_RAW    IO(0x44)   // {word count[31:16], CPU RAM byte address[15:0]}
#define IO_SECLEN    IO(0x48)   // {put[3:2], get[1:0]}
#define IO_DT_TOTAL  IO(0x4C)   // words transferred
#define IO_DT_LIST   IO(0x50)   // W: next transfer list entry {form2[9], mode1[8], page[7:0]}
#define IO_AUD       IO(0x54)   // W {push[31], flush[30], zero[20], shift[19:18], samples[17:8], page[7:0]}
                                // R {done entries[23:16], entries[14:12], samples queued[9:0]}

enum { F_CMD_PEND = 1 << 0, F_RES_READ = 1 << 1, F_SEC_BUSY = 1 << 2, F_DT_ACT = 1 << 3, F_DT_WR_IDLE = 1 << 4,
       F_DT_END = 1 << 5, F_DISC_IN = 1u << 31 };
enum { DT_START = 1 << 0, DT_STOP = 1 << 1, DT_WRITE = 1 << 2, DT_RAWMODE = 1 << 3, DT_CLEAR = 1 << 4 };

// CD RAM: CPU word k is CD RAM word k (16 bits, big-endian: byte 2k in [15:8])
#define CDRAM(w)     (*(volatile uint32_t*)(0x10000000u + 4u * (w)))
static inline uint16_t cd_rd16(uint32_t w) { return CDRAM(w); }
static inline void cd_wr16(uint32_t w, uint16_t v) { *(volatile uint16_t*)(0x10000000u + 4u * w) = v; }
static inline uint8_t cd_rd8(uint32_t a) { return (a & 1) ? (uint8_t)CDRAM(a >> 1) : (uint8_t)(CDRAM(a >> 1) >> 8); }

enum { PAGE_WORDS = 1176, NUM_PAGES = 205 };
static inline uint32_t page_word(unsigned page) { return page * PAGE_WORDS; }

// TOC, written by the disc source: word 0 {first track, last track}, word 1 {disc type, 0}, track t (1..99,
// 100 = lead-out) at words 2t, 2t + 1: {control << 4 | adr (0xFF: no track), LBA[23:16]}, {LBA[15:0]}
enum { TOC_WORD = 0x7F000 / 2 };
#ifdef CD_SRC_FW

// CD_SRC_FW (build.sh CD_SRC=1): the Pocket's disc source registers (glue/rtl/cd_src_b.sv on CDB_HLE's EXT port, RTL
// macro CD_EXTIO; glue/cd/REPORT.txt design B).
// Sector requests then carry {zero[23], ring word address[13:0]} in IO_SEC_LBA instead of an LBA (cd_src.c).
#define IO_X_STATUS  IO(0x60)   // R {slots[27:24], 0xCD[23:16], err[6:4], disc_in[3], dt_busy[1], cmd_busy[0]}
#define IO_X_ID      IO(0x60)   // W APF data slot id
#define IO_X_DTQ     IO(0x64)   // R the data slot table word last read
#define IO_X_OFFSET  IO(0x64)   // W byte offset in the slot's file
#define IO_X_DEST    IO(0x68)   // W {length in bytes[31:16], ring byte offset[15:0]}
#define IO_X_START   IO(0x6C)   // W start the data slot read
#define IO_X_DTADDR  IO(0x70)   // W read the data slot table word [9:0] (entry e: id at 2e, size at 2e + 1)
#define IO_X_DISC    IO(0x74)   // W {disc_in[0]} = CDB_HLE's DISC_IN
#define IO_X_AREA    IO(0x78)   // W {area code[3:0]}: the disc's SMPC area code (0: none), for Region = Auto
enum { XS_CMD_BUSY = 1 << 0, XS_DT_BUSY = 1 << 1, XS_DISC = 1 << 3 };
#endif
