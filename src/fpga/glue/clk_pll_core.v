// clk_pll_core: the Saturn core's PLL on the Pocket, reconfigurable (DPRIO port for glue/rtl/clk_reconf.sv).
// From clk_74a (74.25 MHz): f_vcopost = 74.25 MHz * (M + K / 2^32), N 1, VCO = 2 * f_vcopost (post divider 2),
//   outclk_0 = clk_sys    = f_vcopost / 10
//   outclk_1 = clk_ram    = f_vcopost / 5        (2 x clk_sys, edges aligned with clk_sys)
//   outclk_2 = clk_pix    = f_vcopost / 20       (clk_sys / 2: the APF video clock)
//   outclk_3 = clk_pix_90 = f_vcopost / 20, 90 degrees later (5 VCO-post periods: the APF DDR video clock)
//   outclk_4 = clk_ram shifted (only with NCLK = 5: PSRAM capture clock for psram_phy CLKDIV = 1; phase in
//              VCO-post periods (RD_PRST - 1) plus 1/8 VCO steps (RD_PH); not used by the recommended design)
// Compiled in NTSC 352 (M 7, K 0xB6A87CD7: clk_sys 57.2728 MHz, VCO 1145.456 MHz), the fastest mode, so that the
// timing analysis covers the worst case; clk_reconf changes only K (M is 7 in every mode, glue/clk/pllcalc.py):
//   NTSC 320 53.7482 / PAL 320 53.375 / PAL 352 56.875 MHz (VCO 1067.5-1145.5 MHz, C8 limit 600-1300).
// The C counters never change, so the outputs keep their ratios and their phases in degrees in every mode.
// Physical parameters as altera_pll's IP generator writes them (Reconfigurable subtype); the loop settings
// (charge pump 20, bandwidth resistor 4000) are what the generator picks for the same VCO and total feedback
// division (1145.456 MHz / 74.25 MHz = 15.43, there as M 15 with post divider 1, builds/glue_clk_pllgen/gen_c10);
// the generator itself only offers post divider 1, where M would have to change between modes (14 / 15).
// mimic_fbclk_type "gclk": the fitter (25.1, 5CEBA4F23C8) rejects the generator's "none" for every reconfigurable
// PLL (also the generator's own, builds/glue_clk_t_ipgen); with "gclk" it builds the PLL in Normal mode with
// global-clock feedback (builds/glue_clk_t_gd), as it does for sotn's General PLLs.
`timescale 1 ps / 1 ps

module clk_pll_core #(
    parameter NCLK    = 4,
    parameter RD_PRST = 2,
    parameter RD_PH   = 0
) (
    input  wire        refclk,              // clk_74a
    input  wire        rst,
    output wire        clk_sys,
    output wire        clk_ram,
    output wire        clk_pix,
    output wire        clk_pix_90,
    output wire        clk_ram_rd,
    output wire        locked,
    input  wire [63:0] reconfig_to_pll,
    output wire [63:0] reconfig_from_pll
);
    wire [4:0] outclk;
    assign clk_sys    = outclk[0];
    assign clk_ram    = outclk[1];
    assign clk_pix    = outclk[2];
    assign clk_pix_90 = outclk[3];
    assign clk_ram_rd = (NCLK > 4) ? outclk[4] : 1'b0;

    altera_pll #(
        .fractional_vco_multiplier("true"),
        .reference_clock_frequency("74.25 MHz"),
        .pll_fractional_cout(32),
        .pll_dsm_out_sel("1st_order"),
        .operation_mode("direct"),
        .number_of_clocks(NCLK),
        .output_clock_frequency0("57.272800 MHz"),  .phase_shift0("0 ps"),    .duty_cycle0(50),
        .output_clock_frequency1("114.545600 MHz"), .phase_shift1("0 ps"),    .duty_cycle1(50),
        .output_clock_frequency2("28.636400 MHz"),  .phase_shift2("0 ps"),    .duty_cycle2(50),
        .output_clock_frequency3("28.636400 MHz"),  .phase_shift3("8730 ps"), .duty_cycle3(50),
        .output_clock_frequency4((NCLK > 4) ? "114.545600 MHz" : "0 MHz"),
        .phase_shift4("0 ps"), .duty_cycle4(50),
        .pll_type("Cyclone V"),
        .pll_subtype("Reconfigurable"),
        .m_cnt_hi_div(4),
        .m_cnt_lo_div(3),
        .n_cnt_hi_div(256),
        .n_cnt_lo_div(256),
        .m_cnt_bypass_en("false"),
        .n_cnt_bypass_en("true"),
        .m_cnt_odd_div_duty_en("true"),
        .n_cnt_odd_div_duty_en("false"),
        .c_cnt_hi_div0(5),   .c_cnt_lo_div0(5),   .c_cnt_prst0(1), .c_cnt_ph_mux_prst0(0),
        .c_cnt_in_src0("ph_mux_clk"), .c_cnt_bypass_en0("false"), .c_cnt_odd_div_duty_en0("false"),
        .c_cnt_hi_div1(3),   .c_cnt_lo_div1(2),   .c_cnt_prst1(1), .c_cnt_ph_mux_prst1(0),
        .c_cnt_in_src1("ph_mux_clk"), .c_cnt_bypass_en1("false"), .c_cnt_odd_div_duty_en1("true"),
        .c_cnt_hi_div2(10),  .c_cnt_lo_div2(10),  .c_cnt_prst2(1), .c_cnt_ph_mux_prst2(0),
        .c_cnt_in_src2("ph_mux_clk"), .c_cnt_bypass_en2("false"), .c_cnt_odd_div_duty_en2("false"),
        .c_cnt_hi_div3(10),  .c_cnt_lo_div3(10),  .c_cnt_prst3(6), .c_cnt_ph_mux_prst3(0),
        .c_cnt_in_src3("ph_mux_clk"), .c_cnt_bypass_en3("false"), .c_cnt_odd_div_duty_en3("false"),
        .c_cnt_hi_div4(3),   .c_cnt_lo_div4(2),   .c_cnt_prst4(RD_PRST), .c_cnt_ph_mux_prst4(RD_PH),
        .c_cnt_in_src4("ph_mux_clk"), .c_cnt_bypass_en4((NCLK > 4) ? "false" : "true"),
        .c_cnt_odd_div_duty_en4((NCLK > 4) ? "true" : "false"),
        .pll_vco_div(2),
        .pll_cp_current(20),
        .pll_bwctrl(4000),
        .pll_output_clk_frequency("572.728 MHz"),
        .pll_fractional_division("3064495319"),
        .mimic_fbclk_type("gclk"),             // "none" (what the generator writes) fails on the A4 in Quartus 25.1
        .pll_fbclk_mux_1("glb"),
        .pll_fbclk_mux_2("m_cnt"),
        .pll_m_cnt_in_src("ph_mux_clk"),
        .pll_slf_rst("true")
    ) altera_pll_i (
        .rst               (rst),
        .outclk            (outclk[NCLK-1:0]),
        .locked            (locked),
        .reconfig_to_pll   (reconfig_to_pll),
        .fboutclk          (),
        .fbclk             (1'b0),
        .refclk            (refclk),
        .reconfig_from_pll (reconfig_from_pll)
    );
    generate if (NCLK < 5) begin : g_nc
        assign outclk[4:NCLK] = {(5 - NCLK){1'b0}};
    end endgenerate
endmodule
