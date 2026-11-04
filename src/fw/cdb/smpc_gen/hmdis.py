#!/usr/bin/env python3
# HMCS400 disassembler for the SMPC ROM (rtl/Saturn/SMPC/smpc.mif), following HMCS400_PKG::IDecode() and SMPC.sv's
# memory / port map. usage: hmdis.py smpc.mif [> listing]
import sys, re

def load_mif(p):
    rom = [0] * 2048
    for l in open(p):
        m = re.match(r'\s*([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f]+);', l)
        if m: rom[int(m.group(1), 16)] = int(m.group(2), 16)
    return rom

# RAM names (10-bit W:X:Y addresses)
REGS = {0x00: 'INTC0', 0x01: 'INTC1', 0x02: 'INTC2', 0x03: 'INTC3', 0x04: 'PMRA', 0x08: 'TMA', 0x0D: 'TMC1',
        0x0E: 'TWCL/TRCL', 0x0F: 'TWCU/TRCU', 0x20: 'RF0', 0x21: 'RF1', 0x22: 'RF2', 0x23: 'RF3', 0x24: 'PMRB',
        0x25: 'PMRC', 0x26: 'ESR1', 0x2C: 'DCD0', 0x2D: 'DCD1', 0x2E: 'DCD2', 0x2F: 'DCD3'}
for i in range(8): REGS[0x30 + i] = 'DCR%d' % i

def ramname(a):
    if a in REGS: return REGS[a]
    if 0x40 <= a <= 0x4F: return 'MR%X' % (a - 0x40)
    if 0x260 <= a <= 0x26F: return 'ERAM%X' % (a - 0x260)
    if 0x320 <= a <= 0x35F:
        o = a - 0x320
        return 'OREG%d.%s' % (o >> 1, 'H' if not (o & 1) else 'L')
    if 0x360 <= a <= 0x36F: return {0x360: 'SR.H', 0x361: 'SR.L', 0x362: 'SFCLR'}.get(a, 'SREG%X' % (a - 0x360))
    if a >= 0x3C0: return 'STK%02X' % (a - 0x3C0)
    return 'RAM%03X' % a

DPORT = {0: 'D0(MIRQ_N)', 1: 'D1', 2: 'D2', 3: 'D3(RESET_BTN)', 4: 'D4(SNDRES_N)', 5: 'D5(SYSRES_N)', 6: 'D6(MSHRES_N)',
         7: 'D7(MSHNMI_N)', 8: 'D8(SSHRES_N)', 9: 'D9(SSHNMI_N)', 10: 'D10(DOTSEL)', 13: 'D13(INT0)'}
RPORT = {0: 'R0(INT:~COMREG,VBL)', 1: 'R1(PA3:0)', 2: 'R2(PA6:4)', 3: 'R3(PB3:0)', 4: 'R4(PB6:4)', 5: 'R5(AREA)',
         6: 'R6', 7: 'R7(CDRES)'}

def dis(rom, pc):
    """returns (text, length in words, branch targets)"""
    w = rom[pc]
    nxt = rom[(pc + 1) & 0x7FF]
    b = lambda s: int(s, 2)
    def m(pat):
        pat = pat.replace('_', '')
        for i, c in enumerate(pat):
            bit = (w >> (9 - i)) & 1
            if c in '01' and int(c) != bit: return False
        return True
    lo4 = w & 0xF
    if m('0000000000'): return 'NOP', 1, []
    if m('00000000xx'): return ['NOP', 'XSPX', 'XSPY', 'XSPXY'][w & 3], 1, []
    if m('0000010000'): return 'RTN', 1, []
    if m('0000010001'): return 'RTNI', 1, []
    if m('0000000100'): return 'ANEM', 1, []
    if m('0000010100'): return 'ALEM', 1, []
    if m('0001000100'): return 'BNEM', 1, []
    if m('0011000100'): return 'BLEM', 1, []
    two = {0b0100000100: 'ANEMD', 0b0100010100: 'ALEMD', 0b0100001000: 'AMD', 0b0100011000: 'AMCD', 0b0110011000: 'SMCD',
           0b0100001100: 'ORMD', 0b0100011100: 'EORMD', 0b0110011100: 'ANMD', 0b0110000000: 'XMAD', 0b0110010000: 'LAMD',
           0b0110010100: 'LMAD'}
    if w in two: return '%s %s' % (two[w], ramname(nxt)), 2, []
    if m('0000001000'): return 'AM', 1, []
    if m('0000011000'): return 'AMC', 1, []
    if m('0010011000'): return 'SMC', 1, []
    if m('0000001100'): return 'ORM', 1, []
    if m('0000011100'): return 'EORM', 1, []
    if m('0010011100'): return 'ANM', 1, []
    if m('000010xxxx'): return 'INEM %X' % lo4, 1, []
    if m('000011xxxx'): return 'ILEM %X' % lo4, 1, []
    if m('010010xxxx'): return 'INEMD %X,%s' % (lo4, ramname(nxt)), 2, []
    if m('010011xxxx'): return 'ILEMD %X,%s' % (lo4, ramname(nxt)), 2, []
    xy = ['', 'X', 'Y', 'XY']
    if m('00010000xx'): return 'LBM' + xy[w & 3], 1, []
    if m('00100100xx'): return 'LAM' + xy[w & 3], 1, []
    if m('0001001000'): return 'LAB', 1, []
    if m('0001011000'): return 'LASPY', 1, []
    if m('0001101000'): return 'LASPX', 1, []
    if m('0001001100'): return 'IB', 1, []
    if m('0001011100'): return 'IY', 1, []
    if m('0011001111'): return 'DB', 1, []
    if m('0011011111'): return 'DY', 1, []
    if m('000101000x'): return 'LMAIY' + ('X' if w & 1 else ''), 1, []
    if m('001101000x'): return 'LMADY' + ('X' if w & 1 else ''), 1, []
    if m('0001010100'): return 'AYY', 1, []
    if m('0011010100'): return 'SYY', 1, []
    if m('0001100000'): return 'NEGA', 1, []
    if m('0001100100'): return 'RED', 1, []
    if m('0011100100'): return 'SED', 1, []
    if m('100110xxxx'): return 'REDD %s' % DPORT.get(lo4, 'D%d' % lo4), 1, []
    if m('101110xxxx'): return 'SEDD %s' % DPORT.get(lo4, 'D%d' % lo4), 1, []
    if m('0011100000'): return 'TD', 1, []
    if m('101010xxxx'): return 'TDD %s' % DPORT.get(lo4, 'D%d' % lo4), 1, []
    if m('0001101111'): return 'TC', 1, []
    if m('000111xxxx'): return 'YNEI %X' % lo4, 1, []
    if m('00100000xx'): return 'XMA' + xy[w & 3], 1, []
    if m('00110000xx'): return 'XMB' + xy[w & 3], 1, []
    if m('00100001xx'): return 'SEM %d' % (w & 3), 1, []
    if m('00100010xx'): return 'REM %d' % (w & 3), 1, []
    if m('00100011xx'): return 'TM %d' % (w & 3), 1, []
    if m('01100001xx'): return 'SEMD %d,%s' % (w & 3, ramname(nxt)), 2, []
    if m('01100010xx'): return 'REMD %d,%s' % (w & 3, ramname(nxt)), 2, []
    if m('01100011xx'): return 'TMD %d,%s' % (w & 3, ramname(nxt)), 2, []
    if m('00100101xx'): return 'LMA' + xy[w & 3], 1, []
    if m('0010100000'): return 'ROTR', 1, []
    if m('0010100001'): return 'ROTL', 1, []
    if m('0010100110'): return 'DAA', 1, []
    if m('0010101010'): return 'DAS', 1, []
    if m('0010101111'): return 'LAY', 1, []
    if m('001011xxxx'): return 'TBR %X' % lo4, 1, ['tbr']
    if m('0011001000'): return 'LBA', 1, []
    if m('0011011000'): return 'LYA', 1, []
    if m('0011101000'): return 'LXA', 1, []
    if m('0011101100'): return 'REC', 1, []
    if m('0011101111'): return 'SEC', 1, []
    if m('00111100xx'): return 'LWI %d' % (w & 3), 1, []
    if m('0101000000'): return 'COMB', 1, []
    if m('0101000100'): return 'OR', 1, []
    if m('0101001100'): return 'SBY', 1, []
    if m('0101001101'): return 'STOP', 1, []
    if m('010101xxxx'): t = (lo4 << 10) | nxt; return 'JMPL %04X' % t, 2, [t]
    if m('010110xxxx'): t = (lo4 << 10) | nxt; return 'CALL %04X' % t, 2, [t, 'call']
    if m('010111xxxx'): t = (lo4 << 10) | nxt; return 'BRL %04X' % t, 2, [t]
    if m('011010xxxx'): return 'LMID %X,%s' % (lo4, ramname(nxt)), 2, []
    if m('011011xxxx'): return 'P %X' % lo4, 1, []
    if m('0111xxxxxx'): t = w & 0x3F; return 'CAL %03X' % t, 1, [t, 'call']
    if m('100000xxxx'): return 'LBI %X' % lo4, 1, []
    if m('100001xxxx'): return 'LYI %X' % lo4, 1, []
    if m('100010xxxx'): return 'LXI %X' % lo4, 1, []
    if m('100011xxxx'): return 'LAI %X' % lo4, 1, []
    if m('100100xxxx'): return 'LBR %s' % RPORT.get(lo4, 'R%d' % lo4), 1, []
    if m('100101xxxx'): return 'LAR %s' % RPORT.get(lo4, 'R%d' % lo4), 1, []
    if m('100111xxxx'): return 'LAMR MR%X' % lo4, 1, []
    if m('101000xxxx'): return 'AI %X' % lo4, 1, []
    if m('101001xxxx'): return 'LMIIY %X' % lo4, 1, []
    if m('101011xxxx'): return 'ALEI %X' % lo4, 1, []
    if m('101100xxxx'): return 'LRB %s' % RPORT.get(lo4, 'R%d' % lo4), 1, []
    if m('101101xxxx'): return 'LRA %s' % RPORT.get(lo4, 'R%d' % lo4), 1, []
    if m('101111xxxx'): return 'XMRA MR%X' % lo4, 1, []
    if m('11xxxxxxxx'): t = ((pc + 1) & 0x3F00) | (w & 0xFF); return 'BR %04X' % t, 1, [t]
    return 'ILL %03X' % w, 1, []

if __name__ == '__main__':
    rom = load_mif(sys.argv[1])
    pc = 0
    while pc < 2048:
        t, n, tg = dis(rom, pc)
        words = ' '.join('%03X' % rom[(pc + k) & 0x7FF] for k in range(n))
        print('%04X  %-8s  %s' % (pc, words, t))
        pc += n
