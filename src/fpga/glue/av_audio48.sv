// av_audio48: the SCSP's 44.1 kHz output to the Pocket's 48 kHz I2S (sound_i2s, the APF framework's I2S
// transmitter: it takes the newest sample at each 48 kHz frame through its own dual-clock FIFO, clk_audio -> clk_74a).
//
// INTERP = 0: nothing here (out = in, registered): sound_i2s's own "newest sample at each frame" is the resampler
//   (sample and hold: every ~11th SCSP sample is sent twice, at irregular times; what MiSTer's audio_out does too,
//   there behind an IIR low-pass). 0 DSP.
// INTERP = 1: linear interpolation at the I2S frame times: x0, x1 = the two newest SCSP samples, ph = SCSP clock
//   enables (ce: 512 per sample, exact in every 320 / 352 / PAL mode) since x1 arrived; at each falling edge of the
//   word clock (synchronized here, 48 kHz): out = x0 + (x1 - x0) * ph / 512, left then right through one multiplier
//   (a constant one-sample delay). A new sample is seen as a change of SOUND_L / SOUND_R (they change only at sample
//   boundaries; while they stay constant ph saturates at 511 and out = x1). The pair and the phase stay consistent:
//   a new sample arriving during the 3-clock computation is taken (x0 <= x1, ph <= 0) right after it (<= 2 SCSP_CE
//   of the new sample's phase are lost: < 0.4 % of a sample), and one arriving at the capture clock gives phase 0.
//   (sim/glue_av_audio found the inconsistent case first: one wrong sample per ~1300 frames, ~37 Hz clicks.)
// The core's SOUND_L / SOUND_R are signed 16 bit (SCSP MVolCalc), clk = clk_sys.
`default_nettype none
module av_audio48 #(parameter INTERP = 1) (
    input  wire        clk,                  // clk_sys
    input  wire        ce,                   // SCSP_CE (22.5792 MHz average)
    input  wire [15:0] in_l, in_r,
    input  wire        lrck,                 // I2S word clock (sound_i2s, clk_74a domain)
    output reg  [15:0] out_l = 16'd0,
    output reg  [15:0] out_r = 16'd0
);
    generate if (INTERP == 0) begin : g_sh
        always @(posedge clk) begin out_l <= in_l; out_r <= in_r; end
    end else begin : g_lin
        reg  [15:0] x0l = 16'd0, x0r = 16'd0, x1l = 16'd0, x1r = 16'd0;
        reg  [8:0]  ph = 9'd0, phs = 9'd0;
        reg  [2:0]  lr_s = 3'd0;
        reg  [1:0]  st = 2'd0;               // 0 idle, 1 left, 2 right, 3 right result
        wire chg = ({in_l, in_r} != {x1l, x1r});
        always @(posedge clk) begin
            if (chg && st == 2'd0) begin                        // new sample (held while a result is computed)
                x0l <= x1l; x0r <= x1r; x1l <= in_l; x1r <= in_r; ph <= 9'd0;
            end else if (ce && ph != 9'd511)
                ph <= ph + 9'd1;
            lr_s <= {lr_s[1:0], lrck};
        end
        // one multiplier, left then right
        wire               sel  = (st == 2'd2);
        wire signed [16:0] d    = sel ? ($signed({x1r[15], x1r}) - $signed({x0r[15], x0r}))
                                      : ($signed({x1l[15], x1l}) - $signed({x0l[15], x0l}));
        reg  signed [26:0] prod = 27'sd0;
        reg  signed [15:0] base = 16'sd0;
        wire signed [17:0] y    = $signed({{2{base[15]}}, base}) + $signed(prod[26:9]);
        always @(posedge clk) begin
            prod <= d * $signed({1'b0, phs});
            base <= sel ? $signed(x0r) : $signed(x0l);
            case (st)
                2'd0: if (lr_s[2] & ~lr_s[1]) begin st <= 2'd1; phs <= chg ? 9'd0 : ph; end
                2'd1: st <= 2'd2;                                  // left product in flight
                2'd2: begin st <= 2'd3; out_l <= y[15:0]; end      // left result; right product in flight
                default: begin st <= 2'd0; out_r <= y[15:0]; end   // right result
            endcase
        end
    end endgenerate
endmodule
`default_nettype wire
