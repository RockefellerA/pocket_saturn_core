// SMPC firmware runtime: SMPC.sv's MCU peripherals (mapped registers, interrupt flags and edge detectors, timers A and C
// with their prescalers PSS / PSW, the COMREG handshake, the D and R ports, the RAM map) for the translated MCU program.
// Every rule below is SMPC.sv's, applied at the CE edge it happens on, with the values from before that edge.
//
// periph_to(T) processes the CE edges up to T. RT_EDGE builds do every edge (the reference); the default build jumps
// over the edges where nothing can change (see periph_to).
#include "smpc_mcu.h"

mcu_t m;
uint8_t mre[32];
uint8_t stk[64];
periph_t P;
uint32_t mcu_lim;

void mcu_push(unsigned sp, unsigned st, unsigned ca, unsigned pc, void* label)
{
	unsigned e = sp & 0x3C;
	stk[e] = (uint8_t)((st << 3) | ((pc >> 11) & 7)); stk[e + 1] = (pc >> 7) & 15;
	stk[e + 2] = (uint8_t)((ca << 3) | ((pc >> 4) & 7)); stk[e + 3] = pc & 15;
	m.shadow[e >> 2] = label;
}

enum { INTC0_INIT = 0x8, INTC1_INIT = 0xA, INTC2_INIT = 0xA, INTC3_INIT = 0xA, RF2_INIT = 0xA };

// CE edge numbers: P.t0 + n for CE #n since RST_N (P.t0 = 0 in the firmware); 32 bits, they wrap, so times are
// compared through differences
#define REL(t) ((uint32_t)((t) - P.t0))
#define PHASE(t) ((REL(t) - 2) & 3)            // CYC phase of CE edge t (0..3 = CYC[0..3])
static inline int t_lt(uint32_t a, uint32_t b) { return (int32_t)(a - b) < 0; }
static inline __attribute__((unused)) int t_le(uint32_t a, uint32_t b) { return (int32_t)(a - b) <= 0; }
static inline uint32_t next_phase(uint32_t t, int k) { return t + 1 + ((uint32_t)(k - (int)PHASE(t + 1)) & 3); }   // first CYC[k] edge > t



// core INT_PEND: SMPC.sv ORs INT0, INT1, INT2 (twice), TAI, TBI, TCI (INT3 is not in it); the core gets IE & INT_PEND
static inline int pend_any(void)
{
	return ((P.INTC[0] & 0x4) && !(P.INTC[0] & 0x8)) || ((P.INTC[1] & 0x1) && !(P.INTC[1] & 0x2)) ||
	       ((P.RF[2] & 0x1) && !(P.RF[2] & 0x2)) || ((P.INTC[1] & 0x4) && !(P.INTC[1] & 0x8)) ||
	       ((P.INTC[2] & 0x1) && !(P.INTC[2] & 0x2)) || ((P.INTC[2] & 0x4) && !(P.INTC[2] & 0x8));
}
static inline int pend_core(void) { return (P.INTC[0] & 0x1) && pend_any(); }

static void ev_reset(void);
void mcu_reset(int power_on)
{
	// RST_N (and MRES_N at CE #1): SMPC.sv's reset values. Not reset there (they keep their value across RST_N, 0 at
	// power-up): ESR1, the edge detectors' last samples (INT*_OLD), the core's CA, and the RAMs (MR / ERAM, stack).
	if (power_on) { P.ESR1 = 0; P.old0 = P.old1 = P.old2 = P.old3 = 0; m.CA = 0; }
	P.INTC[0] = INTC0_INIT; P.INTC[1] = INTC1_INIT; P.INTC[2] = INTC2_INIT; P.INTC[3] = INTC3_INIT;
	P.PMRB = 0; P.PMRC = 0; P.TMA = 0; P.TMC1 = 0; P.TWCU = P.TWCL = 0; P.TRCU = P.TRCL = 0;
	P.RF[0] = 0; P.RF[1] = 0; P.RF[2] = RF2_INIT; P.RF[3] = 0;
	for (int i = 0; i < 4; i++) P.DCD[i] = 0;
	for (int i = 0; i < 8; i++) { P.DCR[i] = 0; P.R_O[i] = 0; }
	P.D_O = 0;
	P.TCA = P.TCC = 0; P.TA_OVF = P.TC_OVF = 0; P.TC_UPD = 0; P.PSW = 0; P.PSS = 0;
	P.comreg_pend = P.comreg_int = 0;
	P.t = P.t0 + 1;
	P.snap_t = P.t0;
	ev_reset();
	// core: PC 000, SP 3F, ST 1, the rest 0 (HMCS400_CORE reset)
	m.A = m.B = m.X = m.Y = m.W = m.sx = m.sy = 0; m.ST = 1; m.SP = 0x3F;
	m.vt = P.t0 + 1; m.resume = NULL; m.waiting = 0; m.wake_at = m.vt; m.novt_latch = 0; m.sby_latch = 0; m.halted = 0; m.fail = 0;
	for (int i = 0; i < 16; i++) m.shadow[i] = NULL;
}

#ifdef RT_EDGE
// ======================================================================= reference: every CE edge
static const uint16_t pss_mask[8] = { 0x7FF, 0x3FF, 0x1FF, 0x7F, 0x1F, 0x7, 0x3, 0x1 };
static const uint8_t psw_mask[8] = { 0xFF, 0x7F, 0x3F, 0x0F, 0x03, 0, 0, 0 };
static void edge(uint32_t e)
{
	int k = PHASE(e);
	uint8_t tc_upd = P.TC_UPD;
	P.TC_UPD = 0;
	// ---- mapped-register block (interrupt flags)
	if (k == 0) {
		if (P.TA_OVF) P.INTC[1] |= 0x4;                           // IFTA
		if (P.TC_OVF) P.INTC[2] |= 0x4;                           // IFTC
	} else if (k == 1) {
		uint8_t i0 = 1;                                           // INT0_N: D13 = 1 (PMRC.INT0 or not)
		uint8_t i1 = (P.PMRB & 1) ? (uint8_t)!P.comreg_int : 1;   // INT1_N = R00 = ~COMREG_INT
		uint8_t i2 = (P.PMRB & 2) ? w_vbl_n(e) : 0;               // INT2 = R01 = VBLANK
		uint8_t i3 = (P.PMRB & 4) ? 1 : 0;                        // INT3 = R02 = 1
		if (P.old0 && !i0) P.INTC[0] |= 0x4;
		if (P.old1 && !i1) P.INTC[1] |= 0x1;
		switch (P.ESR1 & 3) {
		case 1: if (P.old2 && !i2) P.RF[2] |= 1; break;
		case 2: if (!P.old2 && i2) P.RF[2] |= 1; break;
		case 3: if (P.old2 != i2) P.RF[2] |= 1; break;
		}
		switch ((P.ESR1 >> 2) & 3) {
		case 1: if (P.old3 && !i3) P.RF[2] |= 4; break;
		case 2: if (!P.old3 && i3) P.RF[2] |= 4; break;
		case 3: if (P.old3 != i3) P.RF[2] |= 4; break;
		}
		P.old0 = i0; P.old1 = i1; P.old2 = i2; P.old3 = i3;
	}
	// ---- timers
	{
		int ce32k = REL(e) > 1 && (REL(e) - 1) % 122 == 0;       // CE32K & SMPC_CE: CE #122j+1 (no wrap in RT_EDGE runs)
		uint16_t pss = P.PSS;
		uint8_t psw = P.PSW;
		if (k == 0) P.TA_OVF = 0;
		int ta_clk;
		if (!(P.TMA & 8)) ta_clk = k == 3 && (pss & pss_mask[P.TMA & 7]) == pss_mask[P.TMA & 7];
		else ta_clk = ce32k && (P.TMA & 7) < 5 && (psw & psw_mask[P.TMA & 7]) == psw_mask[P.TMA & 7];
		if (ta_clk) {
			if (P.TCA == 0xFF) P.TA_OVF = 1;
			P.TCA++;
		}
		if ((P.TMA >> 1) == 7) P.TCA = 0;
		if (k == 3 && (pss & pss_mask[P.TMC1 & 7]) == pss_mask[P.TMC1 & 7]) {
			if (P.TCC == 0xFF) { P.TCC = (P.TMC1 & 8) ? (uint8_t)((P.TWCU << 4) | P.TWCL) : 0; P.TC_OVF = 1; }
			else P.TCC++;
		}
		if (tc_upd) P.TCC = (uint8_t)((P.TWCU << 4) | P.TWCL);
		if (k == 3) P.PSS = (pss + 1) & 0x7FF;
		if (ce32k) P.PSW = (P.TMA >> 1) == 7 ? 0 : (uint8_t)(psw + 1);
	}
	// ---- COMREG handshake (CYC[3]); w_comreg: the host's COMREG write, seen by this edge
	if (k == 3) {
		if (w_comreg(e)) P.comreg_pend = 1;
		if (P.comreg_pend && !P.comreg_int) { P.comreg_int = 1; P.comreg_pend = 0; }
		else if ((P.INTC[1] & 1) && P.comreg_int) P.comreg_int = 0;
	}
}

static void ev_reset(void) {}
void periph_to(uint32_t T)
{
	while (t_lt(P.t, T)) {
		uint32_t e = P.t + 1;
		w_sync(e);
		edge(e);
		P.t = e;
	}
}
#define PTO periph_to
uint32_t periph_next_event(uint32_t t) { return t + 1; }
void periph_dirty(void) {}
static inline uint32_t next_ev(void) { return P.t + 1; }
static inline void tcc_to(uint32_t T) { (void)T; }
static inline void reg_wr_pre(int a, uint32_t t) { (void)a; (void)t; }
static inline void reg_wr_post(int a, uint32_t t) { (void)a; (void)t; }
void periph_materialize(uint32_t T) { periph_to(T); }
#else
// ======================================================================= event-driven
// Only the edges where something may change that the program can see are processed ("events"): the interrupt flags,
// the edge detectors' samples, the COMREG handshake, the timer overflows. In between, PSS is closed-form and PSW, TCA
// and TCC are counted when they are needed (psw_at, tca_to, tcc_to). CE edge numbers are 32-bit and wrap (after 18
// minutes): every comparison goes through a difference (t_lt), every count is relative to a recent anchor.
static const uint8_t pss_shift[8] = { 11, 10, 9, 7, 5, 3, 2, 1 };   // TC_CLK, TA_CLK (TMA[3] = 0): every 2^s states
static const uint8_t psw_shift[5] = { 8, 7, 6, 4, 2 };              // TA_CLK (TMA[3] = 1): every 2^s CE32K edges

#define NEVER(t) ((t) + 0x40000000u)
static uint32_t psw_e; static uint8_t psw_v;   // PSW after the edge psw_e (a CE32K edge, or CE #1) is psw_v
static uint32_t c32_next;                       // TMA[3:1] = 7 (PSW cleared at each CE32K edge): the next CE32K edge
static uint32_t tca_e;                          // P.TCA is TCA after the edge tca_e
static uint32_t ta_next, ta_per, ta_ovf;        // TA_CLK on: the first tick after tca_e, the period, the overflow tick
static uint8_t ta_on;
static uint32_t tcc_e, tc_ovf;                  // P.TCC is TCC after the edge tcc_e; TC_OVF = 0: the overflow tick
static uint32_t vbl_seen;                       // the last CYC[1] edge processed (INT2 sampled there)
static uint8_t tca_clr, in_dirty;               // TCA clears at the next edge; INT1 / PMRB changed: sample at CYC[1]
static uint32_t ev_next; static uint8_t ev_valid;   // next_ev(): the next event after P.t, while ev_valid
static uint32_t vbl_nc, com_nc; static uint8_t vbl_ok, com_ok;   // the world's answers, while it learns nothing new
void periph_dirty(void) { ev_valid = 0; vbl_ok = 0; com_ok = 0; }

static inline uint16_t pss_after(uint32_t e) { return (uint16_t)(((REL(e) - 1) >> 2) & 0x7FF); }
// the first CYC[3] edge after t whose pre-edge PSS is all ones in [s-1:0] (CYC[3] edges are REL 4j + 5, PSS = j there)
static uint32_t pss_next(uint32_t t, int s)
{
	uint32_t r = REL(t), m1 = (1u << s) - 1;
	uint32_t j0 = ((r - 5) >> 2) + 1;
	uint32_t j = j0 + ((m1 - j0) & m1);
	return t + (4 * j + 5 - r);
}
static inline uint8_t psw_at(uint32_t e) { return (uint8_t)(psw_v + (e - psw_e) / 122); }
static void psw_anchor(uint32_t e)              // move the anchor to the last CE32K edge <= e
{
	uint32_t k = (e - psw_e) / 122;
	psw_e += 122 * k; psw_v = (uint8_t)(psw_v + k);
}
static void tcc_to(uint32_t T)
{
	if (!t_lt(tcc_e, T)) return;
	int s = pss_shift[P.TMC1 & 7];
	uint32_t f = pss_next(tcc_e, s);
	if (t_le(f, T)) {
		uint32_t v = P.TCC + ((T - f) >> (s + 2)) + 1;
		if (v > 255) {
			P.TC_OVF = 1;
			if (P.TMC1 & 8) {
				uint32_t r = (uint32_t)((P.TWCU << 4) | P.TWCL), d = v - 256;
				v = r + (d < 256 - r ? d : d % (256 - r));
			} else v &= 255;
		}
		P.TCC = (uint8_t)v;
	}
	tcc_e = T;
}
static void tc_setup(uint32_t t)                // TCC is up to date after t: the overflow tick
{
	int s = pss_shift[P.TMC1 & 7];
	tc_ovf = pss_next(t, s) + ((255u - P.TCC) << (s + 2));
}
static void tca_to(uint32_t T)
{
	if (!t_lt(tca_e, T)) return;
	if (ta_on && t_le(ta_next, T)) {             // fewer ticks than to the overflow (that one is an event)
		uint32_t n = (T - ta_next) / ta_per + 1;
		P.TCA = (uint8_t)(P.TCA + n);
		ta_next += n * ta_per;
	}
	tca_e = T;
}
static void ta_setup(uint32_t t)                // TMA set at the edge t (TCA up to date after t)
{
	ta_on = 0;
	if (!(P.TMA & 8)) {
		int s = pss_shift[P.TMA & 7];
		ta_per = 4u << s; ta_next = pss_next(t, s); ta_on = 1;
	} else if ((P.TMA & 7) < 5) {
		int s = psw_shift[P.TMA & 7];
		uint32_t m1 = (1u << s) - 1;
		uint32_t k0 = (t - psw_e) / 122 + 1;                   // the first CE32K edge after t: psw_e + 122 k0
		uint32_t k = k0 + ((0u - psw_v - k0) & m1);             // its pre-edge PSW, psw_v + k - 1, all ones in [s-1:0]
		ta_next = psw_e + 122 * k; ta_per = 122u << s; ta_on = 1;
	}
	tca_e = t;
	if (ta_on) ta_ovf = ta_next + (ta_per << 8) - ta_per * (uint32_t)(1 + P.TCA);
}
static void ev_reset(void)
{
	uint32_t t = P.t;
	ev_valid = 0; vbl_ok = 0; com_ok = 0;
	psw_e = t; psw_v = 0; c32_next = NEVER(t);
	tcc_e = t; tca_e = t; tca_clr = 0; in_dirty = 1; vbl_seen = t;   // the first CYC[1] edge samples the inputs
	ta_setup(t); tc_setup(t);
}

uint32_t periph_next_event(uint32_t t)
{
	if (P.TC_UPD || tca_clr) return t + 1;
	uint32_t n = NEVER(t), x;
	uint32_t t1 = t + 1, ph = PHASE(t1);
#define NP(k) (t1 + (((k) - ph) & 3))               // next_phase(t, k), with PHASE(t + 1) computed once
#define EV(x_) do { x = (x_); if (t_lt(x, n)) n = x; } while (0)
	if (P.TA_OVF || (P.TC_OVF && !(P.INTC[2] & 4))) EV(NP(0));
	if (in_dirty) EV(NP(1));
	else if (P.PMRB & 2) {
		if (!vbl_ok) { vbl_nc = w_vbl_next(vbl_seen); vbl_ok = 1; }
		uint32_t c = vbl_nc;
		if (c) EV(t_lt(c - 1, t) ? NP(1) : next_phase(c - 1, 1));
	}
	if ((P.comreg_pend && !P.comreg_int) || (P.comreg_int && (P.INTC[1] & 1))) EV(NP(3));
	else {
		if (!com_ok) { com_nc = w_comreg_next(); com_ok = 1; }
		uint32_t c = com_nc;
		if (c) EV(t_lt(c - 1, t) ? NP(3) : next_phase(c - 1, 3));
	}
#undef NP
	if (ta_on) EV(ta_ovf);
	if (!P.TC_OVF) EV(tc_ovf);
	if ((P.TMA >> 1) == 7) EV(c32_next);
#undef EV
	return n;
}

// the next event after P.t, kept until the state or the world's knowledge changes (periph_dirty)
static inline uint32_t next_ev(void)
{
	if (!ev_valid) { ev_next = periph_next_event(P.t); ev_valid = 1; }
	return ev_next;
}

static void __attribute__((noinline)) edge_ev(uint32_t e)
{
	int k = PHASE(e);
	P.nev++;
	ev_valid = 0;
	uint8_t tc_upd = P.TC_UPD;
	P.TC_UPD = 0;
	if (k == 0) {
		if (P.TA_OVF) P.INTC[1] |= 0x4;
		if (P.TC_OVF) P.INTC[2] |= 0x4;
		P.TA_OVF = 0;
	} else if (k == 1) {
		uint8_t i0 = 1;
		uint8_t i1 = (P.PMRB & 1) ? (uint8_t)!P.comreg_int : 1;
		uint8_t i2 = (P.PMRB & 2) ? w_vbl_n(e) : 0;
		uint8_t i3 = (P.PMRB & 4) ? 1 : 0;
		if (P.old0 && !i0) P.INTC[0] |= 0x4;
		if (P.old1 && !i1) P.INTC[1] |= 0x1;
		switch (P.ESR1 & 3) {
		case 1: if (P.old2 && !i2) P.RF[2] |= 1; break;
		case 2: if (!P.old2 && i2) P.RF[2] |= 1; break;
		case 3: if (P.old2 != i2) P.RF[2] |= 1; break;
		}
		switch ((P.ESR1 >> 2) & 3) {
		case 1: if (P.old3 && !i3) P.RF[2] |= 4; break;
		case 2: if (!P.old3 && i3) P.RF[2] |= 4; break;
		case 3: if (P.old3 != i3) P.RF[2] |= 4; break;
		}
		P.old0 = i0; P.old1 = i1; P.old2 = i2; P.old3 = i3;
		in_dirty = 0; vbl_seen = e; vbl_ok = 0;
	}
	// timer A: the overflow tick (tca_to counts the others)
	if (ta_on && e == ta_ovf) {
		P.TCA = 0; P.TA_OVF = 1; tca_e = e;
		ta_next = e + ta_per; ta_ovf = ta_next + (ta_per << 8) - ta_per;   // the 256th tick from here
		psw_anchor(e);
	}
	if (tca_clr) { tca_clr = 0; P.TCA = 0; tca_e = e; }   // TMA[3:1] = 7 (TA_CLK off): TCA cleared at every edge
	// timer C: counted lazily (tcc_to by whoever reads it); here only for the reload after a TWCU write and for the
	// overflow tick (TC_OVF: SMPC.sv never clears it, so only the first one is an event)
	if (tc_upd) { tcc_to(e); P.TCC = (uint8_t)((P.TWCU << 4) | P.TWCL); tc_setup(e); }
	else if (!P.TC_OVF && e == tc_ovf) tcc_to(e);
	// PSW: cleared at the CE32K edges while TMA[3:1] = 7
	if ((P.TMA >> 1) == 7 && e == c32_next) { psw_v = 0; psw_e = e; c32_next = e + 122; }
	if (k == 3) {
		if (w_comreg(e)) { P.comreg_pend = 1; com_ok = 0; }
		if (P.comreg_pend && !P.comreg_int) { P.comreg_int = 1; P.comreg_pend = 0; in_dirty = 1; }
		else if ((P.INTC[1] & 1) && P.comreg_int) { P.comreg_int = 0; in_dirty = 1; }
	}
}

static void __attribute__((noinline)) periph_to_slow(uint32_t T)
{
	w_sync(T);
	for (;;) {
		uint32_t e = next_ev();
		if (t_lt(T, e)) break;
		edge_ev(e);
		P.t = e;
	}
	P.t = T;
	if (T - psw_e > 0x10000000u) psw_anchor(T);          // keep the PSW anchor recent (TA off for minutes)
}
// up to T: nothing to do before the next event when the world knows the inputs that far (fast build: mcu_lim)
static inline void PTO(uint32_t T)
{
	if (!t_lt(P.t, T)) return;
#ifndef MCU_FAITHFUL
	if (!t_lt(mcu_lim, T) && t_lt(T, next_ev())) { P.t = T; return; }
#endif
	periph_to_slow(T);
}
void periph_to(uint32_t T) { PTO(T); }

// a mapped-register write at the edge t: bring the counted values up to t first, set up the new rate after it
static void reg_wr_pre(int a, uint32_t t)
{
	if (a == 0x08) tca_to(t);
	if (a == 0x0D || a == 0x0E || a == 0x0F) tcc_to(t);
}
static void reg_wr_post(int a, uint32_t t)
{
	if (a == 0x08) {
		if ((P.TMA >> 1) == 7) {
			ta_on = 0; tca_clr = 1;
			c32_next = psw_e + 122 * ((t - psw_e) / 122 + 1);
		} else ta_setup(t);
	}
	if (a == 0x0D) tc_setup(t);
	if (a == 0x24) in_dirty = 1;
}
// fill in P.PSS, P.PSW, P.TCA, P.TCC as they are after the edge T (for comparisons)
void periph_materialize(uint32_t T)
{
	PTO(T);
	P.PSS = pss_after(T); P.PSW = psw_at(T);
	tca_to(T); tcc_to(T);
}
#endif

// ---- mapped registers. A read at the state's CYC[3] edge t sees the values before that edge; the TRCU read latches
// TCC at CYC[2] (t - 1). A write lands at the edge t, after that edge's own updates.
uint8_t reg_rd(int a, uint32_t t)
{
	if (a == 0x0F) { PTO(t - 2); w_sync(t - 1); tcc_to(t - 2); P.TRCU = P.TCC >> 4; P.TRCL = P.TCC & 15; }
	PTO(t - 1);
	switch (a) {
	case 0x00: case 0x01: case 0x02: case 0x03: return P.INTC[a];
	case 0x0E: return P.TRCL;
	case 0x0F: return P.TRCU;
	case 0x20: case 0x21: case 0x22: case 0x23: return P.RF[a - 0x20];
	case 0x26: return P.ESR1;
	default: return 0;
	}
}

void reg_wr(int a, uint8_t v, uint32_t t)
{
	PTO(t - 1);
	int before = pend_core();
	PTO(t);
	P.snap_t = t; P.snap_pend = (uint8_t)before;
	v &= 15;
#ifndef RT_EDGE
	uint8_t ev_in = (uint8_t)((P.INTC[1] & 1) | (P.INTC[2] & 4));
#endif
	reg_wr_pre(a, t);
	switch (a) {
	case 0x00: case 0x01: case 0x02: case 0x03: P.INTC[a] = v; break;
	case 0x08: P.TMA = v; break;
	case 0x0D: P.TMC1 = v; break;
	case 0x0E: P.TWCL = v; break;
	case 0x0F: P.TWCU = v; break;
	case 0x20: case 0x21: case 0x22: case 0x23: P.RF[a - 0x20] = v; break;
	case 0x24: P.PMRB = v; break;
	case 0x25: P.PMRC = v; break;
	case 0x26: P.ESR1 = v; break;
	case 0x2C: case 0x2D: case 0x2E: case 0x2F: P.DCD[a - 0x2C] = v; break;
	case 0x30: case 0x31: case 0x32: case 0x33: case 0x34: case 0x35: case 0x36: case 0x37: P.DCR[a - 0x30] = v; break;
	default: break;
	}
	if (a == 0x0F) P.TC_UPD = 1;                  // SMPC.sv: TC_UPD <= (BUS_A[5:0] == 0x0F) on a write
	reg_wr_post(a, t);
#ifndef RT_EDGE
	// the events depend on IF1, IFTC, TMA, TMC1, a TWCU write (TC_UPD), PMRB
	if (a == 0x08 || a == 0x0D || a == 0x0F || a == 0x24 || ((P.INTC[1] & 1) | (P.INTC[2] & 4)) != ev_in) ev_valid = 0;
#endif
	if (a >= 0x2C && a <= 0x2F) {
		uint16_t dd = (uint16_t)(P.DCD[0] | (P.DCD[1] << 4) | (P.DCD[2] << 8) | (P.DCD[3] << 12));
		w_d_out((uint16_t)(P.D_O | ~dd), t);
	}
	if (a >= 0x30 && a <= 0x37) w_r_out(a - 0x30, P.R_O[a - 0x30], P.DCR[a - 0x30], t);
}

int int_latch(uint32_t t)
{
	PTO(t - 1);
	if (P.snap_t == t) return P.snap_pend;
	return pend_core();
}

int int_vector(uint32_t t)
{
	PTO(t - 1);
	int i0 = (P.INTC[0] & 0x4) && !(P.INTC[0] & 0x8), i1 = (P.INTC[1] & 0x1) && !(P.INTC[1] & 0x2);
	int i2 = (P.RF[2] & 0x1) && !(P.RF[2] & 0x2), i3 = (P.RF[2] & 0x4) && !(P.RF[2] & 0x8);
	int ta = (P.INTC[1] & 0x4) && !(P.INTC[1] & 0x8), tb = (P.INTC[2] & 0x1) && !(P.INTC[2] & 0x2);
	int tc = (P.INTC[2] & 0x4) && !(P.INTC[2] & 0x8);
	if (i0) return 1;
	if (i1) return 2;
	if (ta) return 3;
	if (tb || i2) return 4;
	if (tc || i3) return 5;
	return 0;
}

void int_accept(uint32_t t) { PTO(t); P.INTC[0] &= ~1; }
void int_return(uint32_t t) { PTO(t); P.INTC[0] |= 1; }

uint32_t wake_time(uint32_t t)
{
	// SBY from the edge t: SBY clears at the first CYC[3] edge after t whose pre-edge INT_PEND (any IE) is set. The
	// flags change only at peripheral events: go from event to event while the world knows the inputs that far
	// (0 = it does not yet: m.waiting, call again later with the same t).
	if (t_lt(P.t, t + 3)) {
		if (t_lt(w_limit(), t + 3)) { m.waiting = 1; m.wake_at = t + 3; return 0; }
		PTO(t + 3);
		if (pend_any()) { m.waiting = 0; return t + 4; }
	}
	for (;;) {
		uint32_t n = next_ev();
		if (t_lt(w_limit(), n)) { m.waiting = 1; m.wake_at = n; return 0; }
		PTO(n);
		if (pend_any()) { m.waiting = 0; return next_phase(n, 3); }
	}
}

// ---- ports. D: IO_DO = 4 copies of (D_I[N] & ~D_D[N]) | (D_O[N] & D_D[N]); D_I = {11, D13=1, 1..1, D3, D2=0, D1=1, 1}.
static inline uint16_t dd(void) { return (uint16_t)(P.DCD[0] | (P.DCD[1] << 4) | (P.DCD[2] << 8) | (P.DCD[3] << 12)); }
uint8_t io_rd_d(int n, uint32_t t)
{
	PTO(t - 1);
	w_sync(t);
	uint16_t di = (uint16_t)(0xFFF3 | ((w_d3(t) & 1) << 3) | 0x0002);   // D2 = 0, D1 = 1, D0 = 1
	di &= (uint16_t)~(1u << 2);
	int b = ((dd() >> n) & 1) ? (P.D_O >> n) & 1 : (di >> n) & 1;
	return b ? 15 : 0;
}
// (outputs do not depend on the peripherals' state: no PTO before them)
void io_wr_d(int n, uint8_t v, uint32_t t)
{
	P.D_O = (uint16_t)((P.D_O & ~(1u << n)) | ((v & 1u) << n));
	w_d_out((uint16_t)(P.D_O | ~dd()), t);
}
// R: IO_DO = (Rn_I & ~DCRn) | (Rn_O & DCRn); n > 7 reads 1111. R0_I = {1, 1, R01 (VBLANK), ~COMREG_INT};
// R1 = PIOA_I[3:0], R2 = {PIOA_I[6:4], 0}, R3 / R4 the same for port B, R5 = area, R6 = {0, 0, R61 = 1, R60 = 0}, R7 = 0.
uint8_t io_rd_r(int n, uint32_t t)
{
	if (n > 7) return 15;
	PTO(t - 1);
	w_sync(t);
	uint8_t in;
	switch (n) {
	case 0: in = (uint8_t)(0xC | (w_vbl_n(t) << 1) | !P.comreg_int); break;
	case 1: in = w_pio(0, t) & 15; break;
	case 2: in = (uint8_t)((w_pio(0, t) >> 3) & 0xE); break;
	case 3: in = w_pio(1, t) & 15; break;
	case 4: in = (uint8_t)((w_pio(1, t) >> 3) & 0xE); break;
	case 5: in = w_area() & 15; break;
	case 6: in = 0x2; break;
	default: in = 0; break;
	}
	return (uint8_t)((in & ~P.DCR[n]) | (P.R_O[n] & P.DCR[n])) & 15;
}
void io_wr_r(int n, uint8_t v, uint32_t t)
{
	if (n > 7) return;
	P.R_O[n] = (n == 7) ? (v & 7) : (v & 15);    // SMPC.sv: R7_O <= BUS_DO & 4'h7
	w_r_out(n, P.R_O[n], P.DCR[n], t);
}
uint8_t io_rd_v(int iop, int a, uint32_t t)
{
	if ((a >> 6) == 0xF) return stk[a & 63];
	return iop ? io_rd_r(a & 15, t) : io_rd_d(a & 15, t);
}
void io_wr_v(int iop, int a, uint8_t v, uint32_t t)
{
	if (iop) io_wr_r(a & 15, v, t); else io_wr_d(a & 15, v & 1, t);
}

// ---- RAM map (SMPC.sv): 000-03F mapped registers, 040-04F MR, 260-26F ERAM (bit 3 of 265 reads 1), 320-35F OREG and
// 360-36F SR / SF (write only, read 0), 3C0-3FF the stack RAM; anything else reads 0 and ignores writes.
static uint8_t oreg_shadow[32], sr_shadow;
uint8_t ram_rd(int a, uint32_t t)
{
	a &= 0x3FF;
	if (a <= 0x03F) return reg_rd(a, t);
	if (a >= 0x040 && a <= 0x04F) return mre[a & 15];
	if (a >= 0x260 && a <= 0x26F) return (uint8_t)(mre[16 + (a & 15)] | ((a & 15) == 5 ? 8 : 0));
	if (a >= 0x3C0) return stk[a & 63];
	return 0;
}
void ram_wr(int a, uint8_t v, uint32_t t)
{
	a &= 0x3FF; v &= 15;
	if (a <= 0x03F) reg_wr(a, v, t);
	else if (a >= 0x040 && a <= 0x04F) mre[a & 15] = v;
	else if (a >= 0x260 && a <= 0x26F) mre[16 + (a & 15)] = v;
	else if (a >= 0x320 && a <= 0x35F) oreg_wr(a, v, t);
	else if (a >= 0x360 && a <= 0x36F) sreg_wr(a, v, t);
	else if (a >= 0x3C0) stk[a & 63] = v;
}
void oreg_wr(int a, uint8_t v, uint32_t t)
{
	int i = (a >> 1) & 31;
	if (a & 1) oreg_shadow[i] = (uint8_t)((oreg_shadow[i] & 0xF0) | (v & 15));
	else oreg_shadow[i] = (uint8_t)((oreg_shadow[i] & 0x0F) | ((v & 15) << 4));
	w_oreg(i, oreg_shadow[i], t);
}
void sreg_wr(int a, uint8_t v, uint32_t t)
{
	switch (a & 15) {
	case 0: sr_shadow = (uint8_t)((sr_shadow & 0x0F) | ((v & 15) << 4)); w_sr(sr_shadow, t); break;
	case 1: sr_shadow = (uint8_t)((sr_shadow & 0xF0) | (v & 15)); w_sr(sr_shadow, t); break;
	case 2: w_sfclr(t); break;
	default: break;
	}
}

// ---- ROM reads that are not instructions: P (the pattern word at {00, p, B, A}, read at CYC[1] = t): IREG at FF0-FFF
// ({01, IREG[A & 7]}), else the ROM (the program reads only its month table, 011-01C, this way). And the RTC override of
// 0681-068E (the LMIIY immediates of the default time) from RTC_INIT.
uint16_t rom_pattern(int a, uint32_t t)
{
	if ((a & 0x3FF0) == 0x0FF0) { PTO(t - 1); w_sync(t); return (uint16_t)(0x100 | w_ireg(a & 7, t)); }
	if ((a & 0x7F0) == 0x010) return mcu_rom_010[a & 15];
	w_fail(0x20000 | a);
	return 0;
}
uint8_t rtc_init(int i, uint32_t t)
{
	PTO(t - 1);
	w_sync(t);
	return w_rtc_init(i) & 15;
}

#if !defined(MCU_FAITHFUL) && !defined(RT_EDGE)
// ---- fast build: idle loops (gen_mcu.py IDLE). A loop pass depends only on the registers at the head and on what its
// body reads: the peripheral flags (they change only at peripheral events), R0 (VBLANK, COMREG_INT: VBLANK changes,
// events), TRCU / TRCL (timer C ticks). If the last pass started from the same registers as this one and nothing it
// reads changed during it, the next passes repeat it as long as nothing it reads changes: skip them.
#ifdef MCU_PROFILE
uint32_t mcu_count[2048];
#endif
typedef struct { uint32_t vt, k0, k1, nev, per; uint8_t valid, fix; } idle_t;
static idle_t idl[MCU_NIDLE];
static int idle_changed(int h, uint32_t a, uint32_t b)      // an input of the body (besides the flags) changed in (a, b]
{
	if (h & IDLE_VBL) { uint32_t c = w_vbl_next(a); if (c && t_le(c, b)) return 1; }
	if (h & IDLE_TCC) { if (t_le(pss_next(a, pss_shift[P.TMC1 & 7]), b)) return 1; }
	return 0;
}
#ifdef IDLE_DEBUG
void idle_dbg(int i, uint32_t vt, uint32_t per, uint32_t ne, uint32_t he, uint32_t lim, uint32_t skip, int wait);
#endif
uint32_t idle_head(int i, int h, uint32_t vt, uint32_t k0, uint32_t k1)
{
	idle_t* r = &idl[i];
	uint32_t per = 0;
	m.waiting = 0;
	PTO(vt);
	if (r->valid && r->k0 == k0 && r->k1 == k1 && r->nev == P.nev) {
		uint32_t d = vt - r->vt;
		if (!d) { if (r->fix) per = r->per; }                  // run again after a stop here
		else if (!idle_changed(h, r->vt, vt)) per = d;         // a pass (or skipped passes and a pass) since
	}
	r->vt = vt; r->k0 = k0; r->k1 = k1; r->nev = P.nev; r->valid = 1; r->fix = 0;
	if (!per || per > 0x10000) return 0;
	// the passes that end by the edge `he` read what this one read: the next peripheral event changes the flags after
	// its edge; a VBLANK change at c is seen by reads at c on; a timer C tick at x by TRCU reads at x + 2 on
	uint32_t he = next_ev(), x;
	if (h & IDLE_VBL) { x = w_vbl_next(vt); if (x && t_lt(x - 1, he)) he = x - 1; }
	if (h & IDLE_TCC) {
		int s = pss_shift[P.TMC1 & 7];
		x = pss_next(vt, s);
		if ((h & IDLE_TCMP) && (per == 24 || per == 56) && !P.TC_UPD) {
			// the passes keep their path while TC is below the threshold of that path (TRCU < ERAM0: ERAM0 * 16; else
			// ERAM0:ERAM1): the tick that reaches it, (thr - TC) ticks on (TC counts up to it, no reload before)
			unsigned thr = per == 24 ? (unsigned)mre[16] << 4 : ((unsigned)mre[16] << 4) | mre[17];
			tcc_to(vt);
			if (P.TCC < thr) x += (uint32_t)(thr - P.TCC - 1) << (s + 2);
		}
		if (t_lt(x, he)) he = x;
	}
	uint32_t wake = he, lim = w_limit(), skip = 0;
	int wait = t_lt(lim, he);
	if (wait) he = lim;
	if (t_le(vt + per, he)) { uint32_t d = he - vt; skip = d - d % per; }
	if (skip || wait) { r->fix = 1; r->per = per; r->vt = vt + skip; }
	if (wait) { m.waiting = 1; m.wake_at = wake; }   // the world does not know the inputs that far: stop here
#ifdef IDLE_DEBUG
	idle_dbg(i, vt, per, next_ev(), he, lim, skip, wait);
#endif
	return skip;
}
#endif

#ifdef MCU_FAITHFUL
int mcu_step_stop;
static const uint16_t* ret_pcs; static void* const* ret_labels; static int ret_n;
void mcu_ret_tables(const uint16_t* pcs, void* const* labels, int n) { ret_pcs = pcs; ret_labels = labels; ret_n = n; }
// RTN: the label from the shadow stack must be the one of the PC in the RAM stack
int rtn_check(uint16_t pc, void* l)
{
	for (int i = 0; i < ret_n; i++) if (ret_pcs[i] == pc) return ret_labels[i] == l;
	return 0;
}
#endif
