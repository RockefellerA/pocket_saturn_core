/******************************************************************************/
/* Mednafen Sega Saturn Emulation Module                                      */
/******************************************************************************/
/* cdb.c - CD Block Emulation
**  Copyright (C) 2016-2021 Mednafen Team
**
** CD block HLE firmware (RISC-V, rtl/Saturn/CD/CDB_HLE.sv): this file is Mednafen's cdb.c (beetle-saturn's C
** port), changed to run on the HLE hardware: the host registers, the data transfer FIFO, the sector buffers'
** data (CD RAM pages), the drive's sector reads and the CD-DA output are hardware (hw.h); the TOC comes from CD
** RAM; time is the hardware timer (44100 x 256 Hz, the unit of Mednafen's CDB clocks), in 32-bit counters;
** no MPEG card, no save states.
**
** This program is free software; you can redistribute it and/or
** modify it under the terms of the GNU General Public License
** as published by the Free Software Foundation; either version 2
** of the License, or (at your option) any later version.
**
** This program is distributed in the hope that it will be useful,
** but WITHOUT ANY WARRANTY; without even the implied warranty of
** MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
** GNU General Public License for more details.
**
** You should have received a copy of the GNU General Public License
** along with this program; if not, write to the Free Software Foundation, Inc.,
** 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
*/

/*
 Finicky games:
	Astal
		Play and Seek command nuances.

	Batman Forever
		Seek delay must be high enough, or glitchy batmobile.

	BIOS CD-DA Player
		Play and Seek command nuances; test versions for both Japan
		and North America.

	Break Point
		Aborts out to BIOS CD player screen if CDB ever reports
		PLAY status for a 1-sector read.

	DJ Wars
		Same issue as Break Point.

	Dragon Force II
		When trying to skip an FMV, the game will hang until the initial
		Play command completes if the CDB in in a PAUSE state due to
		buffers being full, and the CDB fails to quickly go into BUSY
		state(due to seek start) immediately after a Reset Selector
		command frees up buffers.

	Gremlin Interactive Demo Disc
		Needs commands during disc authentication to be rejected.

	Hop Step Idol
		Similar issue to Break Point, but fails more spectacularly.

	Independence Day (USA)
		Issues 'Get CD Device Connection' command without waiting for
		the previously-issued 'Reset Selector' command to completely
		finish, expecting the returned value to not be the reset
		value.

	Jung Rhythm
		Seek delay must be high enough, or will hang when trying to
		retry a failed stage.

	Magical Drop III
		Needs resetting of 'is_cdrom' status bit to be delayed by a
		few dozen microseconds after a seek start triggered by the
		Play command.

	NBA Action
		Relies on seek to index 2+ functionality.

	Steam Heart's
		Play and Seek command nuances.  Music should resume where it
		left off after pausing and unpausing in-game.

	Tactics Ogre
		If repeat handling is wrong, will hang when trying to resume
		a suspended game.

	Taito Chase H.Q.
		Relies on seek to index 2+ functionality.

	Tenchi Muyou! Ryououki Gokuraku
		Quirks with running commands during an Init command software
		reset.

	Tennis Arena
		Probably same issue as Break Point.

	World Cup France '98
		Same issues as Dragon Force II

********************************************************************************
 Other interesting games:

	Assault Suit Leynos 2
		Reportedly has unique CD handling code; also uses Change Directory
		command fairly frequently.

	Sega Ages: After Burner 2
	Sega Ages: Fantasy Zone
	Sega Ages: OutRun
	Sega Ages: Space Harrier
		Use Put Sector Data command.
*/

// TODO: Respect auth type with COMMAND_AUTH_DEVICE.

// TODO: Test INIT 0x00 side effects(and see if it affects CD device connection)

// TODO: edc_lec_check_and_correct

// TODO: Some filesys commands(at least change dir, read file) seem to reset the saved command start and end positions(accessed via 0xFFFFFF to PLAY command) to something
// akin to 0.

// TODO: SMPC CD off/on

// TODO: Consider serializing HIRQ_PEND and HIRQ_SCDQ with command execution.

// TODO: Look into weird issue where WAIT status for Change Dir might be set to 1 slightly after CMOK IRQ is triggered...

// TODO: Test state reset on Init with SW reset.

// TODO: assert()s

// TODO: Reject all commands during disc startup?

// TODO:     for(unsigned i = 0; i < 5; i++) DT_ReadIntoFIFO();

// TODO: Auth and auth type.

// TODO: Test play command while filesys op is in progress.

#include "hw.h"
#include "rt.h"
#ifdef CD_SRC_FW
#include "cd_src.h"		// the Pocket's disc source (build.sh CD_SRC=1; glue/cd design B): APF data slots, the .cue
#endif
#ifdef SMPC_FW
#include "smpc.h"
#define SMPC_POLL() smpc_poll()     // the SMPC's MCU program, run up to the present (fw: smpc_world.c)
#else
#define SMPC_POLL() ((void)0)
#endif

static void CheckBufPauseResume(void);
static void StartSeek(const uint32_t cmd_target, const uint32_t cur_play_end, const uint32_t cur_play_repeat, const uint32_t play_end_irq_type, const bool no_pickup_change);
static void ClearPendingSec(void);

enum
{
 SECLEN__FIRST = 0,

 SECLEN_2048 = 0,
 SECLEN_2336 = 1,
 SECLEN_2340 = 2,
 SECLEN_2352 = 3,

 SECLEN__LAST = 3,
};

static uint8_t GetSecLen, PutSecLen;

static uint8_t AuthDiscType;
enum
{
 COMMAND_GET_CDSTATUS	= 0x00,
 COMMAND_GET_HWINFO	= 0x01,
 COMMAND_GET_TOC	= 0x02,
 COMMAND_GET_SESSINFO	= 0x03,
 COMMAND_INIT		= 0x04,
 COMMAND_OPEN		= 0x05,
 COMMAND_END_DATAXFER	= 0x06,

 COMMAND_PLAY		= 0x10,
 COMMAND_SEEK		= 0x11,
 COMMAND_SCAN		= 0x12,

 COMMAND_GET_SUBCODE	= 0x20,

 COMMAND_SET_CDDEVCONN	= 0x30,
 COMMAND_GET_CDDEVCONN	= 0x31,
 COMMAND_GET_LASTBUFDST	= 0x32,

 COMMAND_SET_FILTRANGE	= 0x40,
 COMMAND_GET_FILTRANGE	= 0x41,
 COMMAND_SET_FILTSUBHC	= 0x42,
 COMMAND_GET_FILTSUBHC	= 0x43,
 COMMAND_SET_FILTMODE	= 0x44,
 COMMAND_GET_FILTMODE	= 0x45,
 COMMAND_SET_FILTCONN	= 0x46,
 COMMAND_GET_FILTCONN	= 0x47,
 COMMAND_RESET_SEL	= 0x48,

 COMMAND_GET_BUFSIZE	= 0x50,
 COMMAND_GET_SECNUM	= 0x51,
 COMMAND_CALC_ACTSIZE	= 0x52,
 COMMAND_GET_ACTSIZE	= 0x53,
 COMMAND_GET_SECINFO	= 0x54,
 COMMAND_EXEC_FADSRCH	= 0x55,
 COMMAND_GET_FADSRCH	= 0x56,

 COMMAND_SET_SECLEN	= 0x60,
 COMMAND_GET_SECDATA	= 0x61,
 COMMAND_DEL_SECDATA	= 0x62,
 COMMAND_GETDEL_SECDATA	= 0x63,
 COMMAND_PUT_SECDATA	= 0x64,
 COMMAND_COPY_SECDATA	= 0x65,
 COMMAND_MOVE_SECDATA	= 0x66,
 COMMAND_GET_COPYERR	= 0x67,

 COMMAND_CHANGE_DIR	= 0x70,
 COMMAND_READ_DIR	= 0x71,
 COMMAND_GET_FSSCOPE	= 0x72,
 COMMAND_GET_FINFO	= 0x73,
 COMMAND_READ_FILE	= 0x74,
 COMMAND_ABORT_FILE	= 0x75,

 COMMAND_AUTH_DEVICE	= 0xE0,
 COMMAND_GET_AUTH	= 0xE1
};

enum
{
 STATUS_BUSY	 = 0x00,
 STATUS_PAUSE	 = 0x01,
 STATUS_STANDBY	 = 0x02,
 STATUS_PLAY	 = 0x03,
 STATUS_SEEK	 = 0x04,
 STATUS_SCAN	 = 0x05,
 STATUS_OPEN	 = 0x06,
 STATUS_NODISC	 = 0x07,
 STATUS_RETRY	 = 0x08,
 STATUS_ERROR	 = 0x09,
 STATUS_FATAL	 = 0x0A,

 //
 STATUS_PERIODIC = 0x20,
 STATUS_DTREQ	 = 0x40,
 STATUS_WAIT	 = 0x80,

 //
 STATUS_REJECTED = 0xFF
};

enum
{
 HIRQ_CMOK = 0x0001,	// command ok?
 HIRQ_DRDY = 0x0002,	// data transfer ready
 HIRQ_CSCT = 0x0004,	// 1 sector read complete?
 HIRQ_BFUL = 0x0008,	// buffer full
 HIRQ_PEND = 0x0010,	// play end (FIXME: Status must indicate a "Pause" state at the time this is triggered)
 HIRQ_DCHG = 0x0020,	// disc change
 HIRQ_ESEL = 0x0040,	// end of selector something?
 HIRQ_EHST = 0x0080,	// end of host I/O?
 HIRQ_ECPY = 0x0100,	// end of copy/move
 HIRQ_EFLS = 0x0200,	// end of filesystem something?
 HIRQ_SCDQ = 0x0400,	// Sub-channel Q update complete?

 HIRQ_MPED = 0x0800,
 HIRQ_MPCM = 0x1000,
 HIRQ_MPST = 0x2000
};
// HIRQ, its mask, the command and result registers are hardware: CommandPending is the "host wrote CR4" flag,
// ResultsRead the "host read CR4" flag (or the firmware's own setting, see SetResultsRead)
#define CommandPending ((IO_FLAGS & F_CMD_PEND) != 0)
static bool ResultsRead_fw;
static INLINE bool ResultsRead(void) { return ResultsRead_fw || (IO_FLAGS & F_RES_READ); }
static INLINE void SetResultsRead(bool v) { ResultsRead_fw = v; if(!v) IO_FLAGS = F_RES_READ; }
static INLINE void ClearCommandPending(void) { IO_FLAGS = F_CMD_PEND; }
static INLINE void SetResults(uint16_t r0, uint16_t r1, uint16_t r2, uint16_t r3)
{
 IO_RR(0) = r0; IO_RR(1) = r1; IO_RR(2) = r2; IO_RR(3) = r3;
}
static uint16_t SWResetHIRQDeferred;
static bool SWResetPending;
static uint8_t ResetSelPending;

static uint8_t CDDevConn;
static uint8_t LastBufDest;

enum { NumBuffers = 0xC8 };
// A buffer's data is the CD RAM page Page; Hdr keeps its bytes 12-19 (header and subheader) for the filters and
// the sector info commands.
static struct BufferT
{
 uint8_t Page;
 uint8_t Prev;
 uint8_t Next;
 uint8_t Hdr[8];
} Buffers[NumBuffers];

/* MODE_SEL_X / MODE_INIT lived inside `struct FilterS` as an
 * anonymous enum in the C++ form (accessed as FilterS::MODE_SEL_X).
 * Hoisted to file scope for the C conversion -- C scopes anonymous
 * enums in struct bodies to the enclosing scope anyway, but the
 * empty enum declaration inside the struct generates a "declaration
 * does not declare anything" warning.  Same values, file-scope
 * named-enum form. */
enum
{
 MODE_SEL_FILE    = 0x01,
 MODE_SEL_CHANNEL = 0x02,
 MODE_SEL_SUBMODE = 0x04,
 MODE_SEL_CINFO   = 0x08,
 MODE_SEL_SHREV   = 0x10,	/* Reverse sub-header conditions */
 MODE_SEL_FADR	  = 0x40,
 MODE_INIT	  = 0x80
};

static struct FilterS
{
 uint8_t Mode;
 uint8_t TrueConn;
 uint8_t FalseConn;
 //
 uint32_t FAD;
 uint32_t Range;

 uint8_t Channel;
 uint8_t File;

 uint8_t SubMode;
 uint8_t SubModeMask;

 uint8_t CInfo;
 uint8_t CInfoMask;
} Filters[0x18];

static struct
{
 uint8_t FirstBuf;
 uint8_t LastBuf;
 uint8_t Count;
} Partitions[0x18];

static uint8_t FirstFreeBuf;
static uint8_t FreeBufferCount;

static struct
{
 uint32_t fad;
 uint16_t spos;
 uint8_t pnum;
} FADSearch;

static uint32_t CalcedActualSize;
//
//
//
//
//
static bool TrayOpen;
static bool Cur_CDIF;			// a disc is in
static TOC toc;
static int32_t CommandPhase;
//static bool CommandYield;
static int32_t CommandClockCounter;

static struct
{
 uint8_t Command;
 uint16_t CD[4];
} CTR;

// The words themselves go through the hardware (DT_StartList / DT_StartRaw); this is the bookkeeping.
static struct
{
 bool Active;
 bool Writing;
 bool NeedBufFree;

 unsigned BufCount;

 uint8_t FNum;

 uint8_t BufList[NumBuffers];	// buffers, or 0xF0 (file info) / 0xFD / 0xFE (subcode) / 0xFF (TOC)
} DT;

static uint16_t StandbyTime;
static uint8_t ECCEnable;
static uint8_t RetryCount;


static int32_t SeekIndexPhase;
static uint32_t CurSector;
static int32_t DrivePhase;

enum
{
 DRIVEPHASE_STOPPED = 0,
 DRIVEPHASE_PLAY,

 DRIVEPHASE_SEEK_START3,
 DRIVEPHASE_SEEK,
 DRIVEPHASE_SCAN,

 DRIVEPHASE_EJECTED0,
 DRIVEPHASE_EJECTED1,
 DRIVEPHASE_EJECTED_WAITING,
 DRIVEPHASE_STARTUP,

 DRIVEPHASE_RESETTING,

 DRIVEPHASE_SEEK_START1,
 DRIVEPHASE_SEEK_START2,

 DRIVEPHASE_PAUSE
};
static int32_t DriveCounter;
static int32_t PeriodicIdleCounter;
#define PeriodicIdleCounter_Reload 187065

static int32_t PauseCounter;
static bool PlaySectorProcessed;
static uint8_t PlayRepeatCounter;
static uint8_t CurPlayRepeat;

static uint32_t CurPlayStart;
static uint32_t CurPlayEnd;
static uint32_t PlayEndIRQType;
//static uint32_t PlayEndIRQPending;

static uint32_t PlayCmdStartPos, PlayCmdEndPos;
static uint8_t PlayCmdRepCnt;

static int8_t ScanMode;
static uint8_t ScanCounter;

// CD-DA: the hardware plays a queue of CD RAM pages (CDDA_*); the count is the hardware's.
enum { CDDABuf_PrefillCount = 4 };
enum { CDDABuf_MaxCount = 4 + 588 + 4 };

// The sector being read (Mednafen's SecPreBuf) is the CD RAM page SecPrePage, read by the hardware: SecPreBuf_In
// as before, the data is there when the sector engine is done (SecPreReady).
static uint8_t SecPrePage;
static int SecPreBuf_In;
static uint8_t SecPreHdr[8];
static bool SecPreHdrValid;
static uint8_t SecPreQ[0xC];		// subcode Q of the sector read (made from the TOC)

static uint8_t TOC_Buffer[(99 + 3) * 4];

static struct
{
 uint8_t status;
 uint32_t fad;
 uint32_t rel_fad;
 uint8_t ctrl_adr;
 uint8_t idx;
 uint8_t tno;

 bool is_cdrom;
 uint8_t repcount;
} CurPosInfo;

// Higher-level:
static uint8_t SubCodeQBuf[10];
static uint8_t SubCodeRWBuf[24];

// SubQBuf for ADR=1 only for now.
static uint8_t SubQBuf[0xC];
static uint8_t SubQBuf_Safe[0xC];
static bool SubQBuf_Safe_Valid;

// Subcode Q of a sector, made from the TOC the way Mednafen's disc image code does (CDAccess_Image_MakeSubPQ):
// the track is the last one starting at or before the LBA (track 1's 2 s pregap: index 0), outside the disc
// (before the pregap, from the lead-out on) there is none.
static bool MakeSubQ(int32_t lba, uint8_t* q)
{
 int track = 0;
 uint32_t rel;

 memset(q, 0, 0xC);

 if(!Cur_CDIF || lba < (int32_t)toc.tracks[toc.first_track].lba - 150 || lba >= (int32_t)toc.tracks[100].lba)
  return false;

 for(int t = toc.first_track; t <= toc.last_track; t++)
  if(toc.tracks[t].valid && (int32_t)toc.tracks[t].lba <= lba)
   track = t;
 if(!track)
  track = toc.first_track;

 rel = (lba < (int32_t)toc.tracks[track].lba) ? toc.tracks[track].lba - 1 - lba : lba - toc.tracks[track].lba;

 q[0] = 0x01 | (toc.tracks[track].control << 4);
 q[1] = U8_to_BCD(track);
 q[2] = U8_to_BCD((lba < (int32_t)toc.tracks[track].lba) ? 0 : 1);
 q[3] = U8_to_BCD(rel / 75 / 60);
 q[4] = U8_to_BCD((rel / 75) % 60);
 q[5] = U8_to_BCD(rel % 75);
 q[6] = 0;
 q[7] = U8_to_BCD((lba + 150) / 75 / 60);
 q[8] = U8_to_BCD(((lba + 150) / 75) % 60);
 q[9] = U8_to_BCD((lba + 150) % 75);
 return true;
}

static bool DecodeSubQ(const uint8_t* tmp_q)
{
 if((tmp_q[0] & 0xF) == 1)
 {
  memcpy(SubQBuf, tmp_q, 0xC);
  memcpy(SubQBuf_Safe, tmp_q, 0xC);
  SubQBuf_Safe_Valid = true;
  return(true);
 }

 return(false);
}

//
// CD RAM pages: each buffer owns one, so does the sector being read (SecPrePage) and each CD-DA queue entry
// with samples; the rest are spare. Taking a sector into a buffer swaps the two pages.
//
static uint8_t PagePool[NUM_PAGES - NumBuffers];
static uint8_t PagePoolN;
static uint8_t CDDA_QPage[4];		// pages of the hardware CD-DA queue's entries, in order (0xFF: zeros)
static uint8_t CDDA_QN, CDDA_QDone;

static void Pages_Init(void)
{
 for(unsigned i = 0; i < NumBuffers; i++)
  Buffers[i].Page = i;
 SecPrePage = NumBuffers;
 PagePoolN = 0;
 for(unsigned p = NumBuffers + 1; p < NUM_PAGES; p++)
  PagePool[PagePoolN++] = p;
 CDDA_QN = 0;
 CDDA_QDone = IO_AUD >> 16;
}

// pages of finished CD-DA queue entries back to the pool
static void CDDA_Reclaim(void)
{
 const uint8_t done = IO_AUD >> 16;

 while(CDDA_QDone != done && CDDA_QN)
 {
  if(CDDA_QPage[0] != 0xFF)
   PagePool[PagePoolN++] = CDDA_QPage[0];
  for(unsigned i = 1; i < CDDA_QN; i++)
   CDDA_QPage[i - 1] = CDDA_QPage[i];
  CDDA_QN--;
  CDDA_QDone++;
 }
}

static unsigned CDDA_Count(void)
{
 return IO_AUD & 0x3FF;
}

static void CDDA_Flush(void)
{
 IO_AUD = 1u << 30;
 while(CDDA_QN)
 {
  if(CDDA_QPage[0] != 0xFF)
   PagePool[PagePoolN++] = CDDA_QPage[0];
  for(unsigned i = 1; i < CDDA_QN; i++)
   CDDA_QPage[i - 1] = CDDA_QPage[i];
  CDDA_QN--;
 }
 CDDA_QDone = IO_AUD >> 16;
}

static bool CDDA_Push(unsigned page, unsigned samples, unsigned shift, bool zero)
{
 if(CDDA_QN >= 4 || !samples)
  return false;
 IO_AUD = (1u << 31) | ((uint32_t)zero << 20) | (shift << 18) | (samples << 8) | (zero ? 0 : page);
 CDDA_QPage[CDDA_QN++] = zero ? 0xFF : page;
 return true;
}

// the buffer's header bytes from its page (sectors the host wrote)
static void Buffer_ReadHdr(unsigned bfi)
{
 const uint32_t w = page_word(Buffers[bfi].Page) + 6;

 for(unsigned i = 0; i < 4; i++)
 {
  const uint16_t v = cd_rd16(w + i);
  Buffers[bfi].Hdr[i * 2 + 0] = v >> 8;
  Buffers[bfi].Hdr[i * 2 + 1] = v;
 }
}

static void Page_Zero(unsigned page)
{
 const uint32_t w = page_word(page);

 for(unsigned i = 0; i < PAGE_WORDS; i++)
 {
  cd_wr16(w + i, 0);
  if((i & 63) == 63) SMPC_POLL();	// (SMPC_FW: a CD RAM word access takes ~1-2 us: a poll every ~0.1 ms)
 }
}

static void Page_Copy(unsigned dst, unsigned src)
{
 const uint32_t d = page_word(dst), s = page_word(src);

 for(unsigned i = 0; i < PAGE_WORDS; i++)
 {
  cd_wr16(d + i, cd_rd16(s + i));
  if((i & 63) == 63) SMPC_POLL();
 }
}

static void ResetBuffers(void)
{
 Buffers[0].Prev = 0xFF;
 Buffers[0].Next = 1;
 for(unsigned i = 1; i < (NumBuffers - 1); i++)
 {
  Buffers[i].Prev = i - 1;
  Buffers[i].Next = i + 1;
 }
 Buffers[NumBuffers - 1].Prev = NumBuffers - 1 - 1;
 Buffers[NumBuffers - 1].Next = 0xFF;

 FirstFreeBuf = 0;
 FreeBufferCount = NumBuffers;

 for(unsigned i = 0; i < 0x18; i++)
 {
  Partitions[i].FirstBuf = 0xFF;
  Partitions[i].LastBuf = 0xFF;
  Partitions[i].Count = 0;
 }
}

static void Filter_ResetCond(const unsigned fnum)
{
 struct FilterS *f = &Filters[fnum];

 f->Mode = 0;

 f->FAD = 0;
 f->Range = 0;

 f->Channel = 0;
 f->File = 0;

 f->SubMode = 0;
 f->SubModeMask = 0;

 f->CInfo = 0;
 f->CInfoMask = 0;
}

static uint8_t Buffer_Allocate(const bool zero_clear)
{
 const unsigned bfsidx = FirstFreeBuf;
 assert(bfsidx != 0xFF && FreeBufferCount > 0);

 if(zero_clear)
  Page_Zero(Buffers[bfsidx].Page);

 if(Buffers[bfsidx].Prev == 0xFF)
  FirstFreeBuf = Buffers[bfsidx].Next;
 else
  Buffers[Buffers[bfsidx].Prev].Next = Buffers[bfsidx].Next;

 if(Buffers[bfsidx].Next == 0xFF)
 {

 }
 else
  Buffers[Buffers[bfsidx].Next].Prev = Buffers[bfsidx].Prev;

 FreeBufferCount--;

 //
 Buffers[bfsidx].Prev = 0xFF;
 Buffers[bfsidx].Next = 0xFF;
 //

 return bfsidx;
}

// Must not alter "Data" member, as it may be used while "free"'d.
static void Buffer_Free(const uint8_t bfsidx)
{
 assert((FirstFreeBuf == 0xFF && FreeBufferCount == 0) || (FirstFreeBuf != 0xFF && FreeBufferCount > 0));
 assert(Buffers[bfsidx].Next == 0xFF && Buffers[bfsidx].Prev == 0xFF);

 Buffers[bfsidx].Prev = 0xFF;
 Buffers[bfsidx].Next = FirstFreeBuf;

 if(FirstFreeBuf != 0xFF)
 {
  assert(Buffers[FirstFreeBuf].Prev == 0xFF);
  Buffers[FirstFreeBuf].Prev = bfsidx;
 }

 FreeBufferCount++;
 FirstFreeBuf = bfsidx;
}

static void Partition_LinkBuffer(const unsigned pnum, const unsigned bfsidx)
{
 assert(Buffers[bfsidx].Next == 0xFF && Buffers[bfsidx].Prev == 0xFF);

 Buffers[bfsidx].Next = 0xFF;

 if(Partitions[pnum].FirstBuf == 0xFF)
 {
  assert(Partitions[pnum].LastBuf == 0xFF);
  Partitions[pnum].FirstBuf = bfsidx;
  Partitions[pnum].LastBuf = bfsidx;
  Buffers[bfsidx].Prev = 0xFF;
 }
 else
 {
  assert(Partitions[pnum].LastBuf != 0xFF);
  Buffers[Partitions[pnum].LastBuf].Next = bfsidx;
  Buffers[bfsidx].Prev = Partitions[pnum].LastBuf;
 }

 Partitions[pnum].LastBuf = bfsidx;
 Partitions[pnum].Count++;
}

static int Partition_GetBuffer(unsigned pnum, unsigned rbi)
{
 for(unsigned ii = Partitions[pnum].FirstBuf; ii != 0xFF; ii = Buffers[ii].Next)
 {
  if(!rbi)
   return ii;

  rbi--;
 }

 return -1;
}

// Must not alter "Data" member, as it may be used while unlinked.
static void Partition_UnlinkBuffer(unsigned pnum, unsigned bfsidx)
{
 assert(Partitions[pnum].Count > 0);

 Partitions[pnum].Count--;

 if(Buffers[bfsidx].Prev == 0xFF)
 {
  assert(Partitions[pnum].FirstBuf == bfsidx);
  Partitions[pnum].FirstBuf = Buffers[bfsidx].Next;
 }
 else
 {
  assert(Partitions[pnum].FirstBuf != bfsidx);
  Buffers[Buffers[bfsidx].Prev].Next = Buffers[bfsidx].Next;
 }

 if(Buffers[bfsidx].Next == 0xFF)
 {
  assert(Partitions[pnum].LastBuf == bfsidx);
  Partitions[pnum].LastBuf = Buffers[bfsidx].Prev;
 }
 else
 {
  assert(Partitions[pnum].LastBuf != bfsidx);
  Buffers[Buffers[bfsidx].Next].Prev = Buffers[bfsidx].Prev;
 }

 //
 Buffers[bfsidx].Prev = 0xFF;
 Buffers[bfsidx].Next = 0xFF;
}

static void SetCDDeviceConn(const uint8_t fnum)
{
 for(unsigned fs = 0; fs < 0x18; fs++)
  if(Filters[fs].FalseConn == fnum)
   Filters[fs].FalseConn = 0xFF;

 CDDevConn = fnum;
}

static void Filter_SetRange(const uint8_t fnum, const uint32_t fad, const uint32_t range)
{
 Filters[fnum].FAD = fad;
 Filters[fnum].Range = range;
}

static void Filter_SetTrueConn(const uint8_t fnum, const uint8_t tconn)
{
 Filters[fnum].TrueConn = tconn;
}

static void Filter_DisconnectInput(const uint8_t fnum)
{
 if(fnum == 0xFF)
  return;

 if(CDDevConn == fnum)
  CDDevConn = 0xFF;

 for(unsigned fs = 0; fs < 0x18; fs++)
 {
  if(Filters[fs].FalseConn == fnum)
   Filters[fs].FalseConn = 0xFF;
 }
}

static void Filter_SetFalseConn(const uint8_t fnum, const uint8_t fconn)
{
 Filter_DisconnectInput(fconn);
 Filters[fnum].FalseConn = fconn;
}

static void Partition_Clear(const unsigned pnum)
{
 while(Partitions[pnum].Count > 0)
 {
  const unsigned bfi = Partitions[pnum].FirstBuf;

  Partition_UnlinkBuffer(pnum, bfi);
  Buffer_Free(bfi);
  if((Partitions[pnum].Count & 15) == 0) SMPC_POLL();	// (SMPC_FW: 200 buffers take ~1.2 ms)
 }
}

//
//
//
//
//
static struct FileInfoS
{
 uint8_t fad_be[4];
 uint8_t size_be[4];

 /* `uint32_t fad(void) const` / `uint32_t size(void) const` were
  * inline methods on this struct in the C++ form.  C has no member
  * functions; the same logic lives below as free INLINE helpers
  * taking an explicit `fi` pointer.  Three call sites total. */

 uint8_t unit_size;
 uint8_t gap_size;
 uint8_t fnum;
 uint8_t attr;
} FileInfo[256];

static INLINE uint32_t FileInfoS_fad(const struct FileInfoS *fi)
{
 return ((uint32_t)fi->fad_be[0] << 24) | ((uint32_t)fi->fad_be[1] << 16) | ((uint32_t)fi->fad_be[2] << 8) | (uint32_t)fi->fad_be[3];
}

static INLINE uint32_t FileInfoS_size(const struct FileInfoS *fi)
{
 return ((uint32_t)fi->size_be[0] << 24) | ((uint32_t)fi->size_be[1] << 16) | ((uint32_t)fi->size_be[2] << 8) | (uint32_t)fi->size_be[3];
}

MDFN_STATIC_ASSERT(sizeof(struct FileInfoS) == 12 && sizeof(FileInfo) == 12 * 256, "FileInfo wrong size!");
static bool FileInfoValid;
static uint8_t FileInfoValidCount;	// 0 ... 254
static uint32_t FileInfoOffs;		// 2 ... whatever
static bool FileInfoMore;

enum
{
 FATTR_DIR = 0x02,
 FATTR_XA_M2F1 = 0x08,
 FATTR_XA_M2F2 = 0x10,
 FATTR_XA_ILEAVE = 0x20,
 FATTR_XA_CDDA = 0x40,
 FATTR_XA_DIR = 0x80
};

static struct FileInfoS RootDirInfo;
static bool RootDirInfoValid;

static struct
{
 uint32_t Phase;
 bool Active;
 bool DoAuth;
 bool Abort;
 //
 //
 uint8_t pnum;

 uint32_t fioffs;
 uint32_t fiaoffs;

 uint8_t pbuf[2048];	// Sector buffer.
 uint32_t pbuf_offs;
 uint32_t pbuf_read_i;

 uint32_t total_counter;	// Byte counter
 uint32_t total_max;	// Byte size

 uint8_t record[256];	// Temporary buffer.
 uint32_t record_counter;
} FLS;

// a file system sector's 2048 data bytes (after the header, or the subheader in mode 2) into FLS.pbuf
static void FLS_CopyData(unsigned bfi)
{
 const uint32_t w = page_word(Buffers[bfi].Page) + ((Buffers[bfi].Hdr[3] == 0x2) ? 12 : 8);

 for(unsigned i = 0; i < 1024; i++)
 {
  const uint16_t v = cd_rd16(w + i);
  FLS.pbuf[i * 2 + 0] = v >> 8;
  FLS.pbuf[i * 2 + 1] = v;
  if((i & 63) == 63) SMPC_POLL();
 }
}

enum { FLSPhaseBias = __COUNTER__ + 1 };

#define FLS_PROLOGUE	 switch(FLS.Phase + FLSPhaseBias) { for(;;) {
#define FLS_EPILOGUE  }	} FLSGetOut:;

#define FLS_YIELD	   {							\
			    FLS.Phase = __COUNTER__ - FLSPhaseBias + 1;		\
			    goto FLSGetOut;					\
			    case __COUNTER__:;					\
			   }

#define FLS_WAIT_UNTIL_COND(n) {						\
			    case __COUNTER__:					\
			    if(!(n))						\
			    {							\
			     FLS.Phase = __COUNTER__ - FLSPhaseBias - 1;	\
			     goto FLSGetOut;					\
			    }							\
			   }

#define FLS_WAIT_GRAB_BUF 						\
	  FLS_WAIT_UNTIL_COND(Partitions[FLS.pnum].Count > 0);		\
	  {								\
	   const unsigned bfi = Partitions[FLS.pnum].FirstBuf;		\
	   Partition_UnlinkBuffer(FLS.pnum, bfi);			\
	   FLS_CopyData(bfi);						\
	   Buffer_Free(bfi);						\
	   CheckBufPauseResume();						\
	  }								

#define FLS_READ(buffer, boffs, bmask, count)		\
	for(FLS.pbuf_read_i = 0; FLS.pbuf_read_i < (count); FLS.pbuf_read_i++)	\
	{								\
	 if(FLS.pbuf_offs == 0)						\
	 {								\
          FLS_WAIT_GRAB_BUF;						\
	 }								\
	 if((buffer) != NULL)						\
	  (buffer)[((boffs) + FLS.pbuf_read_i) & (bmask)] = FLS.pbuf[FLS.pbuf_offs];	\
	 FLS.pbuf_offs = (FLS.pbuf_offs + 1) % 2048;			\
	 FLS.total_counter++;						\
	}

static void ReadRecord(struct FileInfoS* fi, const uint8_t* rr)
{
 const uint8_t rec_len = rr[0];
 const uint8_t fi_len = rr[32];

 {
  /* Read BE u32 from &rr[6], add 150, write back as BE u32. */
  uint32_t v__ = ((uint32_t)rr[6] << 24) | ((uint32_t)rr[7] << 16) | ((uint32_t)rr[8] << 8) | (uint32_t)rr[9];
  v__ += 150;
  fi->fad_be[0] = v__ >> 24;
  fi->fad_be[1] = v__ >> 16;
  fi->fad_be[2] = v__ >> 8;
  fi->fad_be[3] = v__;
 }
 {
  /* Read BE u32 from &rr[14], copy through. */
  uint32_t v__ = ((uint32_t)rr[14] << 24) | ((uint32_t)rr[15] << 16) | ((uint32_t)rr[16] << 8) | (uint32_t)rr[17];
  fi->size_be[0] = v__ >> 24;
  fi->size_be[1] = v__ >> 16;
  fi->size_be[2] = v__ >> 8;
  fi->size_be[3] = v__;
 }

 fi->attr = rr[25] & 0x2;
 fi->unit_size = rr[26];
 fi->gap_size = rr[27];
 fi->fnum = 0;

 int su_offs = 33 + (fi_len | 1);
 int su_len = (rec_len - su_offs);

 if(su_len >= 14 && (su_offs + su_len) <= 256)
 {
  if(rr[su_offs + 6] == 'X' && rr[su_offs + 7] == 'A')
  {
   fi->attr |= rr[su_offs + 4] & 0xF8;
   fi->fnum = rr[su_offs + 8];
  }
 }
}

static bool FLS_Run(void)
{
 bool ret = false;

 if(FLS.Abort)
  goto Abort;

 //
 FLS_PROLOGUE;
 {
  default: FLS_WAIT_UNTIL_COND(FLS.Active);

  if(FLS.DoAuth)
  {
   SetCDDeviceConn(FLS.pnum);
   Filter_SetTrueConn(FLS.pnum, FLS.pnum);
   Filter_SetFalseConn(FLS.pnum, 0xFF);
   Filter_SetRange(FLS.pnum, 0, 0);
   Filters[FLS.pnum].Mode = 0;
   //
   AuthDiscType = 0xFF;
   StartSeek(0x800000 | 0x96, 0, 0, 0, false);
   //
   //
   static const char ssid[16] = { 'S', 'E', 'G', 'A', ' ', 'S', 'E', 'G', 'A', 'S', 'A', 'T', 'U', 'R', 'N', ' ' };

   FLS_WAIT_GRAB_BUF;
   AuthDiscType = 0x00;

   if(!memcmp(FLS.pbuf, ssid, 16))
   {
    // TODO: Simulate seek delay.
    //StartSeek(0x800000 | 333000);
    //FLS_WAIT_GRAB_BUF;
    //FLS_WAIT_GRAB_BUF;
    //
    AuthDiscType = 0x04;
   }
   else
    AuthDiscType = 0x02;

   SetCDDeviceConn(0xFF);
   StartSeek(0x800000 | 0x96, 0x800000, 0, 0, false);
  }
  else
  {
   SetCDDeviceConn(FLS.pnum);
   Filter_SetTrueConn(FLS.pnum, FLS.pnum);
   Filter_SetFalseConn(FLS.pnum, 0xFF);

   if(!RootDirInfoValid)
   {
    Filter_SetRange(FLS.pnum, 0, 0);
    Filters[FLS.pnum].Mode = 0;

    StartSeek(0x800000 | 0xA6, 0, 0, 0, false);

    for(;;)
    {
     static const char stdid[5] = { 'C', 'D', '0', '0', '1' };
     FLS_WAIT_GRAB_BUF;

     if(memcmp(FLS.pbuf + 1, stdid, 5) || FLS.pbuf[0] == 0xFF)
      break;
     else if(FLS.pbuf[0] == 0x01)	// PVD
     {
      ReadRecord(&RootDirInfo, &FLS.pbuf[156]);
      RootDirInfoValid = true;
      break;
     }
    }
   }
   //
   //
   //
   if(RootDirInfoValid)
   {
    {
     const struct FileInfoS* fi;

     if(FLS.fiaoffs >= 256)
      fi = &RootDirInfo;
     else
      fi = &FileInfo[FLS.fiaoffs];

     Partition_Clear(FLS.pnum);

     Filter_SetRange(FLS.pnum, FileInfoS_fad(fi), (FileInfoS_size(fi) + 2047) >> 11);	// TODO: maybe remove + 2047, actual Saturn drive seems buggy...
     Filters[FLS.pnum].Mode = MODE_SEL_FADR;
     Filters[FLS.pnum].File = fi->fnum;

     Filters[FLS.pnum].Channel = 0;
     Filters[FLS.pnum].SubMode = 0;
     Filters[FLS.pnum].SubModeMask = 0;
     Filters[FLS.pnum].CInfo = 0;
     Filters[FLS.pnum].CInfoMask = 0;

     FLS.total_max = FileInfoS_size(fi);

     StartSeek(0x800000 | FileInfoS_fad(fi), 0, 0, 0, false);
    }
    //
    //
    //
    FLS.total_counter = 0;
    FLS.pbuf_offs = 0;
    FLS.record_counter = 0;

    FileInfoValid = false;

    while(FLS.total_counter < FLS.total_max)
    {
     SMPC_POLL();	// (SMPC_FW: one pass is a 256-byte memset and more; a sector of padding is 2048 passes)
     memset(FLS.record, 0, sizeof(FLS.record));

     FLS_READ(FLS.record, 0, 0xFF, 1);
     if(!FLS.record[0])
      continue;
     FLS_READ(FLS.record, 1, 0xFF, (unsigned)(FLS.record[0] - 1));

     if(FLS.record_counter < 2)
      ReadRecord(&FileInfo[FLS.record_counter & 0xFF], FLS.record);
     else if(FLS.record_counter >= FLS.fioffs)
     {
      if(FLS.record_counter == FLS.fioffs)
      {
       FileInfoOffs = FLS.record_counter;
       FileInfoValidCount = 0;
       FileInfoMore = false;
      }
      else if(FileInfoValidCount == 0xFE)
      {
       FileInfoMore = true;
       break;
      }

      ReadRecord(&FileInfo[(2 + FileInfoValidCount) & 0xFF], FLS.record);
      FileInfoValidCount++;
     }
     FLS.record_counter++;
    }

    if(FLS.record_counter <= 2)
    {
     FileInfoOffs = 0;
     FileInfoValidCount = 0;
     FileInfoMore = false;
    }

    FileInfoValid = true;
   }
  }

  Partition_Clear(FLS.pnum);	// Place before Abort:;
  //
  //
  //
  Abort:;
  FLS.Active = false;
  FLS.DoAuth = false;
  FLS.Abort = false;
  //
  // Pause
  //
  PlayEndIRQType = 0;
  CurPlayEnd = 0x800000;
  CurPlayRepeat = 0;
  //
  //
  //
  ret = true;
 }
 FLS_EPILOGUE;

 return ret;
}

//
// Data transfers: the hardware moves the words (Mednafen's DT_ReadIntoFIFO, DT_SetIBOffsCount and the data port);
// sector length changes take effect at the next buffer, as there.
//
static void UpdateSecLen(void)
{
 IO_SECLEN = (GetSecLen & 3) | ((PutSecLen & 3) << 2);
}

// partition / sector buffers DT.BufList[0 .. DT.BufCount - 1]
static void DT_StartList(bool writing)
{
 IO_DT_CTRL = DT_CLEAR;
 for(unsigned i = 0; i < DT.BufCount; i++)
 {
  const struct BufferT* b = &Buffers[DT.BufList[i]];
  IO_DT_LIST = b->Page | ((b->Hdr[3] == 0x1) << 8) | (((b->Hdr[6] & 0x20) != 0) << 9);
 }
 IO_DT_CTRL = DT_START | (writing ? DT_WRITE : 0);
}

// words from CPU RAM (TOC, subcode, file info), big-endian byte pairs
static void DT_StartRaw(const void* p, unsigned words)
{
 IO_DT_CTRL = DT_CLEAR;
 IO_DT_RAW = ((uint32_t)words << 16) | ((uint32_t)(uintptr_t)p & 0xFFFF);
 IO_DT_CTRL = DT_START | DT_RAWMODE;
}

static uint32_t DT_Stop(void)
{
 if(DT.Writing)
  while(!(IO_FLAGS & F_DT_WR_IDLE)) { SMPC_POLL(); }
 IO_DT_CTRL = DT_STOP;
 return IO_DT_TOTAL;
}

static void SWReset(void)
{
 GetSecLen = SECLEN_2048;
 PutSecLen = SECLEN_2048;

 CDDevConn = 0xFF;

 LastBufDest = 0xFF;

 memset(&DT, 0, sizeof(DT));
 DT.Active = false;

 for(unsigned i = 0; i < 0x18; i++)
 {
  struct FilterS *f = &Filters[i];

  f->TrueConn = i;
  f->FalseConn = 0xFF;

  Filter_ResetCond(i);
 }

 ResetBuffers();
 IO_DT_CTRL = DT_STOP;
 UpdateSecLen();

 FADSearch.fad = 0;
 FADSearch.spos = 0;
 FADSearch.pnum = 0;

 CalcedActualSize = 0;

 PlayEndIRQType = 0;
 CurPlayEnd = 0x800000;
 CurPlayRepeat = 0;
 ClearPendingSec();
 //
 //
 //
 memset(&FLS, 0, sizeof(FLS));
 FileInfoValid = false;
 RootDirInfoValid = false;
 FLS.Phase = 0;
}

static void CDB_ResetCD(void)	// TODO
{
 PeriodicIdleCounter = 0x7FFFFFFF;
 DrivePhase = DRIVEPHASE_RESETTING;
 DriveCounter = 0x7FFFFFFF;

 SetResults(0, 0, 0, 0);
 SetResultsRead(true);

 CommandPhase = -1;
 CommandClockCounter = 0;
 // TODO: Set next event, timestamp + 1.
}

// the TOC from CD RAM (hw.h)
static void ReadTOC(void)
{
#ifdef CD_SRC_FW
 src_toc(&toc);			// CD_SRC_FW: built from the .cue / the data slots (cd_src.c), no CD RAM TOC
 return;
#endif
 const uint16_t w0 = cd_rd16(TOC_WORD + 0), w1 = cd_rd16(TOC_WORD + 1);

 memset(&toc, 0, sizeof(toc));
 toc.first_track = w0 >> 8;
 toc.last_track = w0 & 0xFF;
 toc.disc_type = w1 >> 8;
 for(unsigned t = 1; t <= 100; t++)
 {
  const uint16_t a = cd_rd16(TOC_WORD + 2 * t), b = cd_rd16(TOC_WORD + 2 * t + 1);
  struct TOC_Track* tr = &toc.tracks[t];

  tr->valid = (a >> 8) != 0xFF;
  tr->control = tr->valid ? (a >> 12) : 0;
  tr->adr = tr->valid ? ((a >> 8) & 0xF) : 0;
  tr->lba = tr->valid ? ((uint32_t)(a & 0xFF) << 16) | b : 0;
 }
 if(!toc.first_track || toc.first_track > 99)
  toc.first_track = 1;
 if(toc.last_track < toc.first_track || toc.last_track > 99)
  toc.last_track = toc.first_track;
}

static void CDB_SetDisc(bool tray_open)
{
 TrayOpen = tray_open;
 Cur_CDIF = !tray_open;

 if(!Cur_CDIF)
 {
  if(DrivePhase != DRIVEPHASE_RESETTING)
  {
   AuthDiscType = 0x00;
   DrivePhase = DRIVEPHASE_EJECTED0;
   DriveCounter = 1000;
  }
 }
 else
  ReadTOC();
}

static INLINE void RecalcIRQOut(void)
{
}

static void CDB_Reset(bool powering_up)
{

 if(powering_up)
 {
  //
  //
  //
  GetSecLen = 0;
  PutSecLen = 0;

  AuthDiscType = 0;

  SetResults(0, 0, 0, 0);
  ClearCommandPending();
  SWResetHIRQDeferred = 0;
  SWResetPending = false;
  ResetSelPending = false;

  CDDevConn = 0;
  LastBufDest = 0;

  memset(Buffers, 0x00, sizeof(Buffers));
  Pages_Init();
  memset(Filters, 0x00, sizeof(Filters));
  memset(Partitions, 0x00, sizeof(Partitions));
  FirstFreeBuf = 0;
  FreeBufferCount = 0;
  memset(&FADSearch, 0x00, sizeof(FADSearch));

  CalcedActualSize = 0;
  //static bool TrayOpen;
  //static CDIF* Cur_CDIF;
  //static TOC toc;
  CommandPhase = 0;
  CommandClockCounter = 0;

  memset(&CTR, 0x00, sizeof(CTR));
  memset(&DT, 0x00, sizeof(DT));

  StandbyTime = 0;
  ECCEnable = 0;
  RetryCount = 0;
  SetResultsRead(false);
  SeekIndexPhase = 0;
  CurSector = 0;
  DrivePhase = 0;
  DriveCounter = 0;
  PeriodicIdleCounter = 0;

  PauseCounter = 0;
  PlaySectorProcessed = false;

  PlayRepeatCounter = 0;
  CurPlayRepeat = 0;

  CurPlayStart = 0;
  CurPlayEnd = 0;
  PlayEndIRQType = 0;

  PlayCmdStartPos = 0;
  PlayCmdEndPos = 0;
  PlayCmdRepCnt = 0;

  ScanMode = -1;
  ScanCounter = 0;

  CDDA_Flush();

  SecPreBuf_In = 0;
  SecPreHdrValid = false;
  memset(TOC_Buffer, 0x00, sizeof(TOC_Buffer));

  memset(&CurPosInfo, 0x00, sizeof(CurPosInfo));
  memset(SubCodeQBuf, 0x00, sizeof(SubCodeQBuf));
  memset(SubCodeRWBuf, 0x00, sizeof(SubCodeRWBuf));
  memset(SubQBuf, 0x00, sizeof(SubQBuf));
  memset(SubQBuf_Safe, 0x00, sizeof(SubQBuf_Safe));
  SubQBuf_Safe_Valid = false;

  memset(FileInfo, 0x00, sizeof(FileInfo));
  FileInfoValid = false;
  memset(&RootDirInfo, 0x00, sizeof(RootDirInfo));
  RootDirInfoValid = false;

  memset(&FLS, 0x00, sizeof(FLS));
 }
 //
 // (HIRQ and its mask: the hardware clears them at the CD block reset)
 //
 CDB_ResetCD();
}

static INLINE void TriggerIRQ(unsigned bs)
{
 IO_HIRQ = bs;
}

enum { CommandPhaseBias = __COUNTER__ + 1 };

#define CMD_YIELD	   {							\
			    CommandPhase = __COUNTER__ - CommandPhaseBias + 1;	\
			    CommandClockCounter = -500;				\
			    /*CommandYield = true;*/				\
			    goto CommandGetOut;					\
			    case __COUNTER__:					\
			    /*CommandYield = false;*/				\
			    CommandClockCounter = 0;				\
			   }

#define CMD_EAT_CLOCKS(n) {									\
			    CommandClockCounter -= (int32_t)(n);				\
			    {									\
			     case __COUNTER__:							\
			     if(CommandClockCounter < 0)					\
			     {									\
			      CommandPhase = __COUNTER__ - CommandPhaseBias - 1;			\
			      goto CommandGetOut;						\
			     }									\
			    }									\
			   }

uint8_t GetDriveStatus(void)
{
   return CurPosInfo.status;
}

// Drive commands: Init, Open, Play, Seek, Scan
//   return busy status
// Commands that change drive status:
//	Init, Open, Play, Seek, Scan
//

static uint8_t MakeBaseStatus(const bool rejected, const uint8_t hb)
{
 if(rejected)
  return STATUS_REJECTED;

 uint8_t ret = 0;

 if(TrayOpen)
  ret = STATUS_OPEN;
 else if(!Cur_CDIF)
  ret = STATUS_NODISC;
 else
  ret = CurPosInfo.status;

 return ret | hb;
}

// hdr: the sector's bytes 12-19
static bool TestFilterCond(const unsigned fnum, const uint8_t* hdr)
{
 const struct FilterS *f = &Filters[fnum];

 if(f->Mode & MODE_SEL_FADR)
 {
  const uint32_t fad = AMSF_to_ABA(BCD_to_U8(hdr[0]), BCD_to_U8(hdr[1]), BCD_to_U8(hdr[2]));

  if(fad < f->FAD || fad >= (f->FAD + f->Range))
   return false;
 }

 uint8_t file, channel, submode, cinfo;

 if(hdr[3] == 0x2)
 {
  file = hdr[4];
  channel = hdr[5];
  submode = hdr[6];
  cinfo = hdr[7];
 }
 else
  file = channel = submode = cinfo = 0x00;

 const bool shinv = (bool)(f->Mode & MODE_SEL_SHREV) && (bool)(f->Mode & 0x0F);

 if(f->Mode & MODE_SEL_FILE)
 {
  if((bool)(file != f->File))
   return shinv;
 }

 if(f->Mode & MODE_SEL_CHANNEL)
 {
  if((bool)(channel != f->Channel))
   return shinv;
 }

 if(f->Mode & MODE_SEL_SUBMODE)
 {
  if((bool)((submode & f->SubModeMask) != f->SubMode))
   return shinv;
 }

 if(f->Mode & MODE_SEL_CINFO)
 {
  if((bool)((cinfo & f->CInfoMask) != f->CInfo))
   return shinv;
 }

 return !shinv;
}

static uint8_t FilterBuf(const unsigned fnum, const unsigned bfsidx)
{
 assert(bfsidx != 0xFF);

 unsigned cur = fnum;
 unsigned max_iter = 0x18;
 //uint32_t done = 0;

 while(cur != 0xFF && max_iter--)
 {
  if(TestFilterCond(cur, Buffers[bfsidx].Hdr))
  {
   const uint8_t tconn = Filters[cur].TrueConn;

   if(tconn != 0xFF)
   {
    Partition_LinkBuffer(tconn, bfsidx);
    return cur;
   }
   cur = 0xFF;
  }
  else
   cur = Filters[cur].FalseConn;
 }

 // Discarded.  Poor buffer.
 Buffer_Free(bfsidx);

 return 0xFF;
}

static void TranslateTOC(void)
{
 uint8_t* td = TOC_Buffer;

 for(unsigned i = 1; i < 100; i++)
 {
  const struct TOC_Track *t = &toc.tracks[i];

  if(t->valid)
  {
   const uint32_t fad = t->lba + 150;

   td[0] = (t->control << 4) | t->adr;
   td[1] = fad >> 16;
   td[2] = fad >> 8;
   td[3] = fad >> 0;
  }
  else
   td[0] = td[1] = td[2] = td[3] = 0xFF;

  td += 4;
 }

 // TODO: Better raw TOC support in core code.

 // POINT=A0
 {
  const struct TOC_Track *t = &toc.tracks[toc.first_track];

  td[0] = (t->control << 4) | t->adr;
  td[1] = toc.first_track;
  td[2] = toc.disc_type;
  td[3] = 0;

  td += 4;
 }

 // POINT=A1
 {
  const struct TOC_Track *t = &toc.tracks[toc.last_track];

  td[0] = (t->control << 4) | t->adr;
  td[1] = toc.last_track;
  td[2] = 0;
  td[3] = 0;

  td += 4;
 }

 // Lead-out
 {
  const struct TOC_Track *t = &toc.tracks[100];
  const uint32_t fad = t->lba + 150;

  td[0] = (t->control << 4) | t->adr;
  td[1] = fad >> 16;
  td[2] = fad >> 8;
  td[3] = fad >> 0;
  td += 4;
 }

 assert((td - TOC_Buffer) == sizeof(TOC_Buffer));
 assert(sizeof(TOC_Buffer) == 0xCC * 2);
}

//
//
//
//
//
//
static void MakeReport(const bool rejected, const uint8_t hb)
{
 SetResults((MakeBaseStatus(rejected, hb) << 8) | (CurPosInfo.is_cdrom << 7) | (CurPosInfo.repcount & 0x7F),
	    (CurPosInfo.ctrl_adr << 8) | CurPosInfo.tno,
	    (CurPosInfo.idx << 8) | (CurPosInfo.fad >> 16),
	    CurPosInfo.fad);
}

static void CDStatusResults(const bool rejected, const uint8_t hb)
{
 SetResultsRead(false);
 MakeReport(rejected, hb);

 ClearCommandPending();
 TriggerIRQ(HIRQ_CMOK | SWResetHIRQDeferred);
 SWResetHIRQDeferred = 0;
}

static void BasicResults(uint32_t res0, uint32_t res1, uint32_t res2, uint32_t res3)
{
 SetResultsRead(false);
 SetResults(res0, res1, res2, res3);

 ClearCommandPending();
 TriggerIRQ(HIRQ_CMOK | SWResetHIRQDeferred);
 SWResetHIRQDeferred = 0;
}

//
// Should be closer to 600, but 500 is good enough for Magical Drop 3's intro, so
// be more conservative to reduce the probability of breaking a game due
// to CPU timing emulation deficiencies.
//
enum { SeekCPIUpdateDelay = 500 };

static void SeekStart1(void)
{
 if(CurPlayStart & 0x800000)
 {
  int32_t fad_target = CurPlayStart & 0x7FFFFF;
  int32_t tt = 1;

  if(fad_target < 150)
   fad_target = 150;
  else if(fad_target >= (150 + (int32_t)toc.tracks[100].lba))
   fad_target = 150 + toc.tracks[100].lba;

  for(int32_t track = 1; track <= 100; track++)
  {
   if(!toc.tracks[track].valid)
    continue;

   if(fad_target < (150 + (int32_t)toc.tracks[track].lba))
    break;

   tt = track;
  }

  CurPosInfo.tno = (tt == 100) ? 0xAA : tt;
  CurPosInfo.idx = 1;
  CurPosInfo.fad = fad_target;
  CurPosInfo.rel_fad = fad_target - (150 + toc.tracks[tt].lba);
  CurPosInfo.ctrl_adr = (toc.tracks[tt].control << 4) | (toc.tracks[tt].adr << 0);
 }
 else
 {
  int32_t track_target = (CurPlayStart >> 8) & 0xFF;
  int32_t index_target = CurPlayStart & 0xFF;

  if(track_target > toc.last_track)
   track_target = toc.last_track;
  else if(track_target < toc.first_track)
   track_target = toc.first_track;

  if(index_target < 1)
   index_target = 1;
  else if(index_target > 99)
   index_target = 99;

  CurPosInfo.tno = track_target;
  CurPosInfo.idx = index_target;
  CurPosInfo.fad = 150 + toc.tracks[track_target].lba;
  CurPosInfo.rel_fad = 0;
  CurPosInfo.ctrl_adr = (toc.tracks[track_target].control << 4) | (toc.tracks[track_target].adr << 0);
 }
}

static void SeekStart2(int delay_sub)
{
 CurPosInfo.status = STATUS_BUSY;
 CurPosInfo.is_cdrom = false;
 CurPosInfo.repcount = PlayRepeatCounter & 0xF;
 DrivePhase = DRIVEPHASE_SEEK_START3;

#ifdef CD_SRC_FW
 src_hint(CurPosInfo.fad - 150);	// CD_SRC_FW: Mednafen's CDIF_HintReadSector: the source fetches the target now
#endif
 // (CDIF_HintReadSector: the sector engine has no cache)

 DriveCounter = (256000 - delay_sub);
 SeekIndexPhase = 0;
}

static void ForceCompletePendingSeekStartup(void)
{
 // Don't interrupt an earlier seek's startup.
 // TODO: Test to see if we should emulate it differently(e.g. giving an error, or delaying
 //       command execution).
 if(DrivePhase == DRIVEPHASE_SEEK_START1)
 {
  SeekStart1();
  SeekStart2(0);
 }
 else if(DrivePhase == DRIVEPHASE_SEEK_START2)
  SeekStart2(0);
}

static void StartSeek(const uint32_t cmd_target, const uint32_t cur_play_end, const uint32_t cur_play_repeat, const uint32_t play_end_irq_type, const bool no_pickup_change)
{
 if(!Cur_CDIF)
  return;

 ForceCompletePendingSeekStartup();
 //
 //
 //
 PlayRepeatCounter = 0;

 if(!no_pickup_change)
  ClearPendingSec();
 //
 //
 CurPlayStart = cmd_target;
 CurPlayEnd = cur_play_end;
 CurPlayRepeat = cur_play_repeat;
 PlayEndIRQType = play_end_irq_type;
 //
 //
 if(no_pickup_change)
 {
  if(DrivePhase == DRIVEPHASE_PLAY && ScanMode < 0)
  {
   // Maybe stop scanning?  or before the if(no_pickup_change)...
   return;
  }
 }

 ScanMode = -1;

 CurPosInfo.status = STATUS_BUSY;
 DrivePhase = no_pickup_change ? DRIVEPHASE_SEEK_START2 : DRIVEPHASE_SEEK_START1;
 PeriodicIdleCounter = PeriodicIdleCounter_Reload;
 DriveCounter = SeekCPIUpdateDelay;
}

static void StartScan(bool mode)
{
 if(!Cur_CDIF)
  return;

 ForceCompletePendingSeekStartup();
 //
 //
 //
 ClearPendingSec();
 PlaySectorProcessed = false;

 ScanMode = mode;
 ScanCounter = 0;

 CurPosInfo.status = STATUS_BUSY;
 CurPlayRepeat = 0;
 PeriodicIdleCounter = PeriodicIdleCounter_Reload;

 if(DrivePhase != DRIVEPHASE_PLAY)
 {
  DrivePhase = DRIVEPHASE_SEEK_START2;
  DriveCounter = SeekCPIUpdateDelay;
 }
}

static bool CheckEndMet(void)
{
 bool end_met = (CurPosInfo.tno == 0xAA);

 if(CurPlayEnd != 0)
 {
  if(CurPlayEnd & 0x800000)
   end_met |= (CurPosInfo.fad >= (CurPlayEnd & 0x7FFFFF));
  else
  {
   const unsigned end_track = ((unsigned)(toc.last_track) < (unsigned)(((unsigned)(toc.first_track) > (unsigned)((CurPlayEnd >> 8) & 0xFF) ? (unsigned)(toc.first_track) : (unsigned)((CurPlayEnd >> 8) & 0xFF))) ? (unsigned)(toc.last_track) : (unsigned)(((unsigned)(toc.first_track) > (unsigned)((CurPlayEnd >> 8) & 0xFF) ? (unsigned)(toc.first_track) : (unsigned)((CurPlayEnd >> 8) & 0xFF))));
   const unsigned end_index = ((unsigned)(99) < (unsigned)(((unsigned)(1) > (unsigned)(CurPlayEnd & 0xFF) ? (unsigned)(1) : (unsigned)(CurPlayEnd & 0xFF))) ? (unsigned)(99) : (unsigned)(((unsigned)(1) > (unsigned)(CurPlayEnd & 0xFF) ? (unsigned)(1) : (unsigned)(CurPlayEnd & 0xFF))));

   end_met |= (CurPosInfo.tno > end_track) || (CurPosInfo.tno == end_track && CurPosInfo.idx > end_index);
  }
 }

 //
 // Steam Heart's, it's always Steam Heart's...
 //
 if(CurPlayStart & 0x800000)
 {
  end_met |= (CurPosInfo.fad < (CurPlayStart & 0x7FFFFF));
 }
 else
 {
  const unsigned start_track = ((unsigned)(toc.last_track) < (unsigned)(((unsigned)(toc.first_track) > (unsigned)((CurPlayStart >> 8) & 0xFF) ? (unsigned)(toc.first_track) : (unsigned)((CurPlayStart >> 8) & 0xFF))) ? (unsigned)(toc.last_track) : (unsigned)(((unsigned)(toc.first_track) > (unsigned)((CurPlayStart >> 8) & 0xFF) ? (unsigned)(toc.first_track) : (unsigned)((CurPlayStart >> 8) & 0xFF))));
  //const unsigned start_index = ((unsigned)(99) < (unsigned)(((unsigned)(1) > (unsigned)(CurPlayStart & 0xFF) ? (unsigned)(1) : (unsigned)(CurPlayStart & 0xFF))) ? (unsigned)(99) : (unsigned)(((unsigned)(1) > (unsigned)(CurPlayStart & 0xFF) ? (unsigned)(1) : (unsigned)(CurPlayStart & 0xFF))));

  end_met |= (CurPosInfo.tno < start_track); //|| (CurPosInfo.tno == start_track && CurPosInfo.idx < start_index);
 }

 return end_met;
}

static void CheckBufPauseResume(void)
{
 if(DrivePhase == DRIVEPHASE_PAUSE)
 {
  const bool end_met = CheckEndMet();

  if(!end_met && FreeBufferCount)
  {
   SecPreBuf_In = false;
   CurPosInfo.status = STATUS_BUSY;
   DrivePhase = DRIVEPHASE_SEEK_START2;
   DriveCounter = SeekCPIUpdateDelay;
   PeriodicIdleCounter = PeriodicIdleCounter_Reload;
  }
 }
}

/* Was `template<unsigned sample_shift = 0> static INLINE void
 * BufferCDDA(const uint8_t* inbuf)` in the C++ form.  Two callsites
 * (DRIVEPHASE_PLAY in Drive_Run) instantiate with sample_shift=2
 * and sample_shift=0; both fire at 75 Hz so the shift-by-variable
 * costs nothing measurable vs the C++ shift-by-constant.  Same
 * runtime-parameter pattern used for every other template
 * conversion in this tree. */
// the sector being read (SecPrePage) joins the CD-DA queue, which then owns the page
static INLINE void BufferCDDA(unsigned sample_shift)
{
 unsigned count, n;

 CDDA_Reclaim();
 count = CDDA_Count();

 if(!count && CDDA_Push(0, CDDABuf_PrefillCount, 0, true))
  count = CDDABuf_PrefillCount;

 n = (count + 588 > CDDABuf_MaxCount) ? CDDABuf_MaxCount - count : 588;
 if(n && PagePoolN && CDDA_Push(SecPrePage, n, sample_shift, false))
  SecPrePage = PagePool[--PagePoolN];
}

// the sector engine has the sector being read in its page: take its header bytes once (bytes 12-19 = page words
// 6-9, which the engine writes for data sectors too)
static INLINE bool SecPreReady(void)
{
#ifdef CD_SRC_FW
 if(src_pending())		// CD_SRC_FW: not in the sector engine yet (an APF read is running)
 {
  src_poll();
  return false;
 }
#endif
 if(IO_FLAGS & F_SEC_BUSY)
  return false;
 if(!SecPreHdrValid)
 {
  const uint32_t w = page_word(SecPrePage) + 6;
  for(unsigned i = 0; i < 4; i++)
  {
   const uint16_t v = cd_rd16(w + i);
   SecPreHdr[2 * i + 0] = v >> 8;
   SecPreHdr[2 * i + 1] = v;
  }
  SecPreHdrValid = true;
 }
 return true;
}

// data sectors: the 12 sync bytes are not written (the CD block firmware's DMA starts after them)
static void SecPreRead(int32_t lba, bool data)
{
#ifdef CD_SRC_FW
 SecPrePage = src_read(lba, SecPrePage | (data ? 0x100 : 0));	// CD_SRC_FW: the source puts it into the page (cd_src.c)
#else
 IO_SEC_PAGE = SecPrePage | (data ? 0x100 : 0);
 IO_SEC_LBA = (uint32_t)lba & 0xFFFFFF;
#endif
 SecPreHdrValid = false;
}

static void Drive_Run(int32_t clocks)
{
  DriveCounter -= clocks;
  PeriodicIdleCounter -= clocks;
  while(DriveCounter <= 0)
  {
   switch(DrivePhase)
   {
    case DRIVEPHASE_EJECTED0:
	memset(TOC_Buffer, 0xFF, sizeof(TOC_Buffer));	// TODO: confirm 0xFF(or 0x00?)

	// TODO: Check DrivePhase and these vars in command processing.
	AuthDiscType = 0x00;
	FileInfoValid = false;
	RootDirInfoValid = false;

        CurPosInfo.status = STATUS_OPEN;
	CurPosInfo.fad = 0xFFFFFF;
	CurPosInfo.rel_fad = 0xFFFFFF;
	CurPosInfo.ctrl_adr = 0xFF;
	CurPosInfo.idx = 0xFF;
	CurPosInfo.tno = 0xFF;
	CurPosInfo.is_cdrom = true;
	CurPosInfo.repcount = 0x7F;
	TriggerIRQ(HIRQ_DCHG);

	DrivePhase = DRIVEPHASE_EJECTED1;
	DriveCounter = 4000;
	break;

    case DRIVEPHASE_EJECTED1:
	TriggerIRQ(HIRQ_EFLS);
	DrivePhase = DRIVEPHASE_EJECTED_WAITING;
	DriveCounter = 1;
	break;

    case DRIVEPHASE_EJECTED_WAITING:
	if(Cur_CDIF)
	{
         CurPosInfo.status = STATUS_BUSY;
	 DrivePhase = DRIVEPHASE_STARTUP;
	 DriveCounter = (1 * 44100 * 256);
	}
	else
	 DriveCounter = 1000;
	
	break;

    case DRIVEPHASE_STARTUP:
	TranslateTOC();
	//
	//
	//
	//
        StartSeek(0x800096, 0x800000, 0, 0, false);
	break;

    case DRIVEPHASE_STOPPED:
	CurPosInfo.status = STATUS_STANDBY;
	DriveCounter += 2000;
	break;

    case DRIVEPHASE_SEEK_START1:
	SeekStart1();
	// no break
    case DRIVEPHASE_SEEK_START2:
	SeekStart2(SeekCPIUpdateDelay);
	break;

    case DRIVEPHASE_SEEK_START3:
	//
	// TODO: Motor spinup from stopped state time penalty?
	//
	{
	 int32_t seek_time;
	 int32_t fad_delta;

	 fad_delta = CurPosInfo.fad - CurSector;

	 seek_time = 12 * (44100 * 256) / 150;
	 seek_time += abs(fad_delta) * ((fad_delta < 0) ? 28 : 26);
	 seek_time += (fad_delta < 0 || fad_delta >= 150) ? (44100 * 256) / 150 : 0;

	 CurPosInfo.status = STATUS_SEEK;
	 DrivePhase = DRIVEPHASE_SEEK;
	 DriveCounter += seek_time;
	 CurSector = CurPosInfo.fad;
	 SubQBuf_Safe_Valid = false;
	}
	break;

    case DRIVEPHASE_SEEK:
	//
	// Extremely crude approximation.
	//
	{
	 uint8_t q[0xC];
         const bool old_safe_valid = SubQBuf_Safe_Valid;

	 if(MakeSubQ(CurSector - 150, q))
	  DecodeSubQ(q);

	 if(!SubQBuf_Safe_Valid)
         {
	  CurSector++;
	  DriveCounter += ((44100 * 256) / 150);
         }
	 else
	 {
	  bool index_ok = true;

	  if(!old_safe_valid)
	   CurSector = CurPosInfo.fad;

	  if(!(CurPlayStart & 0x800000))
	  {
	   const unsigned start_track = ((unsigned)(toc.last_track) < (unsigned)(((unsigned)(toc.first_track) > (unsigned)((CurPlayStart >> 8) & 0xFF) ? (unsigned)(toc.first_track) : (unsigned)((CurPlayStart >> 8) & 0xFF))) ? (unsigned)(toc.last_track) : (unsigned)(((unsigned)(toc.first_track) > (unsigned)((CurPlayStart >> 8) & 0xFF) ? (unsigned)(toc.first_track) : (unsigned)((CurPlayStart >> 8) & 0xFF))));
	   const unsigned start_index = ((unsigned)(99) < (unsigned)(((unsigned)(1) > (unsigned)(CurPlayStart & 0xFF) ? (unsigned)(1) : (unsigned)(CurPlayStart & 0xFF))) ? (unsigned)(99) : (unsigned)(((unsigned)(1) > (unsigned)(CurPlayStart & 0xFF) ? (unsigned)(1) : (unsigned)(CurPlayStart & 0xFF))));
	   const unsigned sq_idx = BCD_to_U8(SubQBuf_Safe[0x2]);
	   const unsigned sq_tno = (SubQBuf_Safe[0x1] >= 0xA0) ? SubQBuf_Safe[0x1] : BCD_to_U8(SubQBuf_Safe[0x1]);

	   if(sq_idx < start_index && sq_tno <= start_track)
	   {
	    if(SeekIndexPhase == 2)
	    {
	     index_ok = false;
	     CurSector += 4;
	     DriveCounter += ((44100 * 256) / 150);
	    }
	    else
	    {
	     index_ok = false;
	     CurSector += 128;
	     DriveCounter += ((44100 * 256) / 150);
	     SeekIndexPhase = 1;
	    }
	   }
	   else
	   {
	    if(SeekIndexPhase == 1)
	    {
	     index_ok = false;
	     CurSector -= 124;
	     DriveCounter += ((44100 * 256) / 150);
	     SeekIndexPhase = 2;
	    }
	   }
	  }

	  if(index_ok)
	  {
	   PlaySectorProcessed = false;
	   DrivePhase = DRIVEPHASE_PLAY;
	   DriveCounter += (44100 * 256) / ((SubQBuf_Safe[0] & 0x40) ? 150 : 75);
	  }
         }
        }
	break;

    case DRIVEPHASE_PLAY:
	// (the drive waits here for the sector being read to arrive)
	if(SecPreBuf_In > 0 && !SecPreReady())
	 goto DriveWait;
	if(SecPreBuf_In > 0)
	{
	 if(ScanMode >= 0)
	 {
	  if(!(SubQBuf_Safe[0] & 0x40))
	   BufferCDDA(2);

	  CurPosInfo.is_cdrom = false;
	  SecPreBuf_In = false;
	 }
	 else if(!(SubQBuf_Safe[0] & 0x40))
	 {
	  BufferCDDA(0);

	  CurPosInfo.is_cdrom = false;
	  SecPreBuf_In = false;
	 }
	 else
	 {
	  CurPosInfo.is_cdrom = true;

	  //assert(edc_check(SecPreBuf, false));

	  if(FreeBufferCount > 0)
          {
	   if(AuthDiscType)
	   {
	    const uint8_t bfi = Buffer_Allocate(false);
	    const uint8_t pg = Buffers[bfi].Page;

	    Buffers[bfi].Page = SecPrePage;
	    SecPrePage = pg;
	    memcpy(Buffers[bfi].Hdr, SecPreHdr, 8);

	    LastBufDest = FilterBuf(CDDevConn, bfi);
	   }
	   //
	   SecPreBuf_In = false;
	   TriggerIRQ(HIRQ_CSCT);
	   if(FreeBufferCount == 0)
	    TriggerIRQ(HIRQ_BFUL);
          }
	 }

	 if(!SecPreBuf_In)
	 {
	  PlaySectorProcessed = true;

	  if(ScanMode >= 0)
	  {
	   ScanCounter += (SubQBuf_Safe[0] & 0x40) ? 1 : 2;
	   if(ScanCounter >= 6)
           {
	    ScanCounter = 0;

	    if(!ScanMode)
	     CurSector += 102 + (((uint64_t)1773936 * CurSector + ((uint64_t)1 << 31)) >> 32);
	    else
	     CurSector -= ((uint32_t)(CurSector) < (uint32_t)(104 + (((uint64_t)2180000 * CurSector + ((uint64_t)1 << 31)) >> 32)) ? (uint32_t)(CurSector) : (uint32_t)(104 + (((uint64_t)2180000 * CurSector + ((uint64_t)1 << 31)) >> 32)));

#ifdef CD_SRC_FW
	    src_hint(CurSector - 150);	// CD_SRC_FW: Mednafen's CDIF_HintReadSector at the scan's jump
#else
	    ;
#endif
           }
           else
	    CurSector++;
	  }
	  else
	   CurSector++;
	 }
	} // end if(SecPreBuf_In > 0)
	// Fallthrough:
    case DRIVEPHASE_PAUSE:
        PeriodicIdleCounter = 17712;

	if(SecPreBuf_In) { }
	else
	{
	 // the sector engine reads one sector at a time
	 if(IO_FLAGS & F_SEC_BUSY)
	  goto DriveWait;
	 {
	  uint8_t q[0xC];
	  SecPreRead(CurSector - 150, MakeSubQ(CurSector - 150, q) && (q[0] & 0x40));
	 }
	 SecPreBuf_In = true;

	 // TODO:(maybe pointless...)
	 //if(SubQBuf_Safe[0] & 0x40)
         // CurPosInfo.fad = SECTOR HEADER
         //else
	 // CurPosInfo.fad = SUBQ STUFF
	 CurPosInfo.fad = CurSector;	
	 if(MakeSubQ(CurSector - 150, SecPreQ) && DecodeSubQ(SecPreQ))
	 {
	  CurPosInfo.rel_fad = (BCD_to_U8(SubQBuf[0x3]) * 60 + BCD_to_U8(SubQBuf[0x4])) * 75 + BCD_to_U8(SubQBuf[0x5]);
	  CurPosInfo.tno = (SubQBuf[0x1] >= 0xA0) ? SubQBuf[0x1] : BCD_to_U8(SubQBuf[0x1]);
	  CurPosInfo.idx = BCD_to_U8(SubQBuf[0x2]);
	 }
	}

	DriveCounter += (44100 * 256) / ((SubQBuf_Safe[0] & 0x40) ? 150 : 75);
	break;
   }
  }
  DriveWait:;

  if(PeriodicIdleCounter <= 0)
  {
   PeriodicIdleCounter = PeriodicIdleCounter_Reload;

   //
   //
   //
   if(SecPreBuf_In && (DrivePhase == DRIVEPHASE_PLAY || DrivePhase == DRIVEPHASE_PAUSE))
   {
    const bool end_met = CheckEndMet();

    if(DrivePhase == DRIVEPHASE_PAUSE)
    {
     SecPreBuf_In = false;

     if(PauseCounter == 1)
     {
      CurPosInfo.status = STATUS_PAUSE;

      if(end_met && PlayEndIRQType)
      {
       // Don't generate IRQ if we've repeated and there hasn't been a non-end_met sector since.
       if(!(PlayRepeatCounter & 0x80))
        TriggerIRQ(PlayEndIRQType & 0xFFFF);	// May not be right for EFLS with Read File, maybe EFLS is only triggered after the buffer is written?
       PlayEndIRQType = 0;
      }
      PauseCounter = -1;
     }
     else if(PauseCounter == -1)
     {
      CurPosInfo.status = STATUS_PAUSE;

      if(!end_met && FreeBufferCount)
      {
       CurPosInfo.status = STATUS_BUSY;
       DrivePhase = DRIVEPHASE_SEEK_START2;
       DriveCounter = SeekCPIUpdateDelay;
      }
     }
     else
      PauseCounter++;
    }
    else if(end_met)
    {
     SecPreBuf_In = false;
     if(PlayRepeatCounter >= CurPlayRepeat)
     {
      CurSector = CurPosInfo.fad;
      CurPosInfo.status = STATUS_BUSY;
      DrivePhase = DRIVEPHASE_PAUSE;
      PauseCounter = PlayEndIRQType ? 0 : 1;
     }
     else
     {
      if(PlayRepeatCounter < 0xE)
       PlayRepeatCounter++;

      PlayRepeatCounter |= 0x80;
      //
      SeekStart1();
      SeekStart2(0);
     }
    }
    else if((SubQBuf_Safe[0] & 0x40) && !FreeBufferCount)
    {
     SecPreBuf_In = false;
     CurPosInfo.status = STATUS_BUSY;
     DrivePhase = DRIVEPHASE_PAUSE;
     PauseCounter = 0;
    }
    else
    {
     PlayRepeatCounter &= ~0x80;

     if(PlaySectorProcessed)
     {
      CurPosInfo.status = (ScanMode >= 0) ? STATUS_SCAN : STATUS_PLAY;
      PlaySectorProcessed = false;
     }
    }
   }
   //
   //
   //
   PeriodicIdleCounter = PeriodicIdleCounter_Reload;

   if(ResultsRead())
   {
    if(FLS.Active && FLS.DoAuth)
    {
     SetResults(0x00FF | (STATUS_PERIODIC << 8), 0xFFFF, 0xFFFF, 0xFFFF);
    }
    else
     MakeReport(false, STATUS_PERIODIC);
   }

   // FIXME: Other ADR types, and correct handling when in STANDBY/STOPPED state?
   SubCodeQBuf[0] = CurPosInfo.ctrl_adr;
   SubCodeQBuf[1] = CurPosInfo.tno;
   SubCodeQBuf[2] = CurPosInfo.idx;
   SubCodeQBuf[3] = CurPosInfo.rel_fad >> 16;
   SubCodeQBuf[4] = CurPosInfo.rel_fad >> 8;
   SubCodeQBuf[5] = CurPosInfo.rel_fad >> 0;
   SubCodeQBuf[6] = 0;	// ? OxFF in some cases...
   SubCodeQBuf[7] = CurPosInfo.fad >> 16;
   SubCodeQBuf[8] = CurPosInfo.fad >> 8;
   SubCodeQBuf[9] = CurPosInfo.fad >> 0;

   TriggerIRQ(HIRQ_SCDQ);
  }
}

static void ClearPendingSec(void)
{
 //PlayEndIRQPending = 0;
 PlayEndIRQType = 0;

 SecPreBuf_In = false;
#ifdef CD_SRC_FW
 src_cancel();
#endif

 CDDA_Flush();
}

// Run for `clocks` (44100 x 256 Hz) of time
static void CDB_Run(int32_t clocks)
{
 {
  Drive_Run(clocks);

  //
  //
  //
  CommandClockCounter += clocks;
  switch(CommandPhase + CommandPhaseBias)
  {
   for(;;)
   {
    default:
    case __COUNTER__:

    while(!CommandPending)
    {
     if(FLS_Run())
     {
      CMD_EAT_CLOCKS(60);
      TriggerIRQ(HIRQ_EFLS);
      CMD_EAT_CLOCKS(60);
     }
     else
     {
      CMD_YIELD;
     }
    }
    //
    //
    for(unsigned i = 0; i < 4; i++)
     CTR.CD[i] = IO_CR(i);

    CTR.Command = CTR.CD[0] >> 8;
    //
    //
    CMD_EAT_CLOCKS(84); //90);

    if(FLS.Active && FLS.DoAuth)
    {
     BasicResults(0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF);
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_CDSTATUS) //	= 0x00,
    {
     CDStatusResults(false, 0);
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_HWINFO) //	= 0x01,
    {
     // CR2 high byte is the hardware flag word; bit 1 reports an
     // installed MPEG card.  CR3 reports whether that card has been
     // authenticated (see COMMAND_AUTH_DEVICE with CR2 == 1).  Both are
     // zero when no card is configured, which preserves the stock
     // no-card results exactly.
     // CDC_HFLAG_MPEG in SBL 6.01's sega_cdc.h; the hardware flag is
     // CR2's high byte, so the bit lands at 0x0200.
     const uint16_t mpeg_hwflag = 0x0000;	// no MPEG card
     const uint16_t mpeg_auth   = 0x0000;

     // (HLE: the values the MiSTer core's CD block, firmware 1.05 with its drive link, reports: hardware version
     // 1, drive version 0; Mednafen has 0x0002 and 0x0600 from real hardware)
     BasicResults(MakeBaseStatus(false, 0) << 8,
		  0x0001 | mpeg_hwflag,
		  mpeg_auth,
		  0x0000); // TODO: Before INIT: 0xFF00;
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_TOC) //	= 0x02,
    {
     if(DrivePhase == DRIVEPHASE_STARTUP || DT.Active)
      CDStatusResults(false, STATUS_WAIT);
     else
     {
      BasicResults(MakeBaseStatus(false, STATUS_DTREQ) << 8, 0xCC, 0, 0);

      //
      //
      DT.BufCount = 1;
      DT.BufList[0] = 0xFF;

      DT.Writing = false;
      DT.NeedBufFree = false;
      DT.Active = true;
      DT_StartRaw(TOC_Buffer, 0xCC);
      //
      //
      //
      CMD_EAT_CLOCKS(128);
      TriggerIRQ(HIRQ_DRDY);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_SESSINFO) //	= 0x03,
    {
     if(DrivePhase == DRIVEPHASE_STARTUP)
      CDStatusResults(false, STATUS_WAIT);
     else
     {
      const unsigned sess = CTR.CD[0] & 0xFF;
      uint32_t fad;
      uint8_t rsw;

      if(!sess)
      {
       fad = 150 + toc.tracks[100].lba;
       rsw = 0x01; // Session count;
      }
      else if(sess <= 0x01)
      {
       fad = 0;
       rsw = sess;
      }
      else
      {
       fad = 0xFFFFFF;
       rsw = 0xFF;
      }

      BasicResults(MakeBaseStatus(false, 0) << 8, 0, (rsw << 8) | (fad >> 16), fad);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_INIT) //		= 0x04,
    {
     ClearPendingSec();
     CurPlayEnd = 0x800000;
     CurPlayRepeat = 0;
     CurPosInfo.status = STATUS_BUSY;

     CDStatusResults(false, 0x00);

     //
     if(CTR.CD[0] & 0x01)	// Software reset of CD block
     {
      CMD_EAT_CLOCKS(180);
      SWResetPending = true;

      //
      // If a new command was issued in the time we spent in CMD_EAT_CLOCKS(), process it before we do the software reset
      // down below.
      //
      if(CommandPending)
       continue;
     }

     // TODO TODO TODO
     //  & 0x02;	// Decode subcode RW
     //  & 0x04;	// Ignore mode2 subheader?
     //  & 0x08;	// Retry form2 read
     //  & 0x30;	// CD read speed(unused?)
     //  & 0x80;	// No change?
    }
/*
    //
    //
    //
    else if(CTR.Command == COMMAND_OPEN) //		= 0x05,
    {
    }
*/
    //
    //
    //
    else if(CTR.Command == COMMAND_END_DATAXFER) //	= 0x06,
    {
     if(DT.Active)
     {
      const uint32_t total = DT_Stop();

      DT.Active = false;

      BasicResults((MakeBaseStatus(false, 0) << 8) | (total >> 16), total, 0, 0);

      if(DT.Writing)
      {
       Filter_DisconnectInput(DT.FNum);

       for(unsigned i = 0; i < DT.BufCount; i++)
       {
	Buffer_ReadHdr(DT.BufList[i]);
	FilterBuf(DT.FNum, DT.BufList[i]);
       }

       CMD_EAT_CLOCKS(270);
       if(FreeBufferCount == 0)
        TriggerIRQ(HIRQ_BFUL);
       TriggerIRQ(HIRQ_EHST);
      }
      else
      {
       if(DT.NeedBufFree)
       {
        for(unsigned i = 0; i < DT.BufCount; i++)
        {
 	 Buffer_Free(DT.BufList[i]);
        }
       }

       if(DT.BufList[0] < NumBuffers)	// Only trigger EHST HIRQ after transferring partition/sector buffer data.
       {
        CMD_EAT_CLOCKS(130);
        TriggerIRQ(HIRQ_EHST);
       }
      }
      //
      //
      CheckBufPauseResume();
     }
     else
      BasicResults((MakeBaseStatus(false, 0) << 8) | 0xFF, 0xFFFF, 0, 0);
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_PLAY) //		= 0x10,
    {
     uint32_t cmd_psp = ((CTR.CD[0] & 0xFF) << 16) | CTR.CD[1];
     uint32_t cmd_pep = ((CTR.CD[2] & 0xFF) << 16) | CTR.CD[3];
     uint8_t pm = CTR.CD[2] >> 8;

     if(cmd_psp == 0xFFFFFF)
      cmd_psp = PlayCmdStartPos;

     if(cmd_pep == 0xFFFFFF)
      cmd_pep = PlayCmdEndPos;
     else if((cmd_psp & 0x800000) && (cmd_pep & 0x800000))
      cmd_pep = 0x800000 | ((cmd_psp + cmd_pep) & 0x7FFFFF);

     if(((cmd_psp ^ cmd_pep) & 0x800000) && cmd_pep != 0)
      CDStatusResults(true, 0);
     else
     {
      PlayCmdStartPos = cmd_psp;
      PlayCmdEndPos = cmd_pep;

      if(!(pm & 0x70))
       PlayCmdRepCnt = pm & 0x0F;
      //
      CurPosInfo.status = STATUS_BUSY;	// Happens even if (PlayMode & 0x80)...
      CDStatusResults(false, 0);
      //
      //
      StartSeek(PlayCmdStartPos, PlayCmdEndPos, PlayCmdRepCnt, HIRQ_PEND, (bool)(pm & 0x80));
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_SEEK) //		= 0x11,
    {
     CurPosInfo.status = STATUS_BUSY;
     CDStatusResults(false, 0);
     //
     //
     const uint32_t cmd_sp = ((CTR.CD[0] & 0xFF) << 16) | CTR.CD[1];

     if(!cmd_sp)	// Stop
     {
      ClearPendingSec();
      CurPosInfo.is_cdrom = true;
      CurPosInfo.repcount = 0x7F;
      CurPosInfo.status = STATUS_BUSY;
      CurPosInfo.fad = 0xFFFFFF;
      CurPosInfo.rel_fad = 0xFFFFFF;
      CurPosInfo.ctrl_adr = 0xFF;
      CurPosInfo.idx = 0xFF;
      CurPosInfo.tno = 0xFF;

      DrivePhase = DRIVEPHASE_STOPPED;
      DriveCounter = 380000;
     }
     else if(cmd_sp == 0xFFFFFF) // Pause
     {
      if(DrivePhase == DRIVEPHASE_STOPPED)	// TODO: Test
      {
       StartSeek(0x800096, 0x800000, 0, 0, false);
      }

      SecPreBuf_In = -abs(SecPreBuf_In);
      PlayEndIRQType = 0;
      CurPlayEnd = 0x800000;
      CurPlayRepeat = 0;
     }
     else
     {
      StartSeek(cmd_sp, 0x800000, 0, 0, false);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_SCAN) //		= 0x12,
    {
     uint8_t dir = CTR.CD[0] & 0xFF;

     if(dir >= 0x02)
      CDStatusResults(true, 0);
     else
     {
      CurPosInfo.status = STATUS_BUSY;
      CDStatusResults(false, 0);

      StartScan(dir);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_SUBCODE) //	= 0x20,
    {
     if(DT.Active)
      CDStatusResults(false, STATUS_WAIT);
     else
     {
      uint8_t type;

      type = CTR.CD[0] & 0xFF;

      if(type >= 0x02)
       CDStatusResults(true, 0);
      else
      {
       if(type == 0) // Q (TODO: ADR other than 0x1)
       {
        BasicResults(MakeBaseStatus(false, STATUS_DTREQ) << 8, 0x05, 0, 0);
        DT.BufList[0] = 0xFE;
        DT_StartRaw(SubCodeQBuf, 0x05);
       }
       else	// R-W	(TODO)
       {
        BasicResults(MakeBaseStatus(false, STATUS_DTREQ) << 8, 0x0C, 0, 0);

	for(unsigned i = 0; i < 24; i++)
	 SubCodeRWBuf[i] = 0xFF;

        DT.BufList[0] = 0xFD;
        DT_StartRaw(SubCodeRWBuf, 0x0C);
       }

       DT.BufCount = 1;

       DT.Writing = false;
       DT.NeedBufFree = false;
       DT.Active = true;
       //
       //
       //
       CMD_EAT_CLOCKS(128);
       TriggerIRQ(HIRQ_DRDY);
      }
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_AUTH_DEVICE)
    {
     uint8_t fnum;

     // CR2 == 0x0001 authenticates the MPEG card rather than the disc.
     // It is unambiguous: a partition-0 disc auth uses CR2 == 0x0000,
     // and every other partition puts its number in the high byte.
     fnum = (CTR.CD[2] >> 8);

     if(CTR.CD[2] == 0x0001)
     {
      // (no MPEG card: it does not authenticate)
      CDStatusResults(false, 0);
      TriggerIRQ(HIRQ_MPED);
     }
     else if(fnum >= 0x18)
      CDStatusResults(true, 0);
     else if(FLS.Active)
      CDStatusResults(false, STATUS_WAIT);
     else
     {
      CDStatusResults(false, 0);
      //
      //
      //
      // TODO: Check DrivePhase == DRIVEPHASE_STARTUP
      if(!(toc.tracks[1].control & SUBQ_CTRLF_DATA))	// Audio CD(CD block must not like PCE/PC-FX ;))
      {
       AuthDiscType = 0x01;
       CMD_EAT_CLOCKS(200);
       TriggerIRQ(HIRQ_EFLS);
      }
      else
      {
       FLS.pnum = fnum;
       FLS.DoAuth = true;
       FLS.Active = true;
      }
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_AUTH)
    {
     if(CTR.CD[2])
      BasicResults(MakeBaseStatus(false, 0) << 8, 0, 0, 0);
     else if(FLS.Active && FLS.DoAuth)
      CDStatusResults(true, 0);
     else
      BasicResults(MakeBaseStatus(false, 0) << 8, AuthDiscType, 0, 0);
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_SET_CDDEVCONN) //	= 0x30,
    {
     #define fnum (CTR.CD[2] >> 8)

     if(fnum >= 0x18 && fnum != 0xFF)
      CDStatusResults(true, 0);
     else
     {
      SetCDDeviceConn(fnum);

      CDStatusResults(false, 0);

      CMD_EAT_CLOCKS(96);
      TriggerIRQ(HIRQ_ESEL);
     }
     #undef fnum
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_CDDEVCONN) //	= 0x31,
    {
     BasicResults((MakeBaseStatus(false, 0) << 8), 0, CDDevConn << 8, 0);
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_LASTBUFDST) //	= 0x32,
    {
     BasicResults(MakeBaseStatus(false, 0) << 8, 0, LastBufDest << 8, 0);
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_SET_FILTRANGE) //	= 0x40,
    {
     #define fnum (CTR.CD[2] >> 8)

     if(fnum >= 0x18)
      CDStatusResults(true, 0);
     else
     {
      //CMD_EAT_CLOCKS(30);
      {
       const uint32_t fad = ((CTR.CD[0] & 0xFF) << 16) | CTR.CD[1];
       const uint32_t range = ((CTR.CD[2] & 0xFF) << 16) | CTR.CD[3];

       Filter_SetRange(fnum, fad, range);

       CDStatusResults(false, 0);
      }
      CMD_EAT_CLOCKS(96); //211);
      TriggerIRQ(HIRQ_ESEL);
     }
     #undef fnum
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_FILTRANGE) //	= 0x41,
    {
     const unsigned fnum = CTR.CD[2] >> 8;

     if(fnum >= 0x18)
      CDStatusResults(true, 0);
     else
     {
      const uint32_t fad = Filters[fnum].FAD;
      const uint32_t range = Filters[fnum].Range;

      BasicResults((MakeBaseStatus(false, 0) << 8) | (fad >> 16),
		   fad,
		   (fnum << 8) | (range >> 16),
		   range);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_SET_FILTSUBHC) //	= 0x42,
    {
     #define fnum (CTR.CD[2] >> 8)

     if(fnum >= 0x18)
      CDStatusResults(true, 0);
     else
     {
      //CMD_EAT_CLOCKS(30);

      Filters[fnum].Channel = CTR.CD[0] & 0xFF;
      Filters[fnum].SubModeMask = CTR.CD[1] >> 8;
      Filters[fnum].CInfoMask = CTR.CD[1] & 0xFF;
      Filters[fnum].File = CTR.CD[2] & 0xFF;
      Filters[fnum].SubMode = CTR.CD[3] >> 8;
      Filters[fnum].CInfo = CTR.CD[3] & 0xFF;

      CDStatusResults(false, 0);

      CMD_EAT_CLOCKS(96); //211);
      TriggerIRQ(HIRQ_ESEL);
     }
     #undef fnum
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_FILTSUBHC) //	= 0x43,
    {
     const unsigned fnum = CTR.CD[2] >> 8;

     if(fnum >= 0x18)
      CDStatusResults(true, 0);
     else
     {
      const struct FilterS *f = &Filters[fnum];

      BasicResults((MakeBaseStatus(false, 0) << 8) | f->Channel,
		   (f->SubModeMask << 8) | f->CInfoMask,
		   (fnum << 8) | f->File,
		   (f->SubMode << 8) | f->CInfo);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_SET_FILTMODE) //	= 0x44,
    {
     #define fnum (CTR.CD[2] >> 8)

     if(fnum >= 0x18)
      CDStatusResults(true, 0);
     else
     {
      //CMD_EAT_CLOCKS(30);

      Filters[fnum].Mode = CTR.CD[0] & 0xFF;

      if(CTR.CD[0] & 0x80)
       Filter_ResetCond(fnum);

      CDStatusResults(false, 0);

      CMD_EAT_CLOCKS(96); //211);
      TriggerIRQ(HIRQ_ESEL);
     }
     #undef fnum
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_FILTMODE) //	= 0x45,
    {
     const unsigned fnum = CTR.CD[2] >> 8;

     if(fnum >= 0x18)
      CDStatusResults(true, 0);
     else
      BasicResults((MakeBaseStatus(false, 0) << 8) | Filters[fnum].Mode,
		   0,
		   fnum << 8,
		   0);
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_SET_FILTCONN) //	= 0x46,
    {
     #define fnum (CTR.CD[2] >> 8)
     #define fcflags (CTR.CD[0] & 0xFF)
     #define tconn (CTR.CD[1] >> 8)
     #define fconn (CTR.CD[1] & 0xFF)

     if(fnum >= 0x18 || ((fcflags & 0x1) && (tconn >= 0x18) && tconn != 0xFF) || ((fcflags & 0x2) && (fconn >= 0x18) && fconn != 0xFF))
      CDStatusResults(true, 0);
     else
     {
      //CMD_EAT_CLOCKS(41);

      if(fcflags & 0x1)
       Filter_SetTrueConn(fnum, tconn);

      if(fcflags & 0x2)
       Filter_SetFalseConn(fnum, fconn);

      CDStatusResults(false, 0);

      CMD_EAT_CLOCKS(96); //192 + ((fcflags & 0x1) ? 167 : 0) + ((fcflags & 0x2) ? 198 : 0));
      TriggerIRQ(HIRQ_ESEL);
     }
     #undef fconn
     #undef tconn
     #undef fcflags
     #undef fnum
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_FILTCONN) //	= 0x47,
    {
     const unsigned fnum = CTR.CD[2] >> 8;

     if(fnum >= 0x18)
      CDStatusResults(true, 0);
     else
     {
      const struct FilterS *f = &Filters[fnum];

      BasicResults((MakeBaseStatus(false, 0) << 8),
		   (f->TrueConn << 8) | f->FalseConn,
		   fnum << 8,
		   0);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_RESET_SEL) //	= 0x48,
    {
     unsigned rflags;

     rflags = CTR.CD[0] & 0xFF;

     if(!rflags)
     {
      unsigned pnum;

      pnum = CTR.CD[2] >> 8;

      if(pnum >= 0x18)
       CDStatusResults(true, 0);
      else
      {
       Partition_Clear(pnum);

       //CMD_EAT_CLOCKS(34);

       CDStatusResults(false, 0);
       //
       //
       //
       CMD_EAT_CLOCKS(150); //224);
       TriggerIRQ(HIRQ_ESEL);
       //
       //
       CheckBufPauseResume();
      }
     }
     else
     {
      CDStatusResults(false, 0);
      //
      //
      //
      ResetSelPending = rflags;
      //
      // TODO: Accurate timing(while not blocking other command execution and sector reading).
      CMD_EAT_CLOCKS((ResetSelPending & 0xAC) ? 400 : 300);

      //
      // Half-assed handling of goofy games(e.g. USA release of "Independence Day") that issue a Get CD Device Connection command
      // before the Reset Selector command resets it.
      //
      if((ResetSelPending & 0x3C) > 0x20 && CommandPending && (IO_CR(0) >> 8) == COMMAND_GET_CDDEVCONN)
       continue;
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_BUFSIZE) //	= 0x50,
    {
     BasicResults(MakeBaseStatus(false, 0) << 8,
		  FreeBufferCount,
		  0x18 << 8,
		  NumBuffers);
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_SECNUM) //	= 0x51,
    {
     const unsigned pnum = CTR.CD[2] >> 8;

     if(pnum >= 0x18)
     {
      CDStatusResults(true, 0);
     }
     else
     {
      BasicResults(MakeBaseStatus(false, 0) << 8,
		   0,
		   0,
		   Partitions[pnum].Count);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_CALC_ACTSIZE) //	= 0x52,
    {
     unsigned pnum;
     int offs, numsec;

     offs = CTR.CD[1];
     pnum = CTR.CD[2] >> 8;
     numsec = CTR.CD[3];

     if(pnum >= 0x18)
      CDStatusResults(true, 0);
     else
     {
      offs = CTR.CD[1];
      numsec = CTR.CD[3];

      if(offs == 0xFFFF)
       offs = Partitions[pnum].Count - 1;

      if(numsec == 0xFFFF)
       numsec = Partitions[pnum].Count - offs;

      if((DT.Active && DT.Writing) || numsec <= 0 || offs < 0 || (offs + numsec) > (int)Partitions[pnum].Count)
       CDStatusResults(false, STATUS_WAIT);
      else
      {
       CDStatusResults(false, 0);

       //
       {
        uint32_t tmp_accum = 0;
        for(int i = 0, bfi = Partition_GetBuffer(pnum, offs); i < numsec; i++, bfi = Buffers[bfi].Next)
	{
	 const uint8_t* const sd = Buffers[bfi].Hdr;

	 switch(GetSecLen)
	 {
	  default:
	  case SECLEN_2048:
	  	if((sd[3] == 0x2) && (sd[6] & 0x20))	// Mode 2 Form 2
		 tmp_accum += 1162;
		else	// M2F1 and Mode 1(weird tested inconsistency with Get Sector Data command, not that it probably matters)
	 	 tmp_accum += 1024;
		break;

	  case SECLEN_2336: tmp_accum += 1168; break;
	  case SECLEN_2340: tmp_accum += 1170; break;
	  case SECLEN_2352: tmp_accum += 1176; break;
	 }
	}
        CalcedActualSize = tmp_accum;
       }
       //
       CMD_EAT_CLOCKS(240);	// TODO: proper timing(can be surprisingly large for higher numsec)
       TriggerIRQ(HIRQ_ESEL);
      }
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_ACTSIZE) //	= 0x53,
    {
     BasicResults((MakeBaseStatus(false, 0) << 8) | (CalcedActualSize >> 16), CalcedActualSize, 0, 0);
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_SECINFO) //	= 0x54,
    {
     unsigned offs;
     unsigned pnum;

     offs = CTR.CD[1];
     pnum = CTR.CD[2] >> 8;

     // (HLE: a sector that is not there (yet) is WAIT, as the CD block firmware answers; Mednafen rejects)
     if(pnum >= 0x18)
      CDStatusResults(true, 0);
     else if((offs != 0xFFFF && offs >= Partitions[pnum].Count) || Partitions[pnum].Count == 0)
      CDStatusResults(false, STATUS_WAIT);
     else
     {
      const int bfi = ((offs == 0xFFFF) ? Partitions[pnum].LastBuf : Partition_GetBuffer(pnum, offs));
      const uint8_t* sd = Buffers[bfi].Hdr;
      uint32_t fad;
      uint8_t file = 0, chan = 0, submode = 0, cinfo = 0;

      fad = AMSF_to_ABA(BCD_to_U8(sd[0]), BCD_to_U8(sd[1]), BCD_to_U8(sd[2]));
      if(sd[3] == 0x2)
      {
       file = sd[4];
       chan = sd[5];
       submode = sd[6];
       cinfo = sd[7];
      }

      BasicResults((MakeBaseStatus(false, 0) << 8) | (fad >> 16),
		  fad,
		  (file << 8) | chan,
		  (submode << 8) | cinfo);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_EXEC_FADSRCH) //	= 0x55,
    {
     unsigned offs;
     unsigned pnum;
     uint32_t sfad;

     offs = CTR.CD[1];
     pnum = CTR.CD[2] >> 8;
     sfad = ((CTR.CD[2] & 0xFF) << 16) | CTR.CD[3];

     if(pnum >= 0x18 || (offs != 0xFFFF && offs >= Partitions[pnum].Count) || Partitions[pnum].Count == 0)
      CDStatusResults(true, 0);
     else
     {
      int counter;
      int effoffs, bfi;
      bool match_made;

      FADSearch.spos = 0xFFFF;
      FADSearch.pnum = pnum;
      FADSearch.fad = 0;

      counter = 0;
      effoffs = (offs == 0xFFFF) ? (Partitions[pnum].Count - 1) : offs;
      bfi = Partitions[pnum].FirstBuf;
      match_made = false;

      do
      {
       if(counter >= effoffs)
       {
        const uint8_t* sd = Buffers[bfi].Hdr;
        const uint32_t fad = AMSF_to_ABA(BCD_to_U8(sd[0]), BCD_to_U8(sd[1]), BCD_to_U8(sd[2]));

        if(fad <= sfad && fad >= (FADSearch.fad + match_made))
        {
         FADSearch.spos = counter;
         FADSearch.fad = fad;
         match_made = true;
        }
       }
       bfi = Buffers[bfi].Next;
       counter++;
      } while(bfi != 0xFF);

      CDStatusResults(false, 0);
      //
      //
      //
      CMD_EAT_CLOCKS(300);
      TriggerIRQ(HIRQ_ESEL);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_FADSRCH) //	= 0x56,
    {
     BasicResults(MakeBaseStatus(false, 0) << 8, FADSearch.spos, (FADSearch.pnum << 8) | (FADSearch.fad >> 16), FADSearch.fad);
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_SET_SECLEN) //	= 0x60,
    {
     const unsigned NewGetSecLen = (CTR.CD[0] & 0xFF);
     const unsigned NewPutSecLen = (CTR.CD[1] >> 8);
     const bool NewGetSecLenBad = NewGetSecLen != 0xFF && (NewGetSecLen < SECLEN__FIRST || NewGetSecLen > SECLEN__LAST);
     const bool NewPutSecLenBad = NewPutSecLen != 0xFF && (NewPutSecLen < SECLEN__FIRST || NewPutSecLen > SECLEN__LAST);

     if(NewGetSecLenBad || NewPutSecLenBad)
     {
      CDStatusResults(true, 0);
     }
     else
     {
      if(NewGetSecLen != 0xFF)
       GetSecLen = NewGetSecLen;

      if(NewPutSecLen != 0xFF)
       PutSecLen = NewPutSecLen;

      UpdateSecLen();

      CDStatusResults(false, 0);
      TriggerIRQ(HIRQ_ESEL);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_SECDATA || CTR.Command == COMMAND_DEL_SECDATA || CTR.Command == COMMAND_GETDEL_SECDATA) //	= 0x61, 0x62, 0x63
    {
     unsigned pnum;
     int offs, numsec;

     pnum = CTR.CD[2] >> 8;
     if(pnum >= 0x18)
      CDStatusResults(true, 0);
     else
     {
      offs = CTR.CD[1];
      numsec = CTR.CD[3];

      if(offs == 0xFFFF)
       offs = Partitions[pnum].Count - 1;

      if(numsec == 0xFFFF)
       numsec = Partitions[pnum].Count - offs;

      if((DT.Active && CTR.Command != COMMAND_DEL_SECDATA) || numsec <= 0 || offs < 0 || (offs + numsec) > (int)Partitions[pnum].Count)
       CDStatusResults(false, STATUS_WAIT);
      else
      {
       int sbfi;

       sbfi = Partition_GetBuffer(pnum, offs);

       if(CTR.Command != COMMAND_DEL_SECDATA)
       {
        for(int i = 0, bfi = sbfi; i < numsec; i++)
        {
         const int next_bfi = Buffers[bfi].Next;
	 DT.BufList[i] = bfi;
	 if(CTR.Command == COMMAND_GETDEL_SECDATA)
          Partition_UnlinkBuffer(pnum, bfi);
         bfi = next_bfi;
        }

        CDStatusResults(false, STATUS_DTREQ);

        DT.Writing = false;
        DT.NeedBufFree = (CTR.Command == COMMAND_GETDEL_SECDATA);
        DT.BufCount = numsec;

        DT_StartList(false);

        DT.Active = true;
       }
       else
        CDStatusResults(false, 0);

       //
       //
       //
       if(CTR.Command == COMMAND_DEL_SECDATA)
       {
        for(int i = 0, bfi = sbfi; i < numsec; i++)
        {
         const int next_bfi = Buffers[bfi].Next;
         Partition_UnlinkBuffer(pnum, bfi);
	 Buffer_Free(bfi);
         bfi = next_bfi;
        }

        CMD_EAT_CLOCKS(485);
        TriggerIRQ(HIRQ_EHST);
	//
	//
	CheckBufPauseResume();
       }
       else
       {
        CMD_EAT_CLOCKS(460);
        TriggerIRQ(HIRQ_DRDY);
       }
      }
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_PUT_SECDATA) //	= 0x64,
    {
     unsigned fnum, numsec;

     fnum = CTR.CD[2] >> 8;
     numsec = CTR.CD[3];

     if(fnum >= 0x18)
     {
      CDStatusResults(true, 0);
     }
     else if(numsec == 0 || numsec > FreeBufferCount || DT.Active)
     {
      CDStatusResults(false, STATUS_WAIT);
     }
     else
     {
      Filter_DisconnectInput(fnum);

      CDStatusResults(false, STATUS_DTREQ);

      DT.Writing = true;
      DT.NeedBufFree = false;
      DT.FNum = fnum;
      for(unsigned i = 0; i < numsec; i++)
      {
       DT.BufList[i] = Buffer_Allocate(true);
      }

      DT.BufCount = numsec;

      DT_StartList(true);
      DT.Active = true;
      //
      //
      //
      CMD_EAT_CLOCKS(300);
      TriggerIRQ(HIRQ_DRDY);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_COPY_SECDATA || CTR.Command == COMMAND_MOVE_SECDATA) //	= 0x65,  =0x66
    {
     unsigned dst_fnum, src_pnum;

     dst_fnum = CTR.CD[0] & 0xFF;
     src_pnum = CTR.CD[2] >> 8;

     if(src_pnum >= 0x18 || dst_fnum >= 0x18)
      CDStatusResults(true, 0);
     else
     {
      int src_offs, numsec;

      src_offs = CTR.CD[1];
      numsec = CTR.CD[3];

      if(src_offs == 0xFFFF)
       src_offs = Partitions[src_pnum].Count - 1;

      if(numsec == 0xFFFF)
       numsec = Partitions[src_pnum].Count - src_offs;

      if(DT.Active || numsec <= 0 || (numsec > (int)FreeBufferCount && CTR.Command != COMMAND_MOVE_SECDATA) || src_offs < 0 || (src_offs + numsec) > (int)Partitions[src_pnum].Count)
       CDStatusResults(false, STATUS_WAIT);
      else
      {
       Filter_DisconnectInput(dst_fnum);

       for(int i = 0, bfi = Partition_GetBuffer(src_pnum, src_offs); i < numsec; i++)
       {
        const int next_bfi = Buffers[bfi].Next;

        if(CTR.Command == COMMAND_MOVE_SECDATA)
        {
         Partition_UnlinkBuffer(src_pnum, bfi);
         FilterBuf(dst_fnum, bfi);
        }
        else
	{
	 int abfi = Buffer_Allocate(false);
	
	 Page_Copy(Buffers[abfi].Page, Buffers[bfi].Page);
	 memcpy(Buffers[abfi].Hdr, Buffers[bfi].Hdr, 8);

         FilterBuf(dst_fnum, abfi);
	}

        bfi = next_bfi;
       }
       CDStatusResults(false, 0);
       //
       //
       // TODO: Accurate timing(while not blocking other command execution and sector reading).  Note that "move sector data" is much faster than "copy sector data".
       CMD_EAT_CLOCKS(300);
       if(FreeBufferCount == 0)
        TriggerIRQ(HIRQ_BFUL);
       TriggerIRQ(HIRQ_ECPY);
      }
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_COPYERR) //	= 0x67,
    {
     // TODO: Implement if we ever implement proper asynch copy/moving
     BasicResults((MakeBaseStatus(false, 0) << 8) | 0x00, 0, 0, 0);
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_CHANGE_DIR) //	= 0x70,
    {
     bool reject;
     uint8_t fnum;
     uint32_t fileid;
     uint32_t fiaoffs;

     fnum = (CTR.CD[2] >> 8);
     fileid = ((CTR.CD[2] & 0xFF) << 16) | CTR.CD[3];
     fiaoffs = (fileid < 2) ? fileid : (2 + fileid - FileInfoOffs);

     reject = false;

     if(fnum >= 0x18)
      reject = true;

     if(fileid != 0xFFFFFF)
     {
      if(!FileInfoValid)
       reject = true;
      else if(fileid >= 2 && (fileid < FileInfoOffs || fileid >= (FileInfoOffs + FileInfoValidCount)))
       reject = true;
      else if(!(FileInfo[fiaoffs].attr & 0x2))	// FIXME: test XA directory flag too?
       reject = true;
     }

     if(FLS.Active)
      CDStatusResults(false, STATUS_WAIT);
     else if(reject)
      CDStatusResults(true, 0);
     else if(fileid == 0)	// NOP, kind of(even when FileInfoOffs > 2, interestingly)
     {
      CDStatusResults(false, 0);
      CMD_EAT_CLOCKS(400);
      TriggerIRQ(HIRQ_EFLS);
     }
     else
     {
      CDStatusResults(false, 0);
      //
      //
      FLS.fioffs = 2;
      FLS.fiaoffs = (fileid == 0xFFFFFF) ? 0xFFFFFF : fiaoffs;
      FLS.pnum = fnum;
      FLS.DoAuth = false;
      FLS.Active = true;
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_READ_DIR) //	= 0x71,
    {
     uint8_t fnum;
     uint32_t start_fileid;

     fnum = (CTR.CD[2] >> 8);
     start_fileid = ((CTR.CD[2] & 0xFF) << 16) | CTR.CD[3];

     if(start_fileid < 2)
      start_fileid = 2;

     if(FLS.Active)
      CDStatusResults(false, STATUS_WAIT);
     else if(fnum >= 0x18 || !FileInfoValid)
      CDStatusResults(true, 0);
     // TODO: else if(start_fileid > FileInfoOffs && !FileInfoMore)
     else
     {
      CDStatusResults(false, 0);
      //
      //
      //
      FLS.fioffs = start_fileid;
      FLS.fiaoffs = 0;
      FLS.pnum = fnum;

      FLS.DoAuth = false;
      FLS.Active = true;
      //
      // Check (attr & 2) first?  and & 0x80 for XA?
      //
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_FSSCOPE) //	= 0x72,
    {
     if(FLS.Active)	// Maybe add a specific check for directory reading?  (Will have to if we chain READ_FILE into FLS.Active someday for whatever reason)
      CDStatusResults(false, STATUS_WAIT);
     else if(!FileInfoValid)
      CDStatusResults(true, 0);
     else
     {
      BasicResults((MakeBaseStatus(false, 0) << 8),
		FileInfoValidCount,
		(!FileInfoMore << 8) | (FileInfoOffs >> 16),
		FileInfoOffs);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_GET_FINFO) //	= 0x73,
    {
     uint32_t fileid;
     bool reject;

     fileid = ((CTR.CD[2] & 0xFF) << 16) | CTR.CD[3];

     reject = false;
     reject |= !FileInfoValid;
     reject |= (fileid != 0xFFFFFF && (fileid >= 2 && (fileid < FileInfoOffs || fileid >= (FileInfoOffs + FileInfoValidCount))));
     reject |= (fileid == 0xFFFFFF && !FileInfoValidCount);

     if(FLS.Active || DT.Active)
      CDStatusResults(false, STATUS_WAIT);
     else if(reject)
      CDStatusResults(true, 0);
     else
     {
      unsigned offs, count;	// words

      DT.BufCount = 1;

      if(fileid == 0xFFFFFF)
      {
       offs = 6 * 2;
       count = 6 * FileInfoValidCount;
      }
      else
      {
       const uint32_t fiaoffs = (fileid < 2) ? fileid : (2 + fileid - FileInfoOffs);

       offs = 6 * fiaoffs;
       count = 6;
      }

      DT.BufList[0] = 0xF0;

      DT.Writing = false;
      DT.NeedBufFree = false;
      DT.Active = true;
      DT_StartRaw((const uint8_t*)FileInfo + offs * 2, count);

      BasicResults(MakeBaseStatus(false, STATUS_DTREQ) << 8, count, 0, 0);
      //
      //
      //
      // TODO(also need some changes in CDB_Read()): for(unsigned i = 0; i < 5; i++)
      //  DT_ReadIntoFIFO();

      CMD_EAT_CLOCKS(128);
      TriggerIRQ(HIRQ_DRDY);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_READ_FILE) //	= 0x74,
    {
     uint32_t offset;
     uint32_t fileid;
     uint8_t fnum;

     offset = ((CTR.CD[0] & 0xFF) << 16) | CTR.CD[1];
     fileid = ((CTR.CD[2] & 0xFF) << 16) | CTR.CD[3];
     fnum = CTR.CD[2] >> 8;

     if(FLS.Active)
      CDStatusResults(false, STATUS_WAIT);
     else if(fnum >= 0x18 || !FileInfoValid || (fileid >= 2 && (fileid < FileInfoOffs || fileid >= (FileInfoOffs + FileInfoValidCount))))
      CDStatusResults(true, 0);
     else
     {
      CDStatusResults(false, 0);

      Partition_Clear(fnum);

      const uint32_t fiaoffs = (fileid < 2) ? fileid : (2 + fileid - FileInfoOffs);
      uint32_t start_fad = (FileInfoS_fad(&FileInfo[fiaoffs]) + offset) & 0xFFFFFF;
      uint32_t sec_count = ((FileInfoS_size(&FileInfo[fiaoffs]) + 2047) >> 11) - offset;	// FIXME: Check offset versus ifile size.

      SetCDDeviceConn(fnum);
      Filter_SetTrueConn(fnum, fnum);
      Filter_SetFalseConn(fnum, 0xFF);
      Filter_SetRange(fnum, start_fad, sec_count);	// Not sure if correct for XA interleaved files...

      Filters[fnum].Mode = MODE_SEL_FADR | MODE_SEL_FILE;
      Filters[fnum].File = FileInfo[fiaoffs].fnum;

      Filters[fnum].Channel = 0;
      Filters[fnum].SubMode = 0;
      Filters[fnum].SubModeMask = 0;
      Filters[fnum].CInfo = 0;
      Filters[fnum].CInfoMask = 0;
      //
      StartSeek(0x800000 | start_fad, 0x800000 | ((start_fad + sec_count) & 0x7FFFFF), 0, HIRQ_EFLS, false);
     }
    }
    //
    //
    //
    else if(CTR.Command == COMMAND_ABORT_FILE) //	= 0x75,
    {
     // TODO: Does tray opening during a file operation trigger HIRQ_EFLS?
     CDStatusResults(false, 0);

     FLS.Abort = true;
    }
    //
    //
    //
    else if(CTR.Command >= 0x90 && CTR.Command <= 0xAF)	// MPEG card commands: no card, rejected
    {
     BasicResults(0xFF00, 0xFFFF, 0xFFFF, 0xFFFF);
     TriggerIRQ(HIRQ_MPCM);
    }
    else
    {
     SetResultsRead(false);
     ClearCommandPending();
    }

    if(ResetSelPending)
    {
     const unsigned rflags = ResetSelPending;
     ResetSelPending = false;

     for(unsigned pnum = 0; pnum < 0x18; pnum++)
     {
      if(rflags & 0x04)	// Initialize all partition data
      {
       Partition_Clear(pnum);
      }

      // TODO: Initialize all partition output connectors.
      //       Has to do with MPEG decoding, copy/move sector data
      //       commands, and maybe some other commands too?
      if(rflags & 0x08)
      {

      }

      if(rflags & 0x10)	// Initialize all filter conditions
      {
       Filter_ResetCond(pnum);
      }

      if(rflags & 0x20)	// Initialize all filter input connectors
      {
       if(pnum == CDDevConn)
	CDDevConn = 0xFF;

       if(Filters[pnum].FalseConn < 0x18)
        Filters[pnum].FalseConn = 0xFF;
      }

      if(rflags & 0x40) // Initialize all true output connectors
      {
       Filters[pnum].TrueConn = pnum;
      }

      if(rflags & 0x80) // Initialize all false output connectors
      {
       Filters[pnum].FalseConn = 0xFF;
      }
     }

     TriggerIRQ(HIRQ_ESEL);
     //
     //
     //
     CheckBufPauseResume();
    }

    if(SWResetPending)
    {
     SWResetPending = false;
     SWReset();

     CMD_EAT_CLOCKS(8192 - 180);

     SWResetHIRQDeferred = HIRQ_MPED | HIRQ_EFLS | HIRQ_ECPY | HIRQ_EHST | HIRQ_ESEL | HIRQ_CMOK;
     // If a stupid game(Tenchi Muyou Ryououki Gokuraku) tries to run a new command after the Initialize command's software reset process
     // begins but before it finishes, delay software reset HIRQ bit setting until the command generates its own HIRQ_CMOK(effectively collapsing two HIRQ_CMOKs
     // into one HIRQ_CMOK in the process).
     if(!CommandPending)
     {
      TriggerIRQ(SWResetHIRQDeferred);
      SWResetHIRQDeferred = 0;
     }
    }

    continue;
    //
    //
    //
    case -1 + CommandPhaseBias:

    CMD_EAT_CLOCKS(4880000);

    StandbyTime = 0;
    ECCEnable = 0xFF;
    RetryCount = 1;
    ClearCommandPending();
    SWResetPending = false;
    SWResetHIRQDeferred = 0;
    ResetSelPending = false;
    SetResultsRead(true);

    memset(&DT, 0, sizeof(DT));

    PlayCmdStartPos = 0;	// TODO: Test for correct value.
    PlayCmdEndPos = 0;	// TODO: Test for correct value.
    PlayCmdRepCnt = 0;	// TODO: ...

    CurPlayRepeat = 0;	// TODO: . . .
    PlayRepeatCounter = 0;

    ScanMode = -1;
    ScanCounter = 0;

    DriveCounter = 1000;
    DrivePhase = DRIVEPHASE_EJECTED_WAITING;

    memset(TOC_Buffer, 0xFF, sizeof(TOC_Buffer));	// TODO: confirm 0xFF(or 0x00?)

    AuthDiscType = 0x00;
    FileInfoValid = false;
    RootDirInfoValid = false;
    PeriodicIdleCounter = PeriodicIdleCounter_Reload;

    CurPosInfo.status = STATUS_OPEN;
    CurPosInfo.is_cdrom = false;
    CurPosInfo.fad = 0xFFFFFF;
    CurPosInfo.rel_fad = 0xFFFFFF;
    CurPosInfo.ctrl_adr = 0xFF;
    CurPosInfo.idx = 0xFF;
    CurPosInfo.tno = 0xFF;

    CDDA_Flush();

    //
    //
    SWReset();

    CurPosInfo.status = STATUS_BUSY;	// FIXME(so it's set long enough from POV of program)
    CurPosInfo.is_cdrom = false;
    CurSector = 0;

    SetResultsRead(false);
    SetResults(0x0043, 0x4442, 0x4c4f, 0x434b);	// "CDBLOCK"
    TriggerIRQ(HIRQ_CMOK | HIRQ_DCHG | HIRQ_ESEL | HIRQ_EHST | HIRQ_MPED | HIRQ_ECPY | HIRQ_EFLS);
    continue;
   }
  }
  CommandGetOut:;
  //
  //
  //

  //RunFLS(clocks);
 }
}

//
// Main loop: time from the hardware timer; the disc goes in and out with DISC_IN.
//
#ifdef SMPC_FW
// The SMPC runs on this CPU too: power-on starts it, then the CD block code waits while the SMPC holds the CD block
// in reset (CDRES_N low, as the CPU was held in reset before) and starts as after its reset: its .bss cleared, main.
// When the SMPC pulls CDRES_N low again, smpc_poll() comes back here (cd_restart_entry: a fresh stack).
static void cd_main(void) __attribute__((noreturn));
int main(void)
{
 smpc_init();
#ifdef CD_SRC_FW
 src_power_on();
#endif
 cd_restart();
}

void cd_restart(void)
{
 extern uint32_t __cd_bss_start[], __cd_bss_end[];

 smpc_cd_deadline_on = false;
 while(!smpc_cd_released())
  smpc_poll();
 for(uint32_t* p = __cd_bss_start; p < __cd_bss_end; p++)
 {
  *p = 0;
  if(((uintptr_t)p & 1023) == 1020) smpc_poll();
 }
 cd_running = true;
 cd_main();
}

static void cd_main(void)
#else
int main(void)
#endif
{
 uint32_t last;
 bool disc;

 CDB_Reset(true);
#ifdef CD_SRC_FW
 src_init();			// CD_SRC_FW: the disc comes in (DISC_IN) once the data slots are scanned
#endif
 disc = (IO_FLAGS & F_DISC_IN) != 0;
 CDB_SetDisc(!disc);
 last = IO_TIMER;

 for(;;)
 {
  SMPC_POLL();
#ifdef CD_SRC_FW
  src_poll();
#endif
  const uint32_t now = IO_TIMER;
  const bool d = (IO_FLAGS & F_DISC_IN) != 0;

  if(d != disc)
  {
   disc = d;
   CDB_SetDisc(!disc);
  }
  CDB_Run((int32_t)(now - last));
  last = now;
#ifdef SMPC_FW
  smpc_cd_deadline = now + (uint32_t)DriveCounter;
  smpc_cd_deadline_on = DrivePhase == DRIVEPHASE_PLAY && DriveCounter > 0;
#endif
 }
}
