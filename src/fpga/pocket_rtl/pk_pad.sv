// pk_pad: one Saturn standard pad (13 buttons) from the Pocket's controller 1 (APF cont1_key), in place of MiSTer's
// joystick_0 -> joy1 (emu, Saturn_MiSTer/Saturn.sv); joy1 then feeds the core's HPS2PAD as on MiSTer (port 1 digital
// pad, port 2 idle).
// joy1 (active low): [15] right [14] left [13] down [12] up [11] Start [10] A [9] C [8] B [7] R [6] X [5] Y [4] Z [3] L,
// [2:0] = 111; opposite directions cancel as in MiSTer's emu (both pressed = neither).
// cont1_key: [0] up [1] down [2] left [3] right [4] A [5] B [6] X [7] Y [8] L1 [9] R1 [10] L2 [11] R2 [12] L3 [13] R3
// [14] Select [15] Start. The handheld has Y X B A, L1 R1, Select, Start (8 of the Saturn's 9 face / shoulder
// buttons); a docked controller adds L2 R2. Presets (Core Settings "Button mapping", interact.json):
//   0  A B C = Y B A   X Y Z = L2 X Select/R2   L R = L1 R1      (handheld: all but X)
//   1  A B C = Y B A   X Y Z = L1 X R1          L R = L2 Select/R2 (handheld: all but L)
//   2  A B C = B A R1  X Y Z = Y X L1          L R = Select/L2 R2 (6-button layout; handheld: all but R)
//   3  A B C = B A Y   X Y Z = L2 X R2          L R = L1 R1     Select = Z (handheld: all but X)
// Crossing: cont1_key (clk_74a, io_pad_controller) through 2-flop synchronisers per bit (independent buttons).
`default_nettype none
module pk_pad (
	input  wire        clk_sys,
	input  wire [15:0] keys_74,           // cont1_key[15:0], clk_74a
	input  wire [ 1:0] map,               // clk_sys
	output reg  [15:0] joy1 = 16'hFFFF    // clk_sys
);
	reg [15:0] k0 = 16'd0, k = 16'd0;
	always @(posedge clk_sys) begin k0 <= keys_74; k <= k0; end
	wire up = k[0], dn = k[1], lt = k[2], rt = k[3], ka = k[4], kb = k[5], kx = k[6], ky = k[7];
	wire l1 = k[8], r1 = k[9], l2 = k[10], r2 = k[11], sel = k[14], st = k[15];
	reg  sa, sb, sc, sx, sy, sz, sl, sr;
	always @(*) begin
		case (map)
			2'd0: begin sa = ky; sb = kb; sc = ka; sx = l2; sy = kx; sz = sel | r2; sl = l1;       sr = r1;       end
			2'd1: begin sa = ky; sb = kb; sc = ka; sx = l1; sy = kx; sz = r1;       sl = l2;       sr = sel | r2; end
			2'd2: begin sa = kb; sb = ka; sc = r1; sx = ky; sy = kx; sz = l1;       sl = sel | l2; sr = r2;       end
			default: begin sa = kb; sb = ka; sc = ky; sx = l2; sy = kx; sz = sel | r2; sl = l1;    sr = r1;       end
		endcase
	end
	always @(posedge clk_sys)
		joy1 <= {~rt | lt, ~lt | rt, ~dn | up, ~up | dn, ~st, ~sa, ~sc, ~sb, ~sr, ~sx, ~sy, ~sz, ~sl, 3'b111};
endmodule
`default_nettype wire
