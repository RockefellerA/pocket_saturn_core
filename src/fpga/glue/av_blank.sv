// av_blank: black frames for the Pocket's scaler while the core sends none (clk_pix; between av_video and the APF).
//
// Wherever a frame writes nothing, the scaler shows what its memory holds, and that memory keeps the last picture of
// whatever ran before (another core, the previous game). av_video sends full frames (240 / 256 lines, black outside
// the active area), but only on the VDP2's sync, and the VDP2 makes none while the core is held in reset (from the
// core's start until APF has loaded the BIOS and the saves; a Reset) or while the SMPC holds the VDP2 in reset: its
// counters stand still, so no VS, HS or dot reaches av_video and the old picture stays on the screen. The PSX core
// fixed the same leftovers by sending every line of every frame (fixedVBlank, version 0.3.1).
//
// Here black frames take av_video's place from power-on, and again after IDLE_CLKS clk_pix without a VS from it
// (2^20: 39 / 37 ms in 320 / 352 mode, more than two fields of any mode): 640 x 240 in scaler slot 0, progressive (VS
// feature word 0, end-of-line word 0 = slot 0), with the VDP2's NTSC timing (427 / 455 dots a line = 1708 / 1820
// clk_pix as SMPC_DOTSEL has the PLL; 263 lines), so the refresh rate does not change when av_video takes over. Its
// next VS ends them at that clock: from then on its five signals pass through. Every output is registered (all five
// one clk_pix after av_video's, which shifts nothing between them). APF rules as av_video keeps them: single-clock VS
// and HS, HS >= 3 clocks after VS (clock 8 of each line), DE once per line (clocks H_DE .. H_DE + 639 of lines V_DE ..
// V_DE + 239), no skip, RGB 0.
// A black frame cut by av_video's VS is harmless (its lines are black, the rest still hold the previous black frame).
// av_video's a_wide (the width of the slot it last announced) is not told about the black frames' slot 0: after them a
// 352 / 704-dot picture could go out 704 wide for one frame into the 640 slot. The VDP2 only stops at a reset, after
// which the BIOS starts in 320-dot mode, so that frame does not occur.
`default_nettype none
module av_blank #(
    parameter [19:0] IDLE_CLKS = 20'hFFFFF
) (
    input  wire        clk_pix,
    input  wire        dotsel,               // SMPC_DOTSEL (clk_sys, synchronous; static while the core is in reset)
    input  wire [23:0] in_rgb,               // av_video
    input  wire        in_de, in_skip, in_vs, in_hs,
    output reg  [23:0] video_rgb  = 24'd0,   // to the APF
    output reg         video_de   = 1'b0,
    output reg         video_skip = 1'b0,
    output reg         video_vs   = 1'b0,
    output reg         video_hs   = 1'b0
);
    localparam [10:0] H_DE = 11'd64;         // DE from this clock of the line, 640 clocks
    localparam [ 8:0] V_DE = 9'd20;          // DE on lines V_DE .. V_DE + 239
    localparam [ 8:0] V_TOTAL = 9'd263;

    reg        dsel  = 1'b0;
    reg        idle  = 1'b1;                 // black frames (from power-on: av_video has sent nothing yet)
    reg [19:0] quiet = 20'd0;                // clk_pix since av_video's last VS
    reg [10:0] h = 11'd0;                    // black frame: clock of the line
    reg [ 8:0] v = 9'd0;                     //              line of the frame

    wire [10:0] h_last = dsel ? 11'd1819 : 11'd1707;
    wire        g_vs = h == 11'd0 && v == 9'd0;
    wire        g_hs = h == 11'd8;
    wire        g_de = h >= H_DE && h < H_DE + 11'd640 && v >= V_DE && v < V_DE + 9'd240;

    always @(posedge clk_pix) begin
        dsel <= dotsel;
        if (idle) begin                      // (>=: dotsel may shorten a line under way)
            h <= (h >= h_last) ? 11'd0 : h + 11'd1;
            if (h >= h_last) v <= (v == V_TOTAL - 9'd1) ? 9'd0 : v + 9'd1;
        end
        if (in_vs) begin
            quiet <= 20'd0;
            idle  <= 1'b0;
        end else if (quiet != IDLE_CLKS)
            quiet <= quiet + 20'd1;
        else if (!idle) begin                // av_video has stopped: black frames, from a VS on the next clock
            idle <= 1'b1;
            h <= 11'd0;
            v <= 9'd0;
        end

        if (idle && !in_vs) begin
            video_rgb  <= 24'd0;
            video_de   <= g_de;
            video_skip <= 1'b0;
            video_vs   <= g_vs;
            video_hs   <= g_hs;
        end else begin
            video_rgb  <= in_rgb;
            video_de   <= in_de;
            video_skip <= in_skip;
            video_vs   <= in_vs;
            video_hs   <= in_hs;
        end
    end
endmodule
`default_nettype wire
