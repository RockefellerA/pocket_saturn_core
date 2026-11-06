// glue/cd design B: the Analogue Pocket's disc source as part of the CD block HLE firmware (cd_src.h; hardware:
// glue/rtl/cd_src_b.sv on CDB_HLE's EXT port; glue/cd/REPORT.txt).
//
// Disc = APF data slots (deferred loads, data.json): CUE_ID the .cue (optional); BIN_ID + f the f-th FILE of the cue
// (a Redump set: one .bin per track; or one .bin for the whole disc, chdman's default); without a .cue the slots from
// BIN_ID are tracks 1, 2, ... by convention (Redump: track 1 data with INDEX 01 at the file's start, the others audio
// with INDEX 01 at 00:02:00 of their file), AUDIO1_ID in place of BIN_ID making track 1 audio (an audio CD).
// The layout (built once: in SMPC_FW builds it is kept across CD block resets in .noinit):
//   tracks: control and INDEX 01 LBA (the TOC: Mednafen's tracks[].lba is INDEX 01),
//   extents: disc LBAs [lba, end) = file f's sectors from s on (a PREGAP / POSTGAP is a hole: zeros, not in the file),
//   lead-out.
// Sectors: a ring of N slots (the hardware's, STATUS[27:24]) filled by data slot reads (IO_X_*): a read the drive asks
// for that is in the ring is streamed at once into its page (IO_SEC_LBA = the slot's ring word address), one in the
// read running waits for it, any other waits for that read and starts the ring anew with a one-sector read. While no
// read runs: up to KMAX of the next sectors (to the ring's end; into the next file too when it follows on without a
// hole), as the sotn PSX core's pocket_cd does (which stops at the file's end).
// The requested sector stays in the ring (PAUSE re-reads it). A seek hint (the drive's seek start, Mednafen's
// CDIF_HintReadSector) starts the ring at the seek target while the drive seeks (>= 80 ms).
// CD_SRC_L2: a second read-ahead level in the CD RAM pages the CD block does not use (NUM_PAGES .. + L2N - 1): while
// the sector engine is free, the ring's oldest sector is moved into the next spare page (in LBA order), freeing its
// slot for more read-ahead; a read the drive asks for that is there is handed over by swapping pages (the drive's
// page becomes a spare one): ring + L2N sectors ahead with no more block RAM. A PAUSE re-read of the sector the
// drive's page still holds is answered at once.
// Region: once the layout is built, before the disc goes in, the system ID in track 1's first sector gives the disc's
// area code (disc_area(), IO_X_AREA); pk_settings uses it for Region = Auto.
#include "cd_src.h"
#ifdef SMPC_FW
#include "smpc.h"
#define POLL() smpc_poll()
#else
#define POLL() ((void)0)
#endif

enum { CUE_ID = 14, AUDIO1_ID = 15, BIN_ID = 16, MAXF = 32, DT_ENTRIES = 32, MAXX = 40, KMAX = 3, SECB = 2352,
       CUE_PAGE = NUM_PAGES };
#define DISC_MAGIC 0x43445331u

struct ext { int32_t lba, end; uint32_t fpos; };    // [lba, end) = file fpos >> 24 from sector fpos & 0xFFFFFF

static struct {
	uint32_t magic;
	int32_t leadout;
	uint8_t ntr, nx, audio1;
	uint32_t tr[99];                                // track t + 1: control << 28 | INDEX 01 LBA
	struct ext x[MAXX];
} D __attribute__((section(".noinit")));

static uint8_t nslot;
static int8_t scan_st;
static uint32_t fsec[MAXF];                         // (scan) sectors of each file
static uint8_t nfiles;
static uint32_t cue_size;

static struct { bool on, busy; uint8_t hs, cnt, pend; int32_t head; } R;   // the ring: LBAs head .. head + cnt - 1
#ifdef CD_SRC_L2
enum { L2N = 16 };
static uint8_t l2pg[L2N], l2q, l2n, l2mv, l2drop; // spare pages in queue order (position l2q + i holds LBA l2lba + i)
static int32_t l2lba;                               // l2mv: 1 moving the ring's head, 2 that move is void
static int32_t last_lba;                            // the drive's page last_pg holds LBA last_lba
static uint8_t last_pg;
#endif
static struct { bool on; uint16_t pf; int32_t lba; } Q;
static struct { bool on; int32_t lba; } H;

// ---------------------------------------------------------------- APF: data slot table, data slot reads
static uint32_t dt_read(unsigned w)
{
	IO_X_DTADDR = w;
	while(IO_X_STATUS & XS_DT_BUSY) { }
	return IO_X_DTQ;
}

static bool cmd_busy(void) { return (IO_X_STATUS & XS_CMD_BUSY) != 0; }

static void cmd_start(unsigned id, uint32_t off, unsigned len, unsigned dest)
{
	IO_X_ID = id;
	IO_X_OFFSET = off;
	IO_X_DEST = ((uint32_t)len << 16) | dest;
	IO_X_START = 1;
}

static unsigned fid(unsigned f) { return (f == 0 && D.audio1) ? AUDIO1_ID : BIN_ID + f; }

// ---------------------------------------------------------------- layout
static void layout_convention(void)
{
	int32_t lba = 0;
	D.nx = D.ntr = 0;
	for(unsigned f = 0; f < nfiles && f < 99 && f < MAXX; f++)
	{
		D.x[f].lba = lba;
		D.x[f].end = lba + (int32_t)fsec[f];
		D.x[f].fpos = (uint32_t)f << 24;
		D.tr[f] = ((f == 0 && !D.audio1) ? 4u : 0u) << 28 | (uint32_t)(lba + (f ? 150 : 0));
		lba += fsec[f];
		D.nx++; D.ntr++;
	}
	D.leadout = lba;
}

// the .cue, a line at a time
static struct {
	int8_t f;                   // FILE (-1: none yet)
	uint8_t t, ctrl;            // TRACK, its control bits
	bool i1, xo, bad;           // track t has INDEX 01; an extent is open
	int32_t base, gap;          // disc LBA of file f's sector 0; a PREGAP / POSTGAP to insert at the next INDEX
} P;

static const char* sp(const char* s) { while(*s == ' ' || *s == '\t' || (*s & 0x80)) s++; return s; }   // (and a BOM)

// the .cue's keywords (K_PREGAP before K_PRE: a prefix)
static const char kws[] = "FILE\0TRACK\0FLAGS\0PREGAP\0POSTGAP\0INDEX\0AUDIO\0MODE1/2352\0MODE2/2352\0DCP\0PRE\0" "4CH";
enum { K_FILE, K_TRACK, K_FLAGS, K_PREGAP, K_POSTGAP, K_INDEX, K_AUDIO, K_MODE1, K_MODE2, K_DCP, K_PRE, K_4CH, K_NONE };
// the keyword at *s (*s then after it and its spaces), or K_NONE (*s unchanged)
static unsigned __attribute__((noinline)) word(const char** s)
{
	const char* k = kws;
	for(unsigned i = 0; i < K_NONE; i++)
	{
		const char* p = *s;
		while(*k && *k == *p) { k++; p++; }
		if(!*k)
		{
			*s = sp(p);
			return i;
		}
		while(*k) k++;
		k++;
	}
	return K_NONE;
}
static unsigned __attribute__((noinline)) num(const char** s)
{
	unsigned v = 0;
	while(**s >= '0' && **s <= '9') v = v * 10 + (unsigned)(*(*s)++ - '0');
	return v;
}
static int32_t msf(const char* s)       // mm:ss:ff -> frames
{
	int32_t v = 0;
	for(unsigned i = 0; i < 3; i++)
	{
		v = v * (i == 2 ? 75 : 60) + (int32_t)num(&s);
		s++;
	}
	return v;
}

static void x_close(int32_t end)
{
	if(!P.xo)
		return;
	P.xo = false;
	if(end > D.x[D.nx].lba)
	{
		D.x[D.nx].end = end;
		if(++D.nx >= MAXX) P.bad = true;
	}
}

static void cue_line(const char* s)
{
	unsigned k = word(&s);
	if(k == K_FILE)
	{
		if(P.f >= 0) { x_close(P.base + fsec[P.f]); P.base += fsec[P.f]; }
		if(++P.f >= nfiles) P.bad = true;
	}
	else if(k == K_TRACK)
	{
		const unsigned n = num(&s);
		if(P.f < 0 || n != P.t + 1u || (P.t && !P.i1) || n > 99) P.bad = true;
		P.t = n; P.i1 = false;
		k = word((s = sp(s), &s));
		P.ctrl = k == K_AUDIO ? 0 : 4;
		if(k != K_AUDIO && k != K_MODE1 && k != K_MODE2) P.bad = true;   // MODE1/2048, MODE2/2336, CDG: not raw
	}
	else if(k == K_FLAGS)
	{
		while(*s)
		{
			k = word(&s);
			if(k == K_DCP) P.ctrl |= 2;
			else if(k == K_PRE) P.ctrl |= 1;
			else if(k == K_4CH) P.ctrl |= 8;
			else s++;
		}
	}
	else if(k == K_PREGAP || k == K_POSTGAP)
		P.gap += msf(s);
	else if(k == K_INDEX)
	{
		const unsigned i = num(&s);
		const int32_t q = msf(sp(s));
		if(!P.t || P.bad)
		{
			P.bad = true;
			return;
		}
		if(P.gap)                                   // a hole before this index: no file data
		{
			x_close(P.base + q);
			P.base += P.gap;
			P.gap = 0;
		}
		if(!P.xo)
		{
			if(D.nx >= MAXX)
			{
				P.bad = true;
				return;
			}
			D.x[D.nx].lba = P.base + q;
			D.x[D.nx].fpos = (uint32_t)P.f << 24 | (uint32_t)q;
			P.xo = true;
		}
		if(i == 1)
		{
			D.tr[P.t - 1] = (uint32_t)P.ctrl << 28 | (uint32_t)(P.base + q);
			D.ntr = P.t;
			P.i1 = true;
		}
	}
}

// the .cue from the ring (the first data slot read is done; a .cue longer than the ring is read in more passes): each
// slot through the sector engine into a spare CD RAM page, parsed from there
static bool cue_parse(void)
{
	char ln[96];
	unsigned n = 0;
	uint32_t off = 0;
	const uint32_t ring = (uint32_t)nslot * SECB;

	memset(&P, 0, sizeof(P));
	P.f = -1;
	D.nx = D.ntr = 0;
	while(off < cue_size)
	{
		uint32_t left = cue_size - off < ring ? cue_size - off : ring;
		if(off)
		{
			cmd_start(CUE_ID, off, left, 0);
			while(cmd_busy()) POLL();
		}
		off += left;
		for(unsigned s = 0; left; s++)
		{
			IO_SEC_PAGE = CUE_PAGE;
			IO_SEC_LBA = s * PAGE_WORDS;
			while(IO_FLAGS & F_SEC_BUSY) POLL();
			const unsigned len = left < SECB ? left : SECB;
			left -= len;
			for(unsigned i = 0; i < len; i += 2)
			{
				const uint16_t w = cd_rd16(page_word(CUE_PAGE) + i / 2);
				for(unsigned b = 0; b < 2 && i + b < len; b++)
				{
					const char c = b ? (char)w : (char)(w >> 8);
					if(c == '\n' || c == '\r')
					{
						ln[n] = 0;
						if(n) { cue_line(sp(ln)); POLL(); }
						n = 0;
					}
					else if(n < sizeof(ln) - 1)
						ln[n++] = c;
				}
				if((i & 31) == 30) POLL();      // (every 16 words: SMPC poll gaps stay < 0.5 ms)
			}
		}
	}
	ln[n] = 0;
	if(n) cue_line(sp(ln));
	if(P.f < 0 || !P.t || !P.i1 || P.bad)
		return false;
	x_close(P.base + fsec[P.f]);
	D.leadout = P.base + fsec[P.f] + P.gap;
	return !P.bad;
}

static int find_x(int32_t lba);

// The disc's area for Region = Auto: the first compatible area symbol of the system ID (track 1's first sector, user
// data bytes 0x40-0x49: "J", "U", "E", ...) as an SMPC area code, the one MiSTer's emu takes from the boot header it
// gets from its main program. 0 (none: pk_settings keeps USA) without a data track 1 that starts with the Saturn's
// hardware ID, or for a symbol not in the list. Read through ring slot 0 into the spare page, as the .cue is: before
// the disc goes in nothing else uses either.
static unsigned __attribute__((noinline)) disc_area(void)
{
	static const char hw_id[] = "SEGA SEGASATURN ", sym[] = "JTUBKAEL";
	static const uint8_t code[] = { 0x1, 0x2, 0x4, 0x5, 0x6, 0xA, 0xC, 0xD };
	if(!D.ntr || !((D.tr[0] >> 28) & 4))
		return 0;
	const int32_t lba = (int32_t)(D.tr[0] & 0xFFFFFF);
	const int xi = find_x(lba);
	if(xi < 0)
		return 0;
	const struct ext* x = &D.x[xi];
	cmd_start(fid(x->fpos >> 24), ((x->fpos & 0xFFFFFF) + (uint32_t)(lba - x->lba)) * SECB, SECB, 0);
	while(cmd_busy()) POLL();
	IO_SEC_PAGE = CUE_PAGE;
	IO_SEC_LBA = 0;
	while(IO_FLAGS & F_SEC_BUSY) POLL();
	const uint32_t w = page_word(CUE_PAGE);
	const uint32_t u = w + ((cd_rd16(w + 7) & 0xFF) == 2 ? 12 : 8);   // user data words: mode 1 from byte 16, mode 2
	for(unsigned i = 0; i < 8; i++)                                    // form 1 from byte 24 (byte 15: the mode)
		if(cd_rd16(u + i) != ((unsigned)(uint8_t)hw_id[2 * i] << 8 | (uint8_t)hw_id[2 * i + 1]))
			return 0;
	const uint8_t s = (uint8_t)(cd_rd16(u + 0x20) >> 8);              // (byte 0x40: the first symbol)
	for(unsigned i = 0; i < 8; i++)
		if(s == (uint8_t)sym[i])
			return code[i];
	return 0;
}

static void scan_done(void)
{
	IO_X_AREA = disc_area();                        // (before DISC: a reset this causes comes before the disc is read)
	D.magic = DISC_MAGIC;
	IO_X_DISC = D.ntr != 0;
}

// the data slot table, then the .cue's read, then the layout (one step per call)
static void __attribute__((noinline)) scan_step(void)
{
	if(cmd_busy())                                  // (a read from before a CD block reset)
		return;
	if(scan_st == 0)
	{
		uint32_t sz[MAXF + 1];
		memset(sz, 0, sizeof(sz));
		cue_size = 0;
		for(unsigned e = 0; e < DT_ENTRIES; e++)
		{
			const unsigned id = dt_read(2 * e) & 0xFFFF;
			const uint32_t size = dt_read(2 * e + 1);
			if(id == CUE_ID) cue_size = size;
			else if(id >= AUDIO1_ID && id < BIN_ID + MAXF) sz[id - AUDIO1_ID] = size;
			if((e & 7) == 7) POLL();
		}
		D.audio1 = !cue_size && sz[0];               // (with a .cue, the .cue says what each track is)
		for(nfiles = 0; nfiles < MAXF; nfiles++)
		{
			const uint32_t b = (nfiles == 0 && D.audio1) ? sz[0] : sz[nfiles + 1];
			if(b < SECB) break;
			fsec[nfiles] = b / SECB;                // (a software division, ~20 us: poll every 4)
			if((nfiles & 3) == 3) POLL();
		}
		if(cue_size && nfiles)
		{
			cmd_start(CUE_ID, 0, cue_size < (uint32_t)nslot * SECB ? cue_size : (uint32_t)nslot * SECB, 0);
			scan_st = 1;
			return;
		}
		layout_convention();
		scan_done();
		return;
	}
	if(!cue_parse())
		layout_convention();
	scan_done();
}

void src_power_on(void)
{
	D.magic = 0;
}

void src_init(void)
{
#ifndef SMPC_FW
	D.magic = 0;                                    // (the CPU restarts with the CD block: scan again)
#endif
	nslot = (IO_X_STATUS >> 24) & 0xF;
	if(D.magic != DISC_MAGIC)
	{
		IO_X_DISC = 0;
		scan_st = 0;                                // (a CD block reset during the scan: start it again)
	}
#ifdef CD_SRC_L2
	for(unsigned i = 0; i < L2N; i++)
		l2pg[i] = NUM_PAGES + i;                    // (the CD block's Pages_Init has just run: pages 0 .. NUM_PAGES - 1)
	last_lba = -0x1000000;
#endif
}

bool src_toc(TOC* toc)
{
	memset(toc, 0, sizeof(*toc));
	toc->first_track = toc->last_track = 1;
	if(D.magic != DISC_MAGIC || !D.ntr)
		return false;
	toc->last_track = D.ntr;
	for(unsigned t = 0; t < D.ntr; t++)
	{
		struct TOC_Track* tr = &toc->tracks[t + 1];
		tr->valid = true;
		tr->adr = 1;
		tr->control = D.tr[t] >> 28;
		tr->lba = D.tr[t] & 0xFFFFFF;
	}
	toc->tracks[100].valid = true;
	toc->tracks[100].adr = 1;
	toc->tracks[100].control = toc->tracks[D.ntr].control & 0x4;
	toc->tracks[100].lba = D.leadout;
	return true;
}

// ---------------------------------------------------------------- sectors
static int find_x(int32_t lba)
{
	static uint8_t last;
	if(last < D.nx && lba >= D.x[last].lba && lba < D.x[last].end)
		return last;
	for(unsigned i = 0; i < D.nx; i++)
		if(lba >= D.x[i].lba && lba < D.x[i].end)
			return last = i;
	return -1;
}

// read n sectors from lba (all in extent xi) into the ring from slot on
static void ring_cmd(int xi, int32_t lba, unsigned n, unsigned slot)
{
	const struct ext* x = &D.x[xi];
	const uint32_t sec = (x->fpos & 0xFFFFFF) + (uint32_t)(lba - x->lba);
	cmd_start(fid(x->fpos >> 24), sec * SECB, n * SECB, slot * SECB);
	R.pend = n;
	R.busy = true;
}

static void ring_new(int xi, int32_t lba, unsigned n)
{
	const int32_t rest = D.x[xi].end - lba;
#ifdef CD_SRC_L2
	l2n = 0;
	l2drop = 0;
	if(l2mv) l2mv = 2;
#endif
	R.on = true; R.head = lba; R.hs = 0; R.cnt = 0;
	if((int32_t)n > rest) n = rest;
	ring_cmd(xi, lba, n, 0);
}

static bool in_ring(int32_t lba)
{
	return R.on && lba >= R.head && lba < R.head + R.cnt;
}

#ifdef CD_SRC_L2
// a data track's sector (the drive's rule: subcode Q control of the track the LBA is in; the sync words not written)
static bool data_at(int32_t lba)
{
	unsigned t = 0;
	while(t + 1 < D.ntr && (int32_t)(D.tr[t + 1] & 0xFFFFFF) <= lba) t++;
	return (D.tr[t] >> 28) & 4;
}
#endif

static void stream(unsigned pf, uint32_t what)
{
	IO_SEC_PAGE = pf;
	IO_SEC_LBA = what;
}

void src_poll(void)
{
	if(D.magic != DISC_MAGIC)
	{
		scan_step();
		return;
	}
	if(R.busy && !cmd_busy())
	{
		R.busy = false;
		R.cnt += R.pend;
		R.pend = 0;
	}
#ifdef CD_SRC_L2
	if(l2mv && !(IO_FLAGS & F_SEC_BUSY))            // a move into a spare page is done
	{
		if(l2mv == 1)
		{
			if(!l2n) l2lba = R.head;
			l2n++;
			R.head++;
			if(++R.hs >= nslot) R.hs = 0;
			R.cnt--;
		}
		l2mv = 0;
	}
	if(l2drop && !(IO_FLAGS & F_SEC_BUSY))          // the ring's head went to the drive: no need to keep it
	{
		l2drop = 0;
		if(R.cnt && R.head == last_lba)
		{
			R.head++;
			if(++R.hs >= nslot) R.hs = 0;
			R.cnt--;
		}
	}
#endif
	if(Q.on && !(IO_FLAGS & F_SEC_BUSY))
	{
#ifdef CD_SRC_L2
		l2n = 0;                                    // (the request is not in L2: src_read looked)
		last_lba = Q.lba;
		last_pg = Q.pf;
#endif
		const int xi = find_x(Q.lba);
		if(xi < 0)                                  // off the disc, or a hole: zeros
		{
			stream(Q.pf, 0x800000);
			Q.on = false;
		}
		else if(in_ring(Q.lba))
		{
			const unsigned d = Q.lba - R.head;
			R.hs += d;
			if(R.hs >= nslot) R.hs -= nslot;
			R.cnt -= d;
			R.head = Q.lba;
			stream(Q.pf, R.hs * PAGE_WORDS);
			Q.on = false;
#ifdef CD_SRC_L2
			l2drop = 1;
#endif
		}
		else if(!R.busy)
			ring_new(xi, Q.lba, 1);
	}
	if(R.busy)
		return;
	if(H.on)                                        // seek hint: the target's sectors while the drive seeks
	{
		const int xi = find_x(H.lba);
		H.on = false;
		if(xi >= 0 && !in_ring(H.lba))
		{
			ring_new(xi, H.lba, KMAX);
			return;
		}
	}
#ifdef CD_SRC_L2
	// the ring's oldest sector into the next spare page (no drive request waiting, the engine free)
	if(!Q.on && !l2mv && R.on && R.cnt && l2n < L2N && !(IO_FLAGS & F_SEC_BUSY) && (!l2n || R.head == l2lba + l2n))
	{
		unsigned pos = l2q + l2n;
		if(pos >= L2N) pos -= L2N;
		IO_SEC_PAGE = l2pg[pos] | (data_at(R.head) ? 0x100 : 0);
		IO_SEC_LBA = R.hs * PAGE_WORDS;
		l2mv = 1;
	}
#endif
	if(R.on)                                        // read-ahead (into the next file too, if it follows on)
	{
		const int32_t nxt = R.head + R.cnt;
		const int xi = find_x(nxt);
		if(xi < 0)                                  // the lead-out, or a hole (read as zeros: no ring)
			return;
		const int32_t rest = D.x[xi].end - nxt;
		unsigned ws = R.hs + R.cnt;
		if(ws >= nslot) ws -= nslot;
		const unsigned toend = nslot - ws;
		unsigned n = nslot - R.cnt;
		if(toend < n) n = toend;
		if(KMAX < n) n = KMAX;
		if(rest < (int32_t)n) n = rest;
		if(n && (n == KMAX || (int32_t)n == rest || n == toend || R.cnt <= 1))
			ring_cmd(xi, nxt, n, ws);
	}
}

unsigned src_read(int32_t lba, unsigned pf)
{
#ifdef CD_SRC_L2
	const unsigned page = pf & 0xFF;
	if(lba == last_lba && page == last_pg)          // (a PAUSE re-read: the drive's page still holds it)
	{
		Q.on = false;
		return page;
	}
	if(l2n && lba >= l2lba && lba < l2lba + l2n)    // in a spare page: swap it with the drive's page
	{
		const unsigned i = lba - l2lba;
		unsigned q = l2q + i;
		if(q >= L2N) q -= L2N;
		const unsigned p = l2pg[q];
		l2pg[q] = page;
		l2q = q + 1 < L2N ? q + 1 : 0;
		l2n -= i + 1;
		l2lba = lba + 1;
		last_lba = lba;
		last_pg = p;
		Q.on = false;
		return p;
	}
	if(l2mv == 1 && lba == R.head)                  // being moved: keep it in the ring, stream it again
		l2mv = 2;
#endif
	Q.on = true;
	Q.pf = pf;
	Q.lba = lba;
	src_poll();
	return pf & 0xFF;
}

bool src_pending(void) { return Q.on; }
void src_cancel(void) { Q.on = false; }

void src_hint(int32_t lba)
{
	H.on = true;
	H.lba = lba;
}
