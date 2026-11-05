#
# SEGA Saturn Pocket build: core constraints (work/pocket, P2). Loaded by apf/apf_constraints.sdc after it created
# clk_74a, clk_74b, bridge_spiclk and ran derive_pll_clocks. (fx68k's multicycle paths come with rtl/FX68K/fx68k.qip.)
#
# Clocks
#   clk_74a          APF, 74.25 MHz (pin)
#   core PLL         clk_pll_core (one reconfigurable fractional PLL fed by clk_74a), compiled in NTSC 352 = the fastest
#                    mode, so the analysis covers the worst case: [0] clk_sys 57.27 MHz, [1] clk_ram 114.55 MHz (2 x
#                    clk_sys, edges aligned), [2] clk_pix 28.64 MHz (clk_sys / 2), [3] clk_pix_90 (+90 deg)
#   cram0/1 clocks   the PSRAM clocks: register outputs (psram_phy p_clk) at clk_ram / 2, forwarded to the pins
# Groups: bridge_spiclk and clk_74b are asynchronous to everything (as in the sotn port: the APF bridge synchronises
# itself). clk_74a and the core PLL's clocks are NOT declared asynchronous: their phase relation is not fixed
# (fractional PLL), so every path between them is a clock-domain crossing, and each real one is excepted below, at its
# synchroniser or FIFO. Anything else between them stays timed and would show as a violation.
# clk_sys <-> clk_ram <-> clk_pix are synchronous (same PLL, aligned edges): timed normally, no exceptions (the glue
# samples clk_sys registers on clk_ram edges with a full clk_ram of path, glue/REPORT 10).

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74b } \
 -group [get_clocks {clk_74a *isat|ipll|altera_pll_i|*|divclk}]

set clk_sys [get_clocks {*isat|ipll|altera_pll_i|*[0].*|divclk}]
set clk_ram [get_clocks {*isat|ipll|altera_pll_i|*[1].*|divclk}]

derive_clock_uncertainty

# ------------------------------------------------------------------------------------------------------------------
# Clock-domain crossings clk_74a <-> core PLL (each at a synchroniser, a handshake with held data, or a dual-clock FIFO)
# ------------------------------------------------------------------------------------------------------------------
# pk_reset: level synchronisers (first stages) clk_74a -> clk_sys, clk_ram -> clk_74a, clk_sys -> clk_74a,
# clk_74a -> clk_ram (its clk_ram -> clk_sys and clk_sys -> clk_ram stages are synchronous: timed)
set_false_path -to [get_registers {*|irst|por_ss[0] *|irst|apf_ss[0] *|irst|ld74_ss[0]}]
set_false_path -to [get_registers {*|irst|rdy_74[0] *|irst|held_s[0] *|irst|por_s[0]}]
# pk_settings: quasi-static settings into clk_sys (2-flop per bit); RTC: data held stable behind the synchronised toggle
# ((A6) s0 also carries the four diagnostic settings: FB layout, write combining, debug flags, PSRAM gap)
set_false_path -to [get_registers {*|iset|s0[*] *|iset|rtc_tgl_s[0]}]
# (A6) av_video's debug squares: quasi-static inputs (settings, sticky flags, the displayed-buffer bit that changes once a
# field) through 2-flop synchronisers into clk_pix (first stages)
set_false_path -to [get_registers {*|ivid|on_s0 *|ivid|disp_s0 *|ivid|f_s0[*] *|ivid|set_s0[*]}]
set_false_path -from [get_registers {*|iset|rtc_d[*]}] -to $clk_sys
# pk_pad: controller keys (2-flop per bit)
set_false_path -to [get_registers {*|ipad|k0[*]}]
# clk_reconf: PLL mode {PAL, DOTSEL} (3-flop synchroniser) and the PLL's lock (asynchronous output, 3-flop)
set_false_path -to [get_registers {*|irec|m_s0[*] *|irec|lk_s[0]}]
# cd_src_b / cd_apf (glue/cd REPORT 7): toggle handshakes (2-flop both ways); values held stable across them:
#   table word address and data slot read parameters (clk_sys registers, read in clk_74a after the request toggle),
#   table word and result code (clk_74a registers, read by the CD block CPU after the acknowledge toggle)
set_false_path -to [get_registers {*|icd|apf|dt_ack_s[0] *|icd|apf|cmd_ack_s[0] *|icd|apf|dt_req_s[0] *|icd|apf|cmd_req_s[0]}]
set_false_path -from [get_registers {*|icd|dt_addr[*]}] -to [get_registers {*|icd|apf|datatable_addr[*]}]
set_false_path -from [get_registers {*|icd|id[*] *|icd|dsr_offset[*] *|icd|dest[*] *|icd|len[*]}] -to [get_registers {*|icb|target_2*}]
set_false_path -from [get_registers {*|icd|apf|dt_q[*] *|icd|apf|cmd_err[*]}] -to $clk_sys
# pk_save: bridge read request (toggle, 3-flop; word index held) and answer (toggle, 2-flop; data word held)
set_false_path -to [get_registers {*|isv|req_s[0] *|isv|ack_s[0]}]
set_false_path -from [get_registers {*|isv|req_word[*]}] -to $clk_ram
set_false_path -from [get_registers {*|isv|ans[*]}] -to [get_registers {*|isv|rd_data[*]}]
# dual-clock FIFOs (pk_loader clk_74a -> clk_ram, sound_i2s's sync_fifo clk_sys -> clk_74a): only the gray-coded
# pointers cross, through the FIFOs' synchroniser pipes; Quartus's dcfifo embeds the matching exceptions itself
# (set_false_path -from *rdptr_g* -to *ws_dgrp|..|dffe<first stage>*, -from *delayed_wrptr_g* -to *rs_dgwp|..*),
# so nothing is added here (the data words sit in the FIFO RAM, which has no path between its two clocks)
# (the CD sector ring, cd_ring, is a dual-clock block RAM written on clk_74a and read on clk_sys: no path through it)

# ------------------------------------------------------------------------------------------------------------------
# Memory I/O
# ------------------------------------------------------------------------------------------------------------------
# PSRAM 0 / 1 (psram_phy CLKDIV 2, AS1C8M16PL synchronous burst, variable latency, LC 2; glue/REPORT 1.1, 10).
# The PSRAM clock is the p_clk register (an I/O-cell register), toggling every clk_ram: the generated clocks carry its
# delay to the pin, and the PSRAM's times are given against them:
#   address / control / write data: setup tSP 3 ns (CE# tCSP 4 ns), hold tHD 2 ns to the rising PSRAM clock;
#   reads (and WAIT): valid tACLK <= 9 ns after a rising PSRAM clock edge, held tKOH >= 2 ns after the next one.
# Board traces, each way: 0 to psram_brd ns (not measured).
# Outputs change only at the clk_ram edges that start a PSRAM cycle, one clk_ram before the rising PSRAM clock K that
# samples them (setup: the default one-clk_ram relationship) and one clk_ram after it, so the hold check is moved one
# clk_ram later (-hold -start 1). Read words are sampled 2 clk_ram after the K that drove them (psram_phy RDLAT 2):
# setup -end 2, hold at the next K (-hold -end 1).
set psram_brd 0.5
foreach {c inst} {cram0 iarb|phy cram1 ifb|psram} {
   create_generated_clock -name ${c}_pclk -source [get_pins -compatibility_mode "*|isat|${inst}|p_clk|clk"] -divide_by 2 \
      [get_pins -compatibility_mode "*|isat|${inst}|p_clk|q"]
   create_generated_clock -name ${c}_clk -source [get_pins -compatibility_mode "*|isat|${inst}|p_clk|q"] [get_ports ${c}_clk]
   set_input_delay  -clock ${c}_clk -max [expr {9.0 + 2 * $psram_brd}] [get_ports [list ${c}_dq[*] ${c}_wait]]
   set_input_delay  -clock ${c}_clk -min 2.0 [get_ports [list ${c}_dq[*] ${c}_wait]]
   set outs [get_ports [list ${c}_a[*] ${c}_dq[*] ${c}_adv_n ${c}_we_n ${c}_oe_n ${c}_lb_n ${c}_ub_n ${c}_cre]]
   set_output_delay -clock ${c}_clk -max [expr {3.0 + $psram_brd}] $outs
   set_output_delay -clock ${c}_clk -min [expr {-2.0 - $psram_brd}] $outs
   set ces [get_ports [list ${c}_ce0_n ${c}_ce1_n]]
   set_output_delay -clock ${c}_clk -max [expr {4.0 + $psram_brd}] $ces
   set_output_delay -clock ${c}_clk -min [expr {-2.0 - $psram_brd}] $ces
   set_multicycle_path -setup -end 2 -from [get_clocks ${c}_clk] -to $clk_ram
   set_multicycle_path -hold  -end 1 -from [get_clocks ${c}_clk] -to $clk_ram
   set_multicycle_path -hold -start 1 -from $clk_ram -to [get_clocks ${c}_clk]
}
# SRAM: not used in option (b) (A5, VERILOG_MACRO FB0_PSRAM: VDP1 frame buffer 0 lives in PSRAM 1's die 1; glue/
# vdp1fb_ext.sv drives the SRAM pins with constants: WE#, OE#, UB#, LB# high, DQ released, address 0), so it has no
# timing paths and no constraints. (Option (a)'s block for the 55 ns part: work/a5/tree's core_constraints.sdc.)
# SDRAM (sdram1, MiSTer's controller unchanged: commands on clk_ram, SDRAM clock = clk_ram inverted by a DDIO cell,
# data captured by I/O-cell registers): left unconstrained as on MiSTer and in the sotn port (glue/REPORT R5: the
# capture phase has to be checked on the Pocket's board). Video, audio and misc pins: unconstrained (as sotn); the
# bridge's inputs: below (A8).
# (A8, 2026-11-04) APF bridge inputs. apf/io_bridge_peripheral.v takes MOSI / MISO (two bits per clock, APF -> core:
# addresses, commands, write data, the data slot reads' sectors) at the rising edge of bridge_spiclk, which reaches those
# registers through the fabric (6.8-7.1 ns from its pin); APF changes the lines at the falling edge. Unconstrained (as
# sotn), the data paths followed the placement, and on the Pocket every build whose MOSI / MISO arrived more than ~3.6 ns
# after that clock failed: A7 fa_s11 5.3 ns ("Host commands ignored"), A8 r16nc_s1 4.8 ns (no disc: the CD firmware's
# data slot reads); every one at <= 3.6 ns worked: A3, A5, A6, A7b, A7c, A7d 0.9-3.6 ns (work/a8/tools/bridge.tcl).
# Against these delays the working builds pass at 3.0 ns and the failing ones fail (a8/tools/bridge_check.tcl), so
# APF's own delay lies between ~1.8 and ~3.1 ns: 4.0 ns keeps ~1 ns over it. Min 0: the hold check (the falling edge's
# new data against the rising edge before it) has 2.4-4.3 ns in every build. (Core -> APF: the core drives the clock
# and the data from clk_74a registers a clk_74a period apart: left unconstrained.)
set_input_delay -clock bridge_spiclk -clock_fall -max 4.0 [get_ports {bridge_spimosi bridge_spimiso}]
set_input_delay -clock bridge_spiclk -clock_fall -min 0.0 [get_ports {bridge_spimosi bridge_spimiso}]

# ------------------------------------------------------------------------------------------------------------------
# (A2) VDP2 dot pipeline: a genuine multicycle path (Saturn_MiSTer rtl/Saturn/VDP2/VDP2.sv, unchanged by the Pocket port)
# ------------------------------------------------------------------------------------------------------------------
# The layer dot registers (R0DOTDC / N0DOTDC..N3DOTDC, R0DOTCDP / N0DOTCDP..N3DOTCDP, SDOT) and the priority stage
# (DOT_FST / DOT_SEC / DOT_THD / DOT_FTH) are written only in always blocks enabled by
#     else if (DOT_CE_R || (DOT_CE_F & HRES[1])) begin ... end          (VDP2.sv, both blocks; no other assignment)
# and these other inputs of the priority stage only at DOT_CE_R or DOT_CE_F edges (a subset of the same edges):
#     HRES, DISP           <= REGS.TVMD.. in the  if (DOT_CE_R) begin  branch of the H/V counter block (no reset value)
#     W0_HIT_PIPE, W1_HIT_PIPE   if (DOT_CE_R || DOT_CE_F) begin  (the window hit pipeline; stage 32 from its ring)
#     BACK_DC, LINE_PAL          if (DOT_CE_R) begin  (back / line screen colours; asynchronous reset only)
# with  assign DOT_CE_R = (DOTCLK_DIV == 3) & CE_R;  assign DOT_CE_F = (DOTCLK_DIV == 1) & CE_R;
#       always @(posedge CLK) if (!RES_N) DOTCLK_DIV <= '0; else if (CE_R) DOTCLK_DIV <= DOTCLK_DIV + 2'd1;
# and CE_R = SYS_CE_R = MCLK_DIV (rtl/saturn_top.sv: always @(posedge clk_sys) MCLK_DIV <= ~MCLK_DIV), high in every
# second clk_sys. DOTCLK_DIV moves at most every second clk_sys, so the enable is high at most once in 4 clk_sys (DIV 1
# and 3; a reset only returns DIV to 0, from where 1 is again two CE_R away). A value launched by a source register at
# an enabled edge is therefore taken by a destination register at the next enabled edge, >= 4 clk_sys later, never 1
# later: setup gets 2 clk_sys here (half of the guarantee); the hold check stays at the launch edge (-hold 1).
# (Paths into these registers from anything else, e.g. the CPU-written VDP2 registers REGS / NSxREG, which change
# when the B-bus writes them, keep the default one clk_sys;
# the patterns also take the fitter's ~DUPLICATE copies, which have the same enable.)
set vdp2_dot_src [get_registers {*|isat|saturn|VDP2|N?DOTDC[*]* *|isat|saturn|VDP2|R0DOTDC[*]* *|isat|saturn|VDP2|N?DOTCDP.* *|isat|saturn|VDP2|R0DOTCDP.* *|isat|saturn|VDP2|SDOT.* *|isat|saturn|VDP2|HRES[*]* *|isat|saturn|VDP2|DISP *|isat|saturn|VDP2|DISP~* *|isat|saturn|VDP2|W0_HIT_PIPE[*]* *|isat|saturn|VDP2|W1_HIT_PIPE[*]* *|isat|saturn|VDP2|BACK_DC[*]* *|isat|saturn|VDP2|LINE_PAL[*]*}]
set vdp2_dot_dst [get_registers {*|isat|saturn|VDP2|DOT_FST.* *|isat|saturn|VDP2|DOT_SEC.* *|isat|saturn|VDP2|DOT_THD.* *|isat|saturn|VDP2|DOT_FTH.*}]
set_multicycle_path -setup -end 2 -from $vdp2_dot_src -to $vdp2_dot_dst
set_multicycle_path -hold  -end 1 -from $vdp2_dot_src -to $vdp2_dot_dst

# ------------------------------------------------------------------------------------------------------------------
# (A2) SCSP effect accumulator: a genuine multicycle path (Saturn_MiSTer rtl/Saturn/SCSP/SCSP.sv, Saturn.sv, unchanged)
# ------------------------------------------------------------------------------------------------------------------
# EFF_ACC_L / EFF_ACC_R are loaded only when  SLOT1_CE = SLOT1_EN & CYCLE1_CE,  CYCLE1_CE = CYCLE_NUM[0] & CLK_DIV & CE
# (else only the RES_N clear, which does not depend on the sources below). CYCLE_NUM changes only when  CLK_DIV && CE:
#     always @(posedge CLK) if (CE) begin CLK_DIV <= ~CLK_DIV; ... end
#     always @(posedge CLK) if (CLK_DIV && CE) CYCLE_NUM <= CYCLE_NUM + 3'd1;
# CLK_DIV toggles at every CE, so two edges with CLK_DIV && CE are >= 2 clk_sys apart (CE = SCSP_CE = SCSP_2X_CE &
# SCSP_DIV, rtl/saturn_top.sv, SCSP_DIV toggling at every SCSP_2X_CE: two SCSP_CE are >= 2 clk_sys apart, so these
# edges are even >= 4 apart). CDB_TDIV (Saturn.sv:  if (SCSP_CE) CDB_TDIV <= CDB_TDIV + 9'd1;) changes only at SCSP_CE
# edges, the next SLOT1_CE edge is >= 2 clk_sys later. Setup 2 clk_sys, hold at the launch edge (-hold 1).
set scsp_acc_src [get_registers {*|isat|saturn|SCSP|CYCLE_NUM[*]* *|isat|saturn|CDB_TDIV[*]*}]
set scsp_acc_dst [get_registers {*|isat|saturn|SCSP|EFF_ACC_L[*]* *|isat|saturn|SCSP|EFF_ACC_R[*]*}]
set_multicycle_path -setup -end 2 -from $scsp_acc_src -to $scsp_acc_dst
set_multicycle_path -hold  -end 1 -from $scsp_acc_src -to $scsp_acc_dst

# ------------------------------------------------------------------------------------------------------------------
# (A3 option vqcap) VDP1 VRAM write capture registers: same-edge hold of their data inputs from clk_sys
# ------------------------------------------------------------------------------------------------------------------
# rtl/psram0_arb.sv (option vqcap):
#     always_ff @(posedge clk) begin vc_v <= v_wq && !rst; vc_addr <= vdp1vram_addr; vc_din <= vdp1vram_din; vc_wr <= vdp1vram_wr; end
#     wr_queue ... vq (.req_valid(vc_v), .req_addr(vc_addr), .req_data(vc_din), .req_be(vc_wr), ...)
#     wire v_wq = |vdp1vram_wr && !v_wr_o;   always_ff @(posedge clk) {v_rd_o, v_wr_o} <= {vdp1vram_rd, |vdp1vram_wr};
# v_wq is high only in a clk_ram cycle that starts at a clk_sys edge (vdp1vram_wr, a clk_sys register, changes only at
# clk_sys edges and v_wr_o copies it at every clk_ram edge), so vc_v is high only in the cycle that starts at the middle
# edge: the queue uses vc_addr / vc_din / vc_wr only as loaded at a middle edge. What they load at a clk_ram edge that
# coincides with a clk_sys edge is never used (vc_v is low in the cycle after it), so a value launched by that clk_sys
# edge that reaches them at the same edge does no harm; their setup (one clk_ram from the clk_sys edge to the middle
# edge) is checked as usual. Hold moved one clk_ram earlier for these data registers only; vc_v keeps every check.
set_multicycle_path -hold -end 1 -from $clk_sys -to [get_registers {*|iarb|vc_addr[*] *|iarb|vc_din[*] *|iarb|vc_wr[*]}]
