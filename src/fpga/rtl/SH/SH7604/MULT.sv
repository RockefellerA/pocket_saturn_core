module SH7604_MULT (
	input             CLK,
	input             RST_N,
	input             CE_R,
	input             CE_F,
	input             EN,
	
	input             RES_N,
	
	input      [31:0] CBUS_A,
	input      [31:0] CBUS_DI,
	output     [31:0] CBUS_DO,
	input             CBUS_WR,
	input       [3:0] CBUS_BA,
	input             CBUS_REQ,
	output            CBUS_BUSY,
	
	input       [1:0] MAC_SEL,
	input       [3:0] MAC_OP,
	input             MAC_S,
	input             MAC_WE
`ifdef SH2_SHARE_MULT
	                  ,
	output    [133:0] X_O,		//SH2_SHARE_MULT: this CPU's operands / accumulator / exec flags to the shared SH7604_MULTX
	input      [63:0] X_I		//SH2_SHARE_MULT: the next {MACH,MACL} computed by SH7604_MULTX (this CPU's, in its exec clocks)
`endif
);

	import SH7604_PKG::*;
	
	bit [31:0] MACL;
	bit [31:0] MACH;
	bit [31:0] MA;
	bit [31:0] MB;
	bit        MM_DONE;
	bit         SIGNED;
	
	bit         MACW_EXEC;
	bit         MACL_EXEC;
`ifdef SH2_SHARE_MULT
	// SH2_SHARE_MULT: the multiply / accumulate datapath (SRES, ACC64, ACC32, saturation) is SH7604_MULTX's, one copy for
	// both CPUs (below). An exec flag is set only by a MAC_WE in a CE_R clock and lives for exactly the next clock, the
	// CPU's CE_F clock; with SH2_SHARED_CORE the master's CE_F clocks are the SYS_CE_F clocks and the slave's the SYS_CE_R
	// clocks, so the two CPUs never execute in the same clock, and SH7604_MULTX computes, in every clock, for the CPU
	// whose CE_F clock it is. The registers, the flags and their timing are this module's as before.
	bit         MUL_EXEC;
	bit         DMUL_EXEC;
	bit         SAT;
	assign X_O = {MA, MB, MACH, MACL, SIGNED, SAT, MUL_EXEC, DMUL_EXEC, MACW_EXEC, MACL_EXEC};
`else
	wire [64:0] SRES =   $signed({MA[31]&SIGNED,MA}) *   $signed({MB[31]&SIGNED,MB});
	// MUL/DMUL results also go through the accumulator adder, with the MAC operand gated off (0 + SRES = SRES): the
	// MAC registers then load one sum instead of choosing between the sum and the product. MUL_EXEC, DMUL_EXEC,
	// MACW_EXEC and MACL_EXEC are each set by one MAC_WE and live for one clock, so at most one is set at a time.
	wire        ACCUM  = MACW_EXEC | MACL_EXEC;
	wire [63:0] ACC64  = $signed({MACH,MACL} & {64{ACCUM}}) + $signed(SRES[63:0]);
	// MACL + SRES as a 33-bit sum: the low 32 bits are ACC64's; bit 32 differs from ACC64[32] only by the addend bit
	// (MACL[31] instead of MACH[0]), so it is ACC64[32] ^ MACH[0] ^ MACL[31] (no second adder)
	wire [32:0] ACC32  = {ACC64[32] ^ MACH[0] ^ MACL[31], ACC64[31:0]};
`endif
	
	always @(posedge CLK or negedge RST_N) begin
		bit [ 2: 0] MM_CYC;
`ifndef SH2_SHARE_MULT
		bit         MUL_EXEC;
		bit         DMUL_EXEC;
		bit         SAT;
`endif
		bit [15: 0] DW;
		
		if (!RST_N) begin
			MACL <= '0;
			MACH <= '0;
			MA <= '0;
			MB <= '0;
			MM_DONE <= 1;
			MM_CYC <= '0;
			MUL_EXEC <= 0;
			DMUL_EXEC <= 0;
			MACW_EXEC <= 0;
			MACL_EXEC <= 0;
			SIGNED <= 0;
			// synopsys translate_off
			MACL <= 32'h01234567;
			MACH <= 32'h89ABCDEF;
			// synopsys translate_on
		end
		else begin
			if ((MAC_SEL != 2'b00) && MAC_WE && EN && CE_R) begin
				MM_DONE <= 1;
				case (MAC_OP) 
					4'b0100,			//LDS Rm,MACx
					4'b1000: begin	//LDS @Rm+,MACx
						if (MAC_SEL[0]) MACL <= CBUS_DI;
						if (MAC_SEL[1]) MACH <= CBUS_DI;
					end
					4'b0001,				//MUL.L
					4'b0010,				//DMULU.L
					4'b0011: begin		//DMULS.L
						if (MAC_SEL[1]) MA <= CBUS_DI;
						if (MAC_SEL[0]) begin
							MB <= CBUS_DI;
							MUL_EXEC <= ~MAC_OP[1];
							DMUL_EXEC <= MAC_OP[1];
							SIGNED <= MAC_OP[0] & MAC_OP[1];
							MM_CYC <= 3'd4;
							MM_DONE <= 0;
						end
					end
					4'b0110,				//MULU.W
					4'b0111: begin		//MULS.W
						MA <= {{16{CBUS_DI[15]&MAC_OP[0]}},CBUS_DI[15:0]};
						MB <= {{16{CBUS_DI[31]&MAC_OP[0]}},CBUS_DI[31:16]};
						MUL_EXEC <= MAC_SEL[1];
						SIGNED <= MAC_OP[0];
						MM_CYC <= 3'd1;
						MM_DONE <= 0;
					end
					4'b1001: begin		//MAC.L @Rm+,@Rn+
						if (MAC_SEL[1]) MA <= CBUS_DI;
						if (MAC_SEL[0]) begin
							MB <= CBUS_DI;
							MACL_EXEC <= 1;
							SIGNED <= MAC_OP[0];
							SAT <= MAC_S;
							MM_CYC <= 3'd4;
							MM_DONE <= 0;
						end
					end
					4'b1011: begin		//MAC.W @Rm+,@Rn+
						DW = !CBUS_A[1] ? CBUS_DI[31:16] : CBUS_DI[15:0];
						if (MAC_SEL[1]) MA <= {{16{DW[15]&MAC_OP[0]}},DW};
						if (MAC_SEL[0]) begin
							MB <= {{16{DW[15]&MAC_OP[0]}},DW};
							MACW_EXEC <= 1;
							SIGNED <= MAC_OP[0];
							SAT <= MAC_S;
							MM_CYC <= 3'd2;
							MM_DONE <= 0;
						end
					end
					4'b1111: {MACH,MACL} <= '0;
					default:;
				endcase
			end
			
			if (!MM_DONE && CE_R) begin
				if (MM_CYC != 3'd0) MM_CYC <= MM_CYC - 3'd1;
				if (MM_CYC == 3'd1) MM_DONE <= 1;
			end
			
`ifdef SH2_SHARE_MULT
			if (MUL_EXEC | DMUL_EXEC | MACW_EXEC | MACL_EXEC) begin	//SH7604_MULTX gives this CPU's result in its exec clock
				{MACH,MACL} <= X_I;
				MUL_EXEC <= 0;
				DMUL_EXEC <= 0;
				MACW_EXEC <= 0;
				MACL_EXEC <= 0;
			end
`else
			if (MUL_EXEC) begin
				MACL <= ACC64[31:0];
				MUL_EXEC <= 0;
			end
			
			if (DMUL_EXEC) begin
				{MACH,MACL} <= ACC64;
				DMUL_EXEC <= 0;
			end
			
			if (MACW_EXEC) begin
				if (!SAT) begin
					{MACH,MACL} <= ACC64;
				end else begin
					if (ACC32[32] != ACC32[31]) begin
						MACL <= {ACC32[32],{31{~ACC32[32]}}};
						MACH <= ACC64[63:32] | 32'h00000001;
					end else begin
						MACL <= ACC32[31:0];
//						MACH <= 32'h00000000;//??
					end
				end
				MACW_EXEC <= 0;
			end
			
			if (MACL_EXEC) begin
				if (!SAT) begin
					{MACH,MACL} <= ACC64;
				end else begin
					if (ACC64[63:48] != {16{ACC64[47]}}) begin
						{MACH,MACL} <= {{17{MA[31]^MB[31]}},{47{~(MA[31]^MB[31])}}};
					end else begin
						{MACH,MACL} <= ACC64;
					end
				end
				MACL_EXEC <= 0;
			end
`endif
		end
	end
	
	assign CBUS_DO = MAC_SEL[1] ? MACH : MACL;
	assign CBUS_BUSY = ~MM_DONE && (!MAC_OP[2] ? MAC_SEL[0] : |MAC_SEL);

endmodule
`ifdef SH2_SHARE_MULT

// SH2_SHARE_MULT: the multiply / accumulate datapath of both CPUs' SH7604_MULT, shared in time (rtl/Saturn/Saturn.sv has
// the one instance). In every clock it computes for the CPU whose CE_F clock it is: PH = SYS_CE_R, so the slave
// (CE_F = SYS_CE_R with SH2_SHARED_CORE) when PH = 1 and the master when PH = 0. Its code is SH7604_MULT's exec code:
// XI is the next {MACH,MACL} of the CPU whose exec flag is set (a CPU's flags are only ever set in its CE_F clocks).
module SH7604_MULTX (
	input             PH,
	input     [133:0] XO0,		//the master's SH7604_MULT X_O
	input     [133:0] XO1,		//the slave's
	output reg [63:0] XI
);
	wire [133:0] X = PH ? XO1 : XO0;
	wire [31:0] MA = X[133:102], MB = X[101:70], MACH = X[69:38], MACL = X[37:6];
	wire        SIGNED = X[5], SAT = X[4], MUL_EXEC = X[3], DMUL_EXEC = X[2], MACW_EXEC = X[1], MACL_EXEC = X[0];
	wire [64:0] SRES =   $signed({MA[31]&SIGNED,MA}) *   $signed({MB[31]&SIGNED,MB});
	wire        ACCUM  = MACW_EXEC | MACL_EXEC;
	wire [63:0] ACC64  = $signed({MACH,MACL} & {64{ACCUM}}) + $signed(SRES[63:0]);
	wire [32:0] ACC32  = {ACC64[32] ^ MACH[0] ^ MACL[31], ACC64[31:0]};
	always_comb begin
		XI = ACC64;																//DMUL, MAC.W / MAC.L without saturation
		if (MUL_EXEC) XI = {MACH, ACC64[31:0]};
		else if (MACW_EXEC && SAT) XI = ACC32[32] != ACC32[31] ? {ACC64[63:32] | 32'h00000001, ACC32[32], {31{~ACC32[32]}}} : {MACH, ACC32[31:0]};
		else if (MACL_EXEC && SAT && ACC64[63:48] != {16{ACC64[47]}}) XI = {{17{MA[31]^MB[31]}}, {47{~(MA[31]^MB[31])}}};
	end
endmodule
`endif
`ifdef SH2_SHARE_MULTCS

// SH2_SHARE_MULTCS (R8 study prototype; needs SH2_SHARED_CORE): one MULT for both CPUs, C-slowed. In every clock one
// CPU has its CE_R clock (thread e: the master when PH = SYS_CE_R = 1) and the other its CE_F clock (thread o). The
// MULT's CE_R logic (MAC_WE: operand / MACH / MACL loads, the busy counter) runs once, for thread e, and its exec logic
// (the multiply / accumulate, live in the clock after the MAC_WE, the CPU's CE_F clock) once, for thread o.
// - MA, MACH, MACL, MM_DONE, MM_CYC are pairs X / X_1: X holds thread e's value at the start of a clock, X_1 thread o's;
//   at the edge X_1 <= the CE_R logic's next value of X, X <= the exec logic's next value of X_1 (thread e has its CE_F
//   clock next, thread o its CE_R clock).
// - MB, SIGNED, SAT and the four exec flags are read only by the exec, in the clock right after the MAC_WE that set
//   the flag, and every MAC_WE that sets a flag also writes MB / SIGNED (and SAT for MAC.L / MAC.W): one copy each,
//   written in every clock for thread e (the flags 0 without such a MAC_WE: a CPU's flags are always 0 at the start of
//   its CE_R clock, cleared by its exec in the clock before).
// Outputs: each CPU's MACH / MACL / MM_DONE in every clock (X in its CE_R clocks, X_1 in its CE_F clocks).
module SH7604_MULTCS (
	input             CLK,
	input             RST_N,
	input             PH,
	input             EN,
	input      [40:0] XO0,		//the master's {MAC_WE, MAC_SEL[1:0], MAC_OP[3:0], MAC_S, CBUS_A[1], CBUS_DI[31:0]}
	input      [40:0] XO1,		//the slave's
	output     [64:0] XI0,		//to the master: {MACH, MACL, MM_DONE}
	output     [64:0] XI1		//to the slave
);
	wire [40:0] XE = PH ? XO0 : XO1;
	wire        MAC_WE = XE[40], MAC_S = XE[33], CBUS_A1 = XE[32];
	wire  [1:0] MAC_SEL = XE[39:38];
	wire  [3:0] MAC_OP = XE[37:34];
	wire [31:0] CBUS_DI = XE[31:0];

	bit [31:0] MA, MA_1, MACH, MACH_1, MACL, MACL_1;
	bit        MM_DONE, MM_DONE_1;
	bit  [2:0] MM_CYC, MM_CYC_1;
	bit [31:0] MB;
	bit        SIGNED, SAT, MUL_EXEC, DMUL_EXEC, MACW_EXEC, MACL_EXEC;

	//CE_R logic, thread e (SH7604_MULT's MAC_WE and busy-counter code)
	bit [31:0] n_MA, n_MB, n_MACH, n_MACL;
	bit        n_MM_DONE, n_SIGNED, n_SAT, n_MUL, n_DMUL, n_MACW, n_MACL_EXEC;
	bit  [2:0] n_MM_CYC;
	bit [15:0] DW;
	always_comb begin
		{n_MA, n_MACH, n_MACL, n_MM_DONE, n_MM_CYC} = {MA, MACH, MACL, MM_DONE, MM_CYC};
		{n_MB, n_SIGNED, n_SAT} = {MB, SIGNED, SAT};
		{n_MUL, n_DMUL, n_MACW, n_MACL_EXEC} = '0;
		DW = !CBUS_A1 ? CBUS_DI[31:16] : CBUS_DI[15:0];
		if ((MAC_SEL != 2'b00) && MAC_WE && EN) begin
			n_MM_DONE = 1;
			case (MAC_OP)
				4'b0100,
				4'b1000: begin
					if (MAC_SEL[0]) n_MACL = CBUS_DI;
					if (MAC_SEL[1]) n_MACH = CBUS_DI;
				end
				4'b0001,
				4'b0010,
				4'b0011: begin
					if (MAC_SEL[1]) n_MA = CBUS_DI;
					if (MAC_SEL[0]) begin
						n_MB = CBUS_DI;
						n_MUL = ~MAC_OP[1];
						n_DMUL = MAC_OP[1];
						n_SIGNED = MAC_OP[0] & MAC_OP[1];
						n_MM_CYC = 3'd4;
						n_MM_DONE = 0;
					end
				end
				4'b0110,
				4'b0111: begin
					n_MA = {{16{CBUS_DI[15]&MAC_OP[0]}},CBUS_DI[15:0]};
					n_MB = {{16{CBUS_DI[31]&MAC_OP[0]}},CBUS_DI[31:16]};
					n_MUL = MAC_SEL[1];
					n_SIGNED = MAC_OP[0];
					n_MM_CYC = 3'd1;
					n_MM_DONE = 0;
				end
				4'b1001: begin
					if (MAC_SEL[1]) n_MA = CBUS_DI;
					if (MAC_SEL[0]) begin
						n_MB = CBUS_DI;
						n_MACL_EXEC = 1;
						n_SIGNED = MAC_OP[0];
						n_SAT = MAC_S;
						n_MM_CYC = 3'd4;
						n_MM_DONE = 0;
					end
				end
				4'b1011: begin
					if (MAC_SEL[1]) n_MA = {{16{DW[15]&MAC_OP[0]}},DW};
					if (MAC_SEL[0]) begin
						n_MB = {{16{DW[15]&MAC_OP[0]}},DW};
						n_MACW = 1;
						n_SIGNED = MAC_OP[0];
						n_SAT = MAC_S;
						n_MM_CYC = 3'd2;
						n_MM_DONE = 0;
					end
				end
				4'b1111: {n_MACH,n_MACL} = '0;
				default:;
			endcase
		end
		if (!MM_DONE) begin
			if (MM_CYC != 3'd0) n_MM_CYC = MM_CYC - 3'd1;
			if (MM_CYC == 3'd1) n_MM_DONE = 1;
		end
	end

	//exec logic, thread o (SH7604_MULT's exec code), on X_1 and the shared operand registers
	wire [64:0] SRES =   $signed({MA_1[31]&SIGNED,MA_1}) *   $signed({MB[31]&SIGNED,MB});
	wire        ACCUM  = MACW_EXEC | MACL_EXEC;
	wire [63:0] ACC64  = $signed({MACH_1,MACL_1} & {64{ACCUM}}) + $signed(SRES[63:0]);
	wire [32:0] ACC32  = {ACC64[32] ^ MACH_1[0] ^ MACL_1[31], ACC64[31:0]};
	bit  [63:0] o_MAC;
	always_comb begin
		o_MAC = {MACH_1, MACL_1};
		if (MUL_EXEC) o_MAC = {MACH_1, ACC64[31:0]};
		else if (DMUL_EXEC) o_MAC = ACC64;
		else if (MACW_EXEC) o_MAC = !SAT ? ACC64 : ACC32[32] != ACC32[31] ? {ACC64[63:32] | 32'h00000001, ACC32[32], {31{~ACC32[32]}}} : {MACH_1, ACC32[31:0]};
		else if (MACL_EXEC) o_MAC = !SAT || ACC64[63:48] == {16{ACC64[47]}} ? ACC64 : {{17{MA_1[31]^MB[31]}}, {47{~(MA_1[31]^MB[31])}}};
	end

	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			{MA, MA_1, MACH, MACH_1, MACL, MACL_1} <= '0;
			// synopsys translate_off
			{MACL, MACL_1} <= {2{32'h01234567}};
			{MACH, MACH_1} <= {2{32'h89ABCDEF}};
			// synopsys translate_on
			{MM_DONE, MM_DONE_1} <= 2'b11;
			{MM_CYC, MM_CYC_1} <= '0;
			MB <= '0;
			SIGNED <= 0;
			{MUL_EXEC, DMUL_EXEC, MACW_EXEC, MACL_EXEC} <= '0;
		end
		else begin
			{MA_1, MM_DONE_1, MM_CYC_1, MACH_1, MACL_1} <= {n_MA, n_MM_DONE, n_MM_CYC, n_MACH, n_MACL};
			{MA, MM_DONE, MM_CYC} <= {MA_1, MM_DONE_1, MM_CYC_1};
			{MACH, MACL} <= o_MAC;
			{MB, SIGNED} <= {n_MB, n_SIGNED};
			{MUL_EXEC, DMUL_EXEC, MACW_EXEC, MACL_EXEC} <= {n_MUL, n_DMUL, n_MACW, n_MACL_EXEC};
		end
	end
	always @(posedge CLK) if (RST_N) SAT <= n_SAT;		//not reset (as SH7604_MULT's SAT)

	assign XI0 = PH ? {MACH, MACL, MM_DONE} : {MACH_1, MACL_1, MM_DONE_1};
	assign XI1 = PH ? {MACH_1, MACL_1, MM_DONE_1} : {MACH, MACL, MM_DONE};
endmodule
`endif
