`ifdef CUT_MSH_DIVU_OVF
module SH7604_DIVU #(parameter bit CUT_OVFIE=0) (	//U3 CUT_SSH_DIVU_OVF (the slave) / U4 CUT_MSH_DIVU_OVF (the master): DVCR.OVFIE stays 0, see DVCR
`else
`ifdef CUT_SSH_DIVU_OVF
module SH7604_DIVU #(parameter bit CUT_OVFIE=0) (	//U3 CUT_SSH_DIVU_OVF (the slave only): DVCR.OVFIE stays 0, see DVCR
`else
module SH7604_DIVU (
`endif
`endif
	input             CLK,
	input             RST_N,
	input             CE_R,
	input             CE_F,
	input             EN,
	
	input             RES_N,
	
	input      [31:0] IBUS_A,
	input      [31:0] IBUS_DI,
	output     [31:0] IBUS_DO,
	input       [3:0] IBUS_BA,
	input             IBUS_WE,
	input             IBUS_REQ,
	output reg        IBUS_BUSY,
	output            IBUS_ACT,
	
	output            IRQ,
	output      [7:0] VEC
);

	import SH7604_PKG::*;
	
	DVSR_t      DVSR;
	DVDNT_t     DVDNTL;
	DVDNT_t     DVDNTH;
	DVCR_t      DVCR;
	DVDNT_t     DVDNTL2;
	DVDNT_t     DVDNTH2;
	VCRDIV_t    VCRDIV;
	bit         BUSY;
	
	wire REG_SEL = (IBUS_A >= 32'hFFFFFF00 && IBUS_A <= 32'hFFFFFF3F);
	wire DIV32_START = REG_SEL && IBUS_A[4:0] == 5'h04 && IBUS_WE && IBUS_REQ;
	wire DIV64_START = REG_SEL && IBUS_A[4:0] == 5'h14 && IBUS_WE && IBUS_REQ;
	
	
`ifdef DIVU_LEAN
	// R5 DIVU_LEAN: the same division with a leaner datapath; outside the DIVU nothing differs (STEP and so BUSY, the
	// overflow exit at step 5, DVCR and the interrupt, every register value a bus read can return: see below). Instead
	// of the working copies R (65 bits), D (64), Q (32), R64 (64) and the 65-bit adder, a signed non-restoring division
	// runs in place in DVDNTH:DVDNTL with one 32-bit adder: DVDNTH holds the partial remainder, DVDNTL the dividend's
	// low word (shifting out at the top) and the quotient bits (shifting in at the bottom).
	//   step 1   R_SIGN = the dividend's sign.  step 2: D64H = the divisor (DVSR), OVF0 = divisor 0.
	//   3..35    sum = DVDNTH - D64H when the last quotient bit is 1 (step 3: when the signs are equal), else + D64H;
	//            quotient bit ~(sum[31] ^ D_SIGN) into DVDNTL[0]; DVDNTH = {sum[30:0],DVDNTL[31]} (step 35: sum).
	//            Steps 3..5 are the original's R64 steps (32-bit modular, the same bits), so step 5's overflow check
	//            reads its T64 of steps 3 and 4 in DVDNTL[1:0], and after an overflow DVDNTH:DVDNTL hold R64. Without
	//            an overflow the first remainder is within [-|D|,|D|) and so is every later one: the 32-bit sums are
	//            exact and dividend = D * P + r, P = the sum of the +-1 digits.
	//   36       r (DVDNTH) becomes the truncated remainder: r < 0 with a dividend >= 0, or r = -|D|: r + |D|; r > 0
	//            with a dividend < 0: r - |D| (the adder's add / subtract is then the one T = DVDNTL[0] selects).
	//   37       the quotient: P mod 2^32 = {DVDNTL[31:1],1}; DVDNTL[0] = 0 marks a correction (P - 1), INC: P + 1.
	//   38       as the original (DVDNTL = the quotient, the saturated value or R64, all in place).
	// The original's non-overflow results are the truncated quotient (mod 2^32) and remainder, which this computes
	// (u/r5/REPORT.txt: the proof, the model checks, the lockstep benches).
	// DVDNTH:DVDNTL hold working values only while the DIVU operates (STEP != 3F). A read then waits (BUSY, set by the
	// access that started the division) and gets the final value; at every step-38 edge and while STEP = 3F they are
	// the original's (RES_N and EN: the register block).
	bit  [ 5: 0] STEP;				//0..38 while dividing, 3F idle (the original's)
	bit          DIV64;				//64/32 division (started by a DVDNTL write)
	bit          R_SIGN;			//sign of the dividend (step 1)
	bit  [31: 0] D64H;				//the divisor, DVSR as step 2 took it (RES_N may clear DVSR later)
	bit          OVF;
	bit          OVF0;				//divisor 0 (step 2)
	bit          RZ;					//the remainder of step 35 is 0
	bit          INC;				//the quotient needs +1 (step 37)
	wire         D_SIGN = D64H[31];
	wire         S_SIGN = R_SIGN ^ D_SIGN;	//sign of the quotient
	wire         LIVE = ~DIV64 & OVF0;		//32/32 division by 0: DVDNTH:DVDNTL shift as the original's registers do
	wire         ADJ = (STEP == 6'd37);
	wire         T = (STEP == 6'd3) ? ~S_SIGN : DVDNTL[0];	//subtract the divisor
	wire [31: 0] SUM = (ADJ ? {1'b0,DVDNTL[31:1]} : DVDNTH) + (ADJ ? 32'd0 : D64H ^ {32{T}}) + {31'd0, ADJ ? INC : T};
	wire         QB = ~(SUM[31] ^ D_SIGN);	//quotient bit
	wire         SUM_Z = (SUM == 32'd0);
	wire         FIX_A = DVDNTH[31] & (~R_SIGN | SUM_Z);	//step 36: r < 0 and (dividend >= 0 or r = -|D|): r + |D|
	wire         FIX_B = ~DVDNTH[31] & R_SIGN & ~RZ;		//step 36: r > 0 and dividend < 0: r - |D|
	wire         DVSR_Z = (DVSR == 32'd0);
	wire         OVF_STEP5 = STEP == 6'd5 && (OVF0 || ((DVDNTL[1] != DVDNTL[0] || (DVDNTL[1] != S_SIGN && DVDNTL[0] != S_SIGN)) && DIV64));
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			STEP <= 6'h3F;
			OVF <= 0;
		end
		else if (EN && CE_R) begin
			if (STEP != 6'h3F) begin
				STEP <= STEP + 6'd1;
			end
			if (STEP == 6'h3F && (DIV32_START || DIV64_START)) begin
				STEP <= 6'd0;
				DIV64 <= DIV64_START;
				OVF0 <= 0;
				OVF <= 0;
			end
			if (STEP == 6'd1) begin
				R_SIGN <= DVDNTH[31];
			end
			if (STEP == 6'd2) begin
				D64H <= DVSR;
				if (DVSR_Z) OVF0 <= 1;
			end
			if (OVF_STEP5) begin
				OVF <= 1;
				STEP <= 6'd38;
			end
			if (STEP == 6'd35) begin
				RZ <= SUM_Z;
			end
			if (STEP == 6'd36) begin
				INC <= (FIX_A & D_SIGN) | (FIX_B & ~D_SIGN);
			end
			if (STEP == 6'd38) begin
				STEP <= 6'h3F;
			end
		end
	end
`else
	bit  [ 5: 0] STEP;
	bit          DIV64;
	bit  [64: 0] R;
	bit  [63: 0] D;				//the divisor (|DVSR| << 32, shifted right by one per step); its sign bit is always 0
	bit  [31: 0] Q;
	bit  [63: 0] R64;
	bit  [31: 0] D64H;			//divisor for the overflow check: {DVSR,32'h0}, low half is always 0
	bit          R_SIGN,D_SIGN;
	bit          T64;
	bit          OVF;
	// One 65-bit adder serves both the restoring step (R - D, steps 3-35) and the negator (steps 1, 2, 36, 37)
	wire         DIV_STEP = (STEP >= 6'd3 && STEP <= 6'd35);
	bit  [64: 0] VAL;
	bit          NEG;
	wire [64: 0] ADD_RES = (DIV_STEP ? R : (VAL ^ {65{NEG}})) + (DIV_STEP ? ~{1'b0,D} : 65'd0) + {64'd0, DIV_STEP | NEG};
	wire [64: 0] SUM = ADD_RES;
	wire [32: 0] SUM64H = T64 ? $signed({R64[63],R64[63:32]}) - $unsigned(D64H) : $signed({R64[63],R64[63:32]}) + $unsigned(D64H);
	wire [64: 0] SUM64 = {SUM64H,R64[31:0]};
	// Negator operand: what the original latched on CE_F of steps 1, 2, 36 and 37. Its sources only change on CE_R
	// and CE_R/CE_F alternate, so selecting them combinationally gives the same value on the following CE_R.
	always_comb begin
		case (STEP)
			6'd1:    begin VAL = {DVDNTH[31],DVDNTH,DVDNTL};    NEG = DVDNTH[31]; end
			6'd2:    begin VAL = {DVSR[31],DVSR,32'h00000000}; NEG = DVSR[31]; end
			6'd36:   begin VAL = R;                            NEG = R_SIGN; end
			default: begin VAL = {{33{Q[31]}},Q};              NEG = R_SIGN^D_SIGN; end
		endcase
	end
	// R only ever loads the adder result: in steps 1 and 36 (negator), in a restoring step whose difference is not
	// negative, and in step 5 when the overflow check fires. So it is one enable on the adder output.
	bit          OVF0,OVF64_33;
	wire         OVF_STEP5 = STEP == 6'd5 && (OVF0 || ((OVF64_33 != T64 || (OVF64_33 != (R_SIGN^D_SIGN) && T64 != (R_SIGN^D_SIGN))) && DIV64));
	wire         R_EN = EN & CE_R & (STEP == 6'd1 | STEP == 6'd36 | (DIV_STEP & (~ADD_RES[64] | OVF_STEP5)));
	always @(posedge CLK) begin
		if (R_EN) R <= ADD_RES;
	end
	always @(posedge CLK or negedge RST_N) begin
		bit  [64: 0] NRES;
		
		if (!RST_N) begin
			STEP <= 6'h3F;
			OVF <= 0;
		end
		else if (EN && CE_R) begin
			if (STEP != 6'h3F) begin
				STEP <= STEP + 6'd1;
			end
			if (STEP == 6'h3F && (DIV32_START || DIV64_START)) begin
				STEP <= 6'd0;
				DIV64 <= DIV64_START;
				OVF0 <= 0;
				OVF <= 0;
			end
			
			NRES = ADD_RES;
			if (STEP == 6'd0) begin
				Q <= '0;
			end
			if (STEP == 6'd1) begin
				R_SIGN <= NEG;
				R64 <= VAL[63:0];
			end
			if (STEP == 6'd2) begin
				D <= NRES[63:0];
				D_SIGN <= NEG;
				D64H <= VAL[63:32];
				T64 <= ~(R_SIGN^NEG);
				
				if (VAL[63:32] == 32'h00000000) OVF0 <= 1;
			end
			if (STEP >= 6'd3 && STEP <= 6'd35) begin
				Q <= {Q[30:0],~SUM[64]};
				D <= {1'b0,D[63:1]};
				
				if (STEP >= 6'd3 && STEP <= 6'd5) begin
				R64 <= {SUM64[62:0],~(SUM64[63]^D_SIGN)};
				T64 <= ~(SUM64[63]^D_SIGN);
				end
				
				if (STEP == 6'd4) begin
					OVF64_33 <= T64; 
				end
				if (OVF_STEP5) begin
					OVF <= 1; 
					STEP <= 6'd38;
				end
			end
			if (STEP == 6'd37) begin
				Q <= NRES[31:0];
			end
			if (STEP == 6'd38) begin
				STEP <= 6'h3F;
			end
		end
	end
`endif
	
	wire OPERATE = (STEP != 6'h3F);
	
	
	//Registers
	always @(posedge CLK or negedge RST_N) begin
		bit          SND_UPD;
		
		if (!RST_N) begin
			DVSR <= DVSR_INIT;
			DVDNTL <= DVDNT_INIT;
			DVDNTH <= DVDNT_INIT;
			DVCR <= DVCR_INIT;
			VCRDIV <= VCRDIV_INIT;
			DVDNTL2 <= DVDNT_INIT;
			DVDNTH2 <= DVDNT_INIT;
			// synopsys translate_off
			
			// synopsys translate_on
		end
		else if (CE_R) begin
			if (!RES_N) begin
				DVSR <= DVSR_INIT;
				DVDNTL <= DVDNT_INIT;
				DVDNTH <= DVDNT_INIT;
				DVCR <= DVCR_INIT;
				VCRDIV <= VCRDIV_INIT;
				DVDNTL2 <= DVDNT_INIT;
				DVDNTH2 <= DVDNT_INIT;
			end
			else if (REG_SEL && IBUS_WE && IBUS_REQ && !OPERATE) begin
				case ({IBUS_A[4:2],2'b00})
					5'h00: DVSR <= IBUS_DI & DVSR_WMASK;
					5'h04: {DVDNTH,DVDNTL} <= {{32{IBUS_DI[31]}},IBUS_DI} & {DVDNT_WMASK,DVDNT_WMASK};
					5'h08: begin
						if (IBUS_BA[3:2] != 2'b00) DVCR[31:16] <= IBUS_DI[31:16] & DVCR_WMASK[31:16];
`ifdef CUT_MSH_DIVU_OVF
						// U3 / U4 CUT_OVFIE: OVFIE is written as 0 (reads 0): no overflow interrupt, an overflow always gives the OVFIE = 0
						// result (DVDNTL saturated). The slave (U3) and the master (U4: the BIOS boot, the BIOS menus and every game) only
						// ever wrote OVFIE = 0 (work/usage logs).
						if (IBUS_BA[1:0] != 2'b00) DVCR[15:0]  <= IBUS_DI[15:0]  & DVCR_WMASK[15:0] & {14'h3FFF, ~CUT_OVFIE, 1'b1};
`else
`ifdef CUT_SSH_DIVU_OVF
						// U3 CUT_OVFIE: OVFIE is written as 0 (reads 0): no overflow interrupt, an overflow always gives the OVFIE = 0
						// result (DVDNTL saturated); the slave only ever wrote DVCR = 0 (work/usage logs).
						if (IBUS_BA[1:0] != 2'b00) DVCR[15:0]  <= IBUS_DI[15:0]  & DVCR_WMASK[15:0] & {14'h3FFF, ~CUT_OVFIE, 1'b1};
`else
						if (IBUS_BA[1:0] != 2'b00) DVCR[15:0]  <= IBUS_DI[15:0]  & DVCR_WMASK[15:0];
`endif
`endif
					end
					5'h0C: begin
						if (IBUS_BA[1:0] != 2'b00) VCRDIV[15:0] <= IBUS_DI[15:0] & VCRDIV_WMASK[15:0];
					end
					5'h10: DVDNTH <= IBUS_DI & DVDNT_WMASK;
					5'h14: DVDNTL <= IBUS_DI & DVDNT_WMASK;
					5'h18: DVDNTH2 <= IBUS_DI & DVDNT_WMASK;
					5'h1C: DVDNTL2 <= IBUS_DI & DVDNT_WMASK;
					default:;
				endcase
			end
			
			SND_UPD <= 0;
`ifdef DIVU_LEAN
			// R5 DIVU_LEAN: the division works in place here (datapath above). The original's register block runs on every
			// CE_R, also with EN = 0 or RES_N = 0 (its step assignments override the RES_N reset), its working copies on
			// EN & CE_R only. So that DVDNTH / DVDNTL end as the original's in every case:
			//   - the working values move on EN & CE_R and are held otherwise; RES_N does not clear them while they carry
			//     a dividend the original keeps in R / R64 (from the EN edge of step 1 for a 64/32 division; in step 2
			//     also for a 32/32 one whose divisor, DVSR at that EN edge, is not 0): those results come from the copies;
			//   - a 32/32 division by 0 (LIVE) ends with the original's registers themselves (DVDNTH; DVDNTL with OVFIE):
			//     they shift on every CE_R of steps 3..5 with ~R_SIGN coming in (the original's ~SUM[64] ^ R_SIGN for a
			//     divisor 0), from the dividend or, after RES_N in the steps before, from 0, as the original's do;
			//   - step 38 as the original's, R64 / Q being the values in place (RES_N clears DVDNTH, and DVDNTL, where
			//     the original does not assign it).
			if ((STEP == 6'd1 && EN && DIV64) || (STEP == 6'd2 && (DIV64 || (EN && !DVSR_Z)))) begin
				DVDNTH <= DVDNTH;
				DVDNTL <= DVDNTL;
			end
			if (STEP >= 6'd3 && STEP <= 6'd35) begin	//the 33 division steps
				if (EN || LIVE) begin
					DVDNTH <= STEP == 6'd35 ? SUM : {SUM[30:0],DVDNTL[31]};	//LIVE: D64H = 0, so SUM = DVDNTH
					DVDNTL <= {DVDNTL[30:0],LIVE ? ~R_SIGN : QB};
				end else begin
					DVDNTH <= DVDNTH;
					DVDNTL <= DVDNTL;
				end
			end
			if (STEP == 6'd36) begin
				DVDNTH <= EN && (FIX_A || FIX_B) ? SUM : DVDNTH;
				DVDNTL <= EN ? {DVDNTL[31:1],~(FIX_A | FIX_B)} : DVDNTL;
			end
			if (STEP == 6'd37) begin
				DVDNTH <= DVDNTH;
				DVDNTL <= EN ? {SUM[30:0],DVDNTL[0]} : DVDNTL;
			end
			if (STEP == 6'd38) begin
				if (OVF) begin
					if (!DVCR.OVFIE) begin
						DVDNTL <= {S_SIGN,{31{~S_SIGN}}};
						if (DIV64) DVDNTH <= DVDNTH;
					end else  begin
						if (DIV64) DVDNTL <= DVDNTL;
						if (DIV64) DVDNTH <= DVDNTH;
					end
					DVCR.OVF <= 1;
				end else begin
					DVDNTL <= DVDNTL;
				end
				SND_UPD <= 1;
			end
`else
			if (STEP >= 6'd3 && STEP <= 6'd35) begin
				{DVDNTH,DVDNTL} <= {DVDNTH[30:0],DVDNTL,~SUM[64]^R_SIGN};
			end
			if (STEP == 6'd37) begin
				DVDNTH <= R[31:0];
			end
			if (STEP == 6'd38) begin
				if (OVF) begin
					if (!DVCR.OVFIE) begin
						DVDNTL <= {R_SIGN^D_SIGN,{31{~(R_SIGN^D_SIGN)}}};
						if (DIV64) DVDNTH <= R64[63:32];
					end else  begin
						if (DIV64) DVDNTL <= R64[31:0];
						if (DIV64) DVDNTH <= R64[63:32];
					end
					DVCR.OVF <= 1;
				end else begin
					DVDNTL <= Q;
				end
				SND_UPD <= 1;
			end
`endif
			
			if (SND_UPD) begin
				DVDNTL2 <= DVDNTL;
				DVDNTH2 <= DVDNTH;
			end
		end
	end
	
	assign IRQ = DVCR.OVF & DVCR.OVFIE;
	assign VEC = VCRDIV[7:0];
	
	
	bit [31:0] REG_DO;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			REG_DO <= '0;
		end
		else if (CE_F) begin
			if (REG_SEL && !IBUS_WE && IBUS_REQ) begin
				case ({IBUS_A[4:2],2'b00})
					5'h00: REG_DO <= DVSR & DVSR_RMASK;
					5'h04: REG_DO <= DVDNTL & DVDNT_RMASK;
					5'h08: REG_DO <= DVCR & DVCR_RMASK;
					5'h0C: REG_DO <= {16'h0000,VCRDIV} & VCRDIV_RMASK;
					5'h10: REG_DO <= DVDNTH & DVDNT_RMASK;
					5'h14: REG_DO <= DVDNTL & DVDNT_RMASK;
					5'h18: REG_DO <= DVDNTH2 & DVDNT_RMASK;
					5'h1C: REG_DO <= DVDNTL2 & DVDNT_RMASK;
					default:REG_DO <= '0;
				endcase
			end
		end
	end
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			BUSY <= 0;
		end
		else if (EN && CE_F) begin
			if (REG_SEL && IBUS_REQ && OPERATE && !BUSY) begin
				BUSY <= 1;
			end else if (!OPERATE && BUSY) begin
				BUSY <= 0;
			end
		end
	end
	
	assign IBUS_DO = REG_SEL ? (IBUS_BA != 4'b1111 ? {2{REG_DO[15:0]}} : REG_DO) : '0;
	assign IBUS_BUSY = BUSY;
	assign IBUS_ACT = REG_SEL;

endmodule
`ifdef SH2_SHARE_DIVU

// SH2_SHARE_DIVU (R8 study prototype; needs SH2_SHARED_CORE and DIVU_LEAN): one DIVU for both CPUs, C-slowed like
// rtl/SH/core/SH_core_cs.sv. With SH2_SHARED_CORE the master's SH7604 runs with CE_R = SYS_CE_R and the slave's with
// CE_R = SYS_CE_F, so in every clock one CPU has its CE_R clock (thread e: the master when PH = SYS_CE_R = 1) and the
// other its CE_F clock (thread o). One copy of the DIVU's CE_R logic serves thread e and one copy of its CE_F logic
// (the bus read register, BUSY) serves thread o. Every register X becomes a pair X / X_1: at the start of a clock X
// holds thread e's value and X_1 thread o's; at the edge X_1 <= the CE_R logic's next value of X (thread e, which has
// its CE_F clock next) and X <= the CE_F logic's next value of X_1 (thread o, which has its CE_R clock next). The
// next-state code is SH7604_DIVU's (DIVU_LEAN) with the old values read from X (CE_R logic) or X_1 (CE_F logic) and
// each thread's own bus inputs. Registers the original does not reset on RST_N keep rotating while RST_N is low.
// Outputs: IRQ / VEC exact in every clock (selected by PH). The bus read data (REG_DO) and BUSY are exact in the
// clocks they are used (REG_DO in the CPU's CE_R clock, by the cache's read path; BUSY in its CE_F clock, by the
// cache's IBUS_WAIT); EXACT_OUT = 1 selects them by PH in every clock too.
module SH7604_DIVUX #(parameter bit CUT_OVFIE0=0, bit CUT_OVFIE1=0, bit EXACT_OUT=0) (
	input             CLK,
	input             RST_N,
	input             PH,
	input             EN,
	input      [44:0] XO0,		//the master's {RES_N, REG_SEL, IBUS_A[4:0], IBUS_BA[3:0], IBUS_WE, IBUS_REQ, IBUS_DI[31:0]}
	input      [44:0] XO1,		//the slave's
	output     [41:0] XI0,		//to the master: {REG_DO[31:0], BUSY, IRQ, VEC[7:0]}
	output     [41:0] XI1		//to the slave
);
	import SH7604_PKG::*;

	//thread e (CE_R clock) and thread o (CE_F clock) inputs
	wire [44:0] XE = PH ? XO0 : XO1;
	wire [44:0] XF = PH ? XO1 : XO0;
	wire        RES_N = XE[44], REG_SEL = XE[43], IBUS_WE = XE[33], IBUS_REQ = XE[32];
	wire  [4:0] IBUS_A = XE[42:38];
	wire  [3:0] IBUS_BA = XE[37:34];
	wire [31:0] IBUS_DI = XE[31:0];
	wire        o_REG_SEL = XF[43], o_IBUS_WE = XF[33], o_IBUS_REQ = XF[32];
	wire  [4:0] o_IBUS_A = XF[42:38];
	wire        CUT_OVFIE = PH ? CUT_OVFIE0 : CUT_OVFIE1;

	//registers: X (thread e) / X_1 (thread o)
	DVSR_t      DVSR, DVSR_1;
	DVDNT_t     DVDNTL, DVDNTL_1;
	DVDNT_t     DVDNTH, DVDNTH_1;
	DVCR_t      DVCR, DVCR_1;
	DVDNT_t     DVDNTL2, DVDNTL2_1;
	DVDNT_t     DVDNTH2, DVDNTH2_1;
	VCRDIV_t    VCRDIV, VCRDIV_1;
	bit         BUSY, BUSY_1;
	bit  [31:0] REG_DO, REG_DO_1;
	bit  [ 5:0] STEP, STEP_1;
	bit         DIV64, DIV64_1;
	bit         R_SIGN, R_SIGN_1;
	bit  [31:0] D64H, D64H_1;
	bit         OVF, OVF_1;
	bit         OVF0, OVF0_1;
	bit         RZ, RZ_1;
	bit         INC, INC_1;
	bit         SND_UPD, SND_UPD_1;

	//the CE_R logic (SH7604_DIVU's, DIVU_LEAN), thread e, on X
	wire         DIV32_START = REG_SEL && IBUS_A[4:0] == 5'h04 && IBUS_WE && IBUS_REQ;
	wire         DIV64_START = REG_SEL && IBUS_A[4:0] == 5'h14 && IBUS_WE && IBUS_REQ;
	wire         D_SIGN = D64H[31];
	wire         S_SIGN = R_SIGN ^ D_SIGN;
	wire         LIVE = ~DIV64 & OVF0;
	wire         ADJ = (STEP == 6'd37);
	wire         T = (STEP == 6'd3) ? ~S_SIGN : DVDNTL[0];
	wire [31: 0] SUM = (ADJ ? {1'b0,DVDNTL[31:1]} : DVDNTH) + (ADJ ? 32'd0 : D64H ^ {32{T}}) + {31'd0, ADJ ? INC : T};
	wire         QB = ~(SUM[31] ^ D_SIGN);
	wire         SUM_Z = (SUM == 32'd0);
	wire         FIX_A = DVDNTH[31] & (~R_SIGN | SUM_Z);
	wire         FIX_B = ~DVDNTH[31] & R_SIGN & ~RZ;
	wire         DVSR_Z = (DVSR == 32'd0);
	wire         OVF_STEP5 = STEP == 6'd5 && (OVF0 || ((DVDNTL[1] != DVDNTL[0] || (DVDNTL[1] != S_SIGN && DVDNTL[0] != S_SIGN)) && DIV64));
	wire         OPERATE = (STEP != 6'h3F);

	bit  [ 5:0] n_STEP;
	bit         n_DIV64, n_R_SIGN, n_OVF, n_OVF0, n_RZ, n_INC, n_SND_UPD;
	bit  [31:0] n_D64H;
	DVSR_t      n_DVSR;
	DVDNT_t     n_DVDNTL, n_DVDNTH, n_DVDNTL2, n_DVDNTH2;
	DVCR_t      n_DVCR;
	VCRDIV_t    n_VCRDIV;
	always_comb begin
		{n_STEP, n_DIV64, n_R_SIGN, n_OVF, n_OVF0, n_RZ, n_INC, n_D64H} = {STEP, DIV64, R_SIGN, OVF, OVF0, RZ, INC, D64H};
		{n_DVSR, n_DVDNTL, n_DVDNTH, n_DVDNTL2, n_DVDNTH2, n_DVCR, n_VCRDIV, n_SND_UPD} = {DVSR, DVDNTL, DVDNTH, DVDNTL2, DVDNTH2, DVCR, VCRDIV, SND_UPD};
		//the step machine (EN && CE_R)
		if (EN) begin
			if (STEP != 6'h3F) n_STEP = STEP + 6'd1;
			if (STEP == 6'h3F && (DIV32_START || DIV64_START)) begin
				n_STEP = 6'd0;
				n_DIV64 = DIV64_START;
				n_OVF0 = 0;
				n_OVF = 0;
			end
			if (STEP == 6'd1) n_R_SIGN = DVDNTH[31];
			if (STEP == 6'd2) begin
				n_D64H = DVSR;
				if (DVSR_Z) n_OVF0 = 1;
			end
			if (OVF_STEP5) begin
				n_OVF = 1;
				n_STEP = 6'd38;
			end
			if (STEP == 6'd35) n_RZ = SUM_Z;
			if (STEP == 6'd36) n_INC = (FIX_A & D_SIGN) | (FIX_B & ~D_SIGN);
			if (STEP == 6'd38) n_STEP = 6'h3F;
		end
		//the registers (CE_R)
		if (!RES_N) begin
			n_DVSR = DVSR_INIT;
			n_DVDNTL = DVDNT_INIT;
			n_DVDNTH = DVDNT_INIT;
			n_DVCR = DVCR_INIT;
			n_VCRDIV = VCRDIV_INIT;
			n_DVDNTL2 = DVDNT_INIT;
			n_DVDNTH2 = DVDNT_INIT;
		end
		else if (REG_SEL && IBUS_WE && IBUS_REQ && !OPERATE) begin
			case ({IBUS_A[4:2],2'b00})
				5'h00: n_DVSR = IBUS_DI & DVSR_WMASK;
				5'h04: {n_DVDNTH,n_DVDNTL} = {{32{IBUS_DI[31]}},IBUS_DI} & {DVDNT_WMASK,DVDNT_WMASK};
				5'h08: begin
					if (IBUS_BA[3:2] != 2'b00) n_DVCR[31:16] = IBUS_DI[31:16] & DVCR_WMASK[31:16];
					if (IBUS_BA[1:0] != 2'b00) n_DVCR[15:0]  = IBUS_DI[15:0]  & DVCR_WMASK[15:0] & {14'h3FFF, ~CUT_OVFIE, 1'b1};
				end
				5'h0C: begin
					if (IBUS_BA[1:0] != 2'b00) n_VCRDIV[15:0] = IBUS_DI[15:0] & VCRDIV_WMASK[15:0];
				end
				5'h10: n_DVDNTH = IBUS_DI & DVDNT_WMASK;
				5'h14: n_DVDNTL = IBUS_DI & DVDNT_WMASK;
				5'h18: n_DVDNTH2 = IBUS_DI & DVDNT_WMASK;
				5'h1C: n_DVDNTL2 = IBUS_DI & DVDNT_WMASK;
				default:;
			endcase
		end
		n_SND_UPD = 0;
		if ((STEP == 6'd1 && EN && DIV64) || (STEP == 6'd2 && (DIV64 || (EN && !DVSR_Z)))) begin
			n_DVDNTH = DVDNTH;
			n_DVDNTL = DVDNTL;
		end
		if (STEP >= 6'd3 && STEP <= 6'd35) begin
			if (EN || LIVE) begin
				n_DVDNTH = STEP == 6'd35 ? SUM : {SUM[30:0],DVDNTL[31]};
				n_DVDNTL = {DVDNTL[30:0],LIVE ? ~R_SIGN : QB};
			end else begin
				n_DVDNTH = DVDNTH;
				n_DVDNTL = DVDNTL;
			end
		end
		if (STEP == 6'd36) begin
			n_DVDNTH = EN && (FIX_A || FIX_B) ? SUM : DVDNTH;
			n_DVDNTL = EN ? {DVDNTL[31:1],~(FIX_A | FIX_B)} : DVDNTL;
		end
		if (STEP == 6'd37) begin
			n_DVDNTH = DVDNTH;
			n_DVDNTL = EN ? {SUM[30:0],DVDNTL[0]} : DVDNTL;
		end
		if (STEP == 6'd38) begin
			if (OVF) begin
				if (!DVCR.OVFIE) begin
					n_DVDNTL = {S_SIGN,{31{~S_SIGN}}};
					if (DIV64) n_DVDNTH = DVDNTH;
				end else begin
					if (DIV64) n_DVDNTL = DVDNTL;
					if (DIV64) n_DVDNTH = DVDNTH;
				end
				n_DVCR.OVF = 1;
			end else begin
				n_DVDNTL = DVDNTL;
			end
			n_SND_UPD = 1;
		end
		if (SND_UPD) begin
			n_DVDNTL2 = DVDNTL;
			n_DVDNTH2 = DVDNTH;
		end
	end

	//the CE_F logic (bus read register, BUSY), thread o, on X_1
	wire         o_OPERATE = (STEP_1 != 6'h3F);
	bit  [31:0] n_REG_DO;
	bit         n_BUSY;
	always_comb begin
		n_REG_DO = REG_DO_1;
		if (o_REG_SEL && !o_IBUS_WE && o_IBUS_REQ) begin
			case ({o_IBUS_A[4:2],2'b00})
				5'h00: n_REG_DO = DVSR_1 & DVSR_RMASK;
				5'h04: n_REG_DO = DVDNTL_1 & DVDNT_RMASK;
				5'h08: n_REG_DO = DVCR_1 & DVCR_RMASK;
				5'h0C: n_REG_DO = {16'h0000,VCRDIV_1} & VCRDIV_RMASK;
				5'h10: n_REG_DO = DVDNTH_1 & DVDNT_RMASK;
				5'h14: n_REG_DO = DVDNTL_1 & DVDNT_RMASK;
				5'h18: n_REG_DO = DVDNTH2_1 & DVDNT_RMASK;
				5'h1C: n_REG_DO = DVDNTL2_1 & DVDNT_RMASK;
				default:n_REG_DO = '0;
			endcase
		end
		n_BUSY = BUSY_1;
		if (EN) begin
			if (o_REG_SEL && o_IBUS_REQ && o_OPERATE && !BUSY_1) n_BUSY = 1;
			else if (!o_OPERATE && BUSY_1) n_BUSY = 0;
		end
	end

	//the rotation (registers SH7604_DIVU resets on RST_N)
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			{STEP, STEP_1} <= {6'h3F, 6'h3F};
			{OVF, OVF_1} <= '0;
			{DVSR, DVSR_1} <= {DVSR_INIT, DVSR_INIT};
			{DVDNTL, DVDNTL_1} <= {DVDNT_INIT, DVDNT_INIT};
			{DVDNTH, DVDNTH_1} <= {DVDNT_INIT, DVDNT_INIT};
			{DVCR, DVCR_1} <= {DVCR_INIT, DVCR_INIT};
			{VCRDIV, VCRDIV_1} <= {VCRDIV_INIT, VCRDIV_INIT};
			{DVDNTL2, DVDNTL2_1} <= {DVDNT_INIT, DVDNT_INIT};
			{DVDNTH2, DVDNTH2_1} <= {DVDNT_INIT, DVDNT_INIT};
			{REG_DO, REG_DO_1} <= '0;
			{BUSY, BUSY_1} <= '0;
		end
		else begin
			{STEP_1, OVF_1, DVSR_1, DVDNTL_1, DVDNTH_1, DVCR_1, VCRDIV_1, DVDNTL2_1, DVDNTH2_1} <=
				{n_STEP, n_OVF, n_DVSR, n_DVDNTL, n_DVDNTH, n_DVCR, n_VCRDIV, n_DVDNTL2, n_DVDNTH2};
			{STEP, OVF, DVSR, DVDNTL, DVDNTH, DVCR, VCRDIV, DVDNTL2, DVDNTH2} <=
				{STEP_1, OVF_1, DVSR_1, DVDNTL_1, DVDNTH_1, DVCR_1, VCRDIV_1, DVDNTL2_1, DVDNTH2_1};
			{REG_DO_1, BUSY_1} <= {REG_DO, BUSY};
			{REG_DO, BUSY} <= {n_REG_DO, n_BUSY};
			//both CPUs cut: their DVCR.OVFIE is 0 in every clock (reset 0, written as 0), so both positions hold 0; say so,
			//as SH7604_DIVU's stuck-at-0 register does (else IRQ / VEC and the OVFIE branches survive synthesis)
			if (CUT_OVFIE0 && CUT_OVFIE1) {DVCR.OVFIE, DVCR_1.OVFIE} <= 2'b00;
		end
	end
	//the rotation (registers SH7604_DIVU does not reset on RST_N: they hold, i.e. keep rotating)
	always @(posedge CLK) begin
		if (!RST_N) begin
			{DIV64_1, R_SIGN_1, D64H_1, OVF0_1, RZ_1, INC_1, SND_UPD_1} <= {DIV64, R_SIGN, D64H, OVF0, RZ, INC, SND_UPD};
		end else begin
			{DIV64_1, R_SIGN_1, D64H_1, OVF0_1, RZ_1, INC_1, SND_UPD_1} <= {n_DIV64, n_R_SIGN, n_D64H, n_OVF0, n_RZ, n_INC, n_SND_UPD};
		end
		{DIV64, R_SIGN, D64H, OVF0, RZ, INC, SND_UPD} <= {DIV64_1, R_SIGN_1, D64H_1, OVF0_1, RZ_1, INC_1, SND_UPD_1};
	end

	//outputs. A CPU's register values are at X in its CE_R clocks and at X_1 in its CE_F clocks.
	wire        IRQ0 = PH ? DVCR.OVF & DVCR.OVFIE : DVCR_1.OVF & DVCR_1.OVFIE;
	wire        IRQ1 = PH ? DVCR_1.OVF & DVCR_1.OVFIE : DVCR.OVF & DVCR.OVFIE;
	wire  [7:0] VEC0 = PH ? VCRDIV[7:0] : VCRDIV_1[7:0];
	wire  [7:0] VEC1 = PH ? VCRDIV_1[7:0] : VCRDIV[7:0];
	//REG_DO: the CE_R clock's thread's (X), BUSY: the CE_F clock's thread's (X_1); EXACT_OUT: each CPU's in every clock
	wire [31:0] RDO0 = EXACT_OUT ? (PH ? REG_DO : REG_DO_1) : REG_DO;
	wire [31:0] RDO1 = EXACT_OUT ? (PH ? REG_DO_1 : REG_DO) : REG_DO;
	wire        BSY0 = EXACT_OUT ? (PH ? BUSY : BUSY_1) : BUSY_1;
	wire        BSY1 = EXACT_OUT ? (PH ? BUSY_1 : BUSY) : BUSY_1;
	assign XI0 = {RDO0, BSY0, IRQ0, VEC0};
	assign XI1 = {RDO1, BSY1, IRQ1, VEC1};
endmodule
`endif
