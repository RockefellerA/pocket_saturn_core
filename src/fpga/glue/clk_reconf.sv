// clk_reconf: minimal Cyclone V fractional-PLL reconfiguration writer for the Saturn core's clock on the Pocket
// (replaces MiSTer's pll_cfg = Altera's altera_pll_reconfig_top/core: 755.7 ALMs in the harness fit, 577.1 standalone
// in builds/glue_clk_ip, where it misses 74.25 MHz; this writer: 43.3 ALMs, 147 MHz, builds/glue_clk_a10).
//
// It drives the PLL's DPRIO port (reconfig_to_pll / reconfig_from_pll, the bus altera_pll exposes when
// pll_subtype = "Reconfigurable") with exactly the DPRIO transactions the Altera IP makes when MiSTer's FSM
// (Saturn.sv) writes M (reg 4), K (reg 7) and START (reg 2):
//   power-up (as the IP's self_reset + fpll_dprio_init): DPRIO rst_n low for 341 clocks, then 64 dummy writes
//   (address 0..63, data 0, mdio_dis high: ignored by the PLL), ser_shift_load low for 2 clocks, mdio_dis low;
//   per change of mode (as the IP's DPRIO FSM, same order and the same clock spacing):
//     WRITE_M = 1: W 0x12 = {M hi, M lo}; R 0x15; R 0x17; W 0x15 = rd15 with bit 4 = M bypass (0);
//                  W 0x17 = rd17 with bit 4 = M odd-duty;  then the K part below
//     K part:      R 0x17; W 0x17 = rd17 with bit 11 = 0 (K not ready); W 0x18 = K[15:0]; W 0x19 = K[31:16];
//                  W 0x17 = rd17 with bit 11 = 1 (K ready)
//   read data is taken 2 clocks after the read cycle (the IP's timing); the shared registers 0x15 / 0x17 are
//   read-modify-written, so their other bits keep the configured values.
// With the recommended PLL plan (glue/rtl/clk_pll_core.v: 74.25 MHz, N 1, M 7, vco_div 2, C0 10) M is 7 in all four
// modes and only K changes: WRITE_M = 0 (the IP's own sequence for a K-only change: 4 writes and 1 read).
// WRITE_M = 1 is MiSTer's M + K sequence (needed if M differs between modes, e.g. the C0 = 8 plan: M 5 / 6).
// No C counter, N, bandwidth, charge pump or phase-shift writes: the C counters are fixed, so every output keeps its
// ratio to the VCO (clk_sys : clk_ram : pixel clock = 2 : 4 : 1) and its phase in degrees.
//
// mode = {PAL, DOTSEL} may come from any clock domain (3-flop synchronizer here, like the IP's lock). A new mode
// is applied when the PLL is locked and the previous change is done; a change while one is running is applied
// after it (level-based: the PLL always ends in the last requested mode). After each change the writer waits
// HOLD clocks and for lock again before the next one (the IP waits for lock only).
// busy: from a detected change until the PLL has been reprogrammed and is locked again (status only).
`default_nettype none

module clk_reconf #(
    parameter        WRITE_M   = 0,             // 1: also rewrite M (MiSTer's full pll_cfg sequence)
    parameter [1:0]  INIT_MODE = 2'b01,          // mode the PLL is compiled in (clk_pll_core: NTSC 352)
    // per-mode values, mode = {PAL, DOTSEL}: K = fractional part * 2^32, M as reg 4 of the IP
    // ({odd duty [17], bypass [16], hi [15:8], lo [7:0]}); defaults = the C0 10 plan (glue/clk/pllcalc.py)
    parameter [31:0] K0 = 32'h3D22F7BB,          // NTSC 320: clk_sys 53.7482 MHz
    parameter [31:0] K1 = 32'hB6A87CD7,          // NTSC 352: clk_sys 57.2728 MHz
    parameter [31:0] K2 = 32'h3044F4CB,          // PAL 320:  clk_sys 53.3750 MHz
    parameter [31:0] K3 = 32'hA8F158C8,          // PAL 352:  clk_sys 56.8750 MHz
    parameter [17:0] M0 = 18'h20403, M1 = 18'h20403, M2 = 18'h20403, M3 = 18'h20403,
    parameter        HOLD_W    = 9               // hold-off after a change: 2^HOLD_W clocks (512 = 6.9 us at 74.25 MHz)
) (
    input  wire        clk,                      // management clock = DPRIO clock (clk_74a; <= 100 MHz)
    input  wire [1:0]  mode,                     // {PAL, DOTSEL}, asynchronous
    output wire [63:0] reconfig_to_pll,
    input  wire [63:0] reconfig_from_pll,
    output wire        busy,
    output wire        locked
);
    // ---------------------------------------------------------------- synchronizers (3 flops, as the IP's lock)
    reg [2:0] lk_s = 3'd0;
    reg [1:0] m_s0 = INIT_MODE, m_s1 = INIT_MODE, m_s2 = INIT_MODE;
    always @(posedge clk) begin
        lk_s <= {lk_s[1:0], reconfig_from_pll[16]};
        m_s0 <= mode; m_s1 <= m_s0; m_s2 <= m_s1;
    end
    wire lk = lk_s[2];
    assign locked = lk;

    // reconfiguration sequencer state (used below): st 0 idle / wait for lock, 1..LAST the IP's DPRIO FSM cycles
    localparam LAST = (WRITE_M != 0) ? 4'd15 : 4'd9;
    reg  [3:0]  st = 4'd0;
    reg         hold = 1'b0;                     // hold-off after a change

    // ---------------------------------------------------------------- power-up: the IP's self_reset + dprio init
    // cnt counts the reset phase (local_reset high while 0..340), then the init phase (as fpll_dprio_init's count),
    // then the hold-off after each change.
    localparam P_RST = 2'd0, P_INIT = 2'd1, P_RUN = 2'd2;
    reg  [1:0]  ph = P_RST;
    reg  [8:0]  cnt = 9'd0;
    reg  [1:0]  rsy = 2'b00;                     // fpll_dprio_init's reset synchronizer
    reg         mdio_dis = 1'b1, ssl = 1'b1, init_done = 1'b0;
    wire        rst_n  = (ph != P_RST);          // DPRIO rst_n (the IP's ~local_reset)
    wire [6:0]  ic     = cnt[6:0];
    wire        i_done = ic[6] & ic[2];          // init counter reached 68 (the IP stops it there)
    always @(posedge clk) begin
        rsy <= rst_n ? {rsy[0], 1'b1} : 2'b00;
        if (ph == P_RST) begin
            cnt <= cnt + 9'd1;
            if (cnt == 9'd340) begin ph <= P_INIT; cnt <= 9'd0; end
        end else if (ph == P_INIT) begin
            if (rsy[1] && !i_done) cnt <= cnt + 9'd1;
            mdio_dis  <= ic[6] ? ~ic[2] : 1'b1;
            ssl       <= ic[6] ? |ic[2:1] : 1'b1;
            init_done <= i_done;
            if (init_done) begin ph <= P_RUN; cnt <= 9'd0; end
        end else begin
            // hold-off after a change (st / hold below)
            if (st == LAST) cnt <= 9'd0;
            else if (hold)  cnt <= cnt + 9'd1;
        end
    end

    // ---------------------------------------------------------------- reconfiguration sequencer
    reg  [1:0]  cur = INIT_MODE, tgt = INIT_MODE;
    reg  [15:0] ra = 16'd0, rb = 16'd0;          // read data: ra = reg 0x15 (WRITE_M only), rb = reg 0x17
    wire [15:0] dout = reconfig_from_pll[15:0];

    wire start = (ph == P_RUN) && init_done && (st == 4'd0) && !hold && lk && (m_s2 != cur);
    always @(posedge clk) begin
        if (ph == P_RUN) begin
            if (start) begin st <= 4'd1; tgt <= m_s2; end
            else if (st == LAST) begin st <= 4'd0; hold <= 1'b1; cur <= tgt; end
            else if (st != 4'd0) st <= st + 4'd1;
            if (hold && &cnt[HOLD_W-1:0] && lk) hold <= 1'b0;
        end
        // read captures, at the end of the 2nd clock after the read cycle (the IP's FOUR / FIVE states)
        if (WRITE_M != 0) begin
            if (st == 4'd4)  ra <= dout;         // R 0x15 in st 2
            if (st == 4'd5)  rb <= dout;         // R 0x17 in st 3
            if (st == 4'd10) rb <= dout;         // R 0x17 in st 8 (after the M odd-duty write)
        end else begin
            if (st == 4'd4)  rb <= dout;         // R 0x17 in st 2
        end
    end

    // table: K and M for the target mode
    reg [31:0] k;
    reg [17:0] m;
    always @(*) begin
        case (tgt)
            2'd0: begin k = K0; m = M0; end
            2'd1: begin k = K1; m = M1; end
            2'd2: begin k = K2; m = M2; end
            default: begin k = K3; m = M3; end
        endcase
    end

    // DPRIO bus for the current sequencer step (the IP's ONE..TEN; st counts from the IP's first ONE cycle)
    reg        wr, rd;
    reg [5:0]  a;
    reg [15:0] d;
    always @(*) begin
        wr = 1'b0; rd = 1'b0; a = 6'h00; d = 16'h0000;
        if (WRITE_M != 0) begin
            case (st)
                4'd1:  begin wr = 1'b1; a = 6'h12; d = m[15:0]; end                    // ONE:   M hi / lo
                4'd2:  begin rd = 1'b1; a = 6'h15; end                                 // TWO:   M bypass word
                4'd3:  begin rd = 1'b1; a = 6'h17; end                                 // THREE: M odd word
                4'd6:  begin wr = 1'b1; a = 6'h15; d = {ra[15:5], m[16], ra[3:0]}; end // SIX
                4'd7:  begin wr = 1'b1; a = 6'h17; d = {rb[15:5], m[17], rb[3:0]}; end // SEVEN
                4'd8:  begin rd = 1'b1; a = 6'h17; end                                 // TWO:   K ready word
                4'd12: begin wr = 1'b1; a = 6'h17; d = {rb[15:12], 1'b0, rb[10:0]}; end // SEVEN: K not ready
                4'd13: begin wr = 1'b1; a = 6'h18; d = k[15:0];  end                   // EIGHT
                4'd14: begin wr = 1'b1; a = 6'h19; d = k[31:16]; end                   // NINE
                4'd15: begin wr = 1'b1; a = 6'h17; d = {rb[15:12], 1'b1, rb[10:0]}; end // TEN:  K ready
                default: ;
            endcase
        end else begin
            case (st)
                4'd2:  begin rd = 1'b1; a = 6'h17; end                                 // TWO:   K ready word
                4'd6:  begin wr = 1'b1; a = 6'h17; d = {rb[15:12], 1'b0, rb[10:0]}; end // SEVEN: K not ready
                4'd7:  begin wr = 1'b1; a = 6'h18; d = k[15:0];  end                   // EIGHT
                4'd8:  begin wr = 1'b1; a = 6'h19; d = k[31:16]; end                   // NINE
                4'd9:  begin wr = 1'b1; a = 6'h17; d = {rb[15:12], 1'b1, rb[10:0]}; end // TEN:  K ready
                default: ;
            endcase
        end
    end

    // init phase: the IP's fpll_dprio_init drives the bus (64 dummy writes while mdio_dis is high)
    wire       iw  = (ph == P_INIT) && !init_done && !ic[6] && rst_n;
    wire       bwr = init_done ? wr : iw;
    wire       brd = init_done ? rd : 1'b0;
    wire [5:0] ba  = init_done ? a  : ((ic[6] || !rst_n) ? 6'h00 : ic[5:0]);
    wire [15:0] bd = init_done ? d  : 16'h0000;
    wire [1:0] bbe = init_done ? {2{wr | rd}} : 2'b11;

    assign reconfig_to_pll[0]     = clk;         // DPRIO clock
    assign reconfig_to_pll[1]     = rst_n;
    assign reconfig_to_pll[2]     = bwr;
    assign reconfig_to_pll[3]     = brd;
    assign reconfig_to_pll[9:4]   = ba;
    assign reconfig_to_pll[25:10] = bd;
    assign reconfig_to_pll[27:26] = bbe;
    assign reconfig_to_pll[28]    = ssl;         // ser_shift_load
    assign reconfig_to_pll[29]    = mdio_dis;
    assign reconfig_to_pll[30]    = 1'b0;        // phase_en
    assign reconfig_to_pll[31]    = 1'b0;        // up_dn
    assign reconfig_to_pll[36:32] = 5'd0;        // cnt_sel
    assign reconfig_to_pll[63:37] = 27'd0;       // scanen, atpgmode (unused on Cyclone V), reserved

    assign busy = (ph != P_RUN) || (st != 4'd0) || hold || (m_s2 != cur);
endmodule

`default_nettype wire
