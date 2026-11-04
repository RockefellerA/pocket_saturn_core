#!/usr/bin/env python3
# HMCS400 -> C translator for the SMPC ROM (rtl/Saturn/SMPC/smpc.mif).
#
# Every reachable instruction of the ROM becomes straight C code that does what HMCS400_CORE (with SMPC.sv's memory and
# port map) does for it, state by state. The instruction semantics are not written by hand: they come from the decoder
# (the exhaustive dump of HMCS400_PKG::IDecode(), sim/s4_sys_smpc/idecode_dump.txt: DecInstr_t for every IC, STATE, ST,
# DA_COND) and the core's datapath (operand selects, ALU, register / memory / port writes, PC update), so the C is the
# RTL's behaviour for that opcode. Time (vt) is counted in SMPC_CE edges: every instruction state ends on a CYC[3] edge,
# 4 CE after the previous one.
#
# Output: mcu_exec() in smpc_mcu_gen.c, a coroutine that runs the MCU program from m.resume:
#   - the MCU registers are locals while it runs and live in the struct m between runs (MCU_SAVE / MCU_LOAD);
#   - every access to something outside the core (ports, mapped registers, IREG read by the pattern instruction, OREG / SR
#     writes and the SF clear, the RTC override of 0681-068E, any {W,X,Y}-addressed access) calls the runtime with the
#     CE time of the access; such an instruction starts with MCU_IO(label), where the runtime may stop the run (the
#     instruction then runs again from its start on the next call: nothing in it before the access has an effect);
#   - RTN / RTNI return through a shadow stack of label addresses; the RAM stack is written as on the chip and the faithful
#     build checks that it agrees;
#   - TBR (the command dispatch, TBR 1 at 00FF) is a computed jump through a 16-entry table per page;
#   - interrupts: MCU_STEP at the main-loop instructions (the only place IE can be 1) asks the runtime whether the
#     interrupt sequence comes before this instruction;
#   - SBY / STOP: MCU_SLEEP.
#   - FAITHFUL=1: every instruction boundary is a stop point (MCU_STEP everywhere): the lockstep test against the RTL.
#     Otherwise (fast) the idle loops listed in IDLE wait through MCU_IDLE and the delay routine 00D6 is replaced.
# usage: gen_mcu.py smpc.mif idecode_dump.txt out.c [FAITHFUL]
import sys, re, os

FIELDS = [('ALUAS', 3), ('ALUBS', 3), ('ALUOP', 3), ('ALUCD', 3), ('AW', 1), ('BW', 1), ('XW', 1), ('YW', 1), ('XE', 1),
          ('YE', 1), ('WW', 1), ('CAU', 3), ('STU', 3), ('MA', 2), ('MD', 2), ('MR', 1), ('MW', 1), ('PCU', 3), ('SPI', 1),
          ('SPD', 1), ('PI', 1), ('SBY', 1), ('STOP', 1), ('IWR', 1), ('IOW', 1), ('IOR', 1), ('IOP', 1), ('LST', 1), ('ILI', 1)]
AAS = ['A', 'B', 'Y', 'M', 'I', 'ZERO', 'SPX', 'SPY']
ABS = ['A', 'B', 'M', 'I', 'ONE', 'ZERO', 'BIT', 'NONE']
ALUOP = {0: 'NOP', 1: 'ADD', 2: 'BIT', 3: 'LOG', 4: 'A', 5: 'B', 6: 'NOP', 7: 'NOP'}
CAU = {0: 'NOP', 1: 'ALU', 2: 'ONE', 3: 'ZERO', 4: 'RTN', 5: 'NOP', 6: 'NOP', 7: 'NOP'}
STU = {0: 'NOP', 1: 'NZ', 2: 'NB', 3: 'C', 4: 'CA', 5: 'SET', 6: 'RTN', 7: 'PD'}
MA = {0: 'ADR', 1: 'MR', 2: 'STK1', 3: 'STK2'}
MD = {0: 'A', 1: 'B', 2: 'I', 3: 'ALU'}
PCU = {0: 'INC', 1: 'BR', 2: 'BRL', 3: 'ZP', 4: 'TBR', 5: 'NU', 6: 'RTN', 7: 'INT'}

H = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, H)
from hmdis import dis as _dis


def unpack(v):
    d = {}; pos = 45
    for n, w in FIELDS:
        pos -= w; d[n] = (v >> pos) & ((1 << w) - 1)
    return d


def load_mif(p):
    rom = [0] * 2048
    for l in open(p):
        m = re.match(r'\s*([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f]+);', l)
        if m: rom[int(m.group(1), 16)] = int(m.group(2), 16)
    return rom


rom = load_mif(sys.argv[1])
DEC = {}
for l in open(sys.argv[2]):
    ic, st, it, t, da, v = l.split()
    DEC[(int(ic, 16), int(st), int(it), int(t), int(da))] = unpack(int(v, 16))
OUT = sys.argv[3]
FAITHFUL = len(sys.argv) > 4 and sys.argv[4] == '1'


def deci(ic, state, st, da):
    return DEC[(ic, state, 0, st, da)]


def dis(pc): return _dis(rom, pc)[0]


def states(ic, st, da):
    """the DECI of each state of the instruction for this ST / DA_COND"""
    out = []; s = 0
    while True:
        d = deci(ic, s, st, da)
        out.append(d)
        if d['LST']: break
        s += 1
        assert s < 3
    return out


def length(ic):
    return 2 if deci(ic, 0, 1, 1)['IWR'] else 1


def targets(pc):
    """(next instructions, is_call) for both ST values"""
    ic = rom[pc]; n = length(ic)
    out = set()
    for st in (0, 1):
        cur = pc
        for s, d in enumerate(states(ic, st, 1)):
            p = PCU[d['PCU']]
            if p == 'BR': out.add(((pc + 1) & 0x3F00) | (ic & 0xFF)); cur = None
            elif p == 'BRL': out.add(((ic & 0xF) << 10) | rom[(pc + 1) & 0x7FF]); cur = None
            elif p == 'ZP': out.add(ic & 0x3F); cur = None
            elif p in ('TBR', 'RTN'): cur = None
            if cur is None: break
        if cur is not None: out.add(pc + n)
    return out


def is_call(pc):
    ic = rom[pc]
    for st in (0, 1):
        for d in states(ic, st, 1):
            if MA[d['MA']] in ('STK1', 'STK2') and d['MW']: return True
    return False


# ------------------------------------------------------------------ reachability
ENTRIES = [0x000, 0x002, 0x004, 0x006, 0x008, 0x00A] + list(range(0x100, 0x120))   # reset, vectors, TBR 1 table
code = {}
work = list(ENTRIES)
while work:
    pc = work.pop()
    if pc in code or pc >= 2048: continue
    code[pc] = rom[pc]
    for s in targets(pc): work.append(s & 0x3FFF)
    if is_call(pc): work.append(pc + length(rom[pc]))
TBR_SITES = [pc for pc in code if PCU[deci(code[pc], 0, 1, 1)['PCU']] == 'TBR']
assert TBR_SITES == [0x0FF], TBR_SITES
RET_POINTS = sorted(pc + length(code[pc]) for pc in code if is_call(pc))
# interrupts can only be taken where IE is 1: the main loop (IE set at 0698; every handler runs with IE 0 until its RTNI,
# which returns into the main loop), checked from the instruction after 0698 on
MAIN_LOOP = [0x69A, 0x69C, 0x69D, 0x69E, 0x69F, 0x6A0]
for pc in MAIN_LOOP: assert pc in code

LABELS = set(ENTRIES) | set(RET_POINTS) | set(MAIN_LOOP)
for pc in code:
    for s in targets(pc):
        if s != pc + length(code[pc]): LABELS.add(s & 0x3FFF)
LEAD = set(LABELS)          # fast build: the instructions that start a block (more are added below)
for pc in code:             # every goto target needs its label (also a branch to the next instruction)
    ic = code[pc]
    for st in (0, 1):
        for d in states(ic, st, 1):
            p_ = PCU[d['PCU']]
            if p_ == 'BR': LEAD.add(((pc + 1) & 0x3F00) | (ic & 0xFF))
            elif p_ == 'BRL': LEAD.add(((ic & 0xF) << 10) | rom[(pc + 1) & 0x7FF])
            elif p_ == 'ZP': LEAD.add(ic & 0x3F)

# ------------------------------------------------------------------ fast-mode replacements
# Idle loops: head -> (last instruction of the loop, the inputs its body reads besides the peripheral flags). The body
# (the instructions on a path from the head back to it, checked below) writes no memory, port or stack: one pass
# depends only on the registers at the head and on what it reads. MCU_IDLE at the head (runtime idle_head()): when a
# pass started from the same registers as this one, and nothing it reads changed during it, the next passes repeat it
# until something it reads can change: vt skips over them (and the run stops there if the world does not know its
# inputs that far yet).
# The delay routine 00D6-00EC (called as CALS 00F) counts MR1 / MR0 / B down from constants: it is replaced by its
# result (checked against the listing below; the bench compares the fast build with the reference).
IDLE = {0x265: (0x26D, 'IDLE_VBL'), 0x275: (0x27B, 'IDLE_VBL'), 0x27E: (0x285, 'IDLE_VBL'), 0x2B9: (0x2C7, 'IDLE_TCC | IDLE_TCMP')}
# IDLE_TCMP (the runtime's idle_head relies on this exact loop): wait until timer C >= ERAM0:ERAM1. A pass is 24 CE
# while TRCU < ERAM0 (02B9 02BB 02BD 02BE), 56 CE while TRCU = ERAM0 and TRCL < ERAM1 (... 02BF 02C1 02C2 02C4 02C6
# 02C7): the passes take the same path until TC reaches ERAM0 * 16 resp. ERAM0:ERAM1, not only until its next tick
TCMP_LISTING = ['LAMD ERAM0', 'ALEMD TWCU/TRCU', 'BR 02BF', 'BR 02B9', 'ANEMD TWCU/TRCU', 'BR 028D', 'LAMD ERAM1',
                'ALEMD TWCL/TRCL', 'BR 028D', 'BR 02B9']
IDLE_ID = {pc: i for i, pc in enumerate(sorted(IDLE))}
DELAY = (0x0D6, 0x0EC)
# the routine as the closed form below assumes it (MR1 = MR0 = A, B = 0; three nested count-downs of 16 / 11 / 11)
DELAY_LISTING = ['LMID A,MR1', 'LMID A,MR0', 'LBI 0', 'LAI F', 'AI F', 'BR 00DC', 'LAB', 'AI F', 'LBA', 'BR 00DB',
                 'LAMR MR0', 'AI F', 'LMAD MR0', 'BR 00DB', 'LAMR MR1', 'AI F', 'LMAD MR1', 'BR 00DB', 'RTN']

def check_fast():
    # the delay routine: exactly the listing above, and entered only at its start
    pcs = []; pc = DELAY[0]
    while pc <= DELAY[1]:
        pcs.append(pc); pc += length(rom[pc])
    assert [dis(p) for p in pcs] == DELAY_LISTING, [dis(p) for p in pcs]
    for p in code:
        if p in pcs: continue
        for t in targets(p):
            assert not (DELAY[0] < (t & 0x3FFF) <= DELAY[1] - 1), 'delay routine entered at %03X from %03X' % (t, p)
    # idle loops: no memory, port or stack write in the body (the window head .. head + 1F)
    for head in IDLE:
        end = IDLE[head][0]
        fwd = set(); work = [head]
        while work:
            p = work.pop()
            if p in fwd or not (head <= p <= end): continue
            fwd.add(p)
            for t in targets(p): work.append(t & 0x3FFF)
        # the body: the instructions on a path from the head back to it
        body = {head}; grow = True
        while grow:
            grow = False
            for p in fwd - body:
                if any((t & 0x3FFF) in body for t in targets(p)): body.add(p); grow = True
        assert len(body) > 1, 'not a loop at %03X' % head
        IDLE_BODY[head] = sorted(body)
        if 'IDLE_TCMP' in IDLE[head][1]:
            assert [dis(p) for p in sorted(body)] == TCMP_LISTING, [dis(p) for p in sorted(body)]
        for p in body:
            ic = code[p]
            for st in (0, 1):
                for d in states(ic, st, 1):
                    assert not (d['MW'] or d['IOW'] or d['SPI'] or d['SPD'] or d['SBY'] or d['STOP']), \
                        'idle loop %03X: %03X %s writes' % (head, p, dis(p))
                    assert PCU[d['PCU']] not in ('TBR', 'RTN', 'INT'), 'idle loop %03X: %03X' % (head, p)
IDLE_BODY = {}
DELAY_SKIP = set()
LEAD |= set(IDLE) | {DELAY[1]}
if not FAITHFUL:
    check_fast()
    for h in sorted(IDLE_BODY): print('idle loop %03X: %s' % (h, ' '.join('%03X' % p for p in IDLE_BODY[h])), file=sys.stderr)
    pc = DELAY[0] + length(rom[DELAY[0]])
    while pc < DELAY[1]:
        DELAY_SKIP.add(pc); pc += length(rom[pc])

# ------------------------------------------------------------------ C generation
L = []
def emit(s): L.append(s)
def lab(pc): return 'L_%03X' % (pc & 0x3FFF)


def region(a):
    if a <= 0x03F: return 'REG'
    if 0x040 <= a <= 0x04F: return 'MR'
    if 0x260 <= a <= 0x26F: return 'ERAM'
    if 0x320 <= a <= 0x35F: return 'OREG'
    if 0x360 <= a <= 0x36F: return 'SREG'
    if a >= 0x3C0: return 'STK'
    return 'NONE'


def state_code(pc, ic, s, d):
    """(C lines, is_io) for state s (DECI d) of the instruction at pc. Values are those before the state's CYC[3] edge;
    the edge is at vt + 4 * (s + 1). Register updates are made last (non-blocking semantics)."""
    out = []; io = False
    te = 'vt + %d' % (4 * (s + 1))          # this state's CYC[3] edge
    ma = MA[d['MA']]
    if ma == 'MR': addr = ('c', 0x040 | (ic & 0xF))
    elif ma == 'ADR': addr = ('v', '((W << 8) | (X << 4) | Y)') if s == 0 else ('c', rom[(pc + 1) & 0x7FF])
    else: addr = ('s', None)
    aas = AAS[d['ALUAS']]; abs_ = ABS[d['ALUBS']]; aluop = ALUOP[d['ALUOP']]; cd = d['ALUCD']
    md = MD[d['MD']]; cau = CAU[d['CAU']]; stu = STU[d['STU']]
    uses_alu = (d['AW'] or d['BW'] or (d['XW'] and not d['XE']) or (d['YW'] and not d['YE']) or d['WW'] or
                cau == 'ALU' or stu in ('NZ', 'C', 'NB', 'PD') or ((d['MW'] or d['IOW']) and md == 'ALU'))
    need_m = uses_alu and (aas == 'M' or (abs_ == 'M' and aluop in ('ADD', 'LOG', 'BIT', 'B')))
    # ---- RAM_Q (memory or port read)
    if need_m:
        if addr[0] == 's':
            out.append('m_ = stk[SP & 63];')
        elif d['IOR']:
            if addr[0] == 'c':
                if region(addr[1]) == 'STK': out.append('m_ = stk[%d];' % (addr[1] & 63))
                else:
                    io = True
                    out.append('m_ = %s(%d, %s);' % ('io_rd_r' if d['IOP'] else 'io_rd_d', addr[1] & 0xF, te))
            else:
                io = True
                out.append('m_ = io_rd_v(%d, %s, %s);' % (d['IOP'], addr[1], te))
        elif addr[0] == 'c':
            a = addr[1]; r = region(a)
            if r == 'MR': out.append('m_ = mre[%d];' % (a & 15))
            elif r == 'ERAM': out.append('m_ = mre[%d]%s;' % (16 + (a & 15), ' | 8' if (a & 15) == 5 else ''))
            elif r == 'STK': out.append('m_ = stk[%d];' % (a & 63))
            elif r == 'REG': io = True; out.append('m_ = reg_rd(0x%02X, %s);' % (a, te))
            else: out.append('m_ = 0;')
        else:
            io = True
            out.append('m_ = ram_rd(%s, %s);' % (addr[1], te))
    elif d['MR'] and addr[0] == 'c' and region(addr[1]) == 'REG':
        # a register read that is not used still latches the timer (TRCU read): keep the access
        io = True
        out.append('(void)reg_rd(0x%02X, %s);' % (addr[1], te))
    elif d['MR'] and addr[0] == 'v':
        io = True
        out.append('(void)ram_rd(%s, %s);' % (addr[1], te))
    I = str(ic & 0xF)
    A_ = {'A': 'A', 'B': 'B', 'Y': 'Y', 'M': 'm_', 'I': I, 'ZERO': '0', 'SPX': 'SPX', 'SPY': 'SPY'}[aas]
    B_ = {'A': 'A', 'B': 'B', 'M': 'm_', 'I': I, 'ONE': '1', 'ZERO': '0', 'BIT': str(1 << (ic & 3)), 'NONE': '0'}[abs_]
    R = Cy = Z = LE = None
    if uses_alu:
        if aluop == 'ADD':
            if cd & 3 == 0: out.append('t_ = %s + %s;' % (A_, B_))
            elif cd & 3 == 1: out.append('t_ = %s - %s;' % (A_, B_))
            elif cd & 3 == 2: out.append('t_ = %s + %s + CA;' % (A_, B_))
            else: out.append('t_ = %s - %s - (CA ^ 1);' % (A_, B_))
            R = '(t_ & 15)'; Cy = '(((t_ >> 4) & 1) ^ %d)' % (cd & 1); Z = '((t_ & 15) == 0)'; LE = '(%s <= %s)' % (A_, B_)
        elif aluop == 'LOG':
            if (cd & 6) == 4 or (cd & 6) == 6:
                if cd & 1: out.append('t_ = (%s << 1) | CA; c_ = (%s >> 3) & 1;' % (A_, A_))     # ROTL {A,CA}
                else: out.append('t_ = (%s >> 1) | (CA << 3); c_ = %s & 1;' % (A_, A_))         # ROTR {A[0],CA,A[3:1]}
                R = '(t_ & 15)'; Cy = 'c_'; Z = '((t_ & 15) == 0)'
            else:
                op = {0: '|', 1: '^', 3: '&'}.get(cd & 3)
                out.append('t_ = %s;' % (A_ if op is None else '%s %s %s' % (A_, op, B_)))
                R = '(t_ & 15)'; Cy = 'CA'; Z = '((t_ & 15) == 0)'
        elif aluop == 'BIT':
            op = {0: A_, 1: '%s | %s' % (A_, B_), 2: '%s & ~%s' % (A_, B_), 3: '%s & %s' % (A_, B_)}[cd & 3]
            out.append('t_ = %s;' % op)
            R = '(t_ & 15)'; Cy = '0'; Z = '((t_ & 15) == 0)'
        elif aluop == 'A': R = A_; Cy = 'CA'; Z = '0'
        elif aluop == 'B': R = B_; Cy = 'CA'; Z = '0'
        else: R = '0'; Cy = '0'; Z = '0'
    data = {'A': 'A', 'B': 'B', 'I': I, 'ALU': R if R else '0'}[md]
    # ---- memory write
    if d['MW']:
        if ma in ('STK1', 'STK2'):
            pass   # handled by the caller (push)
        elif addr[0] == 'c':
            a = addr[1]; r = region(a)
            if r == 'MR': out.append('mre[%d] = %s;' % (a & 15, data))
            elif r == 'ERAM': out.append('mre[%d] = %s;' % (16 + (a & 15), data))
            elif r == 'STK': out.append('stk[%d] = %s;' % (a & 63, data))
            elif r == 'REG': io = True; out.append('reg_wr(0x%02X, %s, %s);' % (a, data, te))
            elif r == 'OREG': io = True; out.append('oreg_wr(0x%03X, %s, %s);' % (a, data, te))
            elif r == 'SREG': io = True; out.append('sreg_wr(0x%03X, %s, %s);' % (a, data, te))
        elif addr[0] == 'v':
            io = True; out.append('ram_wr(%s, %s, %s);' % (addr[1], data, te))
        else:
            out.append('stk[SP & 63] = %s;' % data)
    # ---- port write
    if d['IOW']:
        io = True
        if addr[0] == 'c': out.append('%s(%d, %s, %s);' % ('io_wr_r' if d['IOP'] else 'io_wr_d', addr[1] & 0xF, data, te))
        else: out.append('io_wr_v(%d, %s, %s, %s);' % (d['IOP'], addr[1], data, te))
    # ---- register updates
    regs = []
    if d['AW']: regs.append(('A', R))
    if d['BW']: regs.append(('B', R))
    if d['XW']: regs.append(('X', 'SPX' if d['XE'] else R))
    if d['YW']: regs.append(('Y', 'SPY' if d['YE'] else R))
    if d['WW']: regs.append(('W', '(%s) & 3' % R))
    if d['XE']: regs.append(('SPX', 'X'))
    if d['YE']: regs.append(('SPY', 'Y'))
    if cau == 'ALU': regs.append(('CA', Cy))
    elif cau == 'ONE': regs.append(('CA', '1'))
    elif cau == 'ZERO': regs.append(('CA', '0'))
    elif cau == 'RTN': regs.append(('CA', '(stk[(SP & 0x3C) + 2] >> 3)'))
    if stu == 'NZ': regs.append(('ST', '!%s' % Z))
    elif stu == 'C': regs.append(('ST', Cy))
    elif stu == 'NB': regs.append(('ST', LE))
    elif stu == 'CA': regs.append(('ST', 'CA'))
    elif stu == 'SET': regs.append(('ST', '1'))
    elif stu == 'RTN': regs.append(('ST', '(stk[SP & 0x3C] >> 3)'))
    elif stu == 'PD': regs.append(('ST', '(%s) & 1' % R))
    if d['SPD']: regs.append(('SP', '(SP - 4) & 63'))
    if d['SPI']: regs.append(('SP', '(SP + 4) & 63'))
    if len(regs) == 1:
        out.append('%s = %s;' % regs[0])
    elif regs:
        out.append(' '.join('n%s_ = %s;' % (r, v) for r, v in regs))
        out.append(' '.join('%s = n%s_;' % (r, r) for r, _ in regs))
    return out, io


def gen_instr(pc, hook=None):
    """emit the instruction at pc; returns (any_io, states of its longest variant). hook(): the fast build's block
    start (yield check), emitted after MCU_STEP / MCU_IDLE"""
    ic = code[pc]
    n = length(ic)
    if FAITHFUL or pc in LEAD:
        emit('%s: // %03X  %s' % (lab(pc), pc, dis(pc)))
        if not FAITHFUL: emit('  MCU_LEAD(0x%03X);' % pc)
    else:
        emit('  // %03X  %s' % (pc, dis(pc)))
    if pc in DELAY_SKIP:
        return False, 0
    if pc == DELAY[0] and not FAITHFUL:
        # the delay routine 00D6-00EB (pure: it writes only MR0, MR1, A, B, ST) has a constant result: its 101592 states
        # (406368 CE) and the values it leaves; then its RTN at 00EC
        emit('  MCU_COUNT(0x%03X); mre[0] = 15; mre[1] = 15; A = 15; B = 15; ST = 1; vt += 406368;' % pc)
        emit('  goto %s;' % lab(DELAY[1]))
        return False, 1
    if not FAITHFUL:
        emit('  MCU_COUNT(0x%03X);' % pc)
    d0 = deci(ic, 0, 1, 1)
    if d0['SBY'] or d0['STOP']:
        # SBY / STOP: 1 state (PC + 1); STOP halts. SBY: the core latches INT_EXP at this edge as at any instruction end,
        # then sleeps until a CYC[3] edge with an interrupt pending (any IE); then the interrupt sequence (if latched)
        # or the next instruction.
        assert length(ic) == 1 and (pc + 1) in code
        if hook: hook()                 # before the interrupt check: running it again after a stop is not the same
        if FAITHFUL or pc in MAIN_LOOP: emit('  MCU_STEP(%s, 0x%03X);' % (lab(pc), pc))
        emit('  vt += 4;')
        if d0['STOP']:
            emit('  MCU_SAVE; m.halted = 1; m.resume = &&%s; return;' % lab(pc))
            return True, 1
        emit('  m.sby_latch = (uint8_t)int_latch(vt);')
        emit('%s_sby: { uint32_t w_ = wake_time(vt); if (!w_) MCU_STOP_AT(%s_sby); vt = w_; }' % (lab(pc), lab(pc)))
        emit('  if (m.sby_latch) { int v_; m.sby_latch = 0; v_ = int_vector(vt + 4); ST = 1; int_accept(vt + 4);')
        emit('    PUSH(0x%03X, &&%s); SP = (SP - 4) & 63; vt += 8; goto *vec_label[v_]; }' % (pc + 1, lab(pc + 1)))
        emit('  m.novt_latch = 1;')
        emit('  goto %s;' % lab(pc + 1))
        return True, 1
    if hook and pc in MAIN_LOOP:
        hook(); hook = None             # before the interrupt check (m.novt_latch: it must run once at an edge)
    if FAITHFUL or pc in MAIN_LOOP:
        emit('  MCU_STEP(%s, 0x%03X);' % (lab(pc), pc))
    if pc in IDLE and not FAITHFUL:
        emit('  MCU_YIELD(%s, 0x%03X, 1);' % (lab(pc), pc))      # idle_head looks at the inputs up to vt
        emit('  MCU_IDLE(%s, 0x%03X, %d, %s);' % (lab(pc), pc, IDLE_ID[pc], IDLE[pc][1]))
        # the block's own yield resumes after MCU_IDLE: the pass after a skip must run (idle_head again at the same
        # edge would take its passes as repeats of the last one and skip the pass that sees the change)
        emit('%s_body:;' % lab(pc))
    if hook: hook()
    st_dep = any(DEC.get((ic, s, 0, 0, 1)) != DEC.get((ic, s, 0, 1, 1)) for s in range(3) if (ic, s, 0, 0, 1) in DEC)
    da_dep = any(DEC.get((ic, s, 0, 1, 0)) != DEC.get((ic, s, 0, 1, 1)) for s in range(3) if (ic, s, 0, 1, 0) in DEC)
    assert not (st_dep and da_dep)
    variants = [('ST', 1), ('ST', 0)] if st_dep else [('DA', 1), ('DA', 0)] if da_dep else [(None, 1)]
    bodies = []; any_io = False
    rtc_imm = 0x681 <= pc <= 0x68E
    for cond, val in variants:
        st = val if cond == 'ST' else 1
        da = val if cond == 'DA' else 1
        ds = states(ic, st, da)
        lines = []
        tail = None
        for s, d in enumerate(ds):
            sic = ic
            if rtc_imm:
                # SMPC.sv: ROM words 0681-068E (LMIIY i of the RTC default) have their low nibble from RTC_INIT
                assert len(ds) == 1 and MD[d['MD']] == 'I'
            out, io = state_code(pc, ic, s, d)
            if rtc_imm:
                out = [o.replace('ram_wr(((W << 8) | (X << 4) | Y), %d,' % (ic & 0xF), 'ram_wr(((W << 8) | (X << 4) | Y), rtc_init(%d, vt + 2),' % (pc & 0xF)) for o in out]
                assert any('rtc_init' in o for o in out), out
                io = True
            any_io |= io
            ma = MA[d['MA']]
            if d['PI']:
                # P: IW = the word at {00, IC[3:0], B, A}, read at this state's CYC[1] (2 CE before its end); {B,A} <=
                # IW[7:0] if IW[8] (after the other updates of the state)
                lines.append('p_ = rom_pattern((%d << 8) | (B << 4) | A, vt + %d);' % (ic & 0xF, 4 * s + 2))
                any_io = True
            if d['MW'] and ma in ('STK1', 'STK2'):
                # push {ST, PC[13:7], CA, PC[6:0]} into the entry at SP (STK1: PC = pc + s, STK2: PC + 1)
                ret = (pc + s) if ma == 'STK1' else (pc + s + 1)
                assert ret in RET_POINTS, '%03X' % ret
                lines.append('PUSH(0x%03X, &&%s);' % (ret, lab(ret)))
            lines.extend(out)
            if d['PI']:
                lines.append('if (p_ & 0x100) { B = (p_ >> 4) & 15; A = p_ & 15; }')
            p = PCU[d['PCU']]
            if p == 'BR': tail = 'goto %s;' % lab(((pc + 1) & 0x3F00) | (ic & 0xFF))
            elif p == 'BRL': tail = 'goto %s;' % lab(((ic & 0xF) << 10) | rom[(pc + 1) & 0x7FF])
            elif p == 'ZP': tail = 'goto %s;' % lab(ic & 0x3F)
            elif p == 'TBR': tail = 'TBR(%d);' % (ic & 0xF)
            elif p == 'RTN':
                tail = 'RTN(%d);' % (ic & 1)
                if ic & 1: any_io = True        # RTNI: int_return() brings the peripherals to its edge
        lines.append('vt += %d;' % (4 * len(ds)))
        if tail: lines.append(tail)
        elif (pc + n) not in code: lines.append('MCU_FAIL(0x%03X);' % (pc + n))
        bodies.append(lines)
    if len(variants) == 1:
        for l in bodies[0]: emit('  ' + l)
    else:
        cexpr = 'ST' if variants[0][0] == 'ST' else '(A >= 10 || CA == %d)' % (((ic >> 3) & 1) ^ 1)
        emit('  if (%s) {' % cexpr)
        for l in bodies[0]: emit('    ' + l)
        emit('  } else {')
        for l in bodies[1]: emit('    ' + l)
        emit('  }')
    return any_io, max(len(states(ic, v if c == 'ST' else 1, v if c == 'DA' else 1)) for c, v in variants)


emit('// GENERATED by fw/cdb/smpc_gen/gen_mcu.py from smpc.mif and the IDecode dump: do not edit. %s build.' % ('FAITHFUL' if FAITHFUL else 'fast'))
emit('#include "smpc_mcu.h"')
emit('')
emit('const uint16_t mcu_rom_010[16] = {%s};' % ', '.join('0x%03X' % rom[0x010 + i] for i in range(16)))
emit('')
emit('void mcu_exec(void)')
emit('{')
emit('  MCU_LOCALS;')
emit('  static void* const tbr1[32] = {%s};' % ', '.join('&&%s' % lab(0x100 + i) for i in range(32)))
RETS = sorted(set(RET_POINTS) | set(MAIN_LOOP) | {0x6A0})
emit('  static void* const vec_label[6] = {%s};' % ', '.join('&&%s' % lab(v) for v in (0, 2, 4, 6, 8, 10)))
if FAITHFUL:
    emit('  static void* const ret_label[%d] = {%s};' % (len(RETS), ', '.join('&&%s' % lab(r) for r in RETS)))
    emit('  static const uint16_t ret_pc[%d] = {%s};' % (len(RETS), ', '.join('0x%03X' % r for r in RETS)))
    emit('  mcu_ret_tables(ret_pc, ret_label, %d);' % len(RETS))
emit('  MCU_PROLOGUE;')
if FAITHFUL:
    for pc in sorted(code): gen_instr(pc)
else:
    # fast build: blocks. A block starts at a leader (a jump / call / return / dispatch target, an idle loop head, or
    # a split point) and runs straight on to the next leader (exits by taken branches anywhere). Only leaders get a
    # label (a resume point), and a block with world accesses starts with one yield check for all of them:
    # MCU_YIELD(label, pc, D): the world must know its inputs up to vt + D (D: the end of the block's last access).
    # Long blocks are split so that D stays small (the outputs of a block wait for that edge).
    SPLIT = 64
    info = {}
    save = L[:]
    for pc in sorted(code): info[pc] = gen_instr(pc)
    del L[len(save):]
    BLOCK_D = {}; cur = None; off = 0
    for pc in sorted(code):
        if pc in DELAY_SKIP: continue
        io, ns = info[pc]
        if pc not in LEAD and off + 4 * ns > SPLIT and cur is not None and BLOCK_D[cur] > 0: LEAD.add(pc)
        if pc in LEAD: cur = pc; BLOCK_D[cur] = 0; off = 0
        if pc in MAIN_LOOP: BLOCK_D[cur] = max(BLOCK_D[cur], 4)      # the interrupt check looks at vt
        if io: BLOCK_D[cur] = max(BLOCK_D[cur], off + 4 * ns)
        off += 4 * ns
    nyield = 0
    for pc in sorted(code):
        hook = None
        if pc in LEAD and BLOCK_D.get(pc, 0) > 0:
            def hook(pc=pc): emit('  MCU_YIELD(%s, 0x%03X, %d);' % (lab(pc) + ('_body' if pc in IDLE else ''), pc, BLOCK_D[pc]))
            nyield += 1
        gen_instr(pc, hook)
    print('fast build: %d leaders, %d yield checks, longest block D %d CE' % (len(LEAD), nyield, max(BLOCK_D.values())), file=sys.stderr)
    MAX_D = max(BLOCK_D.values())
emit('  MCU_EPILOGUE;')
emit('}')
if not FAITHFUL:
    # the world's run limit (MCU_RUN_CAP, smpc_mcu.h) must let every block run
    emit('_Static_assert(%d <= MCU_RUN_CAP, "a block needs more than MCU_RUN_CAP edges");' % MAX_D)
    emit('_Static_assert(%d <= MCU_RUN_MIN, "a block needs more than MCU_RUN_MIN edges");' % MAX_D)
open(OUT, 'w').write('\n'.join(L) + '\n')
print('%d instructions, %d labels, %d return points' % (len(code), len(LABELS), len(RET_POINTS)), file=sys.stderr)
