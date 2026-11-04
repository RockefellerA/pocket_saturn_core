// synopsys translate_off
`define SIM
// synopsys translate_on

module HMCS400_CORE 
(
	input              CLK,
	input              RST_N,
	input              CE,
	
	input              RESET,
	input      [ 3: 0] CYC,
	input              EXEC,
	
	input              INT_PEND,
	input      [ 2: 0] INT_VEC,
	output             INT_ACP,
	output             INT_RET,
	
	output     [13: 0] ROM_A,
	input      [ 9: 0] ROM_DI,
	
	output     [ 9: 0] BUS_A,
	input      [ 3: 0] BUS_DI,
	output     [ 3: 0] BUS_DO,
	output             BUS_WE,
	output             BUS_RE,
	
	output             IO_WR,
	output             IO_RD,
	output             IO_P,
	
	output             STOP_REQ,
	output             SBY_REQ
);

	import HMCS400_PKG::*;
	
	bit  [13: 0] PC;
	bit  [ 9: 0] IC,IW;
	bit  [ 3: 0] A,B;
	bit  [ 3: 0] X,Y;
	bit  [ 1: 0] W;
	bit  [ 3: 0] SPX,SPY;
	bit          CA,ST;
	bit  [ 5: 0] SP;
	
	DecInstr_t   DECI;
	bit  [ 1: 0] STATE;
	bit          INT_EXP;
	bit  [ 3: 0] ALUA,ALUB,ALUR;
	bit          ALUC,ALUZ;
		
	wire [13: 0] PC_NEXT = PC + 14'd1;
	

	bit  [ 9: 0] BUS_ADDR;
	bit  [ 3: 0] BUS_DATA;
	always_comb begin		
		case (DECI.MA)
			MA_MR:   BUS_ADDR = {6'h04,IC[3:0]};
			MA_ADR:  BUS_ADDR = !STATE ? {W,X,Y} : IW;
			//MA_STK1,
			//MA_STK2,
			default: BUS_ADDR = {4'b1111,SP};
		endcase
		
		case (DECI.MD)
			MD_A:    BUS_DATA = A;
			MD_B:    BUS_DATA = B;
			MD_I:    BUS_DATA = IC[3:0];
			MD_ALU:  BUS_DATA = ALUR;
			default: BUS_DATA = '0;
		endcase
	end
	
	wire [15: 0] STACK_DATA = DECI.MA == MA_STK1 ? {ST,PC[13:7],CA,PC[6:0]} :
                             DECI.MA == MA_STK2 ? {ST,PC_NEXT[13:7],CA,PC_NEXT[6:0]} : 
									                       {4{BUS_DATA}};
	wire [ 3: 0] STACK_WE = DECI.MA == MA_STK1 || DECI.MA == MA_STK2 ? {4{BUS_ADDR[9:6] == 4'b1111 & DECI.MW}} : 
	                                                                   {4{BUS_ADDR[9:6] == 4'b1111 & DECI.MW}} & {~BUS_ADDR[1]&~BUS_ADDR[0],~BUS_ADDR[1]&BUS_ADDR[0],BUS_ADDR[1]&~BUS_ADDR[0],BUS_ADDR[1]&BUS_ADDR[0]};
	bit  [15: 0] STACK_Q;
	HMCS400_STACK STACK(CLK, BUS_ADDR[5:2], STACK_DATA, (STACK_WE & {4{EXEC & CYC[3] & CE}}), STACK_Q);
	
	bit  [ 3: 0] RAM_Q;
	always_comb begin		
		if (BUS_ADDR[9:6] == 4'b1111)
			case (BUS_ADDR[1:0])
				2'h0: RAM_Q <= STACK_Q[15:12];
				2'h1: RAM_Q <= STACK_Q[11: 8];
				2'h2: RAM_Q <= STACK_Q[ 7: 4];
				2'h3: RAM_Q <= STACK_Q[ 3: 0];
			endcase
		else
			RAM_Q <= BUS_DI;
	end
	
	//IC, STATE and INT_EXP: the decoder's inputs (with ST and DA_COND). Their next values also address the decoder ROM.
	bit  [ 9: 0] IC_N;
	bit  [ 1: 0] STATE_N;
	bit          INT_EXP_N;
	always_comb begin
		IC_N = IC;
		STATE_N = STATE;
		INT_EXP_N = INT_EXP;
		if (RESET) begin
			IC_N = 10'h000;
			STATE_N = '0;
			INT_EXP_N = 0;
		end
		else if (EXEC & CE) begin
			if (CYC[1]) begin
				if (STATE == 2'd0) begin
					IC_N = ROM_DI;
				end
			end
			if (CYC[3]) begin
				STATE_N = STATE + 2'd1;
				if (DECI.LST) begin
					STATE_N = 2'd0;
					if (INT_PEND && !INT_EXP) begin
						INT_EXP_N = 1; 
					end
					else begin
						INT_EXP_N = '0;
					end
				end
			end
		end
	end
	always @(posedge CLK or negedge RST_N) begin		
		if (!RST_N) begin
			IC <= 10'h000;
			STATE <= '0;
			INT_EXP <= 0;
		end
		else begin
			IC <= IC_N;
			STATE <= STATE_N;
			INT_EXP <= INT_EXP_N;
		end
	end
	
	always @(posedge CLK or negedge RST_N) begin		
		bit  [ 2: 0] VEC;
	
		if (!RST_N) begin
			IW <= '0;
			PC <= '0;
			SP <= '1;
		end
		else if (RESET) begin
			IW <= '0;
			PC <= '0;
			SP <= '1;
		end
		else if (EXEC & CE) begin
			if (CYC[1]) begin
				if (STATE != 2'd0) begin
					IW <= ROM_DI;
				end
			end
			if (CYC[3]) begin
				if (INT_EXP && STATE == 2'd0) begin
					VEC <= INT_VEC;
				end
				 
				case (DECI.PCU)
					PCU_BR:  PC <= {PC_NEXT[13:8],IC[7:0]};
					PCU_BRL: PC <= {IC[3:0],IW};
					PCU_ZP:  PC <= {8'b00000000,IC[5:0]};
					PCU_TBR: PC <= {2'b00,IC[3:0],B,A};
					PCU_NU:  PC <= PC;
					PCU_RTN: PC <= {STACK_Q[14:8],STACK_Q[6:0]};
					PCU_INT: PC <= {10'b0000000000,VEC,1'b0};
					default: PC <= PC_NEXT;
				endcase
				
				if (DECI.SPD) begin
					SP <= SP - 6'd4;
				end
				if (DECI.SPI) begin
					SP <= SP + 6'd4;
				end
			end
		end
	end
	assign INT_ACP = (INT_EXP && STATE == 2'd0);
	assign INT_RET = (DECI.PCU == PCU_RTN && IC[0]);
	
	wire DA_COND = (A >= 4'd10 || CA == ~IC[3]);
	
	//Decoder as a ROM: see HMCS400_DEC
	bit  [44: 0] DEC_Q;
	HMCS400_DEC DEC(CLK, IC_N, STATE_N, INT_EXP_N, ST, DA_COND, DEC_Q);
	assign DECI = DecInstr_t'(DEC_Q);

	bit          ADD_LE;
	always_comb begin		
		bit          DA_COND;
		bit  [ 3: 0] ADD_RES,LOG_RES,BIT_RES;
		bit          ADD_C,LOG_C;
		
		case (DECI.ALUAS)
			AAS_A:    ALUA = A;
			AAS_B:    ALUA = B;
			AAS_Y:    ALUA = Y;
			AAS_M:    ALUA = RAM_Q;
			AAS_I:    ALUA = IC[3:0];
			AAS_ZERO: ALUA = 4'h0;
			AAS_SPX:  ALUA = SPX;
			AAS_SPY:  ALUA = SPY;
			default:  ALUA = 4'h0;
		endcase
		
		case (DECI.ALUBS)
			ABS_A:    ALUB = A;
			ABS_B:    ALUB = B;
			ABS_M:    ALUB = RAM_Q;
			ABS_I:    ALUB = IC[3:0];
			ABS_ONE:  ALUB = 4'h1;
			ABS_ZERO: ALUB = 4'h0;
			ABS_BIT:  ALUB = (4'h1<<IC[1:0]);
			default:  ALUB = 4'h0;
		endcase
		
		case (DECI.ALUCD[1:0])
			2'b00: {ADD_C,ADD_RES} = {1'b0,ALUA} + {1'b0,ALUB};
			2'b01: {ADD_C,ADD_RES} = {1'b0,ALUA} - {1'b0,ALUB};
			2'b10: {ADD_C,ADD_RES} = {1'b0,ALUA} + {1'b0,ALUB} + {4'b0000,CA};
			2'b11: {ADD_C,ADD_RES} = {1'b0,ALUA} - {1'b0,ALUB} - {4'b0000,~CA};
		endcase
		ADD_LE = (ALUA <= ALUB);
		
		casex (DECI.ALUCD[2:0])
			3'b000: {LOG_C,LOG_RES} = {CA,ALUA} | {1'b0,ALUB};
			3'b001: {LOG_C,LOG_RES} = {CA,ALUA} ^ {1'b0,ALUB};
			3'b010: {LOG_C,LOG_RES} = {CA,ALUA};
			3'b011: {LOG_C,LOG_RES} = {CA,ALUA} & {1'b0,ALUB};
			3'b1x0: {LOG_C,LOG_RES} = {ALUA[0],CA,ALUA[3:1]};
			3'b1x1: {LOG_C,LOG_RES} = {ALUA[3:0],CA};
		endcase
		
		case (DECI.ALUCD[1:0])
			2'b00: BIT_RES = ALUA;
			2'b01: BIT_RES = ALUA | ALUB;
			2'b10: BIT_RES = ALUA & ~ALUB;
			2'b11: BIT_RES = ALUA & ALUB;
		endcase
		
		case (DECI.ALUOP)
			ALU_ADD: {ALUZ,ALUC,ALUR} = {~|ADD_RES,ADD_C^DECI.ALUCD[0],ADD_RES};
			ALU_LOG: {ALUZ,ALUC,ALUR} = {~|LOG_RES,LOG_C,LOG_RES};
			ALU_BIT: {ALUZ,ALUC,ALUR} = {~|BIT_RES,1'b0, BIT_RES};
			ALU_A:   {ALUZ,ALUC,ALUR} = {1'b0,     CA,   ALUA};
			ALU_B:   {ALUZ,ALUC,ALUR} = {1'b0,     CA,   ALUB};
			default: {ALUZ,ALUC,ALUR} = '0;
		endcase
	end
	
	//Registers
	always @(posedge CLK or negedge RST_N) begin				
		if (!RST_N) begin
			A <= '0;
			B <= '0;
			X <= '0;
			Y <= '0;
			W <= '0;
			SPX <= '0;
			SPY <= '0;
		end
		else if (RESET) begin
			
		end
		else if (EXEC & CE) begin
			if (CYC[3]) begin
				if (DECI.AW) A <= ALUR;
				if (DECI.BW) B <= ALUR;
				if (DECI.PI && IW[8]) {B,A} <= IW[7:0];
				if (DECI.XW) X <= DECI.XE ? SPX : ALUR;
				if (DECI.YW) Y <= DECI.YE ? SPY : ALUR;
				if (DECI.WW) W <= ALUR[1:0];
				if (DECI.XE) SPX <= X;
				if (DECI.YE) SPY <= Y;
				case (DECI.CAU) 
					CAU_ALU: CA <= ALUC;
					CAU_ONE: CA <= 1;
					CAU_ZERO: CA <= 0;
					CAU_RTN: CA <= STACK_Q[7];
				endcase
			end
		end
	end
	
	//ST
	always @(posedge CLK or negedge RST_N) begin				
		if (!RST_N) begin
			ST <= 1;
		end
		else if (RESET) begin
			ST <= 1;
		end
		else if (EXEC & CE) begin
			if (CYC[3]) begin
				case (DECI.STU) 
					STU_NZ:  ST <= ~ALUZ;
					STU_C:   ST <= ALUC;
					STU_NB:  ST <= ADD_LE;
					STU_CA:  ST <= CA;
					STU_SET: ST <= 1;
					STU_RTN: ST <= STACK_Q[15];
					STU_PD:  ST <= ALUR[0];
				endcase
			end
		end
	end
	
	assign ROM_A = DECI.PI ? {2'b00,IC[3:0],B,A} : PC;
	
	assign BUS_A = BUS_ADDR;
	assign BUS_DO = BUS_DATA;
	assign BUS_WE = DECI.MW;
	assign BUS_RE = DECI.MR;
	
	assign IO_WR = DECI.IOW;
	assign IO_RD = DECI.IOR;
	assign IO_P = DECI.IOP;
	
	assign STOP_REQ = DECI.STOP;
	assign SBY_REQ = DECI.SBY;
	
endmodule

//Decoder as a ROM (2K x 45 M10K, hmcs400_dec.hex, generated from IDecode() by s4/sys/smpcdec/gen_rom.py, which also
//checks it). The ROM address is registered on every clock from the next values of IC, STATE and INT_EXP, so in every
//clock the ROM row is that of the current IC, STATE and INT_EXP, as IDecode() was. Address {IC,STATE[0]}; the interrupt
//sequence (IC ignored) and STATE 2 (RTN / RTNI only) use the rows of IC 3FC-3FE with STATE 1, which never occur (BR ends
//in state 0). The rows are decoded with ST = 1 and DA_COND = 1; two flags patch the fields that depend on them: F_ST
//(BR, CALL/BRL state 1, CAL state 0): with ST = 0, PCU, MW and SPD are 0 and LST is 1; F_DA (DAA, DAS): with DA_COND = 0,
//AW and CAU are 0. IWR and ILI are not used by the core and are 0. DECI is HMCS400_PKG::DecInstr_t as bits.
//The ROM must be regenerated (gen_rom.py) if IDecode() changes.
module HMCS400_DEC 
(
	input              CLK,
	input      [ 9: 0] IC_N,
	input      [ 1: 0] STATE_N,
	input              INT_EXP_N,
	input              ST,
	input              DA_COND,
	output     [44: 0] DECI
);

	typedef struct packed {
		bit [ 2: 0] ALUAS;
		bit [ 2: 0] ALUBS;
		bit [ 2: 0] ALUOP;
		bit [ 2: 0] ALUCD;
		bit         AW, BW, XW, YW, XE, YE, WW;
		bit [ 2: 0] CAU;
		bit [ 2: 0] STU;
		bit [ 1: 0] MA;
		bit [ 1: 0] MD;
		bit         MR, MW;
		bit [ 2: 0] PCU;
		bit         SPI, SPD, PI, SBY, STOP, IOW, IOR, IOP, LST;
		bit         F_ST, F_DA;
	} DecRow_t;
	
	bit  [10: 0] DA;
	always_comb begin
		if (INT_EXP_N)     DA = {9'h1FE,STATE_N[0],1'b1};	//3FC/3FD, STATE 1: interrupt sequence, STATE 0/1
		else if (STATE_N[1]) DA = {10'h3FE,1'b1};		//3FE, STATE 1: STATE 2 (RTN, RTNI)
		else               DA = {IC_N,STATE_N[0]};
	end
	
	(* romstyle = "M10K" *) bit [44: 0] DEC_ROM[2048];
	initial begin
		$readmemh("hmcs400_dec.hex", DEC_ROM);
	end
	DecRow_t     R;
	always_ff @(posedge CLK) begin
		R <= DEC_ROM[DA];
	end
	
	wire         NST = R.F_ST & ~ST;
	wire         NDA = R.F_DA & ~DA_COND;
	assign DECI = {R.ALUAS, R.ALUBS, R.ALUOP, R.ALUCD, R.AW & ~NDA, R.BW, R.XW, R.YW, R.XE, R.YE, R.WW,
	               R.CAU & {3{~NDA}}, R.STU, R.MA, R.MD, R.MR, R.MW & ~NST, R.PCU & {3{~NST}}, R.SPI, R.SPD & ~NST,
	               R.PI, R.SBY, R.STOP, 1'b0, R.IOW, R.IOR, R.IOP, R.LST | NST, 1'b0};

endmodule
