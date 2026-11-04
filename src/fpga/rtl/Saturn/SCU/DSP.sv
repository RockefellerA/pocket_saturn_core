module SCU_DSP (
	input             CLK,
	input             RST_N,
	input             CE,
	
	input             RES_N,
	
	input             CE_R,
	input             CE_F,
	input       [1:0] A,
	input      [31:0] DI,
	output reg [31:0] DO,
	input       [3:0] WE,
	input             RE,
	
	output     [31:0] DSO,
	output            RA0W,
	output            WA0W,
	output            DMAW,
	
	input      [31:0] DMA_DI,
	output     [31:0] DMA_DO,
	output            DMA_WE,
	output reg        DMA_REQ,
	input             DMA_ACK,
	output            DMA_RUN,
	output            DMA_LAST,
	input             DMA_END,
	
	output            IRQ,
	output DecInst_t  DBG_DECI,
	output     [47:0] DBG_Q,
	output     [47:0] DBG_AC,
	output     [47:0] DBG_P,
	output reg        HOOK1,
	output reg        HOOK2
);
	
	import SCUDSP_PKG::*;

	//Registers
	ALUReg_t   AC;
	ALUReg_t   P;
	bit [31:0] RX;
	bit [31:0] RY;
	bit  [7:0] PC;
	bit [11:0] LOP;
	bit  [7:0] TOP;
	bit  [5:0] CT0;
	bit  [5:0] CT1;
	bit  [5:0] CT2;
	bit  [5:0] CT3;
	bit  [7:0] TN0;
	bit        T0;
	bit        EX;
	bit        EP; 
	bit        PR;
	bit        ES;
	bit        LE;
	bit        E;
	bit        S;
	bit        Z;
	bit        C;
	bit        V;
	
	bit        LPS_EXE;
	bit        PAUSED;
	DMAInst_t  DMAI;

	bit  [5:0] DATA_RAM_ADDR [4];
	bit        DATA_RAM_WE [4];
	bit [31:0] DATA_RAM_Q [4];
	
	bit  [7:0] PRG_RAM_ADDR;
	bit        PRG_RAM_WE;
	bit [31:0] PRG_RAM_Q;
	
	bit  [7:0] DATA_TRANS_ADDR;
	bit        DATA_TRANS_WE;
	bit        DATA_TRANS_RE;
	bit        PRG_TRANS_WE;
	
	wire DMA_EN = T0 && DMA_ACK;
	wire RUN = (EX || ES) && ~EP && ~PAUSED;

	
	reg [31:0] IC;
	DecInst_t DECI;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			IC <= '0;
		end else if (!RES_N) begin
			IC <= '0;
		end else begin
			if (CE) begin
				if (RUN) begin
					IC <= PRG_RAM_Q;
				end
				if (DMAI.PRGW && DECI.D1BUS.PCW && T0) begin
					IC <= '0;
				end
			end
		
			if (CE_R) begin
				if (A == 2'b00 && WE && DI[15]) begin
					if (!EX) IC <= '0;
				end
			end
		end
	end
	
	wire COND = IC[24] ? ((IC[22]&T0) | (IC[21]&C) | (IC[20]&S) | (IC[19]&Z)) : ((~IC[22]|~T0) & (~IC[21]|~C) & (~IC[20]|~S) & (~IC[19]|~Z));
	assign DECI = Decode(IC, COND);
	assign DBG_DECI = DECI;
	
	//ALU
	ALUReg_t   ALU_Q;
	bit        ALU_C;
`ifdef SCU_DSP_LEAN
	//R6 SCU_DSP_LEAN: ADD, SUB and AD2 take their sums from one adder (the original has one adder each). Low part:
	//AC.L + (P.L, or ~P.L for SUB) + SUB = AC.L + P.L or AC.L - P.L (mod 2^32); its carry ALU_SL[32] is ADD's carry, and
	//inverted SUB's borrow (bit 32 of the original's {1'b0,AC.L} - {1'b0,P.L} is 1 exactly when AC.L < P.L, when
	//AC.L + ~P.L + 1 does not carry). High part: AC.H + P.H + the low carry; with SUB = 0 (AD2), {ALU_SH,ALU_SL[31:0]} is
	//the 49-bit sum {1'b0,AC} + {1'b0,P}. Only these three operations take the sums; for the others ALU_Q / ALU_C are
	//computed as before.
	wire        ALU_SUB = IC[29:26] == 4'b0101;
	wire [32:0] ALU_SL = {1'b0,AC.L} + {1'b0,P.L ^ {32{ALU_SUB}}} + {32'd0,ALU_SUB};
	wire [16:0] ALU_SH = {1'b0,AC.H} + {1'b0,P.H} + {16'd0,ALU_SL[32]};
`endif
	always_comb begin
		{ALU_C,ALU_Q} = {1'b0,AC};
		case (IC[29:26])
			4'b0001: {ALU_C,ALU_Q.L} = {1'b0,AC.L} & {1'b0,P.L};
			4'b0010: {ALU_C,ALU_Q.L} = {1'b0,AC.L} | {1'b0,P.L};
			4'b0011: {ALU_C,ALU_Q.L} = {1'b0,AC.L} ^ {1'b0,P.L};
`ifdef SCU_DSP_LEAN
			4'b0100,
			4'b0101: {ALU_C,ALU_Q.L} = {ALU_SL[32] ^ ALU_SUB,ALU_SL[31:0]};
			4'b0110: {ALU_C,ALU_Q  } = {ALU_SH,ALU_SL[31:0]};
`else
			4'b0100: {ALU_C,ALU_Q.L} = {1'b0,AC.L} + {1'b0,P.L};
			4'b0101: {ALU_C,ALU_Q.L} = {1'b0,AC.L} - {1'b0,P.L};
			4'b0110: {ALU_C,ALU_Q  } = {1'b0,AC  } + {1'b0,P  };
`endif
			4'b1000: {ALU_Q.L,ALU_C} = {AC.L[31],AC.L};
			4'b1001: {ALU_Q.L,ALU_C} = {AC.L[0],AC.L};
			4'b1010: {ALU_C,ALU_Q.L} = {AC.L,1'b0};
			4'b1011: {ALU_C,ALU_Q.L} = {AC.L,AC.L[31]};
			4'b1111: {ALU_C,ALU_Q.L} = {AC.L[24:0],AC.L[31:24]};
			default: ;
		endcase
	end
	
	assign DBG_Q = ALU_Q;
	assign DBG_AC = AC;
	assign DBG_P = P;
	
	always @(posedge CLK or negedge RST_N) begin
		bit S31, S47, ZL, ZH;
		bit OVF31, UNF31, OVF47;
		
		if (!RST_N) begin
			S <= 0;
			Z <= 0;
			C <= 0;
			V <= 0;
		end else if (!RES_N) begin
			S <= 0;
			Z <= 0;
			C <= 0;
			V <= 0;
		end else begin
			if (RUN && CE) begin
				S31 = ALU_Q[31];
				S47 = ALU_Q[47];
				ZL = ~|ALU_Q.L;
				ZH = ~|ALU_Q.H;
				OVF31 = (~(AC[31] ^ P[31])) & (AC[31] ^ ALU_Q[31]);
				UNF31 = ( (AC[31] ^ P[31])) & (AC[31] ^ ALU_Q[31]);
				OVF47 = (~(AC[47] ^ P[47])) & (AC[47] ^ ALU_Q[47]);
				if (DECI.ALU) begin
					case (IC[29:26])
						4'b0001: begin S <= S31; Z <= ZL;    C <= ALU_C; end
						4'b0010: begin S <= S31; Z <= ZL;    C <= ALU_C; end
						4'b0011: begin S <= S31; Z <= ZL;    C <= ALU_C; end
						4'b0100: begin S <= S31; Z <= ZL;    C <= ALU_C; V <= V | OVF31; end
						4'b0101: begin S <= S31; Z <= ZL;    C <= ALU_C; V <= V | UNF31; end
						4'b0110: begin S <= S47; Z <= ZL&ZH; C <= ALU_C; V <= V | OVF47; end
						4'b1000: begin S <= S31; Z <= ZL;    C <= ALU_C; end
						4'b1001: begin S <= S31; Z <= ZL;    C <= ALU_C; end
						4'b1010: begin S <= S31; Z <= ZL;    C <= ALU_C; end
						4'b1011: begin S <= S31; Z <= ZL;    C <= ALU_C; end
						4'b1111: begin S <= S31; Z <= ZL;    C <= ALU_C; end
						default:;
					endcase
				end
			end
			
			if (A == 2'b00 && RE) begin
				V <= 0;
			end
		end
	end
	
	wire [47: 0] MUL = $signed(RX) * $signed(RY);


	//Data RAM read muxes shared between rising-edge and falling-edge users: XBUS and YBUS are used only on CE (a CE_R
	//clock), the CPU read of the data RAM (DO, loaded on RE) and D0BUSO (DMA_DO, which the SCU takes into its DMA buffer
	//only on CE_F) only on CE_F clocks, and CE_R and CE_F are never high together. So the X mux also serves DO and the Y
	//mux D0BUSO, picking the bank by CE_F.
	wire [31: 0] D0BUSI = DMA_DI;
	bit  [31: 0] D0BUSO;
	bit  [31: 0] D1BUS;
	bit  [31: 0] XBUS;
	bit  [31: 0] YBUS;
	wire [ 1: 0] XBUS_RAMS = CE_F ? DATA_TRANS_ADDR[7:6] : DECI.XBUS.RAMS;
	wire [ 1: 0] YBUS_RAMS = CE_F ? DMAI.RAMS : DECI.YBUS.RAMS;
	always_comb begin
		XBUS = DATA_RAM_Q[XBUS_RAMS];
		YBUS = DATA_RAM_Q[YBUS_RAMS];
		
`ifdef SCU_DSP_LEAN
		//R6 SCU_DSP_LEAN: while !RUN the D1 bus carries the CPU's data DI, and for a DMA instruction the instruction IC, so
		//that it can be the data RAMs' port A data (DATA_RAM_DA) and DSO as it is, without their two multiplexers. Every
		//D1 bus destination in the DSP (RX, P, CT0-3, LOP, TOP, PC, the DSP's data RAM writes) takes it only on a CE with
		//RUN. With RUN the bus is as before except for a DMA instruction, which has no D1 bus source or destination (the
		//bus was '1 and went nowhere) and now gives IC, which DSO gave for it. While !RUN port A is written only with
		//the CPU's DI, as before. So DATA_RAM_DA is the original's in every clock where port A writes (with RUN: a D1
		//bus write, never by a DMA instruction; without: a CPU write), and DSO in every clock where the SCU reads it
		//(DSP_RA0_SET / DSP_WA0_SET / DSP_DMA_SET = RA0W / WA0W / DMAW, which need RUN & CE); while !RUN, DSO is now DI
		//(read by nothing). The data RAM word is taken at bank IC[1:0], which is D1BUS.RAMS whenever RAMR is set
		//(operation instructions), and the bank TN_VAL reads (DMA.CNTS = IC[1:0]): one multiplexer for both.
		if (DECI.D1BUS.IMMS && RUN) begin
			D1BUS = ImmSext(IC, DECI.D1BUS.IMMT);
		end else if (DECI.D1BUS.ALUS && RUN) begin
			case (DECI.D1BUS.RAMS[0])
				1'b0: D1BUS = ALU_Q[47:16];//ALU HIGH
				2'b1: D1BUS = ALU_Q[31: 0];//ALU LOW
			endcase
		end else if (DECI.D1BUS.RAMR && RUN) begin
			D1BUS = DATA_RAM_Q[IC[1:0]];
		end else begin
			D1BUS = !RUN ? DI : DECI.DMA.ST ? IC : '1;
		end
`else
		if (DECI.D1BUS.IMMS) begin
			D1BUS = ImmSext(IC, DECI.D1BUS.IMMT);
		end else if (DECI.D1BUS.ALUS) begin
			case (DECI.D1BUS.RAMS[0])
				1'b0: D1BUS = ALU_Q[47:16];//ALU HIGH
				2'b1: D1BUS = ALU_Q[31: 0];//ALU LOW
			endcase
		end else if (DECI.D1BUS.RAMR) begin
			D1BUS = DATA_RAM_Q[DECI.D1BUS.RAMS];
		end else begin
			D1BUS = '1;
		end
`endif
		
		D0BUSO = YBUS;
	end
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			// synopsys translate_off
			RX <= '0;
			RY <= '0;
			AC <= '0;
			P <= '0;
			// synopsys translate_on
		end else if (!RES_N) begin
			RX <= '0;
			RY <= '0;
			AC <= '0;
			P <= '0;
		end else if (RUN && CE) begin
			//X set
			if (DECI.XBUS.RXW) begin
				RX <= XBUS;
			end else if (DECI.D1BUS.RXW) begin
				RX <= D1BUS;
			end
			
			//Y set
			if (DECI.YBUS.RYW) begin
				RY <= YBUS;
			end
			
			//AC set
			if (DECI.YBUS.ACW) begin
				case (DECI.YBUS.ACS)
					2'b01: AC <= '0;
					2'b10: AC <= ALU_Q;
					2'b11: AC <= {{16{YBUS[31]}},YBUS};
					default:;
				endcase
			end
			
			//P set
			if (DECI.XBUS.PW) begin
				if (DECI.XBUS.MULS) P <= MUL[47:0];
				else P <= {{16{XBUS[31]}},XBUS};
			end else if (DECI.D1BUS.PW) begin
				P <= {{16{D1BUS[31]}},D1BUS};
			end
		end
	end
	
	always @(posedge CLK or negedge RST_N) begin
		bit RX_CONFLICT;
		
		if (!RST_N) begin
			// synopsys translate_off
			CT0 <= '0;
			CT1 <= '0;
			CT2 <= '0;
			CT3 <= '0;
			// synopsys translate_on
		end else if (!RES_N) begin
			CT0 <= '0;
			CT1 <= '0;
			CT2 <= '0;
			CT3 <= '0;
		end else begin
			RX_CONFLICT = DECI.D1BUS.RXW & DECI.XBUS.RXW;
			if (RUN && CE) begin
				if (DECI.XBUS.CTI[0] || DECI.YBUS.CTI[0] || 
				   (DECI.D1BUS.CTI[0] && !DECI.D1BUS.DCTI[0] && !DECI.XBUS.CTI[0] && !DECI.YBUS.CTI[0] && !RX_CONFLICT) ||
				   (DECI.D1BUS.DCTI[0]                       && !(DECI.XBUS.RAMR && DECI.XBUS.RAMS == 2'd0) && !(DECI.YBUS.RAMR && DECI.YBUS.RAMS == 2'd0) && !(DECI.D1BUS.RAMR && DECI.D1BUS.RAMS == 2'd0) && !RX_CONFLICT) || 
					DECI.DMA.CTI[0]) 
					CT0 <= CT0 + 6'd1;
				if (DECI.D1BUS.CTW[0]) CT0 <= D1BUS[5:0];
				
				if (DECI.XBUS.CTI[1] || DECI.YBUS.CTI[1] || 
				   (DECI.D1BUS.CTI[1] && !DECI.D1BUS.DCTI[1] && !DECI.XBUS.CTI[1] && !DECI.YBUS.CTI[1] && !RX_CONFLICT) ||
				   (DECI.D1BUS.DCTI[1]                       && !(DECI.XBUS.RAMR && DECI.XBUS.RAMS == 2'd1) && !(DECI.YBUS.RAMR && DECI.YBUS.RAMS == 2'd1) && !(DECI.D1BUS.RAMR && DECI.D1BUS.RAMS == 2'd1) && !RX_CONFLICT) || 
					DECI.DMA.CTI[1]) 
					CT1 <= CT1 + 6'd1;
				if (DECI.D1BUS.CTW[1]) CT1 <= D1BUS[5:0];
				
				if (DECI.XBUS.CTI[2] || DECI.YBUS.CTI[2] || 
				   (DECI.D1BUS.CTI[2] && !DECI.D1BUS.DCTI[2] && !DECI.XBUS.CTI[2] && !DECI.YBUS.CTI[2] && !RX_CONFLICT) ||
				   (DECI.D1BUS.DCTI[2]                       && !(DECI.XBUS.RAMR && DECI.XBUS.RAMS == 2'd2) && !(DECI.YBUS.RAMR && DECI.YBUS.RAMS == 2'd2) && !(DECI.D1BUS.RAMR && DECI.D1BUS.RAMS == 2'd2) && !RX_CONFLICT) || 
					DECI.DMA.CTI[2]) 
					CT2 <= CT2 + 6'd1;
				if (DECI.D1BUS.CTW[2]) CT2 <= D1BUS[5:0];
				
				if (DECI.XBUS.CTI[3] || DECI.YBUS.CTI[3] || 
				   (DECI.D1BUS.CTI[3] && !DECI.D1BUS.DCTI[3] && !DECI.XBUS.CTI[3] && !DECI.YBUS.CTI[3] && !RX_CONFLICT) || 
				   (DECI.D1BUS.DCTI[3]                       && !(DECI.XBUS.RAMR && DECI.XBUS.RAMS == 2'd3) && !(DECI.YBUS.RAMR && DECI.YBUS.RAMS == 2'd3) && !(DECI.D1BUS.RAMR && DECI.D1BUS.RAMS == 2'd3) && !RX_CONFLICT) || 
					DECI.DMA.CTI[3]) 
					CT3 <= CT3 + 6'd1;
				if (DECI.D1BUS.CTW[3]) CT3 <= D1BUS[5:0];
			end
			
			if (DMA_EN && CE_R) begin
				if (DMAI.RAMW[0] || DMAI.RAMR[0]) CT0 <= CT0 + 6'd1;
				if (DMAI.RAMW[1] || DMAI.RAMR[1]) CT1 <= CT1 + 6'd1;
				if (DMAI.RAMW[2] || DMAI.RAMR[2]) CT2 <= CT2 + 6'd1;
				if (DMAI.RAMW[3] || DMAI.RAMR[3]) CT3 <= CT3 + 6'd1;
			end
		end
	end
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			// synopsys translate_off
			PC <= '0;
			LOP <= '0;
			TOP <= '0;
			LPS_EXE <= 0;
			// synopsys translate_on
		end else if (!RES_N) begin
			PC <= '0;
			LOP <= '0;
			TOP <= '0;
			LPS_EXE <= 0;
		end else begin
			if (RUN && CE) begin
				PC <= PC + 8'd1;
				if (DECI.CTL.LPS && LOP) begin
					LPS_EXE <= 1;
					PC <= PC;
				end
				
				if (DECI.CTL.LPS) begin
					if (LOP) begin
						LPS_EXE <= 1;
						PC <= PC;
					end
					LOP <= LOP - 12'd1;
				end
				else if (LPS_EXE) begin
					if (LOP) begin
						PC <= PC;
					end
					else begin
						LPS_EXE <= 0;
					end
					LOP <= LOP - 12'd1;
				end
				if (DECI.CTL.BTM) begin
					if (LOP) begin
						PC <= TOP;
					end
					LOP <= LOP - 12'd1;
				end
				
				if (DECI.D1BUS.LOPW) begin
					LOP <= D1BUS[11:0];
				end

				if (DECI.D1BUS.PCW) begin
					PC <= D1BUS[7:0];
					TOP <= PC;
				end
				if (DECI.JPCW) begin
					PC <= IC[7:0];
				end

				if (DECI.D1BUS.TOPW) begin
					TOP <= D1BUS[7:0];
				end
			end
			
			if (CE) begin
				if (DMA_END_PEND && DMAI.PRGW) begin
					PC <= TOP;
				end
			end
			
			if (CE_R) begin
				if (DMA_EN) begin
					if (DMAI.PRGW) begin
						PC <= PC + 8'd1;
					end
				end
				if (!EX) begin
					if (PRG_TRANS_WE) begin
						PC <= PC + 8'd1;
					end
					if (A == 2'b00 && WE && DI[15]) begin
						PC <= DI[7:0];
					end
				end
			end
		end
	end
	
`ifdef SCU_DSP_LEAN
	wire [ 7: 0] TN_VAL = DECI.DMA.CNTM ? DATA_RAM_Q[IC[1:0]][7:0] : IC[7:0];	//R6: IC[1:0] = DMA.CNTS (see D1BUS)
`else
	wire [ 7: 0] TN_VAL = DECI.DMA.CNTM ? DATA_RAM_Q[DECI.DMA.CNTS][7:0] : IC[7:0];
`endif
	wire [ 7: 0] TN0_NEXT = TN0 - 8'd1;
		bit       DMA_END_PEND;
	always @(posedge CLK or negedge RST_N) begin
		bit       DMA_END_OLD;
		
		if (!RST_N) begin
			TN0 <= '0;
			T0 <= 0;
			PAUSED <= 0;
			DMAI <= '0;
			DMA_REQ <= 0;
			DMA_END_PEND <= 0;
			
			HOOK1 <= 0;
			HOOK2 <= 0;
		end else if (!RES_N) begin
			TN0 <= '0;
			T0 <= 0;
			PAUSED <= 0;
			DMAI <= '0;
			DMA_REQ <= 0;
		end else begin
			if (CE) begin
				if (RUN) begin
					if (DECI.DMA.ST && !T0) begin
						T0 <= 1;
						TN0 <= TN_VAL;
						DMAI <= DECI.DMA;
						DMA_REQ <= 1;
					end
					if (DMAI.PRGW && DECI.D1BUS.PCW && T0) begin
						PAUSED <= 1;
					end
				end
				
				DMA_END_PEND <= 0;
				if (DMA_END_PEND) begin
					T0 <= 0;
					PAUSED <= 0;
					DMAI <= '0;
				end
			end
			
			if (CE_F) begin
				DMA_END_OLD <= DMA_END;
				if (!DMA_END && DMA_END_OLD) begin
					DMA_END_PEND <= 1;
				end
				
				if ((DECI.XBUS.RAMR && DECI.XBUS.RAMS == DMAI.RAMS) || 
				    (DECI.YBUS.RAMR && DECI.YBUS.RAMS == DMAI.RAMS) || 
					 (DECI.D1BUS.RAMR && DECI.D1BUS.RAMS == DMAI.RAMS) || 
					 DECI.D1BUS.RAMW[DMAI.RAMS] || DECI.D1BUS.CTW[DMAI.RAMS] ||
				    DECI.XBUS.CTI[DMAI.RAMS] || DECI.YBUS.CTI[DMAI.RAMS] || DECI.D1BUS.CTI[DMAI.RAMS] || 
					 DECI.DMA.ST || DECI.D1BUS.RA0W || DECI.D1BUS.WA0W) begin
					PAUSED <= T0;
				end
			end 
			if (CE_R) begin
				if (!EX) begin
					if (A == 2'b00 && WE && DI[15]) begin
						T0 <= 0;
						PAUSED <= 0;
						DMAI <= '0;
					end
				end
				if (DMA_EN) begin
					DMA_REQ <= 0;
					TN0 <= TN0_NEXT;
					if (TN0_NEXT != 8'd0) begin
						DMA_REQ <= 1;
					end
					
					if (D0BUSO[31:16] != 16'h0000 && D0BUSO[31:16] != 16'hFFFF && DMAI.RAMR[3] && DMAI.DIR) HOOK1 <= 1;
					if (DMA_DI[31:16] != 16'h0000 && DMA_DI[31:16] != 16'hFFFF && (DMAI.RAMW[1] || DMAI.RAMW[2]) && !DMAI.DIR) HOOK2 <= 1;
				end
			end
		end
	end
	
	assign DMA_DO = D0BUSO;
	assign DMA_WE = DMAI.DIR;
	assign DMA_RUN = T0;
	assign DMA_LAST = (TN0_NEXT == 8'd0);
	
`ifdef SCU_DSP_LEAN
	assign DSO = D1BUS;	//R6: IC for a DMA instruction (see D1BUS)
`else
	assign DSO = DECI.DMA.ST ? IC : D1BUS;
`endif
	assign RA0W = DECI.D1BUS.RA0W & RUN & CE;
	assign WA0W = DECI.D1BUS.WA0W & RUN & CE;
	assign DMAW = DECI.DMA.ST & RUN & CE;
	
	//DATA RAM
	//Each data RAM is written by DSP DMA through its port B (DATA_RAM_DMAW: the write enable's DMA term) and by the DSP
	//(D1 bus) and the CPU through its port A, whose data is one multiplexer for all four (see DSP_DATA_RAM)
	wire DATA_TRANS_CS[4] = '{DATA_TRANS_ADDR[7:6] == 2'b00,DATA_TRANS_ADDR[7:6] == 2'b01,DATA_TRANS_ADDR[7:6] == 2'b10,DATA_TRANS_ADDR[7:6] == 2'b11};
`ifdef SCU_DSP_LEAN
	wire [31: 0] DATA_RAM_DA = D1BUS;	//R6: DI while !RUN (see D1BUS)
`else
	wire [31: 0] DATA_RAM_DA = RUN ? D1BUS : DI;
`endif
	wire [ 3: 0] DATA_RAM_DMAW = {4{T0}} & DMAI.RAMW;
	
	assign DATA_RAM_ADDR[0] = RUN || T0 ? CT0 : DATA_TRANS_ADDR[5:0];
	assign DATA_RAM_WE[0] = T0 && DMAI.RAMW[0] ? DMA_EN & CE_R : RUN ? DECI.D1BUS.RAMW[0] & CE : DATA_TRANS_WE && DATA_TRANS_CS[0] & CE_R;
	DSP_DATA_RAM #(6,32) DATA_RAM0(CLK, DATA_RAM_ADDR[0], DATA_RAM_DA, DATA_RAM_WE[0] & ~DATA_RAM_DMAW[0], D0BUSI, DATA_RAM_WE[0] & DATA_RAM_DMAW[0], DATA_RAM_Q[0]);
	
	assign DATA_RAM_ADDR[1] = RUN || T0 ? CT1 : DATA_TRANS_ADDR[5:0];
	assign DATA_RAM_WE[1] = T0 && DMAI.RAMW[1] ? DMA_EN & CE_R : RUN ? DECI.D1BUS.RAMW[1] & CE : DATA_TRANS_WE && DATA_TRANS_CS[1] & CE_R ;
	DSP_DATA_RAM #(6,32) DATA_RAM1(CLK, DATA_RAM_ADDR[1], DATA_RAM_DA, DATA_RAM_WE[1] & ~DATA_RAM_DMAW[1], D0BUSI, DATA_RAM_WE[1] & DATA_RAM_DMAW[1], DATA_RAM_Q[1]);
	
	assign DATA_RAM_ADDR[2] = RUN || T0 ? CT2 : DATA_TRANS_ADDR[5:0];
	assign DATA_RAM_WE[2] = T0 && DMAI.RAMW[2] ? DMA_EN & CE_R : RUN ? DECI.D1BUS.RAMW[2] & CE : DATA_TRANS_WE && DATA_TRANS_CS[2] & CE_R ;
	DSP_DATA_RAM #(6,32) DATA_RAM2(CLK, DATA_RAM_ADDR[2], DATA_RAM_DA, DATA_RAM_WE[2] & ~DATA_RAM_DMAW[2], D0BUSI, DATA_RAM_WE[2] & DATA_RAM_DMAW[2], DATA_RAM_Q[2]);
	
	assign DATA_RAM_ADDR[3] = RUN || T0 ? CT3 : DATA_TRANS_ADDR[5:0];
	assign DATA_RAM_WE[3] = T0 && DMAI.RAMW[3] ? DMA_EN & CE_R : RUN ? DECI.D1BUS.RAMW[3] & CE : DATA_TRANS_WE && DATA_TRANS_CS[3] & CE_R ;
	DSP_DATA_RAM #(6,32) DATA_RAM3(CLK, DATA_RAM_ADDR[3], DATA_RAM_DA, DATA_RAM_WE[3] & ~DATA_RAM_DMAW[3], D0BUSI, DATA_RAM_WE[3] & DATA_RAM_DMAW[3], DATA_RAM_Q[3]);
	
	//Control port
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			EX <= 0;
			EP <= 0; 
			PR <= 0;
			ES <= 0;
			LE <= 0;
			E <= 0;
			PRG_TRANS_WE <= 0;
			DATA_TRANS_ADDR <= '0;
			DATA_TRANS_WE <= 0;
			DATA_TRANS_RE <= 0;
		end else if (!RES_N) begin
			EX <= 0;
			EP <= 0; 
			PR <= 0;
			ES <= 0;
			LE <= 0;
			E <= 0;
			PRG_TRANS_WE <= 0;
			DATA_TRANS_ADDR <= '0;
			DATA_TRANS_WE <= 0;
			DATA_TRANS_RE <= 0;
		end else begin
			if (CE_R) begin
				PRG_TRANS_WE <= 0;
				DATA_TRANS_WE <= 0;
				if (DATA_TRANS_WE) DATA_TRANS_ADDR <= DATA_TRANS_ADDR + 8'd1;
				
				if (WE) begin
					case (A)
						2'b00: begin
							if (DI[25]) begin
								if (!EP) begin
									EP <= 1; 
								end
							end else	if (DI[26]) begin
								if (EP) begin
									EP <= 0; 
								end
							end else begin
								if (!EX && DI[16]) begin
									EX <= 1;
								end else if (EX && !DI[16]) begin
									EX <= 0;
								end
								
								if (!EX && DI[17]) begin
									ES <= 1;
								end
							end
							
							if (DI[15]) begin
								LE <= 1;
							end
						end
						2'b01: begin
							PRG_TRANS_WE <= 1;
						end
						2'b10: begin
							DATA_TRANS_ADDR <= DI[7:0];
						end
						2'b11: begin
							DATA_TRANS_WE <= 1;
						end
						default:;
					endcase
				end
			end 
			/*if (CE_F)*/ begin
				DATA_TRANS_RE <= 0;
				if (DATA_TRANS_RE) DATA_TRANS_ADDR <= DATA_TRANS_ADDR + 8'd1;
				
				if (RE) begin
					case (A)
						2'b00: DO <= {8'h00,T0,S,Z,C,V,E,1'b0,EX&~EP,8'h00,PC};
						2'b01: DO <= '0;
						2'b10: DO <= '0;
						2'b11: begin
							DO <= !EX || EP ? XBUS : '1;
							DATA_TRANS_RE <= 1;
						end
						default: DO <= '0;
					endcase
					if (A == 2'b00 && E) begin
						E <= 0;
					end
				end
			end
			
			if (RUN && CE) begin
				if (ES) ES <= 0;
				
				if (DECI.CTL.END) begin
					EX <= 0;
					if (DECI.CTL.EI) E <= 1;
				end
			end
		end
	end
	
	assign IRQ = E;
	
	//PRG RAM
	//written by the CPU through port A (DI) and by DSP DMA through port B (D0BUSI), see DSP_PRG_RAM
	assign PRG_RAM_ADDR = PC;
	assign PRG_RAM_WE = T0 ? DMAI.PRGW & DMA_EN & CE_R : !RUN & PRG_TRANS_WE & CE_R;
	DSP_PRG_RAM #(8,32," ","prg.txt") PRG_RAM(CLK, PRG_RAM_ADDR, DI, PRG_RAM_WE & ~T0, D0BUSI, PRG_RAM_WE & T0, PRG_RAM_Q);

	
endmodule
