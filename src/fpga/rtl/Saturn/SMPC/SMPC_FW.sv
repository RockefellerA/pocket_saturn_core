// SMPC with its MCU in firmware (`ifdef SMPC_FW, needs CD_HLE): the HMCS400, its ROM and its peripherals (timers,
// interrupt controller, the MCU-only port logic) are gone; the CD block HLE's PicoRV32 runs the SMPC ROM translated to
// C (fw/cdb smpc_*.c: every instruction, at the CE edge the MCU would do it) and reaches this module through the I/O
// words 0x80-0xFF of CDB_HLE (FW_*).
//
// What stays as SMPC.sv has it, clock for clock: the SH-2 side (IREG0-6 and COMREG written into the IREG RAM, OREG
// read from the OREG RAM, SR, SF, PDR1/2, DDR1/2, IOSEL, EXLE, the read data and IO_BUF), the direct-mode port path
// and EXL_N. The MCU's outputs (D pins, the R port latches and directions in SMPC mode, CDRES_N, OREG, SR, SF clear)
// are registers the firmware writes.
//
// For the firmware: the SMPC_CE edge count since RST_N (CE #1 = MRES_N's edge, as the MCU counts), the inputs, and
// the CE edges of the last VBLANK change and the last COMREG write (14 bits, the firmware polls more often than every
// 4 ms), so its MCU sees them at the edge the real MCU would.
//
// Firmware words (FW_A; reads decode FW_A[1:0] only):
//   R  0 TIME   {EXT_RTC[47:40], CE edges since RST_N [23:0]}
//   R  1 EVT    {EXT_RTC[64], 0, COMREG writes (toggle), CE edge from which the last one is visible - 1 [13:0],
//                IRQV_N, CE edge of the last IRQV_N change [13:0]}; read it before TIME (its edges are then <= TIME)
//   R  2 INP    {IREG[FW_A[4:2]] (7 = COMREG), EXT_RTC[36:32], D3, R5, PIOB_I, PIOA_I}  (words 2, 6, .., 30)
//   R  3 RTC    EXT_RTC[31:0]
//   W 16 DPINS  {CDRES_N, D10..D4, D0} (D = D_O | ~D_D as SMPC.sv drives the pins; CDRES_N = R72)
//   W 17 PORTA  {SMPC-mode direction [14:8] = {DCR2[3:1], DCR1}, output [6:0] = {R2_O[3:1], R1_O}}
//   W 18 PORTB  the same for R4 / R3
//   W 19 SR     W 20 SF clear     W 21 OREG {index (OREG RAM word, as SMPC.sv's BUS_A[5:1]) [12:8], byte [7:0]}
// Inputs SMPC.sv reads that Saturn.sv ties to constants are not read (the firmware has D1 = 1, D2 = 0, D13 = 1,
// R60 = 0, R61 = 1, R62 = R63 = R70 = R71 = 0); the R6 / R73 outputs are left at SMPC.sv's reset values.
module SMPC_FW
(
	input              CLK,
	input              RST_N,
	input              EN,

	input              CE,
	input              CE32K,          // not used: the firmware counts CE32K from CE
	input              RESET_N,

	input      [ 6: 1] A,
	input      [ 7: 0] DBI,
	output reg [ 7: 0] DBO,
	input              CS_N,
	input              RW_N,

	output             D0,
	input              D1,
	input              D2,
	input              D3,
	output             D4,
	output             D5,
	output             D6,
	output             D7,
	output             D8,
	output             D9,
	output             D10,
	input              D13_INT0,

	input              R01_INT2,

	output     [ 6: 0] PIOA_O,
	input      [ 6: 0] PIOA_I,
	output     [ 6: 0] PIOA_D,

	output     [ 6: 0] PIOB_O,
	input      [ 6: 0] PIOB_I,
	output     [ 6: 0] PIOB_D,

	input      [ 3: 0] R5,

	output             R60_D,
	output             R60_O,
	input              R60_I,

	output             R61_D,
	output             R61_O,
	input              R61_I,

	input              R62_I,
	input              R63_I,

	input              R70_I,
	input              R71_I,
	output             R72_O,
	output             R73_O,

	output             EXL_N,

	input      [64: 0] EXT_RTC,

	input      [ 4: 0] FW_A,
	input              FW_WE,
	input      [31: 0] FW_WD,
	output     [31: 0] FW_RD
);

	//SMPC interface registers (SMPC.sv)
	bit  [ 7: 0] SR;
	bit          SF;
	bit  [ 6: 0] PDR1_O,PDR2_O;
	bit  [ 6: 0] DDR1,DDR2;
	bit          IOSEL1,IOSEL2;
	bit          EXLE1,EXLE2;

	//the MCU's outputs, from the firmware
	bit  [ 7: 0] DPIN;                                   // {D10..D4, D0}
	bit          CDRES;                                  // R72_O
	bit  [13: 0] PA_R,PB_R;                              // {direction, output} in SMPC mode

	//for the firmware
	bit  [23: 0] CE_CNT;
	bit  [13: 0] VBL_TS,COM_TS;
	bit          VBL_OLD,COM_TGL,COM_WR;

	wire FW_WR_DPIN = FW_WE && FW_A == 5'd16;
	wire FW_WR_PA   = FW_WE && FW_A == 5'd17;
	wire FW_WR_PB   = FW_WE && FW_A == 5'd18;
	wire FW_WR_SR   = FW_WE && FW_A == 5'd19;
	wire FW_WR_SF   = FW_WE && FW_A == 5'd20;
	wire FW_WR_OREG = FW_WE && FW_A == 5'd21;

	wire IREG_SEL = ({A,1'b1} <= 7'h0D || {A,1'b1} == 7'h1F);
	bit  [ 7: 0] IREG_Q;
	SMPC_RAM #(3,8,1) IREG(CLK, A[3:1], DBI, IREG_SEL & ~RW_N & RW_N_OLD & ~CS_N & EN, FW_A[4:2], IREG_Q);

	bit  [ 7: 0] OREG_Q;
	SMPC_RAM #(5,8,1) OREG(CLK, FW_WD[12:8], FW_WD[7:0], FW_WR_OREG & EN, A[5:1], OREG_Q);

	bit         RW_N_OLD;
	always @(posedge CLK or negedge RST_N) begin
		bit         CS_N_OLD;
		bit [ 7: 0] IO_BUF;

		if (!RST_N) begin
			SF <= 0;
			{PDR1_O,PDR2_O} <= '0;
			{DDR1,DDR2} <= '0;
			{IOSEL2,IOSEL1} <= '0;
			{EXLE2,EXLE1} <= '0;
			{COM_TGL,COM_WR} <= '0;
		end
		else if (!RESET_N) begin

		end
		else if (EN) begin
			//Inner access (the firmware)
			if (FW_WR_SR) SR <= FW_WD[7:0];
			if (FW_WR_SF) SF <= 0;

			//Extern access
			RW_N_OLD <= RW_N;
			CS_N_OLD <= CS_N;
			COM_WR <= 0;
			if (!RW_N && RW_N_OLD && !CS_N) begin
				case ({A,1'b1})
					7'h1F: COM_WR <= 1;
					7'h63: SF <= 1;
					7'h75: if (IOSEL1) PDR1_O <= DBI[6:0];
					7'h77: if (IOSEL2) PDR2_O <= DBI[6:0];
					7'h79: DDR1 <= DBI[6:0];
					7'h7B: DDR2 <= DBI[6:0];
					7'h7D: {IOSEL2,IOSEL1} <= DBI[1:0];
					7'h7F: {EXLE2,EXLE1} <= DBI[1:0];
					default:;
				endcase
				IO_BUF <= DBI;
			end
			// SMPC.sv: the COMREG write sets COMREG_PEND, which the MCU's next CE edge sees: the count of CE edges
			// after the write clock is CE_CNT one clock later
			if (COM_WR) begin COM_TGL <= ~COM_TGL; COM_TS <= CE_CNT[13:0]; end

			if (!CS_N && CS_N_OLD && RW_N) begin
				if ({A,1'b1} >= 7'h21 && {A,1'b1} <= 7'h5F) begin
					DBO <= OREG_Q;
				end else begin
					case ({A,1'b1})
						7'h61: DBO <= SR;
						7'h63: DBO <= {IO_BUF[7:1],SF};
						7'h75: DBO <= {IO_BUF[7],PIOA_I};
						7'h77: DBO <= {IO_BUF[7],PIOB_I};
						default: DBO <= IO_BUF;
					endcase
				end
			end
		end
	end

	// the firmware's outputs (SMPC.sv's values after RST_N: D_O = D_D = 0, so the D pins are 1; R7_O = 0)
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			DPIN <= '1;
			CDRES <= 0;
			PA_R <= '0;
			PB_R <= '0;
		end
		else if (EN) begin
			if (FW_WR_DPIN) {CDRES,DPIN} <= FW_WD[8:0];
			if (FW_WR_PA) PA_R <= {FW_WD[14:8],FW_WD[6:0]};
			if (FW_WR_PB) PB_R <= {FW_WD[14:8],FW_WD[6:0]};
		end
	end

	// time and input events for the firmware: CE #1 is MRES_N's edge
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			CE_CNT <= '0;
			VBL_OLD <= 1;
			VBL_TS <= '0;
		end
		else if (EN && CE) begin
			CE_CNT <= CE_CNT + 24'd1;
			if (R01_INT2 != VBL_OLD) begin VBL_OLD <= R01_INT2; VBL_TS <= CE_CNT[13:0] + 14'd1; end
		end
	end

	bit  [31: 0] RD;
	always_comb begin
		case (FW_A[1:0])
			2'd0: RD = {EXT_RTC[47:40],CE_CNT};
			2'd1: RD = {EXT_RTC[64],1'b0,COM_TGL,COM_TS,VBL_OLD,VBL_TS};
			2'd2: RD = {IREG_Q,EXT_RTC[36:32],D3,R5,PIOB_I,PIOA_I};
			default: RD = EXT_RTC[31:0];
		endcase
	end
	assign FW_RD = RD;

	assign {D10,D9,D8,D7,D6,D5,D4,D0} = DPIN;
	assign {R61_D,R60_D} = 2'b00;
	assign {R61_O,R60_O} = 2'b11;
	assign R72_O = CDRES;
	assign R73_O = 0;

	assign PIOA_O = IOSEL1 ? PDR1_O : PA_R[6:0];
	assign PIOA_D = IOSEL1 ? DDR1   : PA_R[13:7];
	assign PIOB_O = IOSEL2 ? PDR2_O : PB_R[6:0];
	assign PIOB_D = IOSEL2 ? DDR2   : PB_R[13:7];
	assign EXL_N = (~EXLE1 | PIOA_I[6]) & (~EXLE2 | PIOB_I[6]);

endmodule
