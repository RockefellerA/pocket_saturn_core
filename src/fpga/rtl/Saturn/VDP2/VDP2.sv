// altera message_off 10027

import VDP2_PKG::*;
	
module VDP2 (
	input             CLK,
	input             RST_N,
	input             CE_R,
	input             CE_F,
	
	input             RES_N,

	input      [15:0] DI,
	output     [15:0] DO,
	input             CS_N,
	input             AD_N,
	input             DTEN_N,
	input             REQ_N,
	output            RDY_N,
	
	output            VINT_N,
	output            HINT_N,
	
	output            DCE_R,
	output            DCE_F,
	output            HTIM_N,
	output            VTIM_N,
	input      [15:0] FBDI,
	output     [15:0] FBDO,
	
	input             PAL,
	
	input             EXLAT_N,
	
	output     [17:1] RA0_A,
	output     [16:1] RA1_A,
	output     [63:0] RA_D,
	output      [7:0] RA_WE,
	output            RA_RD,
	input      [31:0] RA0_Q,
	input      [31:0] RA1_Q,
	
	output     [17:1] RB0_A,
	output     [16:1] RB1_A,
	output     [63:0] RB_D,
	output      [7:0] RB_WE,
	output            RB_RD,
	input      [31:0] RB0_Q,
	input      [31:0] RB1_Q,
	
	output      [7:0] R,
	output      [7:0] G,
	output      [7:0] B,
	output reg        DCLK,
	output reg        HS_N,
	output reg        VS_N,
	output reg        HBL_N,
	output reg        VBL_N,
	
	output            FIELD,
	output            INTERLACE,
	output reg  [2:0] HRES,
	output reg  [1:0] VRES,
	
	input       [7:0] SCRN_EN,
	
	input       [7:0] DBG_EXT
`ifdef DEBUG
                     ,
	output VRAMAccessState_t VA_PIPE0,
	output NVRAMAccess_t NBG_A0VA_DBG,
//	output [18: 1] NxVS_ADDR0,
	output CellDotsColor_t NBG_CDC0_DBG,
	output CellDotsColor_t NBG_CDC1_DBG,
	output CellDotsColor_t NBG_CDC2_DBG,
	output CellDotsColor_t NBG_CDC3_DBG,
	output CellParam_t NBG_CDP0_DBG,
	output           [7:0] RBG0_CDC0_DBG,
	output           [7:0] RBG0_CDC1_DBG,
	output           [7:0] RBG0_CDC2_DBG,
	output           [7:0] RBG0_CDC3_DBG,
	output CellParam_t      RBG0_CDP_DBG,
	output           [7:0] RBG1_CDC0_DBG,
	output           [7:0] RBG1_CDC1_DBG,
	output           [7:0] RBG1_CDC2_DBG,
	output           [7:0] RBG1_CDC3_DBG,
	output CellParam_t      RBG1_CDP_DBG,
//	output RxCHD_t CH_PIPE0,
//	output RxCHD_t CH_PIPE1,
//	output RxCHD_t CH_PIPE2,
//	output [4:0] N0DOTN_DBG,
	output DotData_t R0DOT_DBG,
	output DotData_t N0DOT_DBG,
	output DotData_t N1DOT_DBG,
	output DotData_t N2DOT_DBG,
	output DotData_t N3DOT_DBG,
//	output ScreenDot_t DOT_FST_DBG,
//	output ScreenDot_t DOT_SEC_DBG,
//	output ScreenDot_t DOT_THD_DBG,
	output [2:0] FST_PRI0_DBG, SEC_PRI0_DBG, THD_PRI0_DBG,
	output [2:0] FST_PRI1_DBG, SEC_PRI1_DBG, THD_PRI1_DBG,
	output [2:0] FST_PRI2_DBG, SEC_PRI2_DBG, THD_PRI2_DBG,
	output [2:0] FST_PRI3_DBG, SEC_PRI3_DBG, THD_PRI3_DBG,
	output [2:0] FST_PRI4_DBG, SEC_PRI4_DBG, THD_PRI4_DBG,
	output [2:0] FST_PRI5_DBG, SEC_PRI5_DBG, THD_PRI5_DBG,
//	output [18:0] N0SCX,
//	output [18:0] N0SCY,
	output [18:0] NxOFFX0_DBG,
	output [18:0] NxOFFX1_DBG,
	output [18:0] NxOFFX2_DBG,
	output [18:0] NxOFFX3_DBG,
	output [18:0] NxOFFY0_DBG,
	output [18:0] NxOFFY1_DBG,
	output [18:0] NxOFFY2_DBG,
	output [18:0] NxOFFY3_DBG,
	output [31:0] Xsp_DBG[2],Ysp_DBG[2],
	output [31:0] Xp_DBG[2],Yp_DBG[2],
	output [31:0] dX_DBG[2],dY_DBG[2],
	output [31:0] Xst_DBG[2],Yst_DBG[2],
	output [19:1] R0NP_ADDR_DBG,
//	output RotTbl_t ROTA_TBL,
	output [15:0] VRAM_WRITE_PEND_CNT,
	output RotCoord_t   RPK_DBG,
	output [34:0] KAx0_DBG,
	output [ 3:0] RA_D_ERR,
	output [ 3:0] RB_D_ERR
`endif
);
	
	//H 427/455
	//V 263/313
	parameter HRES_320          = 9'd427;
	parameter HRES_352          = 9'd455;
	parameter HS_START_320      = 9'd350;
	parameter HS_START_352      = 9'd380;
	parameter HS_MID_320        = 9'd137;
	parameter HS_MID_352        = 9'd153;
	parameter HBL_START_320     = 9'd312;
	parameter HBL_START_352     = 9'd344;
	parameter VRES_NTSC         = 10'd263;
	parameter VRES_PAL          = 10'd313;
	parameter VS_START_NTSC_224 = 10'h0ED;
	parameter VS_START_NTSC_240 = 10'h0F5;
	parameter VS_START_PAL_224  = 10'h103;
	parameter VS_START_PAL_240  = 10'h10B;
	parameter VS_START_PAL_256  = 10'h113;
	parameter VS_END_NTSC_224   = /*VS_START_NTSC_224*/10'h1E6 + 10'd3;
	parameter VS_END_NTSC_240   = /*VS_START_NTSC_240*/10'h1EE + 10'd3;
	parameter VS_END_PAL_224    = /*VS_START_PAL_224*/10'h1CA + 10'd3;
	parameter VS_END_PAL_240    = /*VS_START_PAL_240*/10'h1D2 + 10'd3;
	parameter VS_END_PAL_256    = /*VS_START_PAL_256*/10'h1DA + 10'd3;
	parameter VBL_START_224     = 10'h0E0;
	parameter VBL_START_240     = 10'h0F0;
	parameter VBL_START_256     = 10'h100;
	
	VDP2Regs_t REGS;
	
	
	bit [18:1] VRAM_WA;
	bit [18:1] VRAM_RA;
	bit [63:0] VRAM_D;
	bit  [7:0] VRAM_WE;
	bit        VRAM_WRITE_PEND;
	bit        VRAM_READ_PEND;
	
	bit  [17: 1] VRAMA0_A, VRAMB0_A;
	bit  [16: 1] VRAMA1_A, VRAMB1_A;
	bit  [63: 0] VRAMA_D, VRAMB_D;
	bit  [ 7: 0] VRAMA_WE, VRAMB_WE;
	bit          VRAMA0_RD, VRAMA1_RD, VRAMB0_RD, VRAMB1_RD;
	bit  [15: 0] VRAMA0_Q, VRAMA1_Q, VRAMB0_Q, VRAMB1_Q;
	bit          VRAM_READ_PIPE[2];
	wire VRAMA0_READ = (VRAM_RA[18:17] == 2'b00);
	wire VRAMA1_READ = (VRAM_RA[18:17] == 2'b01);
	wire VRAMB0_READ = (VRAM_RA[18:17] == 2'b10);
	wire VRAMB1_READ = (VRAM_RA[18:17] == 2'b11);
	
	
	bit          DOT_CE_R,DOT_CE_F;
	bit  [ 8: 0] H_CNT, HCT;
	bit  [ 8: 0] V_CNT, VCT;
	bit          HCT9;
	bit          VCT0;
	bit  [ 8: 0] SCRNX, SCRNY;
	bit          SCRNX0;
	bit  [ 3: 0] MOSAIC_HCNT,MOSAIC_VCNT;
	bit          DISP;
	bit  [ 1: 0] LSMD;
	VRAMAccessPipeline_t VA_PIPE;
	NBGPipeline_t BG_PIPE;
	RBGPipeline_t RBG_PIPE;
	ScrollData_t NxOFFX[4];
	ScrollData_t NxOFFY[4];
	ScrollData_t VS[2];
	CT_t         CTD[2];			//Coeficient table data A/B
	RotCoord_t   RxX[2],RxY[2];
	RotCoord_t   KAst[2];
	RotAddr_t    RxKA[2];
	bit          RxCTTP[2];
	bit  [ 6: 0] RPxLCSD[2];
	bit          R0RPMSB;
	
	bit  [15: 0] PAL0_Q, PAL1_Q;
	bit  [15: 0] PAL0_DO, PAL1_DO;
	
	
	bit  [ 1: 0] DOTCLK_DIV;
	always @(posedge CLK) begin
		if (!RES_N) begin
			DOTCLK_DIV <= '0;
		end else if (CE_R) begin
			DOTCLK_DIV <= DOTCLK_DIV + 2'd1;
		end
	end
	assign DOT_CE_R = (DOTCLK_DIV == 3) & CE_R;
	assign DOT_CE_F = (DOTCLK_DIV == 1) & CE_R;
	
	assign DCLK = DOT_CE_R | (DOT_CE_F & HRES[1]);
	assign DCE_R = DOT_CE_R;
	assign DCE_F = DOT_CE_F;
	
	wire LAST_DOT = HCT == (HRES[2] ? 9'h1FE : 9'h1FF);
	wire [8:0] HBLANK_START = !HRES[2] ? (!HRES[0] ? 9'h144 : 9'h164) : (!HRES[0] ? 9'h148 : 9'h168);
	wire [8:0] HS_START = (!HRES[0] ? HS_START_320 : HS_START_352) - (!PAL ? 9'd0 : 9'd4);
	wire [8:0] HS_MID = (!HRES[0] ? HS_MID_320 : HS_MID_352) - (!PAL ? 9'd0 : 9'd4);
	wire [8:0] HS_END =  HS_START + 9'd32; 
	wire [8:0] HBL_START = (!HRES[0] ? 9'h143 : 9'h163) - (!HRES[1] || HRES[2] ? 9'd0 : 9'd1);
	wire [8:0] HBL_END = !HRES[1] || HRES[2] ? 9'd2 : 9'd1;
	wire [8:0] BREAK_DOT  = !HRES[2] ? (!HRES[0] ? 9'h15B - 9'd1 : 9'h177 - 9'd1) : (!HRES[0] ? 9'h15A - 9'd2 : 9'h178 - 9'd2);
	wire [8:0] VINC_DOT0  = !HRES[2] ? (!HRES[0] ? 9'h085 - 9'd1 : 9'h093 - 9'd1) : (!HRES[0] ? 9'h15A - 9'd2 : 9'h16C - 9'd2);
	wire [8:0] VINC_DOT1  = !HRES[2] ? (!HRES[0] ? 9'h15B - 9'd1 : 9'h177 - 9'd1) : (!HRES[0] ? 9'h15A - 9'd2 : 9'h16C - 9'd2);
	wire [9:0] VBL_START = HRES[2] ? 10'h1E0 : (!VRES[1] || !PAL ? (!VRES[0] ? VBL_START_224 : VBL_START_240) : VBL_START_256) << 1;
	wire [9:0] VS_NTSC_START  = (!VRES[1] ? (!VRES[0] ? VS_START_NTSC_224 : VS_START_NTSC_240) : VS_START_NTSC_240);
	wire [9:0] VS_PAL_START  = (!VRES[1] ? (!VRES[0] ? VS_START_PAL_224 : VS_START_PAL_240) : VS_START_PAL_256);
	wire [9:0] VS_NTSC_END    = !VRES[1] ? (!VRES[0] ? VS_END_NTSC_224 : VS_END_NTSC_240) : VS_END_NTSC_240;
	wire [9:0] VS_PAL_END    = !VRES[1] ? (!VRES[0] ? VS_END_PAL_224 : VS_END_PAL_240) : VS_END_PAL_256;
	wire [9:0] VS_START  = (PAL ? VS_PAL_START : VS_NTSC_START) - (!NNI        ? 10'd1 : 10'd0);
	wire [9:0] VS_END    = (PAL ? VS_PAL_END   : VS_NTSC_END  ) - (!NNI && ODD ? 10'd1 : 10'd0);
	wire [9:0] VSYNC_HSTART = REGS.TVMD.LSMD[1] && ODD ? HS_MID : HS_START;
//	wire [8:0] VBORD_START  = !VRES[1] ? (!VRES[0] ? 9'd263-9'd12 : 9'd263-9'd4) : 9'd313-9'd0;
//	wire [8:0] VBORD_END  = !VRES[1] ? (!VRES[0] ? 9'd224+9'd12 : 9'd240+9'd4) : 9'd256+9'd0;
	wire [9:0] INC_LINE  = HRES[2] ? 10'h001 : 10'h002;
	wire [9:0] BREAK_LINE  = HRES[2] ? (!HRES[0] ? 10'h1EA : 10'h1F7) - 10'd1                         : (((!PAL ? (!VRES[0] ? 10'h0ED : 10'h0F5) : (!VRES[1] ? (!VRES[0] ? 10'h103 : 10'h10B) : 10'h113)) - (!NNI        ? 10'd1 : 10'd0) - 10'd1) << 1)|10'h001;
	wire [9:0] JUMP_LINE   = HRES[2] ? (!HRES[0] ? 10'h3DD : 10'h3C5) - (!NNI && ODD ? 10'd2 : 10'd0) : (((!PAL ? (!VRES[0] ? 10'h1E6 : 10'h1EE) : (!VRES[1] ? (!VRES[0] ? 10'h1CA : 10'h1D2) : 10'h1DA)) - (!NNI && ODD ? 10'd1 : 10'd0)        ) << 1);
	wire [9:0] NEXT_TO_LAST_LINE  = 10'h3FD;
	wire [9:0] LAST_LINE  = 10'h3FF;
	
	bit          VB_INT,VBLANK;
	bit          HB_INT,HBLANK;
	bit          DISP_INT,DISP_INT2;
	bit          INTERLACE_INT;
	bit          ODD;
	bit          VSYNC;
	bit          HSYNC;
	always @(posedge CLK or negedge RST_N) begin
		bit  [ 1: 0] VRES_LATCH0,VRES_LATCH1;
		bit          F;
		
		if (!RST_N) begin
			{HCT9,HCT} <= '0;
			{VCT,VCT0} <= '0;
			HB_INT <= 0;
			VB_INT <= 0;
			H_CNT <= '0;
			V_CNT <= '0;
			HBLANK <= 0;
			VBLANK <= 0;
			ODD <= 0;
			HSYNC <= 0;
			VSYNC <= 0;
			F <= 0;
		end else if (!RES_N) begin
			{HCT9,HCT} <= 10'h3B0;
			{VCT,VCT0} <= {9'h1E6,1'b0};
			HB_INT <= 0;
			VB_INT <= 0;
			H_CNT <= '0;
			V_CNT <= 9'h1E6;
			HBLANK <= 1;
			VBLANK <= 1;
			ODD <= 1;
			HSYNC <= 0;
			VSYNC <= 1;
			F <= 0;
		end else begin
		if (DOT_CE_R) begin
			{HCT9,HCT} <= ({HCT9,HCT} + (HRES[2] ? 10'd2 : 10'd1)) & {9'b111111111,~HRES[2]};
			if ({HCT9,HCT} == {1'b0,BREAK_DOT}) begin
				{HCT9,HCT} <= HRES[2] && HRES[0] ? 10'h3D0 : 10'h3B0;
			end
			if ({HCT9,HCT} == {1'b0,VINC_DOT0} || {HCT9,HCT} == {1'b0,VINC_DOT1}) begin
				{VCT,VCT0} <= {VCT,VCT0} + 10'd1;
				if ({VCT,VCT0} == BREAK_LINE) begin
					{VCT,VCT0} <= JUMP_LINE;
					ODD <= ~ODD;
				end else if ({VCT,VCT0} == LAST_LINE) begin
					{VCT,VCT0} <= '0;
				end
				
				if ({VCT,VCT0} == (VBL_START - 10'd1)) begin
					VBLANK <= 1;
				end else if ({VCT,VCT0} == LAST_LINE) begin
					VBLANK <= 0;
				end
			end
			
			H_CNT <= (H_CNT + (HRES[2] ? 9'd2 : 9'd1)) & {8'b11111111,~HRES[2]};
			if (LAST_DOT) begin
				H_CNT <= '0;
				V_CNT <= VCT;
			end
			
			if (HCT == HBLANK_START - (HRES[2] ? 9'd2 : 9'd1)) begin
				HBLANK <= 1;
			end else if (HCT == (HRES[2] ? 9'd8 - 9'd2 : 9'd4 - 9'd1)) begin
				HBLANK <= 0;
			end
			
			if (H_CNT == HS_START - 1) begin
				HSYNC <= 1;
			end else if (H_CNT == HS_END - 1) begin
				HSYNC <= 0;
			end

			if (H_CNT == VSYNC_HSTART - 1) begin
				if (VCT == VS_START - 10'd1) begin
					VSYNC <= 1;
				end else if (VCT == VS_END - 10'd1) begin
					VSYNC <= 0;
				end
			end
			
			if (H_CNT == HBL_START - 1) begin
				HB_INT <= 1;
			end else if (H_CNT == HBL_END) begin
				HB_INT <= 0;
			end
			
			if (LAST_DOT && V_CNT == (VBL_START - 10'd1)>>1) begin
				VB_INT <= 1;
			end else if (LAST_DOT && V_CNT == NEXT_TO_LAST_LINE>>1) begin
				VB_INT <= 0;
			end
			
			if (!REGS.TVMD.DISP &&            DISP_INT) DISP_INT <= 0;
			if ( REGS.TVMD.DISP && VBLANK && !DISP_INT) DISP_INT <= 1;
			
			if ({HCT9,HCT} == {1'b0,VINC_DOT1}) begin
//				if ({VCT,VCT0} == LAST_LINE) begin
//					DISP_INT2 <= REGS.TVMD.DISP;
//				end
				if ({VCT,VCT0} == NEXT_TO_LAST_LINE) begin
					LSMD <= REGS.TVMD.LSMD;//?
					if (REGS.TVMD.LSMD == 2'b00) ODD <= 1;
					if (F) INTERLACE_INT <= REGS.TVMD.LSMD[1];
					F <= ~F;
//					HRES2 <= REGS.TVMD.HRESO;
				end
			end
			HRES <= REGS.TVMD.HRESO[2:0];
			VRES_LATCH0 <= REGS.TVMD.VRESO[1:0] & {PAL,1'b1}; VRES_LATCH1 <= VRES_LATCH0;	VRES <= VRES_LATCH1;
			DISP <= REGS.TVMD.DISP;
		end else if (DOT_CE_F) begin
			if (ODD && H_CNT == VSYNC_HSTART - 1) begin
				if (VCT == VS_START - 10'd1) begin
					VSYNC <= 1;
				end else if (VCT == VS_END - 10'd1) begin
					VSYNC <= 0;
				end
			end
		end
		end
	end
	wire NNI = (LSMD == 2'b00);						//Non interlace
	wire DDI = (LSMD == 2'b11);						//Double-density interlace
	
	wire [ 9: 0] HINT_START = !HRES[2] ? (!HRES[0] ? 10'h138 : 10'h158) : (!HRES[0] ? 10'h122 : 10'h142);
	bit          HINT,VINT;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			HINT <= 0;
			VINT <= 0;
		end else if (!RES_N) begin
			HINT <= 0;
			VINT <= 1;
		end else begin
			if ({VCT,VCT0} == VBL_START) begin
				VINT <= 1;
			end
			if ({VCT,VCT0} == 10'h3FE) begin
				VINT <= 0;
			end
			
			if ({HCT9,HCT} == HINT_START) begin
				HINT <= 1;
			end
			if ({HCT9,HCT} == 10'h000) begin
				HINT <= 0;
			end
		end
	end
	assign VINT_N = ~VINT;
	assign HINT_N = ~HINT;
	
	wire [ 9: 0] HTIM_START = !HRES[0] ? 10'h3E0 - 9'h001 : 10'h3E1 - 9'h001;
	wire [ 9: 0] HTIM_END = 10'h3F8;
	bit          HTIM,VTIM;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			HTIM <= 0;
			VTIM <= 0;
		end else if (!RES_N) begin
			HTIM <= 0;
			VTIM <= 0;
		end else if (DOT_CE_R) begin
			if ({HCT9,HCT} == HTIM_START) begin
				HTIM <= 1;
			end else if ({HCT9,HCT} == HTIM_END) begin
				HTIM <= 0;
			end
			
			if ({HCT9,HCT} == HTIM_START) begin
				if (VCT == (VBL_START>>1) + 9'h001) begin
					VTIM <= 1;
				end else if (VCT == 9'h000) begin
					VTIM <= 0;
				end
			end
		end
	end
	assign VTIM_N = ~VTIM;
	assign HTIM_N = ~HTIM;
	
	wire [ 8: 0] NBG_CELLX_START = !HRES[0] ? 9'h18D : 9'h1A9;
	wire [ 8: 0] NBG_FETCH_START = (!HRES[0] ? 9'h195 : 9'h1B1) + (HRES[1] ? 4'd8 : 4'd0);
	wire [ 8: 0] NBG_FETCH_END = (!HRES[0] ? 9'h131 : 9'h151) + (HRES[1] ? 4'd8 : 4'd0);
	wire [ 8: 0] RBG_FETCH_START = !HRES[0] ? 9'h195 + 9'h010 : 9'h1B1 + 9'h010;
	wire [ 8: 0] RBG_FETCH_END = !HRES[0] ? 9'h131 + 9'h010 : 9'h151 + 9'h010;
	wire [ 8: 0] RPA_FETCH_START = !HRES[0] ? 9'h169 : 9'h185;
	wire [ 8: 0] RPB_FETCH_START = !HRES[0] ? 9'h151 : 9'h16D;
	wire [ 8: 0] RCTA_FETCH_START = !HRES[0] ? 9'h18B : 9'h1A7;
	wire [ 8: 0] RCTB_FETCH_START = !HRES[0] ? 9'h18C : 9'h1A8;
	wire [ 8: 0] LS_FETCH_START = !HRES[0] ? 9'h181 : 9'h19D;
	wire [ 8: 0] LW_FETCH_START = !HRES[0] ? 9'h187 : 9'h1A3;
	wire [ 8: 0] LN_FETCH_START = !HRES[0] ? 9'h189 : 9'h1A5;
	wire [ 8: 0] BS_FETCH_START = !HRES[0] ? 9'h18A : 9'h1A6;
	wire [ 8: 0] NOACCESS_START = !HRES[0] ? 9'h136 : 9'h156;
	wire [ 8: 0] NOACCESS_END = !HRES[0] ? 9'h13D : 9'h15D;
	wire [ 8: 0] NOACCESS2_START = !HRES[0] ? 9'h142 : 9'h162;
	wire [ 8: 0] NOACCESS2_END = !HRES[0] ? 9'h145 : 9'h165;
	wire [ 8: 0] NOACCESS3_START = !HRES[0] ? 9'h18D : 9'h1A9;
	wire [ 8: 0] NOACCESS3_END = !HRES[0] ? 9'h18F : 9'h1AB;
	wire [ 8: 0] REFRESH_START = !HRES[0] ? 9'h190 : 9'h1AC;
	wire [ 8: 0] REFRESH_END = !HRES[0] ? 9'h194 : 9'h1B0;
	wire [ 8: 0] NBG_SCREEN_START = !HRES[0] ? 9'h19D : 9'h1B9;
	wire         IS_PRELAST_LINE = (V_CNT == NEXT_TO_LAST_LINE>>1);
	wire         IS_LAST_LINE = (V_CNT == LAST_LINE>>1);
	wire         IS_RENDER_LINES = (V_CNT < (VBL_START - INC_LINE)>>1) || IS_LAST_LINE;
	wire         IS_VISIBLE_LINES = (V_CNT < VBL_START>>1);
	wire         NBG_FETCH_START_EN = (H_CNT == NBG_FETCH_START - 1);
	wire         NBG_FETCH_END_EN = (H_CNT == NBG_FETCH_END);
	
	bit  [ 2: 0] CELLX;
	bit          NPN_FETCH;		//Normal screen pattern data fetch time
	bit          NCH_FETCH;		//Normal screen char data fetch time
	bit          NVCS_FETCH;	//Vertical cell scroll data fetch time
	bit          RBG_CALC;
	bit          RBG_FETCH;		//Rotation screen pattern data fetch time
	bit          RCH_FETCH;		//Rotation screen char data fetch time
	bit          LS_FETCH;		//Line scroll table fetch time
	bit          LW_FETCH;		//Line window table fetch time
	bit          RPA_FETCH;		//Rotation parameter A fetch time
	bit          RPB_FETCH;		//Rotation parameter B fetch time
	bit          RCTA_FETCH;	//Rotation coeficient table line A fetch time
	bit          RCTB_FETCH;	//Rotation coeficient table line B fetch time
	bit          CT_FETCH;		//Coefficient table fetch time
	bit          LN_FETCH;		//Line screen table fetch time
	bit          BACK_FETCH;	//Back screen table fetch time
	bit          REFRESH;		//VRAM refresh time
	bit          NOACCESS;		//VRAM no access time
	bit          DOT_FETCH;
	bit  [ 4: 0] NFETCH_PIPE;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			CELLX <= '0;
			NPN_FETCH <= 0;
			NCH_FETCH <= 0;
			NVCS_FETCH <= 0;
			RBG_FETCH <= 0;
			RBG_CALC <= 0;
			RCTA_FETCH <= 0;
			RCTB_FETCH <= 0;
			LS_FETCH <= 0;
			LW_FETCH <= 0;
			RPA_FETCH <= 0;
			RPB_FETCH <= 0;
			BACK_FETCH <= 0;
			REFRESH <= 0;
			DOT_FETCH <= 0;
		end else if (!RES_N) begin
			CELLX <= '0;
			NPN_FETCH <= 0;
			NCH_FETCH <= 0;
			NVCS_FETCH <= 0;
			RBG_FETCH <= 0;
			RBG_CALC <= 0;
			RCTA_FETCH <= 0;
			RCTB_FETCH <= 0;
			LS_FETCH <= 0;
			LW_FETCH <= 0;
			RPA_FETCH <= 0;
			RPB_FETCH <= 0;
			BACK_FETCH <= 0;
			REFRESH <= 0;
			DOT_FETCH <= 0;
		end else if (DOT_CE_R) begin
			CELLX <= CELLX + 1'd1;
			if (H_CNT == NBG_CELLX_START - 1 && IS_RENDER_LINES) begin
				CELLX <= '0;
			end
			
			if (NBG_FETCH_START_EN && IS_RENDER_LINES && DISP_INT) begin
				NPN_FETCH <= 1;
			end else if (H_CNT == NBG_FETCH_END) begin
				NPN_FETCH <= 0;
			end
			if (H_CNT == NBG_FETCH_START + 4 - 1 && IS_RENDER_LINES && DISP_INT) begin
				NCH_FETCH <= 1;
			end else if (H_CNT == NBG_FETCH_END + 4) begin
				NCH_FETCH <= 0;
			end
			if (H_CNT == NBG_FETCH_START - 1 - 8 && IS_RENDER_LINES && DISP_INT) begin
				NVCS_FETCH <= 1;
			end else if (H_CNT == NBG_FETCH_END) begin
				NVCS_FETCH <= 0;
			end
			
			if (H_CNT == RBG_FETCH_START - 1 - 4 && IS_RENDER_LINES && DISP_INT) begin
				CT_FETCH <= 1;
			end else if (H_CNT == RBG_FETCH_END - 4) begin
				CT_FETCH <= 0;
			end
			if (H_CNT == RBG_FETCH_START - 1 - 1 && IS_RENDER_LINES) begin
				RBG_CALC <= 1;
			end else if (H_CNT == RBG_FETCH_END - 1) begin
				RBG_CALC <= 0;
			end
			if (H_CNT == RBG_FETCH_START - 1 && IS_RENDER_LINES && DISP_INT) begin
				RBG_FETCH <= 1;
			end else if (H_CNT == RBG_FETCH_END) begin
				RBG_FETCH <= 0;
			end
			if (H_CNT == RBG_FETCH_START + 4 - 1 && IS_RENDER_LINES && DISP_INT) begin
				RCH_FETCH <= 1;
			end else if (H_CNT == RBG_FETCH_END /*+ 4*/) begin
				RCH_FETCH <= 0;
			end
			
			if (H_CNT == RPA_FETCH_START - 1 && IS_RENDER_LINES && DISP_INT) begin
				RPA_FETCH <= 1;
			end else if (H_CNT == RPA_FETCH_START + 24 - 1) begin
				RPA_FETCH <= 0;
			end
			if (H_CNT == RPB_FETCH_START - 1 && IS_RENDER_LINES && DISP_INT) begin
				RPB_FETCH <= 1;
			end else if (H_CNT == RPB_FETCH_START + 24 - 1) begin
				RPB_FETCH <= 0;
			end
			
			if (H_CNT == RCTA_FETCH_START - 1 && IS_RENDER_LINES && DISP_INT) begin
				RCTA_FETCH <= 1;
			end else if (H_CNT == RCTA_FETCH_START) begin
				RCTA_FETCH <= 0;
			end
			if (H_CNT == RCTB_FETCH_START - 1 && IS_RENDER_LINES && DISP_INT) begin
				RCTB_FETCH <= 1;
			end else if (H_CNT == RCTB_FETCH_START) begin
				RCTB_FETCH <= 0;
			end
			
			if (H_CNT == LS_FETCH_START - 1 && IS_RENDER_LINES && DISP_INT) begin
				LS_FETCH <= 1;
			end else if (H_CNT == LS_FETCH_START + 6 - 1) begin
				LS_FETCH <= 0;
			end
			
			if (H_CNT == LW_FETCH_START - 1 && IS_RENDER_LINES && DISP_INT) begin
				LW_FETCH <= 1;
			end else if (H_CNT == LW_FETCH_START + 2 - 1) begin
				LW_FETCH <= 0;
			end
			
			if (H_CNT == LN_FETCH_START - 1 && IS_RENDER_LINES && DISP_INT) begin
				LN_FETCH <= 1;
			end else begin
				LN_FETCH <= 0;
			end
			
			if (H_CNT == BS_FETCH_START - 1 && IS_RENDER_LINES && DISP_INT) begin
				BACK_FETCH <= 1;
			end else begin
				BACK_FETCH <= 0;
			end
			
			if (H_CNT == 9'd2 - 1 && IS_VISIBLE_LINES) begin
				DOT_FETCH <= 1;
			end else if (H_CNT == 9'd2 + 9'd352 - 1) begin
				DOT_FETCH <= 0;
			end
			
			if (H_CNT == REFRESH_START - 1 || H_CNT == NOACCESS2_START - 1) begin
				REFRESH <= 1;
			end else if (H_CNT == REFRESH_END || H_CNT == NOACCESS2_END) begin
				REFRESH <= 0;
			end
			
			if (/*H_CNT == NOACCESS_START - 1 ||*/ H_CNT == NOACCESS2_START - 1 || H_CNT == NOACCESS3_START - 1) begin
				NOACCESS <= 1;
			end else if (/*H_CNT == NOACCESS_END ||*/ H_CNT == NOACCESS2_END || H_CNT == NOACCESS3_END) begin
				NOACCESS <= 0;
			end
		end
	end
			
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			SCRNX0 <= 0;
		end
		else if (DOT_CE_F) begin
			SCRNX0 <= 1;
		end
		else if (DOT_CE_R) begin
			SCRNX0 <= 0;
			SCRNX <= SCRNX + 1'd1;
			if (H_CNT == NBG_SCREEN_START - 1 && (IS_VISIBLE_LINES || IS_LAST_LINE)) begin
				SCRNX <= '0;
			end
			
			if (H_CNT == LS_FETCH_START - 1 && (IS_VISIBLE_LINES || IS_LAST_LINE)) begin
				SCRNY <= SCRNY + 1'd1;
				if (IS_LAST_LINE) begin
					SCRNY <= '0;
				end
			end
		end
	end
	wire [8:0] WSCRNY = !DDI ? SCRNY : {SCRNY[7:0],~ODD};
	
	VDP2NSxRegs_t NSxREG;
	VDP2RSxRegs_t RSxREG;
	VDP2RPxRegs_t RPxREG;
	
	assign NSxREG = NSxRegs(REGS);
	assign RSxREG = RSxRegs(REGS);
	assign RPxREG = RPxRegs(REGS);
	
		bit [3:0] VCPA0; 
		bit [3:0] VCPA1; 
		bit [3:0] VCPB0; 
		bit [3:0] VCPB1;
	bit [1:0] RDBSA0; 
	bit [1:0] RDBSA1; 
	bit [1:0] RDBSB0; 
	bit [1:0] RDBSB1;
	always_comb begin
		
		case (CELLX[2:0] & {~HRES[1],2'b11})
			T0: begin VCPA0 = REGS.CYCA0L[15:12]; VCPA1 = REGS.RAMCTL.VRAMD ? REGS.CYCA1L[15:12] : REGS.CYCA0L[15:12]; 
			          VCPB0 = REGS.CYCB0L[15:12]; VCPB1 = REGS.RAMCTL.VRBMD ? REGS.CYCB1L[15:12] : REGS.CYCB0L[15:12]; end
			T1: begin VCPA0 = REGS.CYCA0L[11: 8]; VCPA1 = REGS.RAMCTL.VRAMD ? REGS.CYCA1L[11: 8] : REGS.CYCA0L[11: 8]; 
			          VCPB0 = REGS.CYCB0L[11: 8]; VCPB1 = REGS.RAMCTL.VRBMD ? REGS.CYCB1L[11: 8] : REGS.CYCB0L[11: 8]; end
			T2: begin VCPA0 = REGS.CYCA0L[ 7: 4]; VCPA1 = REGS.RAMCTL.VRAMD ? REGS.CYCA1L[ 7: 4] : REGS.CYCA0L[ 7: 4]; 
			          VCPB0 = REGS.CYCB0L[ 7: 4]; VCPB1 = REGS.RAMCTL.VRBMD ? REGS.CYCB1L[ 7: 4] : REGS.CYCB0L[ 7: 4]; end
			T3: begin VCPA0 = REGS.CYCA0L[ 3: 0]; VCPA1 = REGS.RAMCTL.VRAMD ? REGS.CYCA1L[ 3: 0] : REGS.CYCA0L[ 3: 0]; 
			          VCPB0 = REGS.CYCB0L[ 3: 0]; VCPB1 = REGS.RAMCTL.VRBMD ? REGS.CYCB1L[ 3: 0] : REGS.CYCB0L[ 3: 0]; end
			T4: begin VCPA0 = REGS.CYCA0U[15:12]; VCPA1 = REGS.RAMCTL.VRAMD ? REGS.CYCA1U[15:12] : REGS.CYCA0U[15:12]; 
			          VCPB0 = REGS.CYCB0U[15:12]; VCPB1 = REGS.RAMCTL.VRBMD ? REGS.CYCB1U[15:12] : REGS.CYCB0U[15:12]; end
			T5: begin VCPA0 = REGS.CYCA0U[11: 8]; VCPA1 = REGS.RAMCTL.VRAMD ? REGS.CYCA1U[11: 8] : REGS.CYCA0U[11: 8]; 
			          VCPB0 = REGS.CYCB0U[11: 8]; VCPB1 = REGS.RAMCTL.VRBMD ? REGS.CYCB1U[11: 8] : REGS.CYCB0U[11: 8]; end
			T6: begin VCPA0 = REGS.CYCA0U[ 7: 4]; VCPA1 = REGS.RAMCTL.VRAMD ? REGS.CYCA1U[ 7: 4] : REGS.CYCA0U[ 7: 4]; 
			          VCPB0 = REGS.CYCB0U[ 7: 4]; VCPB1 = REGS.RAMCTL.VRBMD ? REGS.CYCB1U[ 7: 4] : REGS.CYCB0U[ 7: 4]; end
			T7: begin VCPA0 = REGS.CYCA0U[ 3: 0]; VCPA1 = REGS.RAMCTL.VRAMD ? REGS.CYCA1U[ 3: 0] : REGS.CYCA0U[ 3: 0]; 
			          VCPB0 = REGS.CYCB0U[ 3: 0]; VCPB1 = REGS.RAMCTL.VRBMD ? REGS.CYCB1U[ 3: 0] : REGS.CYCB0U[ 3: 0]; end
		endcase
		
		RDBSA0 = REGS.RAMCTL.RDBSA0;
		RDBSA1 = REGS.RAMCTL.VRAMD ? REGS.RAMCTL.RDBSA1 : REGS.RAMCTL.RDBSA0;
		RDBSB0 = REGS.RAMCTL.RDBSB0;
		RDBSB1 = REGS.RAMCTL.VRBMD ? REGS.RAMCTL.RDBSB1 : REGS.RAMCTL.RDBSB0;
		
		VA_PIPE[0].NxA0PN[0] = VCPA0 == VCP_N0PN                  & NPN_FETCH  & NSxREG[0].ON & (RDBSA0 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxA1PN[0] = VCPA1 == VCP_N0PN                  & NPN_FETCH  & NSxREG[0].ON & (RDBSA1 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxB0PN[0] = VCPB0 == VCP_N0PN                  & NPN_FETCH  & NSxREG[0].ON & (RDBSB0 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxB1PN[0] = VCPB1 == VCP_N0PN                  & NPN_FETCH  & NSxREG[0].ON & (RDBSB1 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxA0PN[1] = VCPA0 == VCP_N1PN                  & NPN_FETCH  & NSxREG[1].ON & (RDBSA0 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxA1PN[1] = VCPA1 == VCP_N1PN                  & NPN_FETCH  & NSxREG[1].ON & (RDBSA1 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxB0PN[1] = VCPB0 == VCP_N1PN                  & NPN_FETCH  & NSxREG[1].ON & (RDBSB0 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxB1PN[1] = VCPB1 == VCP_N1PN                  & NPN_FETCH  & NSxREG[1].ON & (RDBSB1 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxA0PN[2] = VCPA0 == VCP_N2PN                  & NPN_FETCH  & NSxREG[2].ON & (RDBSA0 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxA1PN[2] = VCPA1 == VCP_N2PN                  & NPN_FETCH  & NSxREG[2].ON & (RDBSA1 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxB0PN[2] = VCPB0 == VCP_N2PN                  & NPN_FETCH  & NSxREG[2].ON & (RDBSB0 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxB1PN[2] = VCPB1 == VCP_N2PN                  & NPN_FETCH  & NSxREG[2].ON & (RDBSB1 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxA0PN[3] = VCPA0 == VCP_N3PN                  & NPN_FETCH  & NSxREG[3].ON & (RDBSA0 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxA1PN[3] = VCPA1 == VCP_N3PN                  & NPN_FETCH  & NSxREG[3].ON & (RDBSA1 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxB0PN[3] = VCPB0 == VCP_N3PN                  & NPN_FETCH  & NSxREG[3].ON & (RDBSB0 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxB1PN[3] = VCPB1 == VCP_N3PN                  & NPN_FETCH  & NSxREG[3].ON & (RDBSB1 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		
		VA_PIPE[0].NxA0CH[0] = VCPA0 == VCP_N0CH                  & NCH_FETCH  & NSxREG[0].ON & (RDBSA0 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxA1CH[0] = VCPA1 == VCP_N0CH                  & NCH_FETCH  & NSxREG[0].ON & (RDBSA1 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxB0CH[0] = VCPB0 == VCP_N0CH                  & NCH_FETCH  & NSxREG[0].ON & (RDBSB0 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxB1CH[0] = VCPB1 == VCP_N0CH                  & NCH_FETCH  & NSxREG[0].ON & (RDBSB1 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxA0CH[1] = VCPA0 == VCP_N1CH                  & NCH_FETCH  & NSxREG[1].ON & (RDBSA0 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxA1CH[1] = VCPA1 == VCP_N1CH                  & NCH_FETCH  & NSxREG[1].ON & (RDBSA1 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxB0CH[1] = VCPB0 == VCP_N1CH                  & NCH_FETCH  & NSxREG[1].ON & (RDBSB0 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxB1CH[1] = VCPB1 == VCP_N1CH                  & NCH_FETCH  & NSxREG[1].ON & (RDBSB1 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxA0CH[2] = VCPA0 == VCP_N2CH                  & NCH_FETCH  & NSxREG[2].ON & (RDBSA0 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxA1CH[2] = VCPA1 == VCP_N2CH                  & NCH_FETCH  & NSxREG[2].ON & (RDBSA1 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxB0CH[2] = VCPB0 == VCP_N2CH                  & NCH_FETCH  & NSxREG[2].ON & (RDBSB0 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxB1CH[2] = VCPB1 == VCP_N2CH                  & NCH_FETCH  & NSxREG[2].ON & (RDBSB1 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxA0CH[3] = VCPA0 == VCP_N3CH                  & NCH_FETCH  & NSxREG[3].ON & (RDBSA0 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxA1CH[3] = VCPA1 == VCP_N3CH                  & NCH_FETCH  & NSxREG[3].ON & (RDBSA1 == 2'b00 | !RSxREG[0].ON)                ;
		VA_PIPE[0].NxB0CH[3] = VCPB0 == VCP_N3CH                  & NCH_FETCH  & NSxREG[3].ON & (RDBSB0 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		VA_PIPE[0].NxB1CH[3] = VCPB1 == VCP_N3CH                  & NCH_FETCH  & NSxREG[3].ON & (RDBSB1 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON;
		
		VA_PIPE[0].NxA0VS[0] = VCPA0 == VCP_N0VS & NSxREG[0].VCSC & NVCS_FETCH & NSxREG[0].ON & (RDBSA0 == 2'b00 | !RSxREG[0].ON)                 & !REFRESH;
		VA_PIPE[0].NxA1VS[0] = VCPA1 == VCP_N0VS & NSxREG[0].VCSC & NVCS_FETCH & NSxREG[0].ON & (RDBSA1 == 2'b00 | !RSxREG[0].ON)                 & !REFRESH;
		VA_PIPE[0].NxB0VS[0] = VCPB0 == VCP_N0VS & NSxREG[0].VCSC & NVCS_FETCH & NSxREG[0].ON & (RDBSB0 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON & !REFRESH;
		VA_PIPE[0].NxB1VS[0] = VCPB1 == VCP_N0VS & NSxREG[0].VCSC & NVCS_FETCH & NSxREG[0].ON & (RDBSB1 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON & !REFRESH;
		VA_PIPE[0].NxA0VS[1] = VCPA0 == VCP_N1VS & NSxREG[1].VCSC & NVCS_FETCH & NSxREG[1].ON & (RDBSA0 == 2'b00 | !RSxREG[0].ON)                 & !REFRESH;
		VA_PIPE[0].NxA1VS[1] = VCPA1 == VCP_N1VS & NSxREG[1].VCSC & NVCS_FETCH & NSxREG[1].ON & (RDBSA1 == 2'b00 | !RSxREG[0].ON)                 & !REFRESH;
		VA_PIPE[0].NxB0VS[1] = VCPB0 == VCP_N1VS & NSxREG[1].VCSC & NVCS_FETCH & NSxREG[1].ON & (RDBSB0 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON & !REFRESH;
		VA_PIPE[0].NxB1VS[1] = VCPB1 == VCP_N1VS & NSxREG[1].VCSC & NVCS_FETCH & NSxREG[1].ON & (RDBSB1 == 2'b00 | !RSxREG[0].ON) & !RSxREG[1].ON & !REFRESH;
				
		VA_PIPE[0].NxPN_FETCH[0] = NBG_PN_FETCH[0];
		VA_PIPE[0].NxPN_FETCH[1] = NBG_PN_FETCH[1];
		VA_PIPE[0].NxPN_FETCH[2] = NBG_PN_FETCH[2];
		VA_PIPE[0].NxPN_FETCH[3] = NBG_PN_FETCH[3];
		
		VA_PIPE[0].RxA0PN[0] = RDBSA0 == 2'b10 & RBG_FETCH & RSxREG[0].ON;
		VA_PIPE[0].RxA1PN[0] = RDBSA1 == 2'b10 & RBG_FETCH & RSxREG[0].ON;
		VA_PIPE[0].RxB0PN[0] = RDBSB0 == 2'b10 & RBG_FETCH & RSxREG[0].ON;
		VA_PIPE[0].RxB1PN[0] = RDBSB1 == 2'b10 & RBG_FETCH & RSxREG[0].ON;
		VA_PIPE[0].RxA0PN[1] = 0;
		VA_PIPE[0].RxA1PN[1] = 0;
		VA_PIPE[0].RxB0PN[1] = 0;
		VA_PIPE[0].RxB1PN[1] =                   RBG_FETCH & RSxREG[1].ON;
		
		VA_PIPE[0].RxA0CH[0] = RDBSA0 == 2'b11 & RCH_FETCH & RSxREG[0].ON;
		VA_PIPE[0].RxA1CH[0] = RDBSA1 == 2'b11 & RCH_FETCH & RSxREG[0].ON;
		VA_PIPE[0].RxB0CH[0] = RDBSB0 == 2'b11 & RCH_FETCH & RSxREG[0].ON;
		VA_PIPE[0].RxB1CH[0] = RDBSB1 == 2'b11 & RCH_FETCH & RSxREG[0].ON;
		VA_PIPE[0].RxA0CH[1] = 0;
		VA_PIPE[0].RxA1CH[1] = 0;
		VA_PIPE[0].RxB0CH[1] =                   RCH_FETCH & RSxREG[1].ON;
		VA_PIPE[0].RxB1CH[1] = 0;
		
		VA_PIPE[0].RxA0CT[0] = RDBSA0 == 2'b01 & CT_FETCH  & RSxREG[0].ON;
		VA_PIPE[0].RxA1CT[0] = RDBSA1 == 2'b01 & CT_FETCH  & RSxREG[0].ON;
		VA_PIPE[0].RxB0CT[0] = RDBSB0 == 2'b01 & CT_FETCH  & RSxREG[0].ON;
		VA_PIPE[0].RxB1CT[0] = RDBSB1 == 2'b01 & CT_FETCH  & RSxREG[0].ON;
		VA_PIPE[0].RxA0CT[1] = 0;
		VA_PIPE[0].RxA1CT[1] = 0;
		VA_PIPE[0].RxB0CT[1] = 0;
		VA_PIPE[0].RxB1CT[1] = 0;
		
`ifdef CUT_VDP2_CRKTE
		//U8 CUT_VDP2_CRKTE: the coefficient table in CRAM is cut (RAMCTL.CRKTE is only stored and read back)
		VA_PIPE[0].RxCRCT[0] = 0;
`else
		VA_PIPE[0].RxCRCT[0] = REGS.RAMCTL.CRKTE & CT_FETCH & RSxREG[0].ON;
`endif
		VA_PIPE[0].RxCRCT[1] = 0;
		
		VA_PIPE[0].RxCTTP[0] = RxCTTP[0];
		VA_PIPE[0].RxCTTP[1] = RxCTTP[1];
		
		VA_PIPE[0].AxNA = ((VCPA0 == VCP_NA | VCPA1 == VCP_NA) & REGS.RAMCTL.VRAMD) || NOACCESS;
		VA_PIPE[0].BxNA = ((VCPB0 == VCP_NA | VCPB1 == VCP_NA) & REGS.RAMCTL.VRBMD) || NOACCESS;
		
		VA_PIPE[0].LS = LS_FETCH;
		VA_PIPE[0].LS_POS = LS_POS;
		VA_PIPE[0].LW = LW_FETCH;
		VA_PIPE[0].LW_POS = LW_POS;
		VA_PIPE[0].RPA = RPA_FETCH;
		VA_PIPE[0].RPB = RPB_FETCH;
		VA_PIPE[0].RCTA = RCTA_FETCH;
		VA_PIPE[0].RCTB = RCTB_FETCH;
		VA_PIPE[0].R0RP = REGS.RPMD.RPMD == 2'b10 ? R0RPMSB : R0RP_PIPE[3];
		VA_PIPE[0].RP_POS = RP_POS;
		VA_PIPE[0].BS = BACK_FETCH;
		VA_PIPE[0].LN = LN_FETCH;
//		VA_PIPE[0].RBG = RBG_PREFETCH;
		
		VA_PIPE[0].NxX[0] = NxOFFX[0].INT;
		VA_PIPE[0].NxX[1] = NxOFFX[1].INT;
		VA_PIPE[0].NxX[2] = NxOFFX[2].INT;
		VA_PIPE[0].NxX[3] = NxOFFX[3].INT;
		VA_PIPE[0].NxY[0] = NxOFFY[0].INT;
		VA_PIPE[0].NxY[1] = NxOFFY[1].INT;
		VA_PIPE[0].NxY[2] = NxOFFY[2].INT;
		VA_PIPE[0].NxY[3] = NxOFFY[3].INT;
		VA_PIPE[0].RxX[0] = RxX[0].INT;
		VA_PIPE[0].RxX[1] = RxX[1].INT;
		VA_PIPE[0].RxY[0] = RxY[0].INT;
		VA_PIPE[0].RxY[1] = RxY[1].INT;
	end
	
	bit  [ 7 : 0] NxPN_CYC_BY_T[4];
	bit           NxPN_CYC[4];
	// (a1 prototype, Phase 2) The layer coordinates NxX, NxY, RxX, RxY are read only at stage 4 of VA_PIPE; stages 1-3
	// were a plain delay line. Here they go through a 4-slot M10K ring instead: written with VA_PIPE[0]'s values on the
	// same edges as the pipeline (DOT_CE_R with RST_N high; slot VAD_W, which then advances), and VA_PIPE[4] (still a
	// register, so its readers see no change) loads the word written three such edges earlier (slot VAD_W - 3, read on
	// every clock: a step lasts 8 clk_sys, so the word is in the RAM's output register long before the next DOT_CE_R
	// edge; slot VAD_W - 3 is never the slot written at that edge). Power-up: RAM, pointer and pipeline all 0.
	(* ramstyle = "M10K, no_rw_check" *) bit [151:0] VAD_RAM[4];
	bit   [1:0] VAD_W = 2'd0;
	bit [151:0] VAD_Q = '0;
	wire [151:0] VAD_D = {VA_PIPE[0].NxX[3], VA_PIPE[0].NxX[2], VA_PIPE[0].NxX[1], VA_PIPE[0].NxX[0],
	                      VA_PIPE[0].NxY[3], VA_PIPE[0].NxY[2], VA_PIPE[0].NxY[1], VA_PIPE[0].NxY[0],
	                      VA_PIPE[0].RxX[1], VA_PIPE[0].RxX[0], VA_PIPE[0].RxY[1], VA_PIPE[0].RxY[0]};
	always @(posedge CLK) begin
		if (RST_N && DOT_CE_R) begin
			VAD_RAM[VAD_W] <= VAD_D;
			VAD_W <= VAD_W + 2'd1;
		end
		VAD_Q <= VAD_RAM[VAD_W + 2'd1];		//slot VAD_W - 3
	end
	always @(posedge CLK or negedge RST_N) begin
		VRAMAccessState_t VA4_D;
		
		if (!RST_N) begin
			// synopsys translate_off
			VA_PIPE <= '{4{'0}};
			// synopsys translate_on
		end
		else if (DOT_CE_R) begin
			VA4_D = VA_PIPE[3];
			VA4_D.NxX[3] = VAD_Q[151:141]; VA4_D.NxX[2] = VAD_Q[140:130]; VA4_D.NxX[1] = VAD_Q[129:119]; VA4_D.NxX[0] = VAD_Q[118:108];
			VA4_D.NxY[3] = VAD_Q[107: 97]; VA4_D.NxY[2] = VAD_Q[ 96: 86]; VA4_D.NxY[1] = VAD_Q[ 85: 75]; VA4_D.NxY[0] = VAD_Q[ 74: 64];
			VA4_D.RxX[1] = VAD_Q[ 63: 48]; VA4_D.RxX[0] = VAD_Q[ 47: 32]; VA4_D.RxY[1] = VAD_Q[ 31: 16]; VA4_D.RxY[0] = VAD_Q[ 15:  0];
			VA_PIPE[1] <= VA_PIPE[0];
			VA_PIPE[2] <= VA_PIPE[1];
			VA_PIPE[3] <= VA_PIPE[2];
			VA_PIPE[4] <= VA4_D;
			
			NxPN_CYC_BY_T[0][CELLX[2:0] & {~HRES[1],2'b11}] <= (VCPA0 == VCP_N0PN || VCPA1 == VCP_N0PN || VCPB0 == VCP_N0PN || VCPB1 == VCP_N0PN);
			NxPN_CYC_BY_T[1][CELLX[2:0] & {~HRES[1],2'b11}] <= (VCPA0 == VCP_N1PN || VCPA1 == VCP_N1PN || VCPB0 == VCP_N1PN || VCPB1 == VCP_N1PN);
			NxPN_CYC_BY_T[2][CELLX[2:0] & {~HRES[1],2'b11}] <= (VCPA0 == VCP_N2PN || VCPA1 == VCP_N2PN || VCPB0 == VCP_N2PN || VCPB1 == VCP_N2PN);
			NxPN_CYC_BY_T[3][CELLX[2:0] & {~HRES[1],2'b11}] <= (VCPA0 == VCP_N3PN || VCPA1 == VCP_N3PN || VCPB0 == VCP_N3PN || VCPB1 == VCP_N3PN);
			
//			NxPN_CYC[0] <=  (REGS.CYCA0L[15:12] == VCP_N0PN || REGS.CYCA0L[11:8] == VCP_N0PN || REGS.CYCA0L[7:4] == VCP_N0PN || REGS.CYCA0L[3:0] == VCP_N0PN || REGS.CYCA0U[15:12] == VCP_N0PN || REGS.CYCA0U[11:8] == VCP_N0PN || REGS.CYCA0U[7:4] == VCP_N0PN || REGS.CYCA0U[3:0] == VCP_N0PN) || 
//							   ((REGS.CYCA1L[15:12] == VCP_N0PN || REGS.CYCA1L[11:8] == VCP_N0PN || REGS.CYCA1L[7:4] == VCP_N0PN || REGS.CYCA1L[3:0] == VCP_N0PN || REGS.CYCA1U[15:12] == VCP_N0PN || REGS.CYCA1U[11:8] == VCP_N0PN || REGS.CYCA1U[7:4] == VCP_N0PN || REGS.CYCA1U[3:0] == VCP_N0PN) && REGS.RAMCTL.VRAMD) || 
//							 	 (REGS.CYCB0L[15:12] == VCP_N0PN || REGS.CYCB0L[11:8] == VCP_N0PN || REGS.CYCB0L[7:4] == VCP_N0PN || REGS.CYCB0L[3:0] == VCP_N0PN || REGS.CYCB0U[15:12] == VCP_N0PN || REGS.CYCB0U[11:8] == VCP_N0PN || REGS.CYCB0U[7:4] == VCP_N0PN || REGS.CYCB0U[3:0] == VCP_N0PN) || 
//							   ((REGS.CYCB1L[15:12] == VCP_N0PN || REGS.CYCB1L[11:8] == VCP_N0PN || REGS.CYCB1L[7:4] == VCP_N0PN || REGS.CYCB1L[3:0] == VCP_N0PN || REGS.CYCB1U[15:12] == VCP_N0PN || REGS.CYCB1U[11:8] == VCP_N0PN || REGS.CYCB1U[7:4] == VCP_N0PN || REGS.CYCB1U[3:0] == VCP_N0PN) && REGS.RAMCTL.VRBMD);
//			NxPN_CYC[1] <=  (REGS.CYCA0L[15:12] == VCP_N1PN || REGS.CYCA0L[11:8] == VCP_N1PN || REGS.CYCA0L[7:4] == VCP_N1PN || REGS.CYCA0L[3:0] == VCP_N1PN || REGS.CYCA0U[15:12] == VCP_N1PN || REGS.CYCA0U[11:8] == VCP_N1PN || REGS.CYCA0U[7:4] == VCP_N1PN || REGS.CYCA0U[3:0] == VCP_N1PN) ||
//							   ((REGS.CYCA1L[15:12] == VCP_N1PN || REGS.CYCA1L[11:8] == VCP_N1PN || REGS.CYCA1L[7:4] == VCP_N1PN || REGS.CYCA1L[3:0] == VCP_N1PN || REGS.CYCA1U[15:12] == VCP_N1PN || REGS.CYCA1U[11:8] == VCP_N1PN || REGS.CYCA1U[7:4] == VCP_N1PN || REGS.CYCA1U[3:0] == VCP_N1PN) && REGS.RAMCTL.VRAMD) || 
//								 (REGS.CYCB0L[15:12] == VCP_N1PN || REGS.CYCB0L[11:8] == VCP_N1PN || REGS.CYCB0L[7:4] == VCP_N1PN || REGS.CYCB0L[3:0] == VCP_N1PN || REGS.CYCB0U[15:12] == VCP_N1PN || REGS.CYCB0U[11:8] == VCP_N1PN || REGS.CYCB0U[7:4] == VCP_N1PN || REGS.CYCB0U[3:0] == VCP_N1PN) ||
//							   ((REGS.CYCB1L[15:12] == VCP_N1PN || REGS.CYCB1L[11:8] == VCP_N1PN || REGS.CYCB1L[7:4] == VCP_N1PN || REGS.CYCB1L[3:0] == VCP_N1PN || REGS.CYCB1U[15:12] == VCP_N1PN || REGS.CYCB1U[11:8] == VCP_N1PN || REGS.CYCB1U[7:4] == VCP_N1PN || REGS.CYCB1U[3:0] == VCP_N1PN) && REGS.RAMCTL.VRBMD);
//			NxPN_CYC[2] <=  (REGS.CYCA0L[15:12] == VCP_N2PN || REGS.CYCA0L[11:8] == VCP_N2PN || REGS.CYCA0L[7:4] == VCP_N2PN || REGS.CYCA0L[3:0] == VCP_N2PN || REGS.CYCA0U[15:12] == VCP_N2PN || REGS.CYCA0U[11:8] == VCP_N2PN || REGS.CYCA0U[7:4] == VCP_N2PN || REGS.CYCA0U[3:0] == VCP_N2PN) ||
//							   ((REGS.CYCA1L[15:12] == VCP_N2PN || REGS.CYCA1L[11:8] == VCP_N2PN || REGS.CYCA1L[7:4] == VCP_N2PN || REGS.CYCA1L[3:0] == VCP_N2PN || REGS.CYCA1U[15:12] == VCP_N2PN || REGS.CYCA1U[11:8] == VCP_N2PN || REGS.CYCA1U[7:4] == VCP_N2PN || REGS.CYCA1U[3:0] == VCP_N2PN) && REGS.RAMCTL.VRAMD) ||
//								 (REGS.CYCB0L[15:12] == VCP_N2PN || REGS.CYCB0L[11:8] == VCP_N2PN || REGS.CYCB0L[7:4] == VCP_N2PN || REGS.CYCB0L[3:0] == VCP_N2PN || REGS.CYCB0U[15:12] == VCP_N2PN || REGS.CYCB0U[11:8] == VCP_N2PN || REGS.CYCB0U[7:4] == VCP_N2PN || REGS.CYCB0U[3:0] == VCP_N2PN) ||
//							   ((REGS.CYCB1L[15:12] == VCP_N2PN || REGS.CYCB1L[11:8] == VCP_N2PN || REGS.CYCB1L[7:4] == VCP_N2PN || REGS.CYCB1L[3:0] == VCP_N2PN || REGS.CYCB1U[15:12] == VCP_N2PN || REGS.CYCB1U[11:8] == VCP_N2PN || REGS.CYCB1U[7:4] == VCP_N2PN || REGS.CYCB1U[3:0] == VCP_N2PN) && REGS.RAMCTL.VRBMD);
//			NxPN_CYC[3] <=  (REGS.CYCA0L[15:12] == VCP_N3PN || REGS.CYCA0L[11:8] == VCP_N3PN || REGS.CYCA0L[7:4] == VCP_N3PN || REGS.CYCA0L[3:0] == VCP_N3PN || REGS.CYCA0U[15:12] == VCP_N3PN || REGS.CYCA0U[11:8] == VCP_N3PN || REGS.CYCA0U[7:4] == VCP_N3PN || REGS.CYCA0U[3:0] == VCP_N3PN) ||
//							   ((REGS.CYCA1L[15:12] == VCP_N3PN || REGS.CYCA1L[11:8] == VCP_N3PN || REGS.CYCA1L[7:4] == VCP_N3PN || REGS.CYCA1L[3:0] == VCP_N3PN || REGS.CYCA1U[15:12] == VCP_N3PN || REGS.CYCA1U[11:8] == VCP_N3PN || REGS.CYCA1U[7:4] == VCP_N3PN || REGS.CYCA1U[3:0] == VCP_N3PN) && REGS.RAMCTL.VRAMD) ||
//								 (REGS.CYCB0L[15:12] == VCP_N3PN || REGS.CYCB0L[11:8] == VCP_N3PN || REGS.CYCB0L[7:4] == VCP_N3PN || REGS.CYCB0L[3:0] == VCP_N3PN || REGS.CYCB0U[15:12] == VCP_N3PN || REGS.CYCB0U[11:8] == VCP_N3PN || REGS.CYCB0U[7:4] == VCP_N3PN || REGS.CYCB0U[3:0] == VCP_N3PN) ||
//							   ((REGS.CYCB1L[15:12] == VCP_N3PN || REGS.CYCB1L[11:8] == VCP_N3PN || REGS.CYCB1L[7:4] == VCP_N3PN || REGS.CYCB1L[3:0] == VCP_N3PN || REGS.CYCB1U[15:12] == VCP_N3PN || REGS.CYCB1U[11:8] == VCP_N3PN || REGS.CYCB1U[7:4] == VCP_N3PN || REGS.CYCB1U[3:0] == VCP_N3PN) && REGS.RAMCTL.VRBMD);
		end
	end
	assign NxPN_CYC[0] = |NxPN_CYC_BY_T[0];
	assign NxPN_CYC[1] = |NxPN_CYC_BY_T[1];
	assign NxPN_CYC[2] = |NxPN_CYC_BY_T[2];
	assign NxPN_CYC[3] = |NxPN_CYC_BY_T[3];

	
	
	NVRAMAccess_t NBG_A0VA;
	NVRAMAccess_t NBG_A1VA;
	NVRAMAccess_t NBG_B0VA;
	NVRAMAccess_t NBG_B1VA;
	RVRAMAccess_t RBG_A0VA;
	RVRAMAccess_t RBG_A1VA;
	RVRAMAccess_t RBG_B0VA;
	RVRAMAccess_t RBG_B1VA;
	always_comb begin
		NBG_A0VA.PN = |VA_PIPE[0].NxA0PN;
		NBG_A0VA.CH = |VA_PIPE[0].NxA0CH;
		NBG_A0VA.VS = |VA_PIPE[0].NxA0VS;
		NBG_A0VA.Nx = 2'd0;
		if (VA_PIPE[0].NxA0PN[0] || VA_PIPE[0].NxA0CH[0] || VA_PIPE[0].NxA0VS[0]) NBG_A0VA.Nx = 2'd0;
		if (VA_PIPE[0].NxA0PN[1] || VA_PIPE[0].NxA0CH[1] || VA_PIPE[0].NxA0VS[1]) NBG_A0VA.Nx = 2'd1;
		if (VA_PIPE[0].NxA0PN[2] || VA_PIPE[0].NxA0CH[2])                         NBG_A0VA.Nx = 2'd2;
		if (VA_PIPE[0].NxA0PN[3] || VA_PIPE[0].NxA0CH[3])                         NBG_A0VA.Nx = 2'd3;
		
		NBG_A1VA.PN = |VA_PIPE[0].NxA1PN;
		NBG_A1VA.CH = |VA_PIPE[0].NxA1CH;
		NBG_A1VA.VS = |VA_PIPE[0].NxA1VS;
		NBG_A1VA.Nx = 2'd0;
		if (VA_PIPE[0].NxA1PN[0] || VA_PIPE[0].NxA1CH[0] || VA_PIPE[0].NxA1VS[0]) NBG_A1VA.Nx = 2'd0;
		if (VA_PIPE[0].NxA1PN[1] || VA_PIPE[0].NxA1CH[1] || VA_PIPE[0].NxA1VS[1]) NBG_A1VA.Nx = 2'd1;
		if (VA_PIPE[0].NxA1PN[2] || VA_PIPE[0].NxA1CH[2])                         NBG_A1VA.Nx = 2'd2;
		if (VA_PIPE[0].NxA1PN[3] || VA_PIPE[0].NxA1CH[3])                         NBG_A1VA.Nx = 2'd3;
		
		NBG_B0VA.PN = |VA_PIPE[0].NxB0PN;
		NBG_B0VA.CH = |VA_PIPE[0].NxB0CH;
		NBG_B0VA.VS = |VA_PIPE[0].NxB0VS;
		NBG_B0VA.Nx = 2'd0;
		if (VA_PIPE[0].NxB0PN[0] || VA_PIPE[0].NxB0CH[0] || VA_PIPE[0].NxB0VS[0]) NBG_B0VA.Nx = 2'd0;
		if (VA_PIPE[0].NxB0PN[1] || VA_PIPE[0].NxB0CH[1] || VA_PIPE[0].NxB0VS[1]) NBG_B0VA.Nx = 2'd1;
		if (VA_PIPE[0].NxB0PN[2] || VA_PIPE[0].NxB0CH[2])                         NBG_B0VA.Nx = 2'd2;
		if (VA_PIPE[0].NxB0PN[3] || VA_PIPE[0].NxB0CH[3])                         NBG_B0VA.Nx = 2'd3;
		
		
		NBG_B1VA.PN = |VA_PIPE[0].NxB1PN;
		NBG_B1VA.CH = |VA_PIPE[0].NxB1CH;
		NBG_B1VA.VS = |VA_PIPE[0].NxB1VS;
		NBG_B1VA.Nx = 2'd0;
		if (VA_PIPE[0].NxB1PN[0] || VA_PIPE[0].NxB1CH[0] || VA_PIPE[0].NxB1VS[0]) NBG_B1VA.Nx = 2'd0;
		if (VA_PIPE[0].NxB1PN[1] || VA_PIPE[0].NxB1CH[1] || VA_PIPE[0].NxB1VS[1]) NBG_B1VA.Nx = 2'd1;
		if (VA_PIPE[0].NxB1PN[2] || VA_PIPE[0].NxB1CH[2])                         NBG_B1VA.Nx = 2'd2;
		if (VA_PIPE[0].NxB1PN[3] || VA_PIPE[0].NxB1CH[3])                         NBG_B1VA.Nx = 2'd3;
				
		RBG_A0VA.PN = |VA_PIPE[0].RxA0PN;
		RBG_A0VA.CH = |VA_PIPE[0].RxA0CH;
		RBG_A0VA.CT = |VA_PIPE[0].RxA0CT;
		RBG_A0VA.Rx = VA_PIPE[0].RxA0PN[1] | VA_PIPE[0].RxA0CH[1] | VA_PIPE[0].RxA0CT[1];
		
		RBG_A1VA.PN = |VA_PIPE[0].RxA1PN;
		RBG_A1VA.CH = |VA_PIPE[0].RxA1CH;
		RBG_A1VA.CT = |VA_PIPE[0].RxA1CT;
		RBG_A1VA.Rx = VA_PIPE[0].RxA1PN[1] | VA_PIPE[0].RxA1CH[1] | VA_PIPE[0].RxA1CT[1];
		
		RBG_B0VA.PN = |VA_PIPE[0].RxB0PN;
		RBG_B0VA.CH = |VA_PIPE[0].RxB0CH;
		RBG_B0VA.CT = |VA_PIPE[0].RxB0CT;
		RBG_B0VA.Rx = VA_PIPE[0].RxB0PN[1] | VA_PIPE[0].RxB0CH[1] | VA_PIPE[0].RxB0CT[1];
		
		RBG_B1VA.PN = |VA_PIPE[0].RxB1PN;
		RBG_B1VA.CH = |VA_PIPE[0].RxB1CH;
		RBG_B1VA.CT = |VA_PIPE[0].RxB1CT;
		RBG_B1VA.Rx = VA_PIPE[0].RxB1PN[1] | VA_PIPE[0].RxB1CH[1] | VA_PIPE[0].RxB1CT[1];
	end
	
	always_comb begin
		NxOFFX[0] = NXO[0];	//NXO = NX + NSX (S4CHECK_NXO)
		NxOFFX[1] = NXO[1];
		NxOFFX[2] = NXO[2];
		NxOFFX[3] = NXO[3];
		NxOFFY[0] = NMOSY[0] + NVCSY[0];
		NxOFFY[1] = NMOSY[1] + NVCSY[1];
		NxOFFY[2] = NMOSY[2];
		NxOFFY[3] = NMOSY[3];
	end
`ifdef DEBUG
	assign NxOFFX0_DBG = NxOFFX[0];
	assign NxOFFX1_DBG = NxOFFX[1];
	assign NxOFFX2_DBG = NxOFFX[2];
	assign NxOFFX3_DBG = NxOFFX[3];
	assign NxOFFY0_DBG = NxOFFY[0];
	assign NxOFFY1_DBG = NxOFFY[1];
	assign NxOFFY2_DBG = NxOFFY[2];
	assign NxOFFY3_DBG = NxOFFY[3];
`endif
	
	
	// Rotation map registers MPABRA..MPOPRB (16 x {MPx odd, MPx even}) in an MLAB, one copy per read port.
	// RMAP_VALID: written since the last soft reset (RES_N clears the registers: they read as 0 until rewritten).
	function bit [3:0] RxMapIdx(input bit [11:0] RxOFFX, input bit [11:0] RxOFFY, input bit [1:0] RxPLSZ);
		case (RxPLSZ)
			2'b00: return {RxOFFY[10: 9],RxOFFX[10: 9]};
			2'b01: return {RxOFFY[10: 9],RxOFFX[11:10]};
			default: return {RxOFFY[11:10],RxOFFX[11:10]};
		endcase
	endfunction
	function bit [19:1] RxPNAddrM(input bit [11:0] RxOFFX, input bit [11:0] RxOFFY, input bit [8:6] RxMP, input bit [5:0] RxMPv,
	                              input bit [1:0] RxPLSZ, input bit RxCHSZ, input bit RxPNB);
		bit [19: 1] addr;
		bit [ 8: 0] map_addr;
		case (RxPLSZ)
			2'b00: map_addr = {RxMP,RxMPv[5:0]          };
			2'b01: map_addr = {RxMP,RxMPv[5:1],RxOFFX[9]};
			2'b10,
			2'b11: map_addr = {RxMP,RxMPv[5:2],RxOFFY[9],RxOFFX[9]};
		endcase
		case ({RxPNB,RxCHSZ})
			2'b00: addr = {map_addr[5:0],RxOFFY[8:3],RxOFFX[8:3],1'b0};
			2'b01: addr = {map_addr[7:0],RxOFFY[8:4],RxOFFX[8:4],1'b0};
			2'b10: addr = {map_addr[6:0],RxOFFY[8:3],RxOFFX[8:3]};
			2'b11: addr = {map_addr[8:0],RxOFFY[8:4],RxOFFX[8:4]};
		endcase
		return addr;
	endfunction
	bit  [15: 0] RMAP_VALID;
	wire         RMAP_WE = REG_SEL && !WE_N && !DTEN_N && !REQ_N && RES_N && A[8:1] >= 8'h28 && A[8:1] <= 8'h37;
	wire [ 3: 0] RMAP_WA = A[4:1] ^ 4'h8;	//0x050 -> 0 ... 0x06E -> 15
	always @(posedge CLK) begin
		if (!RES_N) RMAP_VALID <= '0;
		else if (RMAP_WE) RMAP_VALID[RMAP_WA] <= 1;
	end
	wire [ 3: 0] RMAP_IDX0 = RxMapIdx(VA_PIPE[0].RxX[VA_PIPE[0].R0RP][11:0], VA_PIPE[0].RxY[VA_PIPE[0].R0RP][11:0], RPxREG[VA_PIPE[0].R0RP].PLSZ);
	wire [ 3: 0] RMAP_IDX1 = RxMapIdx(VA_PIPE[0].RxX[1][11:0], VA_PIPE[0].RxY[1][11:0], RPxREG[1].PLSZ);
	wire [ 3: 0] RMAP_RA0 = {VA_PIPE[0].R0RP,RMAP_IDX0[3:1]};
	wire [ 3: 0] RMAP_RA1 = {1'b1,RMAP_IDX1[3:1]};
	wire [11: 0] RMAP_Q0, RMAP_Q1;
	VDP2_RMAP_RAM rmap0(.CLK(CLK), .WA(RMAP_WA), .D({DI[13:8],DI[5:0]}), .WE(RMAP_WE), .RA(RMAP_RA0), .Q(RMAP_Q0));
	VDP2_RMAP_RAM rmap1(.CLK(CLK), .WA(RMAP_WA), .D({DI[13:8],DI[5:0]}), .WE(RMAP_WE), .RA(RMAP_RA1), .Q(RMAP_Q1));
	wire [ 5: 0] RMAP_V[2];
	assign RMAP_V[0] = !RMAP_VALID[RMAP_RA0] ? 6'h00 : RMAP_IDX0[0] ? RMAP_Q0[11:6] : RMAP_Q0[5:0];
	assign RMAP_V[1] = !RMAP_VALID[RMAP_RA1] ? 6'h00 : RMAP_IDX1[0] ? RMAP_Q1[11:6] : RMAP_Q1[5:0];
	
	PN_t            NBG0_PN_PIPE[2];
	PN_t            NBG1_PN_PIPE[2];
	PN_t            NBG2_PN_PIPE[2];
	PN_t            NBG3_PN_PIPE[2];
	
	bit  [19: 1] NxPN_ADDR[4];
	bit  [19: 1] RxPN_ADDR[2];
	bit  [19: 1] NxCH_ADDR[4];
	bit  [19: 1] RxCH_ADDR[2];
	bit          RxSCRN_OVER[2];
	bit  [19: 1] NxVS_ADDR;
	bit  [19: 1] NxLS_ADDR[2];
	bit  [19: 1] RxRP_ADDR;
	bit  [19: 1] RxCT_ADDR[2];
	bit  [19: 1] RxCTA_ADDR;
	bit  [19: 1] RxCTB_ADDR;
	bit  [19: 1] LW_ADDR[2];
	bit  [19: 1] BS_ADDR;
	bit  [19: 1] LN_ADDR;
	always_comb begin
		bit PN_RP,CH_RP,CT_RP;
		
		PN_RP = VA_PIPE[0].R0RP;
		CH_RP = VA_PIPE[4].R0RP;
		CT_RP = R0_RP;
		
`ifdef CUT_NBG_QTR
		// U2 (CUT_NBG_QTR): NBG0/NBG1 reduction 1/4 (ZMCTL N0ZMQT / N1ZMQT) is cut; ZMQT is read as 0 everywhere
		// (ZMCTL is write-only: REG_DO returns only TVMD, EXTEN, TVSTAT, VRSIZE, HCNT, VCNT and RAMCTL). 1/2 stays.
		NxPN_ADDR[0] = NxPNAddr(NBG_PN_CNT[0], VA_PIPE[0].NxX[0], VA_PIPE[0].NxY[0], NSxREG[0].MP, NSxREG[0].MPn, NSxREG[0].PLSZ, NSxREG[0].CHSZ, NSxREG[0].PNC.NxPNB, NSxREG[0].ZMHF, 1'b0);
		NxPN_ADDR[1] = NxPNAddr(NBG_PN_CNT[1], VA_PIPE[0].NxX[1], VA_PIPE[0].NxY[1], NSxREG[1].MP, NSxREG[1].MPn, NSxREG[1].PLSZ, NSxREG[1].CHSZ, NSxREG[1].PNC.NxPNB, NSxREG[1].ZMHF, 1'b0);
`else
		NxPN_ADDR[0] = NxPNAddr(NBG_PN_CNT[0], VA_PIPE[0].NxX[0], VA_PIPE[0].NxY[0], NSxREG[0].MP, NSxREG[0].MPn, NSxREG[0].PLSZ, NSxREG[0].CHSZ, NSxREG[0].PNC.NxPNB, NSxREG[0].ZMHF, NSxREG[0].ZMQT);
		NxPN_ADDR[1] = NxPNAddr(NBG_PN_CNT[1], VA_PIPE[0].NxX[1], VA_PIPE[0].NxY[1], NSxREG[1].MP, NSxREG[1].MPn, NSxREG[1].PLSZ, NSxREG[1].CHSZ, NSxREG[1].PNC.NxPNB, NSxREG[1].ZMHF, NSxREG[1].ZMQT);
`endif
		NxPN_ADDR[2] = NxPNAddr(2'b00        , VA_PIPE[0].NxX[2], VA_PIPE[0].NxY[2], NSxREG[2].MP, NSxREG[2].MPn, NSxREG[2].PLSZ, NSxREG[2].CHSZ, NSxREG[2].PNC.NxPNB, 1'b0          , 1'b0);
		NxPN_ADDR[3] = NxPNAddr(2'b00        , VA_PIPE[0].NxX[3], VA_PIPE[0].NxY[3], NSxREG[3].MP, NSxREG[3].MPn, NSxREG[3].PLSZ, NSxREG[3].CHSZ, NSxREG[3].PNC.NxPNB, 1'b0          , 1'b0);
		RxPN_ADDR[0] = RxPNAddrM(VA_PIPE[0].RxX[PN_RP][11:0], VA_PIPE[0].RxY[PN_RP][11:0],    RPxREG[PN_RP].MP, RMAP_V[0], RPxREG[PN_RP].PLSZ, RSxREG[0].CHSZ, RSxREG[0].PNC.NxPNB);
		RxPN_ADDR[1] = RxPNAddrM(VA_PIPE[0].RxX[    1][11:0], VA_PIPE[0].RxY[    1][11:0],    RPxREG[1    ].MP, RMAP_V[1], RPxREG[1    ].PLSZ, RSxREG[1].CHSZ, RSxREG[1].PNC.NxPNB);
		
`ifdef CUT_NBG_QTR
		// CUT_NBG_QTR: with ZMQT = 0 NxCHAddr selects PN entries 0/1 only (PN_PIPE[1][2|i], [6|i] were the 1/4 ones)
		NxCH_ADDR[0] = !NSxREG[0].BMEN ? NxCHAddr('{PN_PIPE[1][0],PN_PIPE[1][4],PN_PIPE[1][2],PN_PIPE[1][6]}, NBG_CH_CNT[0], VA_PIPE[4].NxX[0], VA_PIPE[4].NxY[0], NSxREG[0].CHCN, NSxREG[0].CHSZ, NSxREG[0].ZMHF, 1'b0) :
													NxBMAddr(NSxREG[0].MP,                                               NBG_CH_CNT[0], NBG_BM_CNT[0], VA_PIPE[4].NxX[0], VA_PIPE[4].NxY[0], NSxREG[0].CHCN, NSxREG[0].BMSZ, NSxREG[0].ZMHF, 1'b0);
		NxCH_ADDR[1] = !NSxREG[1].BMEN ? NxCHAddr('{PN_PIPE[1][1],PN_PIPE[1][5],PN_PIPE[1][3],PN_PIPE[1][7]}, NBG_CH_CNT[1], VA_PIPE[4].NxX[1], VA_PIPE[4].NxY[1], NSxREG[1].CHCN, NSxREG[1].CHSZ, NSxREG[1].ZMHF, 1'b0) :
													NxBMAddr(NSxREG[1].MP,                                               NBG_CH_CNT[1], NBG_BM_CNT[1], VA_PIPE[4].NxX[1], VA_PIPE[4].NxY[1], NSxREG[1].CHCN, NSxREG[1].BMSZ, NSxREG[1].ZMHF, 1'b0);
`else
		NxCH_ADDR[0] = !NSxREG[0].BMEN ? NxCHAddr('{PN_PIPE[1][0],PN_PIPE[1][4],PN_PIPE[1][2],PN_PIPE[1][6]}, NBG_CH_CNT[0], VA_PIPE[4].NxX[0], VA_PIPE[4].NxY[0], NSxREG[0].CHCN, NSxREG[0].CHSZ, NSxREG[0].ZMHF, NSxREG[0].ZMQT) :
													NxBMAddr(NSxREG[0].MP,                                               NBG_CH_CNT[0], NBG_BM_CNT[0], VA_PIPE[4].NxX[0], VA_PIPE[4].NxY[0], NSxREG[0].CHCN, NSxREG[0].BMSZ, NSxREG[0].ZMHF, NSxREG[0].ZMQT);
		NxCH_ADDR[1] = !NSxREG[1].BMEN ? NxCHAddr('{PN_PIPE[1][1],PN_PIPE[1][5],PN_PIPE[1][3],PN_PIPE[1][7]}, NBG_CH_CNT[1], VA_PIPE[4].NxX[1], VA_PIPE[4].NxY[1], NSxREG[1].CHCN, NSxREG[1].CHSZ, NSxREG[1].ZMHF, NSxREG[1].ZMQT) :
													NxBMAddr(NSxREG[1].MP,                                               NBG_CH_CNT[1], NBG_BM_CNT[1], VA_PIPE[4].NxX[1], VA_PIPE[4].NxY[1], NSxREG[1].CHCN, NSxREG[1].BMSZ, NSxREG[1].ZMHF, NSxREG[1].ZMQT);
`endif
		NxCH_ADDR[2] =                   NxCHAddr2(NBG2_PN_PIPE,                                              NBG_CH_CNT[2], VA_PIPE[4].NxX[2], VA_PIPE[4].NxY[2], NSxREG[2].CHCN, NSxREG[2].CHSZ, 1'b0          , 1'b0);
		NxCH_ADDR[3] =                   NxCHAddr2(NBG3_PN_PIPE,                                              NBG_CH_CNT[3], VA_PIPE[4].NxX[3], VA_PIPE[4].NxY[3], NSxREG[3].CHCN, NSxREG[3].CHSZ, 1'b0          , 1'b0);
		
		RxCH_ADDR[0] = !RSxREG[0].BMEN ? RxCHAddr(RBG_PN_PIPE[1][0], VA_PIPE[4].RxX[CH_RP][11:0], VA_PIPE[4].RxY[CH_RP][11:0], RSxREG[0].CHCN, RSxREG[0].CHSZ) :
													RxBMAddr(RPxREG[CH_RP].MP,  VA_PIPE[4].RxX[CH_RP][11:0], VA_PIPE[4].RxY[CH_RP][11:0], RSxREG[0].CHCN, RSxREG[0].BMSZ);
		RxCH_ADDR[1] =                   RxCHAddr(RBG_PN_PIPE[1][1], VA_PIPE[4].RxX[    1][11:0], VA_PIPE[4].RxY[    1][11:0], RSxREG[1].CHCN, RSxREG[1].CHSZ);
		
		RxSCRN_OVER[0] = RxScreenOver(RPxREG[PN_RP].OVR, VA_PIPE[0].RxX[PN_RP][15:0], VA_PIPE[0].RxY[PN_RP][15:0], RPxREG[PN_RP].PLSZ, RSxREG[0].BMSZ, RSxREG[0].BMEN);
		RxSCRN_OVER[1] = RxScreenOver(RPxREG[    1].OVR, VA_PIPE[0].RxX[    1][15:0], VA_PIPE[0].RxY[    1][15:0], RPxREG[    1].PLSZ, RSxREG[1].BMSZ, RSxREG[1].BMEN);
		
		NxVS_ADDR    = {REGS.VCSTAU.VCSTA,REGS.VCSTAL.VCSTA,1'b0} + {11'h000,VS_OFFS,1'b0};
		
		NxLS_ADDR[0] = NxLSAddr(NSxREG[0].LSTA, LS_TBL_OFFS[0], LS_VAL_OFFS[0]);
		NxLS_ADDR[1] = NxLSAddr(NSxREG[1].LSTA, LS_TBL_OFFS[1], LS_VAL_OFFS[1]);
		
		RxRP_ADDR    = RxRPAddr({REGS.RPTAU.RPTA,REGS.RPTAL.RPTA},{~RP_POS[7],RP_POS[6:2]});
		RxCTA_ADDR   = RxCTAddr(KAst[    0], RxKA[    0], RPxREG[    0].KTAOS, RPxREG[    0].KDBS);
		RxCTB_ADDR   = RxCTAddr(KAst[    1], RxKA[    1], RPxREG[    1].KTAOS, RPxREG[    1].KDBS);
		RxCT_ADDR[0] = CT_RP ? RxCTB_ADDR : RxCTA_ADDR;
		RxCT_ADDR[1] = RxCTB_ADDR;
	end
		
	
	NxPNCNT_t    NBG_PN_CNT;
	bit          NBG_PN_EN[4];
	bit          NBG_PN_FETCH[4];
	NxCHCNT_t    NBG_CH_CNT;
	NxCHCNT_t    NBG_BM_CNT;
	bit          NBG_CH_EN[4];
	bit          RBG_CT_EN[2];
	bit  [ 2: 0] LS_POS;
	bit  [ 3: 2] LS_VAL_OFFS[2];
	bit  [12: 2] LS_TBL_OFFS[2];
	bit          LW_POS;
	bit  [ 6: 0] VS_OFFS;
	bit  [ 7: 2] RP_POS;
	bit  [ 1: 0] VRAM_BANK;
	bit          VRAM_WRITE_PEND_CLR;
	bit          VRAM_RRDY;
	bit          VRAM_WRDY;
	bit          VRAM_WLOCK;
	// shared system fetch (line scroll, line window, rotation parameters, coefficient line A/B, back, line color):
	// all four banks get the same address, in the original priority order
	wire SYS_LS = LS_FETCH && (((NSxREG[0].LSCX ||  NSxREG[0].LSCY || NSxREG[0].LZMX) && !LS_POS[2] && REGS.BGON.N0ON) || ((NSxREG[1].LSCX ||NSxREG[1].LSCY || NSxREG[1].LZMX) && LS_POS[2] && REGS.BGON.N1ON));
	wire SYS_LW = LW_FETCH && (LWE[0] || LWE[1]);
	wire SYS_RP = (RPA_FETCH && REGS.BGON.R0ON && (REGS.RPMD.RPMD[1] || !REGS.RPMD.RPMD[0])) || 
	              (RPB_FETCH && REGS.BGON.R0ON && (REGS.RPMD.RPMD[1] ||  REGS.RPMD.RPMD[0])) || 
	              ((RPA_FETCH || RPB_FETCH) && REGS.BGON.R1ON);
	wire SYS_CTA = (RCTA_FETCH && REGS.BGON.R0ON) || (RCTA_FETCH && REGS.BGON.R1ON);
	wire SYS_CTB = (RCTB_FETCH && REGS.BGON.R0ON) || (RCTB_FETCH && REGS.BGON.R1ON);
	wire SYS_ANY = SYS_LS | SYS_LW | SYS_RP | SYS_CTA | SYS_CTB | BACK_FETCH | LN_FETCH;
	wire [19:1] SYS_ADDR = SYS_LS ? NxLS_ADDR[LS_POS[2]] : SYS_LW ? LW_ADDR[LW_POS] : SYS_RP ? RxRP_ADDR : SYS_CTA ? RxCTA_ADDR :
	                       SYS_CTB ? RxCTB_ADDR : BACK_FETCH ? BS_ADDR : LN_ADDR;
	// per-layer PN / CH hits: layer i's code is in a bank whose number matches the top bits of layer i's address
	bit  NPN_HIT[4], NCH_HIT[4];
	always_comb begin
		for (int g = 0; g < 4; g++) begin
			NPN_HIT[g] = (VA_PIPE[0].NxA0PN[g] && NxPN_ADDR[g][18:17] == 2'b00) || (VA_PIPE[0].NxA1PN[g] && NxPN_ADDR[g][18:17] == 2'b01) ||
			             (VA_PIPE[0].NxB0PN[g] && NxPN_ADDR[g][18:17] == 2'b10) || (VA_PIPE[0].NxB1PN[g] && NxPN_ADDR[g][18:17] == 2'b11);
			NCH_HIT[g] = ((VA_PIPE[0].NxA0CH[g] && NxCH_ADDR[g][18:17] == 2'b00) || (VA_PIPE[0].NxA1CH[g] && NxCH_ADDR[g][18:17] == 2'b01) ||
			              (VA_PIPE[0].NxB0CH[g] && NxCH_ADDR[g][18:17] == 2'b10) || (VA_PIPE[0].NxB1CH[g] && NxCH_ADDR[g][18:17] == 2'b11)) &&
			             (NSxREG[g].BMEN || (VA_PIPE[2].NxPN_FETCH[g] && NxPN_CYC[g]));
		end
	end
	// bank A0: at most one NBG access (one VCP code) and NBG/RBG are exclusive (RDBSx / R0ON / R1ON);
	// RBG accesses keep the original priority (CT over CH over PN: the later assignment won)
	wire A0_NPN = NBG_A0VA.PN && NxPN_ADDR[NBG_A0VA.Nx][18:17] == 2'b00;
	wire A0_NCH = NBG_A0VA.CH && NxCH_ADDR[NBG_A0VA.Nx][18:17] == 2'b00 && ((VA_PIPE[2].NxPN_FETCH[NBG_A0VA.Nx] && NxPN_CYC[NBG_A0VA.Nx]) || NSxREG[NBG_A0VA.Nx].BMEN);
	wire A0_NVS = NBG_A0VA.VS && NxVS_ADDR[18:17] == 2'b00;
	wire A0_RPN = RBG_A0VA.PN && RxPN_ADDR[RBG_A0VA.Rx][18:17] == 2'b00;
	wire A0_RCH = RBG_A0VA.CH && RxCH_ADDR[RBG_A0VA.Rx][18:17] == 2'b00;
	wire A0_RCT = RBG_A0VA.CT && RxCT_ADDR[RBG_A0VA.Rx][18:17] == 2'b00;
	wire A0_HIT = A0_NPN | A0_NCH | A0_NVS | A0_RPN | A0_RCH | A0_RCT;
	wire [19:1] A0_DADDR = A0_RCT ? RxCT_ADDR[RBG_A0VA.Rx] : A0_RCH ? RxCH_ADDR[RBG_A0VA.Rx] : A0_RPN ? RxPN_ADDR[RBG_A0VA.Rx] :
	                        ({19{A0_NPN}} & NxPN_ADDR[NBG_A0VA.Nx]) | ({19{A0_NCH}} & NxCH_ADDR[NBG_A0VA.Nx]) | ({19{A0_NVS}} & NxVS_ADDR);
	// bank A1: at most one NBG access (one VCP code) and NBG/RBG are exclusive (RDBSx / R0ON / R1ON);
	// RBG accesses keep the original priority (CT over CH over PN: the later assignment won)
	wire A1_NPN = NBG_A1VA.PN && NxPN_ADDR[NBG_A1VA.Nx][18:17] == 2'b01;
	wire A1_NCH = NBG_A1VA.CH && NxCH_ADDR[NBG_A1VA.Nx][18:17] == 2'b01 && ((VA_PIPE[2].NxPN_FETCH[NBG_A1VA.Nx] && NxPN_CYC[NBG_A1VA.Nx]) || NSxREG[NBG_A1VA.Nx].BMEN);
	wire A1_NVS = NBG_A1VA.VS && NxVS_ADDR[18:17] == 2'b01;
	wire A1_RPN = RBG_A1VA.PN && RxPN_ADDR[RBG_A1VA.Rx][18:17] == 2'b01;
	wire A1_RCH = RBG_A1VA.CH && RxCH_ADDR[RBG_A1VA.Rx][18:17] == 2'b01;
	wire A1_RCT = RBG_A1VA.CT && RxCT_ADDR[RBG_A1VA.Rx][18:17] == 2'b01;
	wire A1_HIT = A1_NPN | A1_NCH | A1_NVS | A1_RPN | A1_RCH | A1_RCT;
	wire [19:1] A1_DADDR = A1_RCT ? RxCT_ADDR[RBG_A1VA.Rx] : A1_RCH ? RxCH_ADDR[RBG_A1VA.Rx] : A1_RPN ? RxPN_ADDR[RBG_A1VA.Rx] :
	                        ({19{A1_NPN}} & NxPN_ADDR[NBG_A1VA.Nx]) | ({19{A1_NCH}} & NxCH_ADDR[NBG_A1VA.Nx]) | ({19{A1_NVS}} & NxVS_ADDR);
	// bank B0: at most one NBG access (one VCP code) and NBG/RBG are exclusive (RDBSx / R0ON / R1ON);
	// RBG accesses keep the original priority (CT over CH over PN: the later assignment won)
	wire B0_NPN = NBG_B0VA.PN && NxPN_ADDR[NBG_B0VA.Nx][18:17] == 2'b10;
	wire B0_NCH = NBG_B0VA.CH && NxCH_ADDR[NBG_B0VA.Nx][18:17] == 2'b10 && ((VA_PIPE[2].NxPN_FETCH[NBG_B0VA.Nx] && NxPN_CYC[NBG_B0VA.Nx]) || NSxREG[NBG_B0VA.Nx].BMEN);
	wire B0_NVS = NBG_B0VA.VS && NxVS_ADDR[18:17] == 2'b10;
	wire B0_RPN = RBG_B0VA.PN && RxPN_ADDR[RBG_B0VA.Rx][18:17] == 2'b10;
	wire B0_RCH = RBG_B0VA.CH && RxCH_ADDR[RBG_B0VA.Rx][18:17] == 2'b10;
	wire B0_RCT = RBG_B0VA.CT && RxCT_ADDR[RBG_B0VA.Rx][18:17] == 2'b10;
	wire B0_HIT = B0_NPN | B0_NCH | B0_NVS | B0_RPN | B0_RCH | B0_RCT;
	wire [19:1] B0_DADDR = B0_RCT ? RxCT_ADDR[RBG_B0VA.Rx] : B0_RCH ? RxCH_ADDR[RBG_B0VA.Rx] : B0_RPN ? RxPN_ADDR[RBG_B0VA.Rx] :
	                        ({19{B0_NPN}} & NxPN_ADDR[NBG_B0VA.Nx]) | ({19{B0_NCH}} & NxCH_ADDR[NBG_B0VA.Nx]) | ({19{B0_NVS}} & NxVS_ADDR);
	// bank B1: at most one NBG access (one VCP code) and NBG/RBG are exclusive (RDBSx / R0ON / R1ON);
	// RBG accesses keep the original priority (CT over CH over PN: the later assignment won)
	wire B1_NPN = NBG_B1VA.PN && NxPN_ADDR[NBG_B1VA.Nx][18:17] == 2'b11;
	wire B1_NCH = NBG_B1VA.CH && NxCH_ADDR[NBG_B1VA.Nx][18:17] == 2'b11 && ((VA_PIPE[2].NxPN_FETCH[NBG_B1VA.Nx] && NxPN_CYC[NBG_B1VA.Nx]) || NSxREG[NBG_B1VA.Nx].BMEN);
	wire B1_NVS = NBG_B1VA.VS && NxVS_ADDR[18:17] == 2'b11;
	wire B1_RPN = RBG_B1VA.PN && RxPN_ADDR[RBG_B1VA.Rx][18:17] == 2'b11;
	wire B1_RCH = RBG_B1VA.CH && RxCH_ADDR[RBG_B1VA.Rx][18:17] == 2'b11;
	wire B1_RCT = RBG_B1VA.CT && RxCT_ADDR[RBG_B1VA.Rx][18:17] == 2'b11;
	wire B1_HIT = B1_NPN | B1_NCH | B1_NVS | B1_RPN | B1_RCH | B1_RCT;
	wire [19:1] B1_DADDR = B1_RCT ? RxCT_ADDR[RBG_B1VA.Rx] : B1_RCH ? RxCH_ADDR[RBG_B1VA.Rx] : B1_RPN ? RxPN_ADDR[RBG_B1VA.Rx] :
	                        ({19{B1_NPN}} & NxPN_ADDR[NBG_B1VA.Nx]) | ({19{B1_NCH}} & NxCH_ADDR[NBG_B1VA.Nx]) | ({19{B1_NVS}} & NxVS_ADDR);
	always @(posedge CLK or negedge RST_N) begin
		bit DTEN_N_OLD,CS_N_OLD;
		bit VRAMA_ALLOW,VRAMB_ALLOW;
		
		if (!RST_N) begin
			VRAMA0_A <= '0;
			VRAMA1_A <= '0;
			VRAMB0_A <= '0;
			VRAMB1_A <= '0;
			VRAMA_WE <= '0;
			VRAMB_WE <= '0;
			VRAMA0_RD <= 0;
			VRAMA1_RD <= 0;
			VRAMB0_RD <= 0;
			VRAMB1_RD <= 0;
			VRAMA_ALLOW <= 0;
			VRAMB_ALLOW <= 0;
			NBG_PN_CNT <= '{2{'0}};
			NBG_CH_CNT <= '{4{'0}};
			NBG_CH_EN <= '{4{0}};
			RP_POS <= '0;
			LS_POS <= '0;
			
			VRAM_WRITE_PEND <= 0;
			VRAM_READ_PEND <= 0;
			VRAM_RRDY <= 1;
			VRAM_WRDY <= 1;
			VRAM_WLOCK <= 0;
		end else begin
			VRAM_WRITE_PEND_CLR = 0;
			if (DOT_CE_F) begin
				VRAMA_WE <= '0;
				VRAMB_WE <= '0;
				VRAMA0_RD <= 0;
				VRAMA1_RD <= 0;
				VRAMB0_RD <= 0;
				VRAMB1_RD <= 0;
				VRAM_READ_PIPE[0] <= 0;
				if (SYS_ANY) begin
					VRAMA0_A <= {1'b0,SYS_ADDR[16:1]};
					VRAMA1_A <= {     SYS_ADDR[16:1]};
					VRAMB0_A <= {1'b0,SYS_ADDR[16:1]};
					VRAMB1_A <= {     SYS_ADDR[16:1]};
					VRAMA0_RD <= ~SYS_ADDR[18];
					VRAMA1_RD <= ~SYS_ADDR[18];
					VRAMB0_RD <=  SYS_ADDR[18];
					VRAMB1_RD <=  SYS_ADDR[18];
				end else if (REFRESH) begin
					//
				end else if (!DISP_INT || VB_INT || (!REGS.BGON.N0ON && !REGS.BGON.N1ON && !REGS.BGON.N2ON && !REGS.BGON.N3ON && !REGS.BGON.R0ON && !REGS.BGON.R1ON) ||
				             !(NPN_FETCH || NCH_FETCH || NVCS_FETCH || RBG_FETCH || RCH_FETCH || CT_FETCH)) begin
					if (VRAM_WRITE_PEND) begin
						VRAMA0_A <= {VRAM_WA[17:2],1'b0};
						VRAMA1_A <= {VRAM_WA[16:2],1'b0};
						VRAMB0_A <= {VRAM_WA[17:2],1'b0};
						VRAMB1_A <= {VRAM_WA[16:2],1'b0};
						VRAMA_D <= VRAM_D;
						VRAMB_D <= VRAM_D;
						VRAMA_WE <= VRAM_WE & {8{~VRAM_WA[18]}};
						VRAMB_WE <= VRAM_WE & {8{ VRAM_WA[18]}};
						VRAM_WRITE_PEND_CLR = 1;
					end else if (VRAM_READ_PEND) begin 
						VRAMA0_A <= {1'b0,VRAM_RA[16:1]};
						VRAMA1_A <= {     VRAM_RA[16:1]};
						VRAMB0_A <= {1'b0,VRAM_RA[16:1]};
						VRAMB1_A <= {     VRAM_RA[16:1]};
						VRAMA0_RD <= VRAMA0_READ;
						VRAMA1_RD <= VRAMA1_READ;
						VRAMB0_RD <= VRAMB0_READ;
						VRAMB1_RD <= VRAMB1_READ;
						VRAM_READ_PEND <= 0;
						VRAM_READ_PIPE[0] <= 1;
					end
				end else begin		
					for (int i=0; i<4; i++) if (NPN_HIT[i]) NBG_PN_FETCH[i] <= 1;	//was: if (x_NPN) NBG_PN_FETCH[NBG_xVA.Nx] <= 1, per bank
					if (A0_HIT) begin VRAMA0_A <= {1'b0,A0_DADDR[16:1]}; VRAMA0_RD <= 1; end
					
					if (A1_HIT) begin VRAMA1_A <= {     A1_DADDR[16:1]}; VRAMA1_RD <= 1; end
					
					
					VRAMA_ALLOW <= 0;
					if (!NBG_A0VA.PN && !RBG_A0VA.PN && !NBG_A0VA.CH && !RBG_A0VA.CH && !RBG_A0VA.CT && !NBG_A0VA.VS &&
						 !NBG_A1VA.PN && !RBG_A1VA.PN && !NBG_A1VA.CH && !RBG_A1VA.CH && !RBG_A1VA.CT && !NBG_A1VA.VS && !VA_PIPE[0].AxNA) begin
						if (((VRAM_READ_PEND && (VRAMA0_READ || VRAMA1_READ)) || (VRAM_WRITE_PEND && !VRAM_WA[18])) && (VRAMA_ALLOW || !REGS.RAMCTL.VRAMD || VA_PIPE[1].AxNA)) begin
							if (VRAM_WRITE_PEND) begin
								VRAMA0_A <= {VRAM_WA[17:2],1'b0};
								VRAMA_D <= VRAM_D;
								VRAMA_WE <= VRAM_WE;
								VRAM_WRITE_PEND_CLR = 1;
							end else if (VRAM_READ_PEND) begin
								VRAMA0_A <= {1'b0,VRAM_RA[16:1]};
								VRAMA1_A <= {     VRAM_RA[16:1]};
								VRAMA0_RD <= VRAMA0_READ;
								VRAMA1_RD <= VRAMA1_READ;
								VRAM_READ_PIPE[0] <= 1;
								VRAM_READ_PEND <= 0;
							end
						end
						VRAMA_ALLOW <= 1;
					end
					
					if (B0_HIT) begin VRAMB0_A <= {1'b0,B0_DADDR[16:1]}; VRAMB0_RD <= 1; end
					
					if (B1_HIT) begin VRAMB1_A <= {     B1_DADDR[16:1]}; VRAMB1_RD <= 1; end
					
					
					VRAMB_ALLOW <= 0;
					if (!NBG_B0VA.PN && !RBG_B0VA.PN && !NBG_B0VA.CH && !RBG_B0VA.CH && !RBG_B0VA.CT && !NBG_B0VA.VS &&
						 !NBG_B1VA.PN && !RBG_B1VA.PN && !NBG_B1VA.CH && !RBG_B1VA.CH && !RBG_B1VA.CT && !NBG_B1VA.VS && !VA_PIPE[0].BxNA) begin
						if (((VRAM_READ_PEND && (VRAMB0_READ || VRAMB1_READ)) || (VRAM_WRITE_PEND && VRAM_WA[18])) && (VRAMB_ALLOW || !REGS.RAMCTL.VRBMD || VA_PIPE[1].BxNA)) begin
							if (VRAM_WRITE_PEND) begin
								VRAMB0_A <= {VRAM_WA[17:2],1'b0};
								VRAMA_D <= VRAM_D;//////////////////////
								VRAMB_D <= VRAM_D;
								VRAMB_WE <= VRAM_WE;
								VRAM_WRITE_PEND_CLR = 1;
							end else if (VRAM_READ_PEND) begin
								VRAMB0_A <= {1'b0,VRAM_RA[16:1]};
								VRAMB1_A <= {     VRAM_RA[16:1]};
								VRAMB0_RD <= VRAMB0_READ;
								VRAMB1_RD <= VRAMB1_READ;
								VRAM_READ_PIPE[0] <= 1;
								VRAM_READ_PEND <= 0;
							end
						end
						VRAMB_ALLOW <= 1;
					end
				end
				VRAM_READ_PIPE[1] <= VRAM_READ_PIPE[0];
			end
			
			if (DOT_CE_R) begin
				if (LS_FETCH) begin
					VRAM_BANK <= NxLS_ADDR[LS_POS[2]][18:17];
					
					if ((WSCRNY[2:0] & NxLSSMask(NSxREG[{1'b0,LS_POS[2]}].LSS,1'b0) & {2'b11,~DDI}) == 3'b000) begin
						case (LS_POS[1:0])
							2'd0: if (NSxREG[{1'b0,LS_POS[2]}].LSCX) LS_VAL_OFFS[LS_POS[2]] <= LS_VAL_OFFS[LS_POS[2]] + 2'd1;
							2'd1: if (NSxREG[{1'b0,LS_POS[2]}].LSCY) LS_VAL_OFFS[LS_POS[2]] <= LS_VAL_OFFS[LS_POS[2]] + 2'd1;
							2'd2:                                    LS_VAL_OFFS[LS_POS[2]] <= 2'd0;
						endcase
						if (LS_POS[1:0] == 2'd2) begin
							LS_TBL_OFFS[LS_POS[2]] <= LS_TBL_OFFS[LS_POS[2]] + NxLSTblSize(NSxREG[{1'b0,LS_POS[2]}].LSCX,NSxREG[{1'b0,LS_POS[2]}].LSCY,NSxREG[{1'b0,LS_POS[2]}].LZMX,~|NSxREG[{1'b0,LS_POS[2]}].LSS&DDI);
						end
					end
					LS_POS <= LS_POS + 3'd1;
					if (LS_POS[1:0] == 2'd2) LS_POS <= LS_POS + 3'd2;
					VS_OFFS <= '0;
				end else if (LW_FETCH) begin
					VRAM_BANK <= LW_ADDR[LW_POS][18:17];
					LW_POS <= ~LW_POS;
					LW_ADDR[LW_POS] <= LW_ADDR[LW_POS] + (DDI ? 9'd4 : 9'd2);
				end else if (RPA_FETCH || RPB_FETCH) begin
					RP_POS[6:2] <= RP_POS[6:2] + 5'd1;
					if (RP_POS[6:2] == 5'd23) RP_POS <= {~RP_POS[7],5'd0};
					VRAM_BANK <= RxRP_ADDR[18:17];
				end else if (RCTA_FETCH) begin
					VRAM_BANK <= RxCTA_ADDR[18:17];
				end else if (RCTB_FETCH) begin
					VRAM_BANK <= RxCTB_ADDR[18:17];
				end else if (BACK_FETCH) begin
					VRAM_BANK <= BS_ADDR[18:17];
					BS_ADDR <= BS_ADDR + (REGS.BKTAU.BKCLMD ? 19'd1 : 19'd0);
				end else if (LN_FETCH) begin
					VRAM_BANK <= LN_ADDR[18:17];
					LN_ADDR <= LN_ADDR + (REGS.LCTAU.LCCLMD ? 19'd1 : 19'd0);
				end else if (!DISP_INT || VB_INT || (!REGS.BGON.N0ON && !REGS.BGON.N1ON && !REGS.BGON.N2ON && !REGS.BGON.N3ON && !REGS.BGON.R0ON && !REGS.BGON.R1ON)) begin
					
				end else if (NPN_FETCH || NCH_FETCH || RBG_FETCH || RCH_FETCH || CT_FETCH || NVCS_FETCH) begin
					NBG_PN_EN <= '{4{0}};
					NBG_CH_EN <= '{4{0}};
					RBG_CT_EN <= '{2{0}};
					// per-layer form of the four bank sections: a bank holds one VCP code, so "NBG_xVA.PN/CH && NBG_xVA.Nx == i"
					// is VA_PIPE[0].NxxPN/CH[i], and every bank naming layer i compares the same address
					for (int i=0; i<4; i++) begin
						if (NPN_HIT[i]) NBG_PN_EN[i] <= 1;
						if (i < 2 && (VA_PIPE[0].NxA0PN[i] || VA_PIPE[0].NxA1PN[i] || VA_PIPE[0].NxB0PN[i] || VA_PIPE[0].NxB1PN[i])) NBG_PN_CNT[i] <= NBG_PN_CNT[i] + 2'd1;
						if (NCH_HIT[i]) begin
							NBG_CH_EN[i] <= 1;
							NBG_CH_CNT[i] <= NBG_CH_CNT[i] + 3'd1;
						end
						if ((VA_PIPE[0].NxA0CH[i] || VA_PIPE[0].NxA1CH[i] || VA_PIPE[0].NxB0CH[i] || VA_PIPE[0].NxB1CH[i]) && NSxREG[i].BMEN) NBG_BM_CNT[i] <= NBG_BM_CNT[i] + 3'd1;
					end
					if ((NBG_A0VA.VS && NxVS_ADDR[18:17] == 2'b00) || (NBG_A1VA.VS && NxVS_ADDR[18:17] == 2'b01) ||
					    (NBG_B0VA.VS && NxVS_ADDR[18:17] == 2'b10) || (NBG_B1VA.VS && NxVS_ADDR[18:17] == 2'b11)) begin
						VS_OFFS <= VS_OFFS + 1'd1;
					end
					if (RBG_A0VA.CT && RxCT_ADDR[RBG_A0VA.Rx][18:17] == 2'b00) begin
						RBG_CT_EN[RBG_A0VA.Rx] <= 1;
					end
					if (RBG_A1VA.CT && RxCT_ADDR[RBG_A1VA.Rx][18:17] == 2'b01) begin
						RBG_CT_EN[RBG_A1VA.Rx] <= 1;
					end
					if (RBG_B0VA.CT && RxCT_ADDR[RBG_B0VA.Rx][18:17] == 2'b10) begin
						RBG_CT_EN[RBG_B0VA.Rx] <= 1;
					end
					if (RBG_B1VA.CT && RxCT_ADDR[RBG_B1VA.Rx][18:17] == 2'b11) begin
						RBG_CT_EN[RBG_B1VA.Rx] <= 1;
					end
				end
				
				if ((CELLX & ~{HRES[1],2'b00}) == 3'd3) begin
					NBG_CH_CNT <= '{4{'0}};
					NBG_BM_CNT <= '{4{'0}};
				end
				if ((CELLX | {HRES[1],2'b00}) == 3'd7) begin
					NBG_PN_CNT <= '{2{'0}};
				end
				if (NBG_FETCH_START_EN) begin
					NBG_PN_CNT <= '{2{'0}};
					NBG_CH_CNT <= '{4{'0}};
					NBG_BM_CNT <= '{4{'0}};
				end
				
				if (H_CNT == LS_FETCH_START - 2 && IS_LAST_LINE) begin
					LS_POS <= '0;
					LS_VAL_OFFS <= '{2{'0}};
					LS_TBL_OFFS[0] <= !NSxREG[0].LSS && DDI && !ODD ? NxLSTblSize(NSxREG[0].LSCX,NSxREG[0].LSCY,NSxREG[0].LZMX,0) : '0;
					LS_TBL_OFFS[1] <= !NSxREG[1].LSS && DDI && !ODD ? NxLSTblSize(NSxREG[1].LSCX,NSxREG[1].LSCY,NSxREG[1].LZMX,0) : '0;
				end
				
				if (LAST_DOT && IS_PRELAST_LINE) begin
					NBG_PN_FETCH <= '{4{0}};
					LW_POS <= 0;
					LW_ADDR[0] <= {REGS.LWTA0U.WxLWTA,REGS.LWTA0L.WxLWTA,1'b0} + (DDI && !ODD ? 9'd2 : 9'd0);
					LW_ADDR[1] <= {REGS.LWTA1U.WxLWTA,REGS.LWTA1L.WxLWTA,1'b0} + (DDI && !ODD ? 9'd2 : 9'd0);
					BS_ADDR <= {REGS.BKTAU.BKTA,REGS.BKTAL.BKTA};
					LN_ADDR <= {REGS.LCTAU.LCTA,REGS.LCTAL.LCTA};
					RP_POS <= '0;
				end
				
				if (VRAM_READ_PIPE[1]) begin
					VRAMA0_Q <= RA0_Q[31:16];
					VRAMA1_Q <= RA1_Q[31:16];
					VRAMB0_Q <= RB0_Q[31:16];
					VRAMB1_Q <= RB1_Q[31:16];
					VRAM_READ_PIPE[1] <= 0;
					if (!VRAM_RRDY) VRAM_RRDY <= 1;
				end
			end
			
			if (VRAM_REQ && WE_N) begin
				VRAM_RA <= A[18:1];
				VRAM_READ_PEND <= 1;
				VRAM_RRDY <= 0;
			end
			
			if (VRAM_WRITE_PEND_CLR) begin
				VRAM_WRITE_PEND <= 0;
				VRAM_WE <= '0;
				VRAM_WRDY <= 1;
			end
			
			
			//Write single
			if (VRAM_REQ && !WE_N && !DTEN_N && !BURST) begin
				case (A[2:1])
					2'b00: begin
						VRAM_WA <= A[18:1];
						VRAM_D[63:48] <= DI;
						VRAM_WE[7:6] <= ~{2{WE_N}} & ~DQM;
						VRAM_WRITE_PEND <= 1;
					end
					2'b01: begin
						VRAM_WA <= A[18:1];
						VRAM_D[47:32] <= DI;
						VRAM_WE[5:4] <= ~{2{WE_N}} & ~DQM;
						VRAM_WRITE_PEND <= 1;
					end
					2'b10: begin
						VRAM_WA <= A[18:1];
						VRAM_D[31:16] <= DI;
						VRAM_WE[3:2] <= ~{2{WE_N}} & ~DQM;
						VRAM_WRITE_PEND <= 1;
					end
					2'b11: begin
						VRAM_WA <= A[18:1];
						VRAM_D[15:0] <= DI;
						VRAM_WE[1:0] <= ~{2{WE_N}} & ~DQM;
						VRAM_WRITE_PEND <= 1;
					end
				endcase
			end
			
			DTEN_N_OLD <= DTEN_N;
			if (DTEN_N && !DTEN_N_OLD && !BURST) begin
				if (VRAM_WE) VRAM_WRDY <= 0;
			end
			
			//Write burst
			if (!FIFO_EMPTY && !VRAM_WRITE_PEND) begin
				case (FIFO_A[2:1])
					2'b00: begin
						VRAM_WA <= FIFO_A[18:1];
						VRAM_D[63:48] <= FIFO_D;
						VRAM_WE[7:6] <= ~FIFO_DQM;
						VRAM_WRITE_PEND <= FIFO_LAST;
					end
					2'b01: begin
						VRAM_WA <= FIFO_A[18:1];
						VRAM_D[47:32] <= FIFO_D;
						VRAM_WE[5:4] <= ~FIFO_DQM;
						VRAM_WRITE_PEND <= FIFO_LAST;
					end
					2'b10: begin
						VRAM_WA <= FIFO_A[18:1];
						VRAM_D[31:16] <= FIFO_D;
						VRAM_WE[3:2] <= ~FIFO_DQM;
						VRAM_WRITE_PEND <= FIFO_LAST;
					end
					2'b11: begin
						VRAM_WA <= FIFO_A[18:1];
						VRAM_D[15:0] <= FIFO_D;
						VRAM_WE[1:0] <= ~FIFO_DQM;
						VRAM_WRITE_PEND <= 1;
					end
				endcase
			end
			
			CS_N_OLD <= CS_N;
			if (CS_N && !CS_N_OLD) begin
				VRAM_WLOCK <= ~FIFO_EMPTY;
			end
			if (FIFO_EMPTY && VRAM_WRITE_PEND_CLR && VRAM_WLOCK) begin
				VRAM_WLOCK <= 0;
			end
			
			if (!RES_N) begin
				VRAM_WE <= '0;
				VRAM_WRITE_PEND <= 0;
				VRAM_READ_PEND <= 0;
				VRAM_RRDY <= 1;
				VRAM_WRDY <= 1;
				VRAM_WLOCK <= 0;
			end
			//debug
`ifdef DEBUG
			if (VRAM_WRITE_PEND) VRAM_WRITE_PEND_CNT <= VRAM_WRITE_PEND_CNT + 1'd1;
			else VRAM_WRITE_PEND_CNT <= '0;
`endif
		end
	end
	
	bit         FIFO_WRREQ;
	bit         FIFO_RDREQ;
	bit [35: 0] FIFO_Q;
	bit         FIFO_EMPTY;
	bit         FIFO_FULL;
	bit         FIFO_LAST;
	VDP2_WRITE_FIFO fifo(CLK, RES_N, {A[18:1],DQM,DI}, FIFO_WRREQ, FIFO_RDREQ, FIFO_Q, FIFO_EMPTY, FIFO_FULL, FIFO_LAST);
	assign FIFO_WRREQ = VRAM_REQ & ~WE_N & ~DTEN_N & BURST;
	assign FIFO_RDREQ = ~FIFO_EMPTY & ~VRAM_WRITE_PEND;
	wire [18: 1] FIFO_A = FIFO_Q[35:18];
	wire [ 1: 0] FIFO_DQM = FIFO_Q[17:16];
	wire [15: 0] FIFO_D = FIFO_Q[15:0];
	
	assign RA0_A = VRAMA0_A;
	assign RA1_A = VRAMA1_A;
	assign RA_D = VRAMA_D;
	assign RA_WE = VRAMA_WE;
	assign RA_RD = VRAMA0_RD | VRAMA1_RD;
	
	assign RB0_A = VRAMB0_A;
	assign RB1_A = VRAMB1_A;
	assign RB_D = VRAMB_D;
	assign RB_WE = VRAMB_WE;
	assign RB_RD = VRAMB0_RD | VRAMB1_RD;

	wire [15:0] VRAM_DO = VRAMA0_READ ? VRAMA0_Q :
	                      VRAMA1_READ ? VRAMA1_Q :
							    VRAMB0_READ ? VRAMB0_Q :
								 VRAMB1_Q;
								 
	
	bit  [31: 0] RA0_BUF,RA1_BUF,RB0_BUF,RB1_BUF;
	// RA0_BUF..RB1_BUF one dot later (S4CHECK_BUF2). NBG_CH[i] / RBG_CH[i] used to capture the bank buffer selected by
	// NxCHS / RxCHS when BG_PIPE[2].NxCH[i] / RBG_PIPE[2].RxCH[i], and were read only in the following dot, under
	// BG_PIPE[3].NxCH[i] / RBG_PIPE[3].RxCH[i]; reading VBUF2 at BG_PIPE[3].NxCHS / RBG_PIPE[3].RxCHS gives the same word.
	bit  [31: 0] RA0_BUF2,RA1_BUF2,RB0_BUF2,RB1_BUF2;
	bit  [ 1: 0] VRAM_BANK_2;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			// synopsys translate_off
			RA0_BUF <= '0;
			RA1_BUF <= '0;
			RB0_BUF <= '0;
			RB1_BUF <= '0;
			VRAM_BANK_2 <= '0;
			// synopsys translate_on
		end
		else begin
			if (DOT_CE_R) begin
				RA0_BUF <= RA0_Q;
				RA1_BUF <= RA1_Q;
				RB0_BUF <= RB0_Q;
				RB1_BUF <= RB1_Q;
				RA0_BUF2 <= RA0_BUF;
				RA1_BUF2 <= RA1_BUF;
				RB0_BUF2 <= RB0_BUF;
				RB1_BUF2 <= RB1_BUF;
				VRAM_BANK_2 <= VRAM_BANK;
			end
		end
	end
	
	//Scroll data  
	// NXO holds NX + NSX (the X offset the address logic reads) instead of NX alone: NX and NSX change together only
	// at the line-scroll load (NX <= 0, so NXO <= the new NSX), and at a cell step NSX is unchanged (NXO adds what NX
	// added). NSX itself is still kept for NCX (bits 10:0).
	ScrollData_t NXO[4];
	ScrollData_t NSX[4];
	ScrollData_t NY[4];
	ScrollData_t NSY[4];
	ScrollData_t NVCSY[2];
	ScrollData_t NMOSY[4];
	CoordInc_t   LZMX[2];
	always @(posedge CLK or negedge RST_N) begin
		ScrollData_t CX[4];
		bit  [31: 0] LS_WD;
		bit          LS_RD;
		bit          N2;
		bit          SCYN_UPD[4];
		ScrollData_t NSX_N;
		
		if (!RST_N) begin
			// synopsys translate_off
			NXO <= '{4{'0}};
			NSX <= '{4{'0}};
			NY <= '{4{'0}};
			NSY <= '{4{'0}};
			LZMX <= '{2{'0}};
			MOSAIC_VCNT <= '0;
			// synopsys translate_on
		end
		else begin
			if (DOT_CE_R || (DOT_CE_F & HRES[1])) begin
				if (NPN_FETCH) begin
					CX[0] <= CX[0] + LZMX[0];
					CX[1] <= CX[1] + LZMX[1];
					CX[2] <= CX[2] + 19'h00100;
					CX[3] <= CX[3] + 19'h00100;
				end
			end
			
			if (DOT_CE_R) begin
				if (NPN_FETCH && (CELLX | {HRES[1],2'b00}) == 3'd7) begin
					NXO[0] <= NXO[0] + CX[0] + LZMX[0];
					CX[0] <= '0;
					NXO[1] <= NXO[1] + CX[1] + LZMX[1];
					CX[1] <= '0;
					NXO[2] <= NXO[2] + CX[2] + 19'h00100;
					CX[2] <= '0;
					NXO[3] <= NXO[3] + CX[3] + 19'h00100;
					CX[3] <= '0;
				end
				if (NBG_FETCH_START_EN || CELLX == 3'h7) begin
					NVCSY[0] <= VS[0] & {19{NSxREG[0].VCSC&~NSxREG[0].MZE}};
					NVCSY[1] <= VS[1] & {19{NSxREG[1].VCSC&~NSxREG[1].MZE}};
				end
				
				N2 = VA_PIPE[2].LS_POS[2];
				if (VA_PIPE[2].LS) begin
					if (VA_PIPE[2].LS_POS == 3'b000) begin
						MOSAIC_VCNT <= MOSAIC_VCNT + 4'd1;
						if (MOSAIC_VCNT == REGS.MZCTL.MZSZV || IS_LAST_LINE) begin
							MOSAIC_VCNT <= '0;
						end
					end
					
					case (VRAM_BANK_2)
						2'b00: LS_WD = RA0_BUF;
						2'b01: LS_WD = RA1_BUF;
						2'b10: LS_WD = RB0_BUF;
						2'b11: LS_WD = RB1_BUF;
					endcase
					
					LS_RD = ((WSCRNY[2:0] & NxLSSMask(NSxREG[{1'b0,N2}].LSS,1'b0) & {2'b11,~DDI}) == 3'b000);
					case (VA_PIPE[2].LS_POS[1:0])
						2'b00: begin
							if (!NSxREG[{1'b0,N2}].LSCX)              begin NSX_N = NSxREG[{1'b0,N2}].SCX; end
							else if (LS_RD)                           begin NSX_N = NSxREG[{1'b0,N2}].SCX + LS_WD[26:8]; end
							else                                      begin NSX_N = NSX[{1'b0,N2}]; end
							                                                NSX[{1'b0,N2}] <= NSX_N;
							                                                NXO[{1'b0,N2}] <= NSX_N;	//NX <= 0
							
							                                                NXO[{1'b1,N2}] <= NSxREG[{1'b1,N2}].SCX;	//NX <= 0
					                                                      NSX[{1'b1,N2}] <= NSxREG[{1'b1,N2}].SCX;
						end
						2'b01: begin
							if (NSxREG[{1'b0,N2}].LSCY && LS_RD)      begin NSY[{1'b0,N2}] <= NSxREG[{1'b0,N2}].SCY + LS_WD[26:8]; 
							                                                NY[{1'b0,N2}]  <= '0; end
							else 
							if (IS_LAST_LINE || SCYN_UPD[{1'b0,N2}])  begin NSY[{1'b0,N2}] <= NSxREG[{1'b0,N2}].SCY;
							                                                NY[{1'b0,N2}]  <= (!DDI || ODD ? '0 : NSxREG[{1'b0,N2}].ZMY); end
							else                                      begin NY[{1'b0,N2}]  <= NY[{1'b0,N2}] + (!DDI ? NSxREG[{1'b0,N2}].ZMY : NSxREG[{1'b0,N2}].ZMY<<1); end
							SCYN_UPD[{1'b0,N2}] <= 0;
							
							if (IS_LAST_LINE || SCYN_UPD[{1'b1,N2}])  begin NSY[{1'b1,N2}] <= NSxREG[{1'b1,N2}].SCY;
							                                                NY[{1'b1,N2}]  <= (!DDI || ODD ? '0 : 19'h00100); end
					      else                                      begin NY[{1'b1,N2}]  <= NY[{1'b1,N2}] + (!DDI ? 19'h00100 : 19'h00200); end
							SCYN_UPD[{1'b1,N2}] <= 0;
						end
						2'b10: begin
							if (!NSxREG[{1'b0,N2}].LZMX)              begin LZMX[{1'b0,N2}] <= NSxREG[{1'b0,N2}].ZMX; end
							else if (LS_RD)                           begin LZMX[{1'b0,N2}] <= LS_WD[18:8]; end
							
							if (!MOSAIC_VCNT || !NSxREG[{1'b0,N2}].MZE || IS_LAST_LINE) begin
								NMOSY[{1'b0,N2}] <= NY[{1'b0,N2}] + NSY[{1'b0,N2}];
							end
							if (!MOSAIC_VCNT || !NSxREG[{1'b1,N2}].MZE || IS_LAST_LINE) begin
								NMOSY[{1'b1,N2}] <= NY[{1'b1,N2}] + NSY[{1'b1,N2}];
							end
						end
					endcase
				end
			end
			
			if (REG_SEL && !WE_N && !DTEN_N && !REQ_N) begin
				case ({A[8:1],1'b0})
//					9'h074: SCYN_UPD[0] <= 1;
//					9'h076: SCYN_UPD[0] <= 1;
//					9'h084: SCYN_UPD[1] <= 1;
//					9'h086: SCYN_UPD[1] <= 1;
					9'h092: SCYN_UPD[2] <= 1;
					9'h096: SCYN_UPD[3] <= 1;
					default:;
				endcase
			end
		end
	end
	
	//Rotation parameters
	ScrnStart_t  RP_Xst;		//00
	ScrnStart_t  RP_Yst;		//04
	ScrnStart_t  RP_Zst;		//08
	ScrnInc_t    RP_DXst;	//0C
	ScrnInc_t    RP_DYst;	//10
	ScrnInc_t    RP_DX;		//14
	ScrnInc_t    RP_DY;		//18
	MatrParam_t  RP_A;		//1C
	MatrParam_t  RP_B;		//20
	MatrParam_t  RP_C;		//24
	MatrParam_t  RP_D;		//28
	MatrParam_t  RP_E;		//2C
	MatrParam_t  RP_F;		//30
	ScrnCoord_t  RP_PX;		//34
	ScrnCoord_t  RP_PY;		//36
	ScrnCoord_t  RP_PZ;		//38
	ScrnCoord_t  RP_CX;		//3C
	ScrnCoord_t  RP_CY;		//3E
	ScrnCoord_t  RP_CZ;		//40
	Shift_t      RP_MX;		//44
	Shift_t      RP_MY;		//48
	Scalling_t   RP_KX[2];	//4C
	Scalling_t   RP_KY[2];	//50
	TblAddr_t    RP_KAst;	//54
	AddrInc_t    RP_DKAst;	//58
	AddrInc_t    RP_DKAx[2];//5C
	RotCoord_t   Xsp[2],Ysp[2];
	RotCoord_t   Xp[2],Yp[2];
	RotCoord_t   dX[2],dY[2];
	RotCoord_t   Xst[2],Yst[2];
	RotAddr_t    KAx[2],KAy[2];
`ifdef CUT_VDP1_ROT
	// (a1 prototype, Phase 2) The rotation parameter table words the per-line calculation reads (RP_POS[6:2] = 0-18,
	// 21, 22: Xst ... MY, KAst, DKAst; KX, KY, DKAx stay registers: they are read on every dot) are kept in M10K
	// copies, one per read port, instead of 389 flip-flops (FBDO, the only other reader, is cut by CUT_VDP1_ROT).
	// Written as the registers were: same clock edge (DOT_CE_R with RPA / RPB, RST_N high), same word (RP_WD), index
	// RP_POS[6:2]. Read: each port's address follows the current step (VA_PIPE[2].RP_POS[6:2], which only changes on
	// DOT_CE_R edges) and is registered on every clock. A step lasts 8 clk_sys (DOT_CE_R = DOTCLK_DIV 3 & CE_R, CE_R
	// every other clock), so from the step's second clock on each port gives the word as the registers held it during
	// the step: every write up to the previous step's DOT_CE_R edge, and no write of the step itself (which lands on the
	// step's own closing DOT_CE_R edge, after the consumers' last use). No step reads the word it writes.
	wire [31:0] RPT_WD = VRAM_BANK_2 == 2'b00 ? RA0_BUF : VRAM_BANK_2 == 2'b01 ? RA1_BUF : VRAM_BANK_2 == 2'b10 ? RB0_BUF : RB1_BUF;
	wire        RPT_WE = RST_N & DOT_CE_R & (VA_PIPE[2].RPA | VA_PIPE[2].RPB);
	wire  [4:0] RPT_S  = VA_PIPE[2].RP_POS[6:2];
	(* ramstyle = "M10K, no_rw_check" *) bit [31:0] RPT1[32];
	(* ramstyle = "M10K, no_rw_check" *) bit [31:0] RPT2[32];
	(* ramstyle = "M10K, no_rw_check" *) bit [31:0] RPT3[32];
	(* ramstyle = "M10K, no_rw_check" *) bit [31:0] RPT4[32];
	bit   [4:0] RPT_A1, RPT_A2, RPT_A3, RPT_A4;
	always_comb begin
		// port 1: SUB A operand / increments; port 2: SUB B operand / start values / {CX,CY}; port 3: MULXA; port 4: MULYA
		RPT_A1 = 5'd0; RPT_A2 = 5'd0; RPT_A3 = 5'd0; RPT_A4 = 5'd0;
		case (RPT_S)
			5'd04: begin RPT_A1 = 5'd03; RPT_A2 = 5'd00; end                                   //DXst, Xst
			5'd05: begin RPT_A1 = 5'd04; RPT_A2 = 5'd01; end                                   //DYst, Yst
			5'd12: begin RPT_A1 = 5'd05; RPT_A3 = 5'd07; RPT_A4 = 5'd10; end                   //DX, A, D
			5'd13: begin RPT_A1 = 5'd06; RPT_A3 = 5'd08; RPT_A4 = 5'd11; end                   //DY, B, E
			5'd14: begin RPT_A2 = 5'd13; RPT_A3 = 5'd07; RPT_A4 = 5'd10; end                   //PX, A, D
			5'd15: begin RPT_A2 = 5'd13; RPT_A3 = 5'd08; RPT_A4 = 5'd11; end                   //PY, B, E
			5'd16: begin RPT_A1 = 5'd02; RPT_A2 = 5'd14; RPT_A3 = 5'd09; RPT_A4 = 5'd12; end   //Zst, PZ, C, F
			5'd17: begin RPT_A1 = 5'd13; RPT_A2 = 5'd15; RPT_A3 = 5'd07; RPT_A4 = 5'd10; end   //PX, {CX,CY}, A, D
			5'd18: begin RPT_A1 = 5'd13; RPT_A2 = 5'd15; RPT_A3 = 5'd08; RPT_A4 = 5'd11; end   //PY, CY, B, E
			5'd19: begin RPT_A1 = 5'd14; RPT_A2 = 5'd16; RPT_A3 = 5'd09; RPT_A4 = 5'd12; end   //PZ, CZ, C, F
			5'd20: begin RPT_A3 = 5'd17; RPT_A4 = 5'd18; end                                   //MX, MY
			5'd23: begin RPT_A3 = 5'd21; RPT_A4 = 5'd22; end                                   //KAst, DKAst
			default: ;
		endcase
	end
	bit  [31:0] RPT_Q1, RPT_Q2, RPT_Q3, RPT_Q4;
	always @(posedge CLK) begin
		if (RPT_WE) begin
			RPT1[RPT_S] <= RPT_WD; RPT2[RPT_S] <= RPT_WD; RPT3[RPT_S] <= RPT_WD; RPT4[RPT_S] <= RPT_WD;
		end
		RPT_Q1 <= RPT1[RPT_A1]; RPT_Q2 <= RPT2[RPT_A2]; RPT_Q3 <= RPT3[RPT_A3]; RPT_Q4 <= RPT4[RPT_A4];
	end
`endif
	always @(posedge CLK or negedge RST_N) begin
		bit  [31: 0] RP_WD,RCT_WD;
		bit          CT_RP;
		CT_t         CT_D;
		RotCoord_t   SUBXA,SUBXB;
		RotCoord_t   SUBYA,SUBYB;
		RotCoord_t   MULXA;
		RotCoord_t   MULYA;
		RotCoord_t   SUMX,ACCX;
		RotCoord_t   SUMY,ACCY;
		RotCoord_t   ADD1;
		RotCoord_t   MULT1,MULT2;
		RotCoord_t   RES;
		RotCoord_t   RES_LATCH[4];
		bit          N;
		
		if (!RST_N) begin
			// synopsys translate_off
			// synopsys translate_on
			Xsp <= '{2{RC_NULL}};
			Ysp <= '{2{RC_NULL}};
			Xp <= '{2{RC_NULL}};
			Yp <= '{2{RC_NULL}};
			dX <= '{2{RC_NULL}};
			dY <= '{2{RC_NULL}};
			Xst <= '{2{RC_NULL}};
			Yst <= '{2{RC_NULL}};
		end
		else begin
			if (DOT_CE_R) begin
				N = ~VA_PIPE[2].RP_POS[7];
				case (VRAM_BANK_2)
					2'b00: RP_WD = RA0_BUF;
					2'b01: RP_WD = RA1_BUF;
					2'b10: RP_WD = RB0_BUF;
					2'b11: RP_WD = RB1_BUF;
				endcase
				if (VA_PIPE[2].RPA || VA_PIPE[2].RPB) begin
					case (VA_PIPE[2].RP_POS[6:2])
`ifndef CUT_VDP1_ROT
						5'd00: RP_Xst <= RP_WD;
						5'd01: RP_Yst <= RP_WD;
						5'd02: RP_Zst <= RP_WD;
						5'd03: RP_DXst <= RP_WD;
						5'd04: RP_DYst <= RP_WD;
						5'd05: RP_DX <= RP_WD;
						5'd06: RP_DY <= RP_WD;
						5'd07: RP_A <= RP_WD;
						5'd08: RP_B <= RP_WD;
						5'd09: RP_C <= RP_WD;
						5'd10: RP_D <= RP_WD;
						5'd11: RP_E <= RP_WD;
						5'd12: RP_F <= RP_WD;
						5'd13: {RP_PX,RP_PY} <= RP_WD;
						5'd14: RP_PZ <= RP_WD[31:16];
						5'd15: {RP_CX,RP_CY} <= RP_WD;
						5'd16: RP_CZ <= RP_WD[31:16];
						5'd17: RP_MX <= RP_WD;
						5'd18: RP_MY <= RP_WD;
						5'd21: RP_KAst <= RP_WD;
						5'd22: RP_DKAst <= RP_WD;
`endif
						5'd19: RP_KX[N] <= RP_WD;
						5'd20: RP_KY[N] <= RP_WD;
						5'd23: RP_DKAx[N] <= RP_WD;
					endcase
				end
				
				if (VA_PIPE[2].RCTA) begin
					CTD[0] <= CTData(RPxREG[0].KMD, RPxREG[0].KDBS, RP_WD);
				end
				if (VA_PIPE[2].RCTB) begin
					CTD[1] <= CTData(RPxREG[1].KMD, RPxREG[1].KDBS, RP_WD);
				end

`ifdef CUT_VDP2_CRKTE
				if (RBG_PIPE[2].RxCT[0]) begin	//CUT_VDP2_CRKTE: coefficient words from VRAM only
					CT_RP = R0RP_PIPE[2];
					if (RBG_PIPE[1].RxCT_EN[0]) 
						case (RBG_PIPE[2].RxCTS[0])
							2'd0: RCT_WD = RA0_BUF;
							2'd1: RCT_WD = RA1_BUF;
							2'd2: RCT_WD = RB0_BUF;
							2'd3: RCT_WD = RB1_BUF;
						endcase
					else
						RCT_WD = '0;
`else
				if (RBG_PIPE[2].RxCT[0] || RBG_PIPE[2].RxCRCT[0]) begin
					CT_RP = R0RP_PIPE[2];
					if (RBG_PIPE[2].RxCT[0]) 
						if (RBG_PIPE[1].RxCT_EN[0]) 
							case (RBG_PIPE[2].RxCTS[0])
								2'd0: RCT_WD = RA0_BUF;
								2'd1: RCT_WD = RA1_BUF;
								2'd2: RCT_WD = RB0_BUF;
								2'd3: RCT_WD = RB1_BUF;
							endcase
						else
							RCT_WD = '0;
					else
						RCT_WD = CT_CRAM_Q;
`endif
						
					CT_D = CTData(RPxREG[CT_RP].KMD, RPxREG[CT_RP].KDBS, RCT_WD);
					CTD[0] <= CT_D;
					if (CT_RP) CTD[1] <= CT_D;
				end
				
				SUMX = $signed(ACCX) + $signed(MultRC(MULXA, ($signed(SUBXA) - $signed(SUBXB))));
				SUMY = $signed(ACCY) + $signed(MultRC(MULYA, ($signed(SUBXA) - $signed(SUBXB))));
				
				ACCX <= SUMX;
				ACCY <= SUMY;
				if (VA_PIPE[2].RPA || VA_PIPE[2].RPB) begin
					case (VA_PIPE[2].RP_POS[6:2])
						5'd04: begin 
							Xst[N] <= $signed(Xst[N]) + $signed(ScrnIncToRC(ScrnInc_t'(RPT_Q1)));
							if (IS_LAST_LINE) begin
								Xst[N] <= ScrnStartToRC(ScrnStart_t'(RPT_Q2));
							end
						end
						5'd05: begin 
							Yst[N] <= $signed(Yst[N]) + $signed(ScrnIncToRC(ScrnInc_t'(RPT_Q1)));
							if (IS_LAST_LINE) begin
								Yst[N] <= ScrnStartToRC(ScrnStart_t'(RPT_Q2));
							end
						end
						
						5'd12: begin 																				//sumx = 0 + (A * (РћвЂќX - 0)), sumy = 0 + (D * (РћвЂќX - 0))
							SUBXA <= ScrnIncToRC(ScrnInc_t'(RPT_Q1)); SUBXB <= RC_NULL; 								//sub = РћвЂќX - 0
							SUBYA <= ScrnIncToRC(ScrnInc_t'(RPT_Q1)); SUBYB <= RC_NULL; 								//sub = РћвЂќX - 0
							MULXA <= MatrParamToRC(MatrParam_t'(RPT_Q3));														//multx = A * sub
							MULYA <= MatrParamToRC(MatrParam_t'(RPT_Q4));														//multy = D * sub
							ACCX <= '0; 																		//accx = 0
							ACCY <= '0; 																		//accy = 0
						end
						5'd13: begin 																				//sumx = accx + (B * (РћвЂќY - 0)), sumy = 0 + (E * (РћвЂќY - 0))
							SUBXA <= ScrnIncToRC(ScrnInc_t'(RPT_Q1)); SUBXB <= RC_NULL; 								//sub = РћвЂќY - 0
							SUBYA <= ScrnIncToRC(ScrnInc_t'(RPT_Q1)); SUBYB <= RC_NULL; 								//sub = РћвЂќY - 0
							MULXA <= MatrParamToRC(MatrParam_t'(RPT_Q3));														//multx = B * sub
							MULYA <= MatrParamToRC(MatrParam_t'(RPT_Q4)); 													//multy = E * sub
						end
						5'd14: begin 
							dX[N] <= SUMX;																			//dX = accx + multx
							dY[N] <= SUMY;																			//dY = accy + multy
							SUBXA <= Xst[N]; SUBXB <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[31:16]));								//sub = Xst - Px
							SUBYA <= Xst[N]; SUBYB <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[31:16]));								//sub = Xst - Px
							MULXA <= MatrParamToRC(MatrParam_t'(RPT_Q3));														//multx = A * sub
							MULYA <= MatrParamToRC(MatrParam_t'(RPT_Q4)); 													//multy = D * sub
							ACCX <= RC_NULL; 																		//accx = 0
							ACCY <= RC_NULL; 																		//accy = 0
						end
						5'd15: begin 
							SUBXA <= Yst[N]; SUBXB <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[15:0]));								//sub = Yst - Py
							SUBYA <= Yst[N]; SUBYB <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[15:0]));								//sub = Yst - Py
							MULXA <= MatrParamToRC(MatrParam_t'(RPT_Q3));														//multx = B * sub
							MULYA <= MatrParamToRC(MatrParam_t'(RPT_Q4)); 													//multy = E * sub
						end
						5'd16: begin 
							SUBXA <= ScrnStartToRC(ScrnStart_t'(RPT_Q1)); SUBXB <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[31:16]));			//sub = Zst - Pz
							SUBYA <= ScrnStartToRC(ScrnStart_t'(RPT_Q1)); SUBYB <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[31:16]));			//sub = Zst - Pz
							MULXA <= MatrParamToRC(MatrParam_t'(RPT_Q3));														//multx = C * sub
							MULYA <= MatrParamToRC(MatrParam_t'(RPT_Q4)); 													//multy = F * sub
						end
						5'd17: begin 
							Xsp[N] <= SUMX;																		//Xsp = accx + multx
							Ysp[N] <= SUMY;																		//Ysp = accy + multy
							SUBXA <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q1[31:16])); SUBXB <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[31:16]));			//sub = Px - Cx
							SUBYA <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q1[31:16])); SUBYB <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[31:16]));			//sub = Px - Cx
							MULXA <= MatrParamToRC(MatrParam_t'(RPT_Q3)); 													//multx = A * sub
							MULYA <= MatrParamToRC(MatrParam_t'(RPT_Q4));														//multy = D * sub
							ACCX <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[31:16])); 													//accx = Cx
							ACCY <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[15:0])); 													//accy = Cy
						end
						5'd18: begin 
							SUBXA <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q1[15:0])); SUBXB <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[15:0]));			//sub = Py - Cy
							SUBYA <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q1[15:0])); SUBYB <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[15:0]));			//sub = Py - Cy
							MULXA <= MatrParamToRC(MatrParam_t'(RPT_Q3));														//multx = B * sub
							MULYA <= MatrParamToRC(MatrParam_t'(RPT_Q4));												 		//multy = E * sub
						end
						5'd19: begin 
							SUBXA <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q1[31:16])); SUBXB <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[31:16]));			//sub = Py - Cy
							SUBYA <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q1[31:16])); SUBYB <= ScrnCoordToRC(ScrnCoord_t'(RPT_Q2[31:16]));			//sub = Py - Cy
							MULXA <= MatrParamToRC(MatrParam_t'(RPT_Q3));														//multx = C * sub
							MULYA <= MatrParamToRC(MatrParam_t'(RPT_Q4));														//multy = F * sub
						end
						5'd20: begin 
							SUBXA <= RC_ONE; SUBXB <= RC_NULL;												//sub = 1 - 0
							SUBYA <= RC_ONE; SUBYB <= RC_NULL;												//sub = 1 - 0
							MULXA <= ShiftToRC(Shift_t'(RPT_Q3));															//multx = Mx * 1
							MULYA <= ShiftToRC(Shift_t'(RPT_Q4));															//multy = My * 1
						end
						5'd21: begin 
							Xp[N] <= SUMX;																			//Xp = accx + multx
							Yp[N] <= SUMY;																			//Yp = accy + multy
							SUBXA <= RC_NULL; SUBXB <= RC_NULL;												//
							SUBYA <= RC_NULL; SUBYB <= RC_NULL;												//
							MULXA <= RC_NULL; 																	//
							MULYA <= RC_NULL; 					 												//
							ACCX <= RC_NULL; 																		//accx = 0
							ACCY <= RC_NULL; 																		//accy = 0
						end
						5'd22: begin 
						end
						5'd23: begin
							KAst[N] <= TblAddrToRC(TblAddr_t'(RPT_Q3));
							KAy[N] <= $signed(KAy[N]) + $signed(AddrIncToRA(AddrInc_t'(RPT_Q4)));
							if (IS_LAST_LINE) begin
								KAy[N] <= '0;
							end
							KAx[N] <= '0;
						end
					endcase
				end
				
`ifdef CUT_VDP2_CRKTE
				if (VA_PIPE[0].RxA0CT[0] || VA_PIPE[0].RxA1CT[0] || VA_PIPE[0].RxB0CT[0] || VA_PIPE[0].RxB1CT[0]) begin	//CUT_VDP2_CRKTE
`else
				if (VA_PIPE[0].RxA0CT[0] || VA_PIPE[0].RxA1CT[0] || VA_PIPE[0].RxB0CT[0] || VA_PIPE[0].RxB1CT[0] || VA_PIPE[0].RxCRCT[0]) begin
`endif
					KAx[0] <= $signed(KAx[0]) + $signed(AddrIncToRA(RP_DKAx[0]));
					KAx[1] <= $signed(KAx[1]) + $signed(AddrIncToRA(RP_DKAx[1]));
				end
				
				if (RBG_CALC) begin
					Xsp[0] <= $signed(Xsp[0]) + $signed(dX[0]);
					Ysp[0] <= $signed(Ysp[0]) + $signed(dY[0]);
					Xsp[1] <= $signed(Xsp[1]) + $signed(dX[1]);
					Ysp[1] <= $signed(Ysp[1]) + $signed(dY[1]);
				end
			end
				
			case (DOTCLK_DIV)
				2'd0: begin
					ADD1 = Xp[0];
					if (RPxREG[0].KTE && !RPxREG[0].KMD[1])
						MULT1 = {CTD[0].INT,CTD[0].FRAC};
					else
						MULT1 = ScallingToRC(RP_KX[0]);
					MULT2 = Xsp[0];
				end
				2'd1: begin
					ADD1 = Yp[0];
					if (RPxREG[0].KTE && !RPxREG[0].KMD[0])
						MULT1 = {CTD[0].INT,CTD[0].FRAC};
					else
						MULT1 = ScallingToRC(RP_KY[0]);
					MULT2 = Ysp[0];
				end
				2'd2: begin
					ADD1 = Xp[1];
					if (RPxREG[1].KTE && !RPxREG[1].KMD[1])
						MULT1 = {CTD[1].INT,CTD[1].FRAC};
					else
						MULT1 = ScallingToRC(RP_KX[1]);
					MULT2 = Xsp[1];
				end
				2'd3: begin
					ADD1 = Yp[1];
					if (RPxREG[1].KTE && !RPxREG[1].KMD[0])
						MULT1 = {CTD[1].INT,CTD[1].FRAC};
					else
						MULT1 = ScallingToRC(RP_KY[1]);
					MULT2 = Ysp[1];
				end
			endcase
			RES = $signed(ADD1) + $signed(MultRC(MULT1,MULT2));
			
			if (CE_R) begin
				RES_LATCH[DOTCLK_DIV] <= RES;
			end
			
			if (DOT_CE_R) begin
				if (RBG_CALC) begin
					RxX[0] <= RES_LATCH[0];
					RxY[0] <= RES_LATCH[1];
					RxX[1] <= RES_LATCH[2];
					RxY[1] <= RES;
					RPxLCSD[0] <= CTD[0].LCSD;
					RPxLCSD[1] <= CTD[1].LCSD;
				end
				RxCTTP[0] <= REGS.RPMD.RPMD == 2'b10 && CTD[0].TP ? CTD[1].TP & RPxREG[1].KTE : CTD[R0RP_PIPE[3]].TP & RPxREG[R0RP_PIPE[3]].KTE;
				RxCTTP[1] <=                                                                    CTD[           1].TP & RPxREG[           1].KTE;
				R0RPMSB <= CTD[0].TP;
			end
`ifdef DEBUG
			RPK_DBG = MULT1;
`endif
		end
	end
	assign RxKA[0] = $signed(KAy[0]) + $signed(KAx[0]);
	assign RxKA[1] = $signed(KAy[1]) + $signed(KAx[1]);
				
	//Rotattion parameter window
	wire RPW0_HIT = W0_HIT_PIPE[3*2+1];
	wire RPW1_HIT = W1_HIT_PIPE[3*2+1];
	wire RPW_EN = WinTest(RPW0_HIT ^ REGS.WCTLD.RPW0A, RPW1_HIT ^ REGS.WCTLD.RPW1A, 0, REGS.WCTLD.RPW0E, REGS.WCTLD.RPW1E, 0, REGS.WCTLD.RPLOG);
	
	//Rotattion parameter select
	wire R0_RP = !REGS.RPMD.RPMD[1] ? REGS.RPMD.RPMD[0] : 
	             !REGS.RPMD.RPMD[0] ? 1'b0 : RPW_EN;
					 
	bit          R0RP_PIPE[4];
	bit  [ 6: 0] RPxLCSD_PIPE[9];
	bit          RPxKLCE_PIPE[9];
	// (a1 prototype, Phase 2) RPxLCSD_PIPE / RPxKLCE_PIPE are read at stage 8 only: stages 1-7 were a plain delay line.
	// An 8-slot M10K ring takes stage 0's value on the pipeline's edges (DOT_CE_R, RST_N high; slot LCD_W, which then
	// advances) and stage 8 (still a register) loads the word written seven such edges earlier (slot LCD_W - 7, read on
	// every clock; a step lasts 8 clk_sys). Power-up: all 0.
	(* ramstyle = "M10K, no_rw_check" *) bit [7:0] LCD_RAM[8];
	bit   [2:0] LCD_W = 3'd0;
	bit   [7:0] LCD_Q = '0;
	always @(posedge CLK) begin
		if (RST_N && DOT_CE_R) begin
			LCD_RAM[LCD_W] <= {RPxLCSD[R0_RP], RPxREG[R0_RP].KLCE};
			LCD_W <= LCD_W + 3'd1;
		end
		LCD_Q <= LCD_RAM[LCD_W + 3'd1];		//slot LCD_W - 7
	end
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			// synopsys translate_off
			R0RP_PIPE <= '{4{0}};
			RPxLCSD_PIPE <= '{9{'0}};
			RPxKLCE_PIPE <= '{9{0}};
			// synopsys translate_on
		end
		else begin
			if (DOT_CE_R) begin
				R0RP_PIPE[0] <= R0_RP;
				for (int i=0; i<3; i++) begin
					R0RP_PIPE[i+1] <= R0RP_PIPE[i];
				end
				
				RPxLCSD_PIPE[0] = RPxLCSD[R0_RP];
				RPxKLCE_PIPE[0] = RPxREG[R0_RP].KLCE;
				for (int i=0; i<8; i++) begin
					RPxLCSD_PIPE[i+1] <= RPxLCSD_PIPE[i];
					RPxKLCE_PIPE[i+1] <= RPxKLCE_PIPE[i];
				end
				{RPxLCSD_PIPE[8], RPxKLCE_PIPE[8]} <= LCD_Q;	//(a1) stage 8 from the ring (stages 1-7 unread)
			end
		end
	end
	
`ifdef CUT_VDP1_ROT
	// U1 (CUT_VDP1_ROT): the export of the rotation parameters to VDP1 is cut. FBDO only feeds VDP1's VOUTI,
	// which only VDP1's rotation frame-buffer read-out (TVMR.TVM1) reads, and that is cut by the same macro.
	assign FBDO = '0;
`else
	wire [8:0] FBD_HSTART = !HRES[0] ? 9'h18B : 9'h1A8;
	always @(posedge CLK or negedge RST_N) begin
		bit  [6:0] HPOS_PIPE;
		
		if (!RST_N) begin
			HPOS_PIPE <= '0;
			FBDO <= '0;
		end
		else begin
			if (DOT_CE_R) begin
				HPOS_PIPE <= {HPOS_PIPE[5:0],1'b0};
				if (H_CNT == FBD_HSTART - 1 - 1) HPOS_PIPE[0] <= 1;
				
				if (HPOS_PIPE[0])
					FBDO <= RP_Xst[31:16];
				else if (HPOS_PIPE[1])
					FBDO <= RP_Yst[31:16];
				else if (HPOS_PIPE[2])
					FBDO <= RP_DXst[31:16];
				else if (HPOS_PIPE[3])
					FBDO <= RP_DYst[31:16];
				else if (HPOS_PIPE[4])
					FBDO <= RP_DX[31:16];
				else if (HPOS_PIPE[5])
					FBDO <= RP_DY[31:16];
			end
			
			if (DOT_CE_F) begin
				if (HPOS_PIPE[1])
					FBDO <= RP_Xst[15:0];
				else if (HPOS_PIPE[2])
					FBDO <= RP_Yst[15:0];
				else if (HPOS_PIPE[3])
					FBDO <= RP_DXst[15:0];
				else if (HPOS_PIPE[4])
					FBDO <= RP_DYst[15:0];
				else if (HPOS_PIPE[5])
					FBDO <= RP_DX[15:0];
				else if (HPOS_PIPE[6])
					FBDO <= RP_DY[15:0];
			end
		end
	end
`endif
	
	//Windows
	wire [ 9: 0] WPSX[2] = '{REGS.WPSX0.WxSX,REGS.WPSX1.WxSX};
	wire [ 9: 0] WPEX[2] = '{REGS.WPEX0.WxEX,REGS.WPEX1.WxEX};
	wire         LWE[2] = '{REGS.LWTA0U.WxLWE,REGS.LWTA1U.WxLWE};
	bit  [ 9: 0] WxSX[2];
	bit  [ 9: 0] WxEX[2];
	always @(posedge CLK or negedge RST_N) begin
		bit          N;
		bit  [31: 0] LW_WD;
		
		if (!RST_N) begin
			// synopsys translate_off
			WxSX <= '{2{'0}};
			WxEX <= '{2{'0}};
			// synopsys translate_on
		end
		else begin
			if (DOT_CE_R) begin
				if (VA_PIPE[2].LW) begin
					N = VA_PIPE[2].LW_POS;
					case (VRAM_BANK_2)
						2'b00: LW_WD = RA0_BUF;
						2'b01: LW_WD = RA1_BUF;
						2'b10: LW_WD = RB0_BUF;
						2'b11: LW_WD = RB1_BUF;
					endcase
					
					if (LWE[N]) begin
						WxSX[N] <= LW_WD[25:16];
						WxEX[N] <= LW_WD[9:0];
					end else begin
						WxSX[N] <= WPSX[N];
						WxEX[N] <= WPEX[N];
					end 
				end
			end
		end
	end
	wire [ 8: 0] WxSY[2] = '{REGS.WPSY0.WxSY,REGS.WPSY1.WxSY};
	wire [ 8: 0] WxEY[2] = '{REGS.WPEY0.WxEY,REGS.WPEY1.WxEY};
	
	wire W0_HIT = ({SCRNX,SCRNX0&HRES[1]} >= {WxSX[0][9:1],WxSX[0][0]&HRES[1]} || WxSX[0][9:0] >= 10'h360) && {SCRNX,SCRNX0&HRES[1]} <= {WxEX[0][9:1],WxEX[0][0]&HRES[1]} && {WxEX[0][9:1],WxEX[0][0]&HRES[1]} < 10'h360 && {WxEX[0][9:1],WxEX[0][0]&HRES[1]} != 10'h2EC &&
	             (((WSCRNY                >=  WxSY[0][8:0]                                               ) && WSCRNY                 <=  WxEY[0][8:0]                     && WxSY[0][8:0] != 9'h1FE && WxEY[0][8:0] < 9'h1FE) || (WxEY[0][8:0] >= (VRES == 2'b00 ? 9'h0F0 : 9'h100) && WxEY[0][8:0] <= 9'h1ED && !DDI));
	wire W1_HIT = ({SCRNX,SCRNX0&HRES[1]} >= {WxSX[1][9:1],WxSX[1][0]&HRES[1]} || WxSX[1][9:0] >= 10'h360) && {SCRNX,SCRNX0&HRES[1]} <= {WxEX[1][9:1],WxEX[1][0]&HRES[1]} && {WxEX[1][9:1],WxEX[1][0]&HRES[1]} < 10'h360 && {WxEX[1][9:1],WxEX[1][0]&HRES[1]} != 10'h2EC &&
	             (((WSCRNY                >=  WxSY[1][8:0]                                               ) && WSCRNY                 <=  WxEY[1][8:0]                     && WxSY[1][8:0] != 9'h1FE && WxEY[1][8:0] < 9'h1FE) || (WxEY[1][8:0] >= (VRES == 2'b00 ? 9'h0F0 : 9'h100) && WxEY[1][8:0] <= 9'h1ED && !DDI));
					  
	bit          W0_HIT_PIPE[17*2];
	bit          W1_HIT_PIPE[17*2];
	// (a1 prototype, Phase 2) W0/W1_HIT_PIPE are read at stages 7, 32 and 33: stages 8-31 were a plain delay line. A
	// 64-slot M10K ring takes stage 0's input (W0_HIT, W1_HIT) on the pipeline's edges (DOT_CE_R or DOT_CE_F, RST_N high;
	// slot WHP_W, which then advances) and stage 32 (still a register) loads the word written 32 such edges earlier
	// (slot WHP_W - 32, read on every clock; the edges are 4 clk_sys apart). Power-up: all 0.
	(* ramstyle = "M10K, no_rw_check" *) bit [1:0] WHP_RAM[64];
	bit   [5:0] WHP_W = 6'd0;
	bit   [1:0] WHP_Q = '0;
	always @(posedge CLK) begin
		if (RST_N && (DOT_CE_R || DOT_CE_F)) begin
			WHP_RAM[WHP_W] <= {W1_HIT, W0_HIT};
			WHP_W <= WHP_W + 6'd1;
		end
		WHP_Q <= WHP_RAM[WHP_W - 6'd32];		//slot WHP_W - 32
	end
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			// synopsys translate_off
			W0_HIT_PIPE <= '{17*2{0}};
			W1_HIT_PIPE <= '{17*2{0}};
			// synopsys translate_on
		end
		else begin
			if (DOT_CE_R || DOT_CE_F) begin
				W0_HIT_PIPE[0] <= W0_HIT;
				W1_HIT_PIPE[0] <= W1_HIT;
				for (int i=0; i<(17*2)-1; i++) begin
					W0_HIT_PIPE[i+1] <= W0_HIT_PIPE[i];
					W1_HIT_PIPE[i+1] <= W1_HIT_PIPE[i];
				end
				{W1_HIT_PIPE[32], W0_HIT_PIPE[32]} <= WHP_Q;	//(a1) stage 32 from the ring (stages 8-31 unread)
			end
		end
	end
	
	//Back & line screen  
	bit  [23: 0] BACK_DC;
	bit  [10: 0] LINE_PAL;
	always @(posedge CLK or negedge RST_N) begin
		bit  [15: 0] WD;
		
		if (!RST_N) begin
			BACK_DC <= '0;
			LINE_PAL <= '0;
		end
		else begin
			if (DOT_CE_R) begin
				case (VRAM_BANK_2)
					2'b00: WD = RA0_BUF[31:16];
					2'b01: WD = RA1_BUF[31:16];
					2'b10: WD = RB0_BUF[31:16];
					2'b11: WD = RB1_BUF[31:16];
				endcase
				
				if (VA_PIPE[2].BS) begin
					BACK_DC <= Color555To888(WD[14:0]);
				end
				if (!DISP_INT && !REGS.TVMD.BDCLMD) begin
					BACK_DC <= DC_NULL;
				end
				
				if (VA_PIPE[2].LN) begin
					LINE_PAL <= WD[10:0];
				end
				
				if (DOT_FETCH) begin
					if (RPxKLCE_PIPE[8]) LINE_PAL[6:0] <= RPxLCSD_PIPE[8];
				end
			end
		end
	end
					
	//BG data
	wire [31: 0] VBUF2[4] = '{RA0_BUF2,RA1_BUF2,RB0_BUF2,RB1_BUF2};
	
	PNPipe_t        PN_PIPE;
	CellParam_t     NBG_CDP[8];
	// NBG cell dot capture, time-shared over the dot period (R2). NBG_CDC[0..3] (8 bytes per layer) used to be written
	// at DOT_CE_R, up to 8 bytes or nibbles at once, and was read only by the NDC ring writes, byte j = NDC_WB at clock j.
	// Now each DOT_CE_R capture only records, per layer, what it would write: the CH word (CDC_W) and a write plan
	// (CDC_PM mode, CDC_PF flip, CDC_PC count), decided from the same inputs at the same edge as before. NBG_CDC itself
	// lives in CDC_RAM (8 x 32 MLAB, word j = bytes j of layers 3..0): in the next dot period byte j of each layer is
	// rewritten at clock NDC_WB = j from its old value and the plan (CdcByte); the result also feeds the ring write of
	// that clock. Between two DOT_CE_R every j comes once (DOTCLK_DIV 0..3 with CE_R/CE_F alternating; a soft-reset
	// stall repeats j = 0/1, and applying a plan again gives the same byte), so at clock j the formatter output equals
	// the byte NBG_CDC[k][j] the original held (S5CHECK_CDC).
	bit  [ 2: 0]    CDC_PM[4];	//0 none, 1 low nibbles, 2 high nibbles, 3 bytes (8 bpp), 4 byte pairs (16 bpp), 5 one byte (32 bpp)
	bit             CDC_PF[4];
	bit  [ 2: 0]    CDC_PC[4];
	bit  [31: 0]    CDC_W[4];
	RPNPipe_t       RBG_PN_PIPE;
	bit             RBG_TP_PIPE[5][2];
	// NBG pattern-name word capture, one datapath per layer pair: NBG0/NBG1 capture only at DOTCLK_DIV 3 and
	// NBG2/NBG3 only at DOTCLK_DIV 1, so the bank-word select and PNData of NBG0 serve NBG2 and those of NBG1 serve NBG3
	PN_t            PND_G[2];
	always_comb begin
		bit [ 1: 0] s;
		bit [31: 0] w;
		PNCNx_t     pnc;
		bit         chsz;
		bit [ 2: 0] chcn;
		for (int g=0; g<2; g++) begin
			s    = DOTCLK_DIV[1] ? BG_PIPE[2].NxPNS[g]  : BG_PIPE[2].NxPNS[g+2];
			pnc  = DOTCLK_DIV[1] ? NSxREG[g].PNC        : NSxREG[g+2].PNC;
			chsz = DOTCLK_DIV[1] ? NSxREG[g].CHSZ       : NSxREG[g+2].CHSZ;
			chcn = DOTCLK_DIV[1] ? NSxREG[g].CHCN       : NSxREG[g+2].CHCN;
			case (s)
				2'd0: w = RA0_BUF;
				2'd1: w = RA1_BUF;
				2'd2: w = RB0_BUF;
				2'd3: w = RB1_BUF;
			endcase
			PND_G[g] = !pnc.NxPNB ? w : PNData(pnc, chsz, chcn, w[31:16]);
		end
	end
	bit  [ 7: 0]    RBG_DC[2][4];
	CellParam_t     RBG_CDP[2];
	// (a1 prototype, Phase 2) PN_PIPE entries 1-7 and both RBG_PN_PIPE entries are read at stage 1 and stage 4 only
	// (entry 0 of PN_PIPE also at stages 2 and 3: it stays in the register pipeline), and stage 4 reads only PALN, HF,
	// PR and CC. Stages 2-3 of those entries were a plain delay line: here a 4-slot M10K ring carries the four fields
	// instead, written with PN_PIPE[0] / RBG_PN_PIPE[0] on the pipeline's own edges (DOT_CE_R, RST_N high; slot PND_W,
	// which then advances); stage 4 (still registers) loads the word written three such edges earlier (slot PND_W - 3,
	// read on every clock: a step lasts 8 clk_sys). The fields stage 4 never reads (VF, CHRN, the unused bits) are 0
	// there now. Power-up: RAM, pointer and pipeline all 0.
	function automatic bit [9:0] PNF(input PN_t pn); return {pn.PALN, pn.HF, pn.PR, pn.CC}; endfunction
	function automatic PN_t PNU(input bit [9:0] f); PN_t r; r = '0; {r.PALN, r.HF, r.PR, r.CC} = f; return r; endfunction
	(* ramstyle = "M10K, no_rw_check" *) bit [89:0] PND_RAM[4];
	bit   [1:0] PND_W = 2'd0;
	bit  [89:0] PND_Q = '0;
	wire [89:0] PND_D = {PNF(PN_PIPE[0][7]), PNF(PN_PIPE[0][6]), PNF(PN_PIPE[0][5]), PNF(PN_PIPE[0][4]), PNF(PN_PIPE[0][3]),
	                     PNF(PN_PIPE[0][2]), PNF(PN_PIPE[0][1]), PNF(RBG_PN_PIPE[0][1]), PNF(RBG_PN_PIPE[0][0])};
	always @(posedge CLK) begin
		if (RST_N && DOT_CE_R) begin
			PND_RAM[PND_W] <= PND_D;
			PND_W <= PND_W + 2'd1;
		end
		PND_Q <= PND_RAM[PND_W + 2'd1];		//slot PND_W - 3
	end
	always @(posedge CLK or negedge RST_N) begin
		bit [31: 0] PN_WD[4];
		bit [ 1: 0] NCHSEL[4];	//bank of the CH word NCH[k] reads (was NBG_CH[source])
		bit [31: 0] VS_WD[2];
		bit [31: 0] LS_WD[2];
		bit [ 1: 0] PN_CNT[4];
		bit [ 3: 0] NCNT[4];
		bit         NHF[8];
		bit         NPR[8];
		bit         NCC[8];
		bit [ 6: 0] NPALN[8];
		bit [31: 0] NCH[4];
		bit [ 2: 0] NCHCN[4];
		bit         NCHEN[4];
		bit         NEN[4];
		bit [ 2: 0] RCNT[2];
		bit         RHF[2];
		bit         RPR[4];
		bit         RCC[4];
		bit [ 6: 0] RPALN[2];
		bit [31: 0] RCH[2];
		bit         RTP[2];
		bit [ 2: 0] RCELLX[2];
		bit [31: 0] RPN_WD[2];
		bit [31: 0] RCT_WD[2];
		
		bit         PN_RP;
		bit         CH_RP;
		bit         RPN_OVR;
		NxPND_t     PN4_D;		//(a1) PN_PIPE[4] next
		RxPND_t     RPN4_D;		//(a1) RBG_PN_PIPE[4] next
//		bit         CT_RP;
		
		
		if (!RST_N) begin
			// synopsys translate_off
			NBG_CDL[0] <= '{8{'0}};
			NBG_CDL[1] <= '{8{'0}};
			NBG_CDL[2] <= '{8{'0}};
			NBG_CDL[3] <= '{8{'0}};
			RBG_CDL[0] <= '{8{'0}};
			RBG_CDL[1] <= '{8{'0}};
			// synopsys translate_on
		end
		else begin
			//NBG0,NBG1,NBG2,NBG3
			for (int i=0; i<4; i++) begin
				BG_PIPE[0].NxPN[i] = VA_PIPE[0].NxA0PN[i] | VA_PIPE[0].NxA1PN[i] | VA_PIPE[0].NxB0PN[i] | VA_PIPE[0].NxB1PN[i];
				BG_PIPE[0].NxPNS[i] = VA_PIPE[0].NxA0PN[i] && NxPN_ADDR[NBG_A0VA.Nx][18:17] == 2'b00 ? 2'd0 : 
									       VA_PIPE[0].NxA1PN[i] && NxPN_ADDR[NBG_A1VA.Nx][18:17] == 2'b01 ? 2'd1 : 
									       VA_PIPE[0].NxB0PN[i] && NxPN_ADDR[NBG_B0VA.Nx][18:17] == 2'b10 ? 2'd2 : 
									       2'd3;
				BG_PIPE[0].NxCH[i] = VA_PIPE[0].NxA0CH[i] | VA_PIPE[0].NxA1CH[i] | VA_PIPE[0].NxB0CH[i] | VA_PIPE[0].NxB1CH[i];
				BG_PIPE[0].NxCHS[i] = VA_PIPE[0].NxA0CH[i] && NxCH_ADDR[NBG_A0VA.Nx][18:17] == 2'b00 ? 2'd0 : 
									       VA_PIPE[0].NxA1CH[i] && NxCH_ADDR[NBG_A1VA.Nx][18:17] == 2'b01 ? 2'd1 : 
									       VA_PIPE[0].NxB0CH[i] && NxCH_ADDR[NBG_B0VA.Nx][18:17] == 2'b10 ? 2'd2 : 
									       2'd3;
				if (i < 2) begin
					BG_PIPE[0].NxVS[i] = VA_PIPE[0].NxA0VS[i] | VA_PIPE[0].NxA1VS[i] | VA_PIPE[0].NxB0VS[i] | VA_PIPE[0].NxB1VS[i];
					BG_PIPE[0].NxVSS[i] = VA_PIPE[0].NxA0VS[i] && NxVS_ADDR[18:17] == 2'b00 ? 2'd0 : 
										       VA_PIPE[0].NxA1VS[i] && NxVS_ADDR[18:17] == 2'b01 ? 2'd1 : 
										       VA_PIPE[0].NxB0VS[i] && NxVS_ADDR[18:17] == 2'b10 ? 2'd2 : 
										       2'd3;		 
					BG_PIPE[0].NxPN_CNT[i] = NBG_PN_CNT[i];
				end
				BG_PIPE[0].NxPN_EN[i] = NBG_PN_EN[i];
				BG_PIPE[0].NxCH_CNT[i] = NBG_CH_CNT[i];
				BG_PIPE[0].NxCH_EN[i] = NBG_CH_EN[i];
			end
			
			if (CE_R) begin
				for (int i=0; i<4; i++) begin
					if (BG_PIPE[2].NxPN[i] && BG_PIPE[1].NxPN_EN[i]) begin
						
						
						if (i <= 1) begin
							PN_CNT[i] = BG_PIPE[2].NxPN_CNT[i];
							if (DOTCLK_DIV == 2'd3) begin
`ifdef CUT_NBG_QTR
								PN_PIPE[0][{NSxREG[i].ZMHF&PN_CNT[i][0],2'b00}|i] <= PND_G[i & 1];	//DOTCLK_DIV 3: layer i (CUT_NBG_QTR: no 1/4 entries 2|i, 6|i)
`else
								PN_PIPE[0][{(NSxREG[i].ZMQT|NSxREG[i].ZMHF)&PN_CNT[i][0],NSxREG[i].ZMQT&PN_CNT[i][1],1'b0}|i] <= PND_G[i & 1];	//DOTCLK_DIV 3: layer i
`endif
							end
						end else begin
							PN_CNT[i] = 0;
							if (DOTCLK_DIV == 2'd1/*(!BG_PIPE[2].NxPNS[i][1] && DOTCLK_DIV == 2'd1) || (BG_PIPE[2].NxPNS[i][1] && DOTCLK_DIV == 2'd3)*/) begin
								PN_PIPE[0][i] <= PND_G[i & 1];	//DOTCLK_DIV 1: layer i (i-2)
							end
						end
					end
				end
			end
//			
			if (DOT_CE_R) begin
				for (int i=0; i<2; i++) begin
					if (BG_PIPE[2].NxVS[i]) begin
						case (BG_PIPE[2].NxVSS[i])
							2'd0: VS_WD[i] = RA0_BUF;
							2'd1: VS_WD[i] = RA1_BUF;
							2'd2: VS_WD[i] = RB0_BUF;
							2'd3: VS_WD[i] = RB1_BUF;
						endcase
						VS[i].INT  <= VS_WD[i][26:16];
						VS[i].FRAC <= VS_WD[i][15: 8];
					end
				end
				
				
				
//				if (NBG_FETCH_START_EN) begin
//					NBG_CDC[0] <= '{8{'0}}; NBG_CDP[0] <= CDP_NULL; NBG_CDP[4] <= CDP_NULL; NBG_CDP[6] <= CDP_NULL;
//					NBG_CDC[1] <= '{8{'0}}; NBG_CDP[1] <= CDP_NULL; NBG_CDP[5] <= CDP_NULL; NBG_CDP[7] <= CDP_NULL;
//					NBG_CDC[2] <= '{8{'0}}; NBG_CDP[2] <= CDP_NULL; 
//					NBG_CDC[3] <= '{8{'0}}; NBG_CDP[3] <= CDP_NULL; 
//				end
					
				NEN[3] = 0;
				if (BG_PIPE[3].NxCH[0] && NSxREG[0].CHCN[2]) begin
					NCNT[3] = BG_PIPE[3].NxCH_CNT[0];
					NPALN[3] = !NSxREG[0].BMEN ? PN_PIPE[4][0].PALN : {NSxREG[0].BMP,4'b0000}; NPALN[7] = !NSxREG[0].BMEN ? PN_PIPE[4][7].PALN : {NSxREG[0].BMP,4'b0000};
					NHF[3] = !NSxREG[0].BMEN ? PN_PIPE[4][0].HF : 1'b0;                        NHF[7] = !NSxREG[0].BMEN ? PN_PIPE[4][7].HF : 1'b0;
					NPR[3] = !NSxREG[0].BMEN ? PN_PIPE[4][0].PR : NSxREG[0].BMPR;              NPR[7] = !NSxREG[0].BMEN ? PN_PIPE[4][7].PR : NSxREG[0].BMPR;
					NCC[3] = !NSxREG[0].BMEN ? PN_PIPE[4][0].CC : NSxREG[0].BMCC;              NCC[7] = !NSxREG[0].BMEN ? PN_PIPE[4][7].CC : NSxREG[0].BMCC;
					NCHSEL[3] = BG_PIPE[3].NxCHS[0];
					NCHCN[3] = NSxREG[0].CHCN;
					NCHEN[3] = BG_PIPE[2].NxCH_EN[0];
					NEN[3] = BG_PIPE[3].NxCH[0];
				end else if (BG_PIPE[3].NxCH[1] && NSxREG[1].CHCN[1]) begin
					NCNT[3] = BG_PIPE[3].NxCH_CNT[1];
					NPALN[3] = !NSxREG[1].BMEN ? PN_PIPE[4][1].PALN : {NSxREG[1].BMP,4'b0000}; NPALN[7] = !NSxREG[1].BMEN ? PN_PIPE[4][7].PALN : {NSxREG[1].BMP,4'b0000};
					NHF[3] = !NSxREG[1].BMEN ? PN_PIPE[4][1].HF : 1'b0;                        NHF[7] = !NSxREG[1].BMEN ? PN_PIPE[4][7].HF : 1'b0;
					NPR[3] = !NSxREG[1].BMEN ? PN_PIPE[4][1].PR : NSxREG[1].BMPR;              NPR[7] = !NSxREG[1].BMEN ? PN_PIPE[4][7].PR : NSxREG[1].BMPR;
					NCC[3] = !NSxREG[1].BMEN ? PN_PIPE[4][1].CC : NSxREG[1].BMCC;              NCC[7] = !NSxREG[1].BMEN ? PN_PIPE[4][7].CC : NSxREG[1].BMCC;
					NCHSEL[3] = BG_PIPE[3].NxCHS[1];
					NCHCN[3] = {1'b0,NSxREG[1].CHCN[1:0]};
					NCHEN[3] = BG_PIPE[2].NxCH_EN[1];
					NEN[3] = BG_PIPE[3].NxCH[1];
`ifdef CUT_NBG_QTR
				end else if (BG_PIPE[3].NxCH[1] && NSxREG[1].CHCN == 3'b001 && NSxREG[1].ZMHF) begin	//CUT_NBG_QTR: NBG1 8bpp 1/2 only (4bpp 1/4 cut)
`else
				end else if (BG_PIPE[3].NxCH[1] && ((NSxREG[1].CHCN == 3'b000 && NSxREG[1].ZMQT) || 
																(NSxREG[1].CHCN == 3'b001 && NSxREG[1].ZMHF))) begin
`endif
					NCNT[3] = BG_PIPE[3].NxCH_CNT[1];
					NPALN[3] = !NSxREG[1].BMEN ? PN_PIPE[4][5].PALN : {NSxREG[1].BMP,4'b0000}; NPALN[7] = !NSxREG[1].BMEN ? PN_PIPE[4][7].PALN : {NSxREG[1].BMP,4'b0000};
					NHF[3] = !NSxREG[1].BMEN ? PN_PIPE[4][5].HF : 1'b0;                        NHF[7] = !NSxREG[1].BMEN ? PN_PIPE[4][7].HF : 1'b0;
					NPR[3] = !NSxREG[1].BMEN ? PN_PIPE[4][5].PR : NSxREG[1].BMPR;              NPR[7] = !NSxREG[1].BMEN ? PN_PIPE[4][7].PR : NSxREG[1].BMPR;
					NCC[3] = !NSxREG[1].BMEN ? PN_PIPE[4][5].CC : NSxREG[1].BMCC;              NCC[7] = !NSxREG[1].BMEN ? PN_PIPE[4][7].CC : NSxREG[1].BMCC;
					NCHSEL[3] = BG_PIPE[3].NxCHS[1];
					NCHCN[3] = {2'b00,NSxREG[1].CHCN[0]};
					NCHEN[3] = BG_PIPE[2].NxCH_EN[1];
					NEN[3] = BG_PIPE[3].NxCH[1];
				end else begin
					NCNT[3] = BG_PIPE[3].NxCH_CNT[3];
					NPALN[3] = !NSxREG[3].BMEN ? PN_PIPE[4][3].PALN : {NSxREG[3].BMP,4'b0000}; NPALN[7] = !NSxREG[3].BMEN ? PN_PIPE[4][7].PALN : {NSxREG[3].BMP,4'b0000};
					NHF[3] = !NSxREG[3].BMEN ? PN_PIPE[4][3].HF : 1'b0;                        NHF[7] = !NSxREG[3].BMEN ? PN_PIPE[4][7].HF : 1'b0;
					NPR[3] = !NSxREG[3].BMEN ? PN_PIPE[4][3].PR : NSxREG[3].BMPR;              NPR[7] = !NSxREG[3].BMEN ? PN_PIPE[4][7].PR : NSxREG[3].BMPR;
					NCC[3] = !NSxREG[3].BMEN ? PN_PIPE[4][3].CC : NSxREG[3].BMCC;              NCC[7] = !NSxREG[3].BMEN ? PN_PIPE[4][7].CC : NSxREG[3].BMCC;
					NCHSEL[3] = BG_PIPE[3].NxCHS[3];
					NCHCN[3] = {2'b00,NSxREG[3].CHCN[0]};
					NCHEN[3] = BG_PIPE[2].NxCH_EN[3];
					NEN[3] = BG_PIPE[3].NxCH[3];
				end
				NCH[3] = VBUF2[NCHSEL[3]];
				// write plan of NBG_CDC[3] (applied byte by byte in the next dot period, see CDC_RAM)
				CDC_PM[3] <= 3'd0; CDC_PF[3] <= 1'b0; CDC_PC[3] <= NCNT[3]; CDC_W[3] <= NCH[3];
				if (NEN[3] && NCHEN[3]) begin
					case (NCHCN[3])
						3'b000: begin				//4bits/dot, 16 colors
`ifdef CUT_NBG_QTR
							if (!NCNT[3][2] && NCNT[3][1:0] == 2'b00) begin	//CUT_NBG_QTR: no NBG1 1/4 nibble plans (mode 2 / second low nibbles)
							CDC_PM[3] <= 3'd1; CDC_PF[3] <= NHF[3];	//low nibbles
							end
`else
							if (!NCNT[3][2] && NCNT[3][0] == 2'b11 && NSxREG[1].ZMQT && NSxREG[1].ON) begin
							CDC_PM[3] <= 3'd2; CDC_PF[3] <= NHF[7];	//high nibbles
							end else if (!NCNT[3][2] && ((NCNT[3][1:0] == 2'b00 && !(NSxREG[1].ZMQT && NSxREG[1].ON)) || (NCNT[3][1:0] == 2'b10 && NSxREG[1].ZMQT && NSxREG[1].ON))) begin
							CDC_PM[3] <= 3'd1; CDC_PF[3] <= NHF[3];	//low nibbles
							end
`endif
						end
						3'b001: begin				//8bits/dot, 256 colors
							if (!NCNT[3][2] && ((NCNT[3][1] == 1'b0 && !(NSxREG[1].CHCN == 3'b001 && NSxREG[1].ZMHF && NSxREG[1].ON)) || (NCNT[3][1] == 1'b1 && NSxREG[1].ZMHF && NSxREG[1].ON))) begin
							CDC_PM[3] <= 3'd3; CDC_PF[3] <= NHF[3];	//bytes {NCNT[0],x}
							end
						end
						3'b010,3'b011: begin				//16bits/dot, 2048/32768 colors
							if (!NCNT[3][2]) begin
							CDC_PM[3] <= 3'd4; CDC_PF[3] <= NHF[1];	//bytes {NCNT[1:0],x}: NCH[3][31:24], [15:8]
							end
						end
						3'b100: begin				//32bits/dot, 16M colors
							CDC_PM[3] <= 3'd5;	//byte NCNT: NCH[3][31:24]
						end
						default:;
					endcase
				end
				if (NEN[3] && NCHEN[3]) begin
					case (NCHCN[3])
						3'b000: begin				//4bits/dot, 16 colors
`ifdef CUT_NBG_QTR
							if (!NCNT[3][2] && NCNT[3][1:0] == 2'b00) begin	//CUT_NBG_QTR: NBG_CDP[7] (NBG1 1/4) is gone
							NBG_CDP[3] <= {NPR[3], NCC[3], NPALN[3], 1'b0};
							end
`else
							if (!NCNT[3][2] && NCNT[3][0] == 2'b11 && NSxREG[1].ZMQT && NSxREG[1].ON) begin
							NBG_CDP[7] <= {NPR[7], NCC[7], NPALN[7], 1'b0};
							end else if (!NCNT[3][2] && ((NCNT[3][1:0] == 2'b00 && !(NSxREG[1].ZMQT && NSxREG[1].ON)) || (NCNT[3][1:0] == 2'b10 && NSxREG[1].ZMQT && NSxREG[1].ON))) begin
							NBG_CDP[3] <= {NPR[3], NCC[3], NPALN[3], 1'b0};
							end
`endif
						end
						3'b001: begin				//8bits/dot, 256 colors
							if (!NCNT[3][2] && ((NCNT[3][1] == 1'b0 && !(NSxREG[1].CHCN == 3'b001 && NSxREG[1].ZMHF && NSxREG[1].ON)) || (NCNT[3][1] == 1'b1 && NSxREG[1].ZMHF && NSxREG[1].ON))) begin
							NBG_CDP[3] <= {NPR[3], NCC[3], NPALN[3], 1'b0};
							end
						end
						3'b010,3'b011: begin				//16bits/dot, 2048 colors
							
						end
						3'b100: begin				//32bits/dot, 16M colors
							
						end
						default:;
					endcase
				end
				
				NEN[2] = 0;
				if (BG_PIPE[3].NxCH[0] && NSxREG[0].CHCN[2:1]) begin
					NCNT[2] = BG_PIPE[3].NxCH_CNT[0];
					NPALN[2] = !NSxREG[0].BMEN ? PN_PIPE[4][0].PALN : {NSxREG[0].BMP,4'b0000}; NPALN[6] = !NSxREG[0].BMEN ? PN_PIPE[4][6].PALN : {NSxREG[0].BMP,4'b0000};
					NHF[2] = !NSxREG[0].BMEN ? PN_PIPE[4][0].HF : 1'b0;                        NHF[6] = !NSxREG[0].BMEN ? PN_PIPE[4][6].HF : 1'b0;
					NPR[2] = !NSxREG[0].BMEN ? PN_PIPE[4][0].PR : NSxREG[0].BMPR;              NPR[6] = !NSxREG[0].BMEN ? PN_PIPE[4][6].PR : NSxREG[0].BMPR;
					NCC[2] = !NSxREG[0].BMEN ? PN_PIPE[4][0].CC : NSxREG[0].BMCC;              NCC[6] = !NSxREG[0].BMEN ? PN_PIPE[4][6].CC : NSxREG[0].BMCC;
					NCHSEL[2] = BG_PIPE[3].NxCHS[0];
					NCHCN[2] = NSxREG[0].CHCN;
					NCHEN[2] = BG_PIPE[2].NxCH_EN[0];
					NEN[2] = BG_PIPE[3].NxCH[0];
`ifdef CUT_NBG_QTR
				end else if (BG_PIPE[3].NxCH[0] && NSxREG[0].CHCN == 3'b001 && NSxREG[0].ZMHF) begin	//CUT_NBG_QTR: NBG0 8bpp 1/2 only (4bpp 1/4 cut)
`else
				end else if (BG_PIPE[3].NxCH[0] && ((NSxREG[0].CHCN == 3'b000 && NSxREG[0].ZMQT) || 
																(NSxREG[0].CHCN == 3'b001 && NSxREG[0].ZMHF))) begin
`endif
					NCNT[2] = BG_PIPE[3].NxCH_CNT[0];
					NPALN[2] = !NSxREG[0].BMEN ? PN_PIPE[4][4].PALN : {NSxREG[0].BMP,4'b0000}; NPALN[6] = !NSxREG[0].BMEN ? PN_PIPE[4][6].PALN : {NSxREG[0].BMP,4'b0000};
					NHF[2] = !NSxREG[0].BMEN ? PN_PIPE[4][4].HF : 1'b0;                        NHF[6] = !NSxREG[0].BMEN ? PN_PIPE[4][6].HF : 1'b0;
					NPR[2] = !NSxREG[0].BMEN ? PN_PIPE[4][4].PR : NSxREG[0].BMPR;              NPR[6] = !NSxREG[0].BMEN ? PN_PIPE[4][6].PR : NSxREG[0].BMPR;
					NCC[2] = !NSxREG[0].BMEN ? PN_PIPE[4][4].CC : NSxREG[0].BMCC;              NCC[6] = !NSxREG[0].BMEN ? PN_PIPE[4][6].CC : NSxREG[0].BMCC;
					NCHSEL[2] = BG_PIPE[3].NxCHS[0];
					NCHCN[2] = NSxREG[0].CHCN;
					NCHEN[2] = BG_PIPE[2].NxCH_EN[0];
					NEN[2] = BG_PIPE[3].NxCH[0];
				end else begin
					NCNT[2] = BG_PIPE[3].NxCH_CNT[2];
					NPALN[2] = !NSxREG[2].BMEN ? PN_PIPE[4][2].PALN : {NSxREG[2].BMP,4'b0000}; NPALN[6] = !NSxREG[2].BMEN ? PN_PIPE[4][2].PALN : {NSxREG[2].BMP,4'b0000};
					NHF[2] = !NSxREG[2].BMEN ? PN_PIPE[4][2].HF : 1'b0;                        NHF[6] = !NSxREG[2].BMEN ? PN_PIPE[4][2].HF : 1'b0;
					NPR[2] = !NSxREG[2].BMEN ? PN_PIPE[4][2].PR : NSxREG[2].BMPR;              NPR[6] = !NSxREG[2].BMEN ? PN_PIPE[4][2].PR : NSxREG[2].BMPR;
					NCC[2] = !NSxREG[2].BMEN ? PN_PIPE[4][2].CC : NSxREG[2].BMCC;              NCC[6] = !NSxREG[2].BMEN ? PN_PIPE[4][2].CC : NSxREG[2].BMCC;
					NCHSEL[2] = BG_PIPE[3].NxCHS[2];
					NCHCN[2] = {2'b00,NSxREG[2].CHCN[0]};
					NCHEN[2] = BG_PIPE[2].NxCH_EN[2];
					NEN[2] = BG_PIPE[3].NxCH[2];
				end
				NCH[2] = VBUF2[NCHSEL[2]];
				// write plan of NBG_CDC[2] (applied byte by byte in the next dot period, see CDC_RAM)
				CDC_PM[2] <= 3'd0; CDC_PF[2] <= 1'b0; CDC_PC[2] <= NCNT[2]; CDC_W[2] <= NCH[2];
				if (NEN[2] && NCHEN[2]) begin
					case (NCHCN[2])
						3'b000: begin				//4bits/dot, 16 colors
`ifdef CUT_NBG_QTR
							if (!NCNT[2][2] && NCNT[2][1:0] == 2'b00) begin	//CUT_NBG_QTR: no NBG0 1/4 nibble plans (mode 2 / second low nibbles)
							CDC_PM[2] <= 3'd1; CDC_PF[2] <= NHF[2];	//low nibbles
							end
`else
							if (!NCNT[2][2] && NCNT[2][1:0] == 2'b11 && NSxREG[0].ZMQT && NSxREG[0].ON) begin
							CDC_PM[2] <= 3'd2; CDC_PF[2] <= NHF[6];	//high nibbles
							end else if (!NCNT[2][2] && ((NCNT[2][1:0] == 2'b00 && !(NSxREG[0].ZMQT && NSxREG[0].ON)) || (NCNT[2][1:0] == 2'b10 && NSxREG[0].ZMQT && NSxREG[0].ON))) begin
							CDC_PM[2] <= 3'd1; CDC_PF[2] <= NHF[2];	//low nibbles
							end
`endif
						end
						3'b001: begin				//8bits/dot, 256 colors
							if (!NCNT[2][2] && ((NCNT[2][1] == 1'b0 && !(NSxREG[0].CHCN == 3'b001 && NSxREG[0].ZMHF && NSxREG[0].ON)) || (NCNT[2][1] == 1'b1 && NSxREG[0].ZMHF && NSxREG[0].ON))) begin
							CDC_PM[2] <= 3'd3; CDC_PF[2] <= NHF[2];	//bytes {NCNT[0],x}
							end
						end
						3'b010,3'b011: begin				//16bits/dot, 2048/32768 colors
							if (!NCNT[2][2]) begin
							CDC_PM[2] <= 3'd4; CDC_PF[2] <= NHF[2];	//bytes {NCNT[1:0],x}: NCH[2][31:24], [15:8]
							end
						end
						3'b100: begin				//32bits/dot, 16M colors
							CDC_PM[2] <= 3'd5;	//byte NCNT: NCH[2][15:8]
						end
						default:;
					endcase
				end
				if (NEN[2] && NCHEN[2]) begin
					case (NCHCN[2])
						3'b000: begin				//4bits/dot, 16 colors
`ifdef CUT_NBG_QTR
							if (!NCNT[2][2] && NCNT[2][1:0] == 2'b00) begin	//CUT_NBG_QTR: NBG_CDP[6] (NBG0 1/4) is gone
							NBG_CDP[2] <= {NPR[2], NCC[2], NPALN[2], 1'b0};
							end
`else
							if (!NCNT[2][2] && NCNT[2][1:0] == 2'b11 && NSxREG[0].ZMQT && NSxREG[0].ON) begin
							NBG_CDP[6] <= {NPR[6], NCC[6], NPALN[6], 1'b0};
							end else if (!NCNT[2][2] && ((NCNT[2][1:0] == 2'b00 && !(NSxREG[0].ZMQT && NSxREG[0].ON)) || (NCNT[2][1:0] == 2'b10 && NSxREG[0].ZMQT && NSxREG[0].ON))) begin
							NBG_CDP[2] <= {NPR[2], NCC[2], NPALN[2], 1'b0};
							end
`endif
						end
						3'b001: begin				//8bits/dot, 256 colors
							if (!NCNT[2][2] && ((NCNT[2][1] == 1'b0 && !(NSxREG[0].CHCN == 3'b001 && NSxREG[0].ZMHF && NSxREG[0].ON)) || (NCNT[2][1] == 1'b1 && NSxREG[0].ZMHF && NSxREG[0].ON))) begin
							NBG_CDP[2] <= {NPR[2], NCC[2], NPALN[2], 1'b0};
							end
						end
						3'b010,3'b011: begin				//16bits/dot, 2048 colors (NBG0)
							
						end
						3'b100: begin				//32bits/dot, 16M colors (NBG0)
							 
						end
						default:;
					endcase
				end
				
				NEN[1] = 0;
				if (BG_PIPE[3].NxCH[0] && NSxREG[0].CHCN[2]) begin
					NCNT[1] = BG_PIPE[3].NxCH_CNT[0];
					NPALN[1] = !NSxREG[0].BMEN ? PN_PIPE[4][0].PALN : {NSxREG[0].BMP,4'b0000}; NPALN[5] = !NSxREG[0].BMEN ? PN_PIPE[4][5].PALN : {NSxREG[0].BMP,4'b0000};
					NHF[1] = !NSxREG[0].BMEN ? PN_PIPE[4][0].HF : 1'b0;                        NHF[5] = !NSxREG[0].BMEN ? PN_PIPE[4][5].HF : 1'b0;
					NPR[1] = !NSxREG[0].BMEN ? PN_PIPE[4][0].PR : NSxREG[0].BMPR;              NPR[5] = !NSxREG[0].BMEN ? PN_PIPE[4][5].PR : NSxREG[0].BMPR;
					NCC[1] = !NSxREG[0].BMEN ? PN_PIPE[4][0].CC : NSxREG[0].BMCC;              NCC[5] = !NSxREG[0].BMEN ? PN_PIPE[4][5].CC : NSxREG[0].BMCC;
					NCHSEL[1] = BG_PIPE[3].NxCHS[0];
					NCHCN[1] = NSxREG[0].CHCN;
					NCHEN[1] = BG_PIPE[2].NxCH_EN[0];
					NEN[1] = BG_PIPE[3].NxCH[0];
`ifndef CUT_NBG_QTR
				end else if (BG_PIPE[3].NxCH[1] && NSxREG[1].CHCN == 3'b000 && (NSxREG[1].ZMHF || NSxREG[1].ZMQT)) begin
					NCNT[1] = BG_PIPE[3].NxCH_CNT[1];
					NPALN[1] = !NSxREG[1].BMEN ? PN_PIPE[4][1].PALN : {NSxREG[1].BMP,4'b0000}; NPALN[5] = !NSxREG[1].BMEN ? PN_PIPE[4][5].PALN : {NSxREG[1].BMP,4'b0000};
					NHF[1] = !NSxREG[1].BMEN ? PN_PIPE[4][1].HF : 1'b0;                        NHF[5] = !NSxREG[1].BMEN ? PN_PIPE[4][5].HF : 1'b0;
					NPR[1] = !NSxREG[1].BMEN ? PN_PIPE[4][1].PR : NSxREG[1].BMPR;              NPR[5] = !NSxREG[1].BMEN ? PN_PIPE[4][5].PR : NSxREG[1].BMPR;
					NCC[1] = !NSxREG[1].BMEN ? PN_PIPE[4][1].CC : NSxREG[1].BMCC;              NCC[5] = !NSxREG[1].BMEN ? PN_PIPE[4][5].CC : NSxREG[1].BMCC;
					NCHSEL[1] = BG_PIPE[3].NxCHS[1];
					NCHCN[1] = NSxREG[1].CHCN;
					NCHEN[1] = BG_PIPE[2].NxCH_EN[1];
					NEN[1] = BG_PIPE[3].NxCH[1] & (!BG_PIPE[3].NxCH_CNT[1][1] | (NSxREG[1].ZMHF & ~NSxREG[1].ZMQT));
`endif
				end else if (BG_PIPE[3].NxCH[1] && NSxREG[1].CHCN == 3'b001 && NSxREG[1].ZMHF) begin
					NCNT[1] = BG_PIPE[3].NxCH_CNT[1];
					NPALN[1] = !NSxREG[1].BMEN ? PN_PIPE[4][1].PALN : {NSxREG[1].BMP,4'b0000}; NPALN[5] = !NSxREG[1].BMEN ? PN_PIPE[4][5].PALN : {NSxREG[1].BMP,4'b0000};
					NHF[1] = !NSxREG[1].BMEN ? PN_PIPE[4][1].HF : 1'b0;                        NHF[5] = !NSxREG[1].BMEN ? PN_PIPE[4][5].HF : 1'b0;
					NPR[1] = !NSxREG[1].BMEN ? PN_PIPE[4][1].PR : NSxREG[1].BMPR;              NPR[5] = !NSxREG[1].BMEN ? PN_PIPE[4][5].PR : NSxREG[1].BMPR;
					NCC[1] = !NSxREG[1].BMEN ? PN_PIPE[4][1].CC : NSxREG[1].BMCC;              NCC[5] = !NSxREG[1].BMEN ? PN_PIPE[4][5].CC : NSxREG[1].BMCC;
					NCHSEL[1] = BG_PIPE[3].NxCHS[1];
					NCHCN[1] = NSxREG[1].CHCN;
					NCHEN[1] = BG_PIPE[2].NxCH_EN[1];
					NEN[1] = BG_PIPE[3].NxCH[1];
				end else begin
					NCNT[1] = BG_PIPE[3].NxCH_CNT[1];
					NPALN[1] = !NSxREG[1].BMEN ? PN_PIPE[4][1].PALN : {NSxREG[1].BMP,4'b0000}; NPALN[5] = !NSxREG[1].BMEN ? PN_PIPE[4][5].PALN : {NSxREG[1].BMP,4'b0000};
					NHF[1] = !NSxREG[1].BMEN ? PN_PIPE[4][1].HF : 1'b0;                        NHF[5] = !NSxREG[1].BMEN ? PN_PIPE[4][5].HF : 1'b0;
					NPR[1] = !NSxREG[1].BMEN ? PN_PIPE[4][1].PR : NSxREG[1].BMPR;              NPR[5] = !NSxREG[1].BMEN ? PN_PIPE[4][5].PR : NSxREG[1].BMPR;
					NCC[1] = !NSxREG[1].BMEN ? PN_PIPE[4][1].CC : NSxREG[1].BMCC;              NCC[5] = !NSxREG[1].BMEN ? PN_PIPE[4][5].CC : NSxREG[1].BMCC;
					NCHSEL[1] = BG_PIPE[3].NxCHS[1];
					NCHCN[1] = {1'b0,NSxREG[1].CHCN[1:0]};
					NCHEN[1] = BG_PIPE[2].NxCH_EN[1];
					NEN[1] = BG_PIPE[3].NxCH[1];
				end
				NCH[1] = VBUF2[NCHSEL[1]];
				// write plan of NBG_CDC[1] (applied byte by byte in the next dot period, see CDC_RAM)
				CDC_PM[1] <= 3'd0; CDC_PF[1] <= 1'b0; CDC_PC[1] <= NCNT[1]; CDC_W[1] <= NCH[1];
				if (NEN[1] && NCHEN[1]) begin
					case (NCHCN[1])
						3'b000: begin				//4bits/dot, 16 colors
`ifdef CUT_NBG_QTR
							if (NCNT[1][0] && NSxREG[1].ZMHF && NSxREG[1].ON) begin	//CUT_NBG_QTR: high nibbles for 1/2 only
`else
							if (NCNT[1][0] && (NSxREG[1].ZMHF || NSxREG[1].ZMQT) && NSxREG[1].ON) begin
`endif
							CDC_PM[1] <= 3'd2; CDC_PF[1] <= NHF[5];	//high nibbles
							end else if (!NCNT[1][2:0]) begin
							CDC_PM[1] <= 3'd1; CDC_PF[1] <= NHF[1];	//low nibbles
							end
						end
						3'b001: begin				//8bits/dot, 256 colors
							if (!NCNT[1][2] && !NCNT[1][1]) begin
							CDC_PM[1] <= 3'd3; CDC_PF[1] <= NHF[1];	//bytes {NCNT[0],x}
							end
						end
						3'b010,3'b011: begin				//16bits/dot, 2048/32768 colors
							if (!NCNT[1][2]) begin
							CDC_PM[1] <= 3'd4; CDC_PF[1] <= NHF[1];	//bytes {NCNT[1:0],x}: NCH[1][23:16], [7:0]
							end
						end
						3'b100: begin				//32bits/dot, 16M colors
							CDC_PM[1] <= 3'd5;	//byte NCNT: NCH[1][23:16]
						end
						default:;
					endcase
				end
				if (NEN[1] && NCHEN[1]) begin
					case (NCHCN[1])
						3'b000: begin				//4bits/dot, 16 colors
`ifdef CUT_NBG_QTR
							if (NCNT[1][0] && NSxREG[1].ZMHF && NSxREG[1].ON) begin	//CUT_NBG_QTR
`else
							if (NCNT[1][0] && (NSxREG[1].ZMHF || NSxREG[1].ZMQT) && NSxREG[1].ON) begin
`endif
							NBG_CDP[5] <= {NPR[5], NCC[5], NPALN[5], 1'b0};
							end else if (!NCNT[1][2:0]) begin
							NBG_CDP[1] <= {NPR[1], NCC[1], NPALN[1], 1'b0};
							end
						end
						3'b001: begin				//8bits/dot, 256 colors
							if (!NCNT[1][2] && !NCNT[1][1]) begin
							NBG_CDP[1] <= {NPR[1], NCC[1], NPALN[1], 1'b0};
							end
						end
						3'b010,3'b011: begin				//16bits/dot, 2048 colors
							if (!NCNT[1][2]) begin
							NBG_CDP[1] <= {NPR[1], NCC[1], NPALN[1], 1'b0};
							end
						end
						3'b100: begin				//32bits/dot, 16M colors
							
						end
						default:;
					endcase
				end
				
				NEN[0] = 0;
`ifdef CUT_NBG_QTR
				//CUT_NBG_QTR: the NBG0 4bpp-reduction branch equals the default one without ZMQT (only its 1/4 enable mask differed)
				if (BG_PIPE[3].NxCH[0] && NSxREG[0].CHCN == 3'b001 && NSxREG[0].ZMHF) begin
`else
				if (BG_PIPE[3].NxCH[0] && NSxREG[0].CHCN == 3'b000 && (NSxREG[0].ZMHF || NSxREG[0].ZMQT)) begin
					NCNT[0] = BG_PIPE[3].NxCH_CNT[0];
					NPALN[0] = !NSxREG[0].BMEN ? PN_PIPE[4][0].PALN : {NSxREG[0].BMP,4'b0000}; NPALN[4] = !NSxREG[0].BMEN ? PN_PIPE[4][4].PALN : {NSxREG[0].BMP,4'b0000};
					NHF[0] = !NSxREG[0].BMEN ? PN_PIPE[4][0].HF : 1'b0;                        NHF[4] = !NSxREG[0].BMEN ? PN_PIPE[4][4].HF : 1'b0;
					NPR[0] = !NSxREG[0].BMEN ? PN_PIPE[4][0].PR : NSxREG[0].BMPR;              NPR[4] = !NSxREG[0].BMEN ? PN_PIPE[4][4].PR : NSxREG[0].BMPR;
					NCC[0] = !NSxREG[0].BMEN ? PN_PIPE[4][0].CC : NSxREG[0].BMCC;              NCC[4] = !NSxREG[0].BMEN ? PN_PIPE[4][4].CC : NSxREG[0].BMCC;
					NCHSEL[0] = BG_PIPE[3].NxCHS[0];
					NCHCN[0] = NSxREG[0].CHCN;
					NCHEN[0] = BG_PIPE[2].NxCH_EN[0];
					NEN[0] = BG_PIPE[3].NxCH[0] & (!BG_PIPE[3].NxCH_CNT[0][1] | (NSxREG[0].ZMHF & ~NSxREG[0].ZMQT));
				end else if (BG_PIPE[3].NxCH[0] && NSxREG[0].CHCN == 3'b001 && NSxREG[0].ZMHF) begin
`endif
					NCNT[0] = BG_PIPE[3].NxCH_CNT[0];
					NPALN[0] = !NSxREG[0].BMEN ? PN_PIPE[4][0].PALN : {NSxREG[0].BMP,4'b0000}; NPALN[4] = !NSxREG[0].BMEN ? PN_PIPE[4][4].PALN : {NSxREG[0].BMP,4'b0000};
					NHF[0] = !NSxREG[0].BMEN ? PN_PIPE[4][0].HF : 1'b0;                        NHF[4] = !NSxREG[0].BMEN ? PN_PIPE[4][4].HF : 1'b0;
					NPR[0] = !NSxREG[0].BMEN ? PN_PIPE[4][0].PR : NSxREG[0].BMPR;              NPR[4] = !NSxREG[0].BMEN ? PN_PIPE[4][4].PR : NSxREG[0].BMPR;
					NCC[0] = !NSxREG[0].BMEN ? PN_PIPE[4][0].CC : NSxREG[0].BMCC;              NCC[4] = !NSxREG[0].BMEN ? PN_PIPE[4][4].CC : NSxREG[0].BMCC;
					NCHSEL[0] = BG_PIPE[3].NxCHS[0];	//NCH[0] is only read under NCHEN[0] = BG_PIPE[2].NxCH_EN[0]
					NCHCN[0] = NSxREG[0].CHCN;
					NCHEN[0] = BG_PIPE[2].NxCH_EN[0];
					NEN[0] = BG_PIPE[3].NxCH[0] & !BG_PIPE[3].NxCH_CNT[0][1];
				end else begin
					NCNT[0] = BG_PIPE[3].NxCH_CNT[0];
					NPALN[0] = !NSxREG[0].BMEN ? PN_PIPE[4][0].PALN : {NSxREG[0].BMP,4'b0000}; NPALN[4] = !NSxREG[0].BMEN ? PN_PIPE[4][4].PALN : {NSxREG[0].BMP,4'b0000};
					NHF[0] = !NSxREG[0].BMEN ? PN_PIPE[4][0].HF : 1'b0;                        NHF[4] = !NSxREG[0].BMEN ? PN_PIPE[4][4].HF : 1'b0;
					NPR[0] = !NSxREG[0].BMEN ? PN_PIPE[4][0].PR : NSxREG[0].BMPR;              NPR[4] = !NSxREG[0].BMEN ? PN_PIPE[4][4].PR : NSxREG[0].BMPR;
					NCC[0] = !NSxREG[0].BMEN ? PN_PIPE[4][0].CC : NSxREG[0].BMCC;              NCC[4] = !NSxREG[0].BMEN ? PN_PIPE[4][4].CC : NSxREG[0].BMCC;
					NCHSEL[0] = BG_PIPE[3].NxCHS[0];	//NCH[0] is only read under NCHEN[0] = BG_PIPE[2].NxCH_EN[0]
					NCHCN[0] = NSxREG[0].CHCN;
					NCHEN[0] = BG_PIPE[2].NxCH_EN[0];
					NEN[0] = BG_PIPE[3].NxCH[0];
				end
				NCH[0] = VBUF2[NCHSEL[0]];
				// write plan of NBG_CDC[0] (applied byte by byte in the next dot period, see CDC_RAM)
				CDC_PM[0] <= 3'd0; CDC_PF[0] <= 1'b0; CDC_PC[0] <= NCNT[0]; CDC_W[0] <= NCH[0];
				if (NEN[0] && NCHEN[0]) begin
					case (NCHCN[0])
						3'b000: begin				//4bits/dot, 16 colors
`ifdef CUT_NBG_QTR
							if (NCNT[0][0] && NSxREG[0].ZMHF && NSxREG[0].ON) begin	//CUT_NBG_QTR: high nibbles for 1/2 only
`else
							if (NCNT[0][0] && (NSxREG[0].ZMHF || NSxREG[0].ZMQT) && NSxREG[0].ON) begin
`endif
							CDC_PM[0] <= 3'd2; CDC_PF[0] <= NHF[4];	//high nibbles
							end else if (!NCNT[0][2:0]) begin
							CDC_PM[0] <= 3'd1; CDC_PF[0] <= NHF[0];	//low nibbles
							end
						end
						3'b001: begin				//8bits/dot, 256 colors
							if (!NCNT[0][2] && !NCNT[0][1]) begin
							CDC_PM[0] <= 3'd3; CDC_PF[0] <= NHF[0];	//bytes {NCNT[0],x}
							end
						end
						3'b010,3'b011: begin				//16bits/dot, 2048/32768 colors
							if (!NCNT[0][2]) begin
							CDC_PM[0] <= 3'd4; CDC_PF[0] <= NHF[0];	//bytes {NCNT[1:0],x}: NCH[0][23:16], [7:0]
							end
						end
						3'b100: begin				//32bits/dot, 16M colors
							CDC_PM[0] <= 3'd5;	//byte NCNT: NCH[0][7:0]
						end
						default:;
					endcase
				end
				if (NEN[0] && NCHEN[0]) begin
					case (NCHCN[0])
						3'b000: begin				//4bits/dot, 16 colors
`ifdef CUT_NBG_QTR
							if (NCNT[0][0] && NSxREG[0].ZMHF && NSxREG[0].ON) begin	//CUT_NBG_QTR
`else
							if (NCNT[0][0] && (NSxREG[0].ZMHF || NSxREG[0].ZMQT) && NSxREG[0].ON) begin
`endif
							NBG_CDP[4] <= {NPR[4], NCC[4], NPALN[4], 1'b0};
							end else if (!NCNT[0][2:0]) begin
							NBG_CDP[0] <= {NPR[0], NCC[0], NPALN[0], 1'b0};
							end
						end
						3'b001: begin				//8bits/dot, 256 colors
							if (!NCNT[0][2] && !NCNT[0][1]) begin
							NBG_CDP[0] <= {NPR[0], NCC[0], NPALN[0], 1'b0};
							end
						end
						3'b010,3'b011: begin				//16bits/dot, 2048 colors
							if (!NCNT[0][2]) begin
							NBG_CDP[0] <= {NPR[0], NCC[0], NPALN[0], 1'b0};
							end
						end
						3'b100: begin				//32bits/dot, 16M colors
							NBG_CDP[0] <= {NPR[0], NCC[0], NPALN[0], 1'b0};
						end
						default:;
					endcase
				end
				
				BG_PIPE[1] <= BG_PIPE[0];
				BG_PIPE[2] <= BG_PIPE[1];
				BG_PIPE[3] <= BG_PIPE[2];
				
				PN4_D = PN_PIPE[3];
				for (int e = 1; e < 8; e++) PN4_D[e] = PNU(PND_Q[20 + (e - 1) * 10 +: 10]);
				PN_PIPE[1] <= PN_PIPE[0];
				PN_PIPE[2] <= PN_PIPE[1];
				PN_PIPE[3] <= PN_PIPE[2];
				PN_PIPE[4] <= PN4_D;
				
				NBG0_PN_PIPE[0] <= PN_PIPE[0][0];
				NBG0_PN_PIPE[1] <= NBG0_PN_PIPE[0];
				
				if (BG_PIPE[3].NxPN[0] && NSxREG[0].CHCN[2]) begin
					NBG1_PN_PIPE[0] <= PN_PIPE[2][0];
				end else begin
					NBG1_PN_PIPE[0] <= PN_PIPE[0][1];
				end
				NBG1_PN_PIPE[1] <= NBG1_PN_PIPE[0];
				
				if (BG_PIPE[3].NxPN[0] && NSxREG[0].CHCN[2:1]) begin
					NBG2_PN_PIPE[0] <= PN_PIPE[1][0];
				end else begin
					NBG2_PN_PIPE[0] <= PN_PIPE[0][2];
				end
				NBG2_PN_PIPE[1] <= NBG2_PN_PIPE[0];
				
				if (BG_PIPE[3].NxPN[0] && NSxREG[0].CHCN[2]) begin
					NBG3_PN_PIPE[0] <= PN_PIPE[3][0];
				end else if (BG_PIPE[3].NxPN[1] && NSxREG[1].CHCN[1]) begin
					NBG3_PN_PIPE[0] <= PN_PIPE[1][1];
				end else begin
					NBG3_PN_PIPE[0] <= PN_PIPE[0][3];
				end
				NBG3_PN_PIPE[1] <= NBG3_PN_PIPE[0];
			end
			
			//RBG0,RBG1
			if (DOT_CE_R) begin
			for (int i=0; i<2; i++) begin
				PN_RP = (i == 0 ? VA_PIPE[2].R0RP : 1'b1);
				CH_RP = (i == 0 ? VA_PIPE[4].R0RP : 1'b1);
				
				RBG_PIPE[0].RxCT[i] = VA_PIPE[0].RxA0CT[i] | VA_PIPE[0].RxA1CT[i] | VA_PIPE[0].RxB0CT[i] | VA_PIPE[0].RxB1CT[i];
				RBG_PIPE[0].RxCTS[i] = VA_PIPE[0].RxA0CT[i] && RxCT_ADDR[RBG_A0VA.Rx][18:17] == 2'b00 ? 2'd0 : 
									        VA_PIPE[0].RxA1CT[i] && RxCT_ADDR[RBG_A1VA.Rx][18:17] == 2'b01 ? 2'd1 : 
									        VA_PIPE[0].RxB0CT[i] && RxCT_ADDR[RBG_B0VA.Rx][18:17] == 2'b10 ? 2'd2 : 
									        2'd3;
				RBG_PIPE[0].RxCRCT[i] = VA_PIPE[0].RxCRCT[i];
				RBG_PIPE[0].RxPN[i] = VA_PIPE[0].RxA0PN[i] | VA_PIPE[0].RxA1PN[i] | VA_PIPE[0].RxB0PN[i] | VA_PIPE[0].RxB1PN[i];
				RBG_PIPE[0].RxPNS[i] = VA_PIPE[0].RxA0PN[i] && RxPN_ADDR[RBG_A0VA.Rx][18:17] == 2'b00 ? 2'd0 : 
									        VA_PIPE[0].RxA1PN[i] && RxPN_ADDR[RBG_A1VA.Rx][18:17] == 2'b01 ? 2'd1 : 
									        VA_PIPE[0].RxB0PN[i] && RxPN_ADDR[RBG_B0VA.Rx][18:17] == 2'b10 ? 2'd2 : 
									        2'd3;
				RBG_PIPE[0].RxOVR[i] = RxSCRN_OVER[i];
				RBG_PIPE[0].RxCTTP[i] = VA_PIPE[0].RxCTTP[i];
				RBG_PIPE[0].RxCH[i] = VA_PIPE[0].RxA0CH[i] | VA_PIPE[0].RxA1CH[i] | VA_PIPE[0].RxB0CH[i] | VA_PIPE[0].RxB1CH[i];
				RBG_PIPE[0].RxCHS[i] = VA_PIPE[0].RxA0CH[i] && RxCH_ADDR[RBG_A0VA.Rx][18:17] == 2'b00 ? 2'd0 : 
									        VA_PIPE[0].RxA1CH[i] && RxCH_ADDR[RBG_A1VA.Rx][18:17] == 2'b01 ? 2'd1 : 
									        VA_PIPE[0].RxB0CH[i] && RxCH_ADDR[RBG_B0VA.Rx][18:17] == 2'b10 ? 2'd2 : 
									        2'd3;
				RBG_PIPE[0].RxCELLX[i] = VA_PIPE[4].RxX[CH_RP][2:0];
				RBG_PIPE[0].RxCT_EN[i] = RBG_CT_EN[i];
				
				if (RBG_PIPE[2].RxPN[i]) begin
					case (RBG_PIPE[2].RxPNS[i])
						2'd0: RPN_WD[i] = RA0_BUF;
						2'd1: RPN_WD[i] = RA1_BUF;
						2'd2: RPN_WD[i] = RB0_BUF;
						2'd3: RPN_WD[i] = RB1_BUF;
					endcase
					//one PNData for the over-pattern word and the 1-word pattern name (same layer registers, exclusive cases)
					RPN_OVR = RPxREG[PN_RP].OVR == 2'b01 && RBG_PIPE[2].RxOVR[i];
					if (RPN_OVR || RSxREG[i].PNC.NxPNB)
						RBG_PN_PIPE[0][i] <= PNData(RSxREG[i].PNC, RSxREG[i].CHSZ, RSxREG[i].CHCN, RPN_OVR ? RPxREG[PN_RP].OVPNR : RPN_WD[i][31:16]);
					else
						RBG_PN_PIPE[0][i] <= RPN_WD[i];
				end
				
				RBG_TP_PIPE[0][i] <= (RPxREG[PN_RP].OVR[1] && RBG_PIPE[2].RxOVR[i]) || RBG_PIPE[2].RxCTTP[i];
					
				
				
				if (RBG_PIPE[3].RxCH[i]) begin
					RCELLX[i] = RBG_PIPE[3].RxCELLX[i];
					RPALN[i] = !RSxREG[i].BMEN ? RBG_PN_PIPE[4][i].PALN : {RSxREG[i].BMP,4'b0000};
					RHF[i] = RBG_PN_PIPE[4][i].HF & ~RSxREG[i].BMEN;
					RPR[i] = !RSxREG[i].BMEN ? RBG_PN_PIPE[4][i].PR : RSxREG[i].BMPR;
					RCC[i] = !RSxREG[i].BMEN ? RBG_PN_PIPE[4][i].CC : RSxREG[i].BMCC;
					RCH[i] = VBUF2[RBG_PIPE[3].RxCHS[i]] & {32{~RBG_TP_PIPE[4][i]}};
					RTP[i] = RBG_TP_PIPE[4][i];
					case (RSxREG[i].CHCN)
						3'b000: begin				//4bits/dot, 16 colors
							case (RCELLX[i] ^ {3{RHF[i]}})
							3'b000: RBG_DC[i][0] <= {4'h0,RCH[i][31:28]};
							3'b001: RBG_DC[i][0] <= {4'h0,RCH[i][27:24]};
							3'b010: RBG_DC[i][0] <= {4'h0,RCH[i][23:20]};
							3'b011: RBG_DC[i][0] <= {4'h0,RCH[i][19:16]};
							3'b100: RBG_DC[i][0] <= {4'h0,RCH[i][15:12]};
							3'b101: RBG_DC[i][0] <= {4'h0,RCH[i][11: 8]};
							3'b110: RBG_DC[i][0] <= {4'h0,RCH[i][ 7: 4]};
							3'b111: RBG_DC[i][0] <= {4'h0,RCH[i][ 3: 0]};
							endcase
							RBG_CDP[i] <= {RPR[i], RCC[i], RPALN[i], RTP[i]};
						end
						3'b001: begin				//8bits/dot, 256 colors
							case (RCELLX[i][1:0] ^ {2{RHF[i]}})
							2'b00:  RBG_DC[i][0] <= {     RCH[i][31:24]};
							2'b01:  RBG_DC[i][0] <= {     RCH[i][23:16]};
							2'b10:  RBG_DC[i][0] <= {     RCH[i][15: 8]};
							2'b11:  RBG_DC[i][0] <= {     RCH[i][ 7: 0]};
							endcase
							RBG_CDP[i] <= {RPR[i], RCC[i], RPALN[i], RTP[i]};
						end
						3'b010,3'b011: begin		//16bits/dot, 2048/32768 colors
							case (RCELLX[i][0:0] ^ {1{RHF[i]}})
							1'b0: begin
						           RBG_DC[i][2] <= {     RCH[i][31:24]};
							        RBG_DC[i][0] <= {     RCH[i][23:16]}; end
							1'b1: begin
						           RBG_DC[i][2] <= {     RCH[i][15: 8]};
							        RBG_DC[i][0] <= {     RCH[i][ 7: 0]}; end
							endcase
							RBG_CDP[i] <= {RPR[i], RCC[i], 7'h00, RTP[i]};
						end
						3'b100: begin				//32bits/dot, 16M colors
									  RBG_DC[i][3] <= {     RCH[i][31:24]}; 
									  RBG_DC[i][1] <= {     RCH[i][23:16]}; 
									  RBG_DC[i][2] <= {     RCH[i][15: 8]}; 
									  RBG_DC[i][0] <= {     RCH[i][ 7: 0]};
							RBG_CDP[i] <= {RPR[i], RCC[i], 7'h00, RTP[i]};
						end
						default:;
					endcase
				end
			end
			
			RBG_PIPE[1] <= RBG_PIPE[0];
			RBG_PIPE[2] <= RBG_PIPE[1];
			RBG_PIPE[3] <= RBG_PIPE[2];
			
			RPN4_D[0] = PNU(PND_Q[9:0]);
			RPN4_D[1] = PNU(PND_Q[19:10]);
			RBG_PN_PIPE[1] <= RBG_PN_PIPE[0];
			RBG_PN_PIPE[2] <= RBG_PN_PIPE[1];
			RBG_PN_PIPE[3] <= RBG_PN_PIPE[2];
			RBG_PN_PIPE[4] <= RPN4_D;
			RBG_TP_PIPE[1] <= RBG_TP_PIPE[0];
			RBG_TP_PIPE[2] <= RBG_TP_PIPE[1];
			RBG_TP_PIPE[3] <= RBG_TP_PIPE[2];
			RBG_TP_PIPE[4] <= RBG_TP_PIPE[3];
			end
		end
	end

	//Dots data
	CellParam_t NCDP0[2], NCDP1[2], NCDP2[2], NCDP3[2], NCDP4[2], NCDP5[2], NCDP6[2], NCDP7[2];
	// Cell dot buffers NDC0-3 (logical 16 bytes each: 0-7 previous cell, 8-15 current cell) as rings of three
	// 8-byte cells in MLABs. The next cell is written byte by byte on the 8 clock edges of the dot period that ends
	// at the cell boundary (NBG_CDC only changes on DOT_CE_R, so it holds the value the old copy took); at the
	// boundary the pointers rotate instead of shifting data. One MLAB copy per simultaneous reader.
	wire        NDC_BOUND = (CELLX[2:0] | {HRES[1],2'b00}) == 3'd7;
	wire [ 2:0] NDC_WB = {DOTCLK_DIV,CE_R};		//CE_R/CE_F alternate: 8 distinct values per dot period
	bit  [ 1:0] NDC_PREV = 2'd0, NDC_CUR = 2'd1;
	wire [ 1:0] NDC_NEXT = 2'd3 - NDC_PREV - NDC_CUR;
	function bit [4:0] NdcRA(input bit [3:0] idx, input bit [1:0] prev, input bit [1:0] cur);
		return {idx[3] ? cur : prev, idx[2:0]};
	endfunction
	wire [ 4:0] NDC_WA = {NDC_NEXT,NDC_WB};
	bit [31: 0] RxDC[2];
	CellParam_t RxCDP[2];
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			// synopsys translate_off
			
			// synopsys translate_on
		end
		else if (DOT_CE_R) begin
			if ((CELLX[2:0] | {HRES[1],2'b00}) == 3'd7) begin
				NDC_PREV <= NDC_CUR; NDC_CUR <= NDC_NEXT;
					
				NCDP0[0] <= NCDP0[1]; NCDP0[1] <= NBG_CDP[0];
				NCDP1[0] <= NCDP1[1]; NCDP1[1] <= NBG_CDP[1];
				NCDP2[0] <= NCDP2[1]; NCDP2[1] <= NBG_CDP[2];
				NCDP3[0] <= NCDP3[1]; NCDP3[1] <= NBG_CDP[3];
				NCDP4[0] <= NCDP4[1]; NCDP4[1] <= NBG_CDP[4];
				NCDP5[0] <= NCDP5[1]; NCDP5[1] <= NBG_CDP[5];
`ifndef CUT_NBG_QTR
				NCDP6[0] <= NCDP6[1]; NCDP6[1] <= NBG_CDP[6];
				NCDP7[0] <= NCDP7[1]; NCDP7[1] <= NBG_CDP[7];
`endif
			end
		end
	end
	assign RxDC[0] = {RBG_DC[0][3],RBG_DC[0][1],RBG_DC[0][2],RBG_DC[0][0]};
	assign RxCDP[0] = RBG_CDP[0];
	assign RxDC[1] = {RBG_DC[1][3],RBG_DC[1][1],RBG_DC[1][2],RBG_DC[1][0]};
	assign RxCDP[1] = RBG_CDP[1];
	
	ScrollData_t NCX[4];
	always @(posedge CLK or negedge RST_N) begin
		ScrollData_t X[4];
		
		if (!RST_N) begin
			// synopsys translate_off
			NCX <= '{4{SCRLD_NULL}};
			// synopsys translate_on
		end
		else begin
			X[0] = NCX[0] + LZMX[0];
			X[1] = NCX[1] + LZMX[1];
			X[2] = NCX[2] + 19'h00100;
			X[3] = NCX[3] + 19'h00100;
			if (DOT_CE_R || (DOT_CE_F & HRES[1])) begin
				if (DOT_FETCH) begin
					NCX[0] <= X[0];
					NCX[1] <= X[1];
					NCX[2] <= X[2];
					NCX[3] <= X[3];
					
					MOSAIC_HCNT <= MOSAIC_HCNT + 4'd1;
					if (MOSAIC_HCNT == REGS.MZCTL.MZSZH) begin
						MOSAIC_HCNT <= '0;
					end
				end
			end
			if (DOT_CE_R) begin
				if (DOT_FETCH) begin
					if ((SCRNX[2:0] | {HRES[1],2'b00}) == 3'd7) begin
						NCX[0] <= X[0] & {11'h007,8'hFF};
						NCX[1] <= X[1] & {11'h007,8'hFF};
						NCX[2] <= X[2] & {11'h007,8'hFF};
						NCX[3] <= X[3] & {11'h007,8'hFF};
					end
				end
				if (VA_PIPE[3].LS) begin
					NCX[0] <= NSX[0] & {11'h007,8'hFF};
					NCX[1] <= NSX[1] & {11'h007,8'hFF};
					NCX[2] <= NSX[2] & {11'h007,8'hFF};
					NCX[3] <= NSX[3] & {11'h007,8'hFF};
					MOSAIC_HCNT <= '0;
				end
			end
		end
	end
	
	bit  [ 3:0] N0I_S0, N1I_S1;
	wire [ 7:0] S0A_Q, S1A_Q, S1B_Q, S2A_Q, S2B_Q, S3A_Q, S3B_Q, S3C_Q;
	// NBG_CDC (see CDC_PM): CDC_Q = old bytes j of the four layers, CDC_NEW = the same bytes with this period's plan
	// applied (= the original NBG_CDC[k][j] during this period); written back every clock.
	function bit [7:0] CdcByte(input bit [2:0] m, input bit f, input bit [2:0] c, input bit [31:0] w, input bit [2:0] j,
	                           input bit [7:0] old, input bit hi16, input bit [1:0] b32);
		bit [2:0] ni;
		bit [3:0] nib;
		bit [1:0] bi;
		bit [7:0] byt, res;
		ni = j ^ {3{f}};	//nibble ni of w (0 = w[31:28]) is half ni[0] of byte ni[2:1]
		bi = m == 3'd1 || m == 3'd2 ? ni[2:1] : m == 3'd4 ? {ni[0], ~hi16} : m == 3'd5 ? b32 : ni[1:0];
		case (bi)
			2'd0: byt = w[31:24];
			2'd1: byt = w[23:16];
			2'd2: byt = w[15: 8];
			2'd3: byt = w[ 7: 0];
		endcase
		nib = ni[0] ? byt[3:0] : byt[7:4];
		res = old;
		case (m)
			3'd1: res[3:0] = nib;
			3'd2: res[7:4] = nib;
			3'd3: if (j[2] == c[0]) res = byt;
			3'd4: if (j[2:1] == c[1:0]) res = byt;
			3'd5: if (j == c) res = byt;
			default:;
		endcase
		return res;
	endfunction
`ifdef CUT_NBG_QTR
	// CUT_NBG_QTR: NBG_CDC[2]/[3] never get plan mode 2 (high nibbles: only the NBG0/NBG1 1/4 plans set it there).
	// Mapping 2 to 0 (none) is the identity on every plan they can hold and lets synthesis drop mode 2 from their
	// formatters.
	function bit [2:0] CdcNoHi(input bit [2:0] m);
		return {m[2], m[1] & m[0], m[0]};
	endfunction
`endif
	wire [31: 0] CDC_Q;
	bit  [ 7: 0] CDC_NEW[4];
	always_comb begin
		CDC_NEW[0] = CdcByte(CDC_PM[0], CDC_PF[0], CDC_PC[0], CDC_W[0], NDC_WB, CDC_Q[ 7: 0], 1'b0, 2'd3);	//16 bpp NCH[0][23:16],[7:0]; 32 bpp [7:0]
		CDC_NEW[1] = CdcByte(CDC_PM[1], CDC_PF[1], CDC_PC[1], CDC_W[1], NDC_WB, CDC_Q[15: 8], 1'b0, 2'd1);	//16 bpp NCH[1][23:16],[7:0]; 32 bpp [23:16]
`ifdef CUT_NBG_QTR
		CDC_NEW[2] = CdcByte(CdcNoHi(CDC_PM[2]), CDC_PF[2], CDC_PC[2], CDC_W[2], NDC_WB, CDC_Q[23:16], 1'b1, 2'd2);	//16 bpp NCH[2][31:24],[15:8]; 32 bpp [15:8]
		CDC_NEW[3] = CdcByte(CdcNoHi(CDC_PM[3]), CDC_PF[3], CDC_PC[3], CDC_W[3], NDC_WB, CDC_Q[31:24], 1'b1, 2'd0);	//16 bpp NCH[3][31:24],[15:8]; 32 bpp [31:24]
`else
		CDC_NEW[2] = CdcByte(CDC_PM[2], CDC_PF[2], CDC_PC[2], CDC_W[2], NDC_WB, CDC_Q[23:16], 1'b1, 2'd2);	//16 bpp NCH[2][31:24],[15:8]; 32 bpp [15:8]
		CDC_NEW[3] = CdcByte(CDC_PM[3], CDC_PF[3], CDC_PC[3], CDC_W[3], NDC_WB, CDC_Q[31:24], 1'b1, 2'd0);	//16 bpp NCH[3][31:24],[15:8]; 32 bpp [31:24]
`endif
	end
	VDP2_CDC_RAM cdcram(CLK, NDC_WB, {CDC_NEW[3],CDC_NEW[2],CDC_NEW[1],CDC_NEW[0]}, NDC_WB, CDC_Q);	//S5CHECK_CDC
	
	// Ring copies with one read address share one 16-bit MLAB (R2). S2A (ring 2) and S1A / S3A (rings 1, 3) are read for
	// N0DOT only in the modes where their index equals N0I_S0 (NBG0 4bpp 1/4, 8bpp 1/2 and normal; in 4bpp 1/2 N0DOT
	// takes S0A alone), and S3B only where its index equals N1I_S1; so the NBG0 readers of rings 0-3 read at N0I_S0 and
	// the NBG1 readers of rings 1 and 3 at N1I_S1, and the bytes they return when unused do not matter. 8 MLABs -> 5
	// (one 32-bit MLAB pair costs 26 ALUTs more than two 16-bit MLABs in context).
	VDP2_NDC_RAM #(16) ndcn0(CLK, NDC_WA, {CDC_NEW[2],CDC_NEW[0]}, NDC_BOUND, NdcRA(N0I_S0, NDC_PREV, NDC_CUR), {S2A_Q,S0A_Q});
	VDP2_NDC_RAM #(16) ndcn2(CLK, NDC_WA, {CDC_NEW[3],CDC_NEW[1]}, NDC_BOUND, NdcRA(N0I_S0, NDC_PREV, NDC_CUR), {S3A_Q,S1A_Q});
	VDP2_NDC_RAM #(16) ndcn1(CLK, NDC_WA, {CDC_NEW[3],CDC_NEW[1]}, NDC_BOUND, NdcRA(N1I_S1, NDC_PREV, NDC_CUR), {S3B_Q,S1B_Q});
	VDP2_NDC_RAM ndc2b(CLK, NDC_WA, CDC_NEW[2], NDC_BOUND, NdcRA(NCX[2].INT[3:0], NDC_PREV, NDC_CUR), S2B_Q);
	VDP2_NDC_RAM ndc3c(CLK, NDC_WA, CDC_NEW[3], NDC_BOUND, NdcRA(NCX[3].INT[3:0], NDC_PREV, NDC_CUR), S3C_Q);
	always_comb begin
		// read indices of the NBG0 / NBG1 readers, in the priority order of the dot selection below
		if (NSxREG[0].CHCN == 3'b000 && NSxREG[0].ZMHF) begin
			N0I_S0 = {NCX[0].INT[4],NCX[0].INT[2:0]};
`ifndef CUT_NBG_QTR
		end else if (NSxREG[0].CHCN == 3'b000 && NSxREG[0].ZMQT) begin
			N0I_S0 = {NCX[0].INT[5],NCX[0].INT[2:0]};
`endif
		end else if (NSxREG[0].CHCN == 3'b001 && NSxREG[0].ZMHF) begin
			N0I_S0 = {NCX[0].INT[4],NCX[0].INT[2:0]};
		end else begin
			N0I_S0 = NCX[0].INT[3:0];
		end
		if (NSxREG[1].CHCN == 3'b000 && NSxREG[1].ZMHF) begin
			N1I_S1 = {NCX[1].INT[4],NCX[1].INT[2:0]};
`ifndef CUT_NBG_QTR
		end else if (NSxREG[1].CHCN == 3'b000 && NSxREG[1].ZMQT) begin
			N1I_S1 = {NCX[1].INT[5],NCX[1].INT[2:0]};
`endif
		end else if (NSxREG[1].CHCN == 3'b001 && NSxREG[1].ZMHF) begin
			N1I_S1 = {NCX[1].INT[4],NCX[1].INT[2:0]};
		end else begin
			N1I_S1 = NCX[1].INT[3:0];
		end
	end
	
	DotData_t R0DOT, N0DOT, N1DOT, N2DOT, N3DOT;
	bit [31:0] N0DOTDC, N1DOTDC, N2DOTDC, N3DOTDC;
	bit [31:0] R0DOTDC;
	CellParam_t N0DOTCDP, N1DOTCDP, N2DOTCDP, N3DOTCDP;
	CellParam_t R0DOTCDP;
	always @(posedge CLK or negedge RST_N) begin
		bit          NxDOT_FETCH[4];
		bit          R0DOT_FETCH;
	
		if (!RST_N) begin
			// synopsys translate_off
			R0DOT <= DD_NULL;
			N0DOT <= DD_NULL;
			N1DOT <= DD_NULL;
			N2DOT <= DD_NULL;
			N3DOT <= DD_NULL;
			// synopsys translate_on
		end
		else if (DOT_CE_R || (DOT_CE_F & HRES[1])) begin
			NxDOT_FETCH[0] = (!MOSAIC_HCNT || !NSxREG[0].MZE);
			NxDOT_FETCH[1] = (!MOSAIC_HCNT || !NSxREG[1].MZE);
			NxDOT_FETCH[2] = (!MOSAIC_HCNT || !NSxREG[2].MZE);
			NxDOT_FETCH[3] = (!MOSAIC_HCNT || !NSxREG[3].MZE);
			R0DOT_FETCH    = (!MOSAIC_HCNT || !RSxREG[0].MZE);
			
			if (NxDOT_FETCH[0]) begin
				if (RSxREG[1].ON) begin
					N0DOTDC <= RxDC[1];
					N0DOTCDP <= RxCDP[1];
				end else if (NSxREG[0].CHCN == 3'b000 && NSxREG[0].ZMHF) begin
					case (NCX[0].INT[3])
						1'b0: begin N0DOTDC <= {28'h0000000,S0A_Q[ 3: 0]}; N0DOTCDP <= NCDP0[NCX[0].INT[4]]; end
						1'b1: begin N0DOTDC <= {28'h0000000,S0A_Q[ 7: 4]}; N0DOTCDP <= NCDP4[NCX[0].INT[4]]; end
					endcase
`ifndef CUT_NBG_QTR
				end else if (NSxREG[0].CHCN == 3'b000 && NSxREG[0].ZMQT) begin
					case (NCX[0].INT[4:3])
						2'b00: begin N0DOTDC <= {28'h0000000,S0A_Q[ 3: 0]}; N0DOTCDP <= NCDP0[NCX[0].INT[5]]; end
						2'b01: begin N0DOTDC <= {28'h0000000,S0A_Q[ 7: 4]}; N0DOTCDP <= NCDP4[NCX[0].INT[5]]; end
						2'b10: begin N0DOTDC <= {28'h0000000,S2A_Q[ 3: 0]}; N0DOTCDP <= NCDP2[NCX[0].INT[5]]; end
						2'b11: begin N0DOTDC <= {28'h0000000,S2A_Q[ 7: 4]}; N0DOTCDP <= NCDP6[NCX[0].INT[5]]; end
					endcase
`endif
				end else if (NSxREG[0].CHCN == 3'b001 && NSxREG[0].ZMHF) begin
					case (NCX[0].INT[3])
						1'b0: begin N0DOTDC <= {24'h000000,S0A_Q[ 7: 0]}; N0DOTCDP <= NCDP0[NCX[0].INT[4]]; end
						1'b1: begin N0DOTDC <= {24'h000000,S2A_Q[ 7: 0]}; N0DOTCDP <= NCDP2[NCX[0].INT[4]]; end
					endcase
				end else begin
					N0DOTDC <= {S3A_Q,S1A_Q,S2A_Q,S0A_Q};
					N0DOTCDP <= NCDP0[NCX[0].INT[3]];
				end
			end
			
			if (NxDOT_FETCH[1]) begin
				if (NSxREG[1].CHCN == 3'b000 && NSxREG[1].ZMHF) begin
					case (NCX[1].INT[3])
						1'b0: begin N1DOTDC <= {28'h0000000,S1B_Q[ 3: 0]}; N1DOTCDP <= NCDP1[NCX[1].INT[4]]; end
						1'b1: begin N1DOTDC <= {28'h0000000,S1B_Q[ 7: 4]}; N1DOTCDP <= NCDP5[NCX[1].INT[4]]; end
					endcase
`ifndef CUT_NBG_QTR
				end else if (NSxREG[1].CHCN == 3'b000 && NSxREG[1].ZMQT) begin
					case (NCX[1].INT[4:3])
						2'b00: begin N1DOTDC <= {28'h0000000,S1B_Q[ 3: 0]}; N1DOTCDP <= NCDP1[NCX[1].INT[5]]; end
						2'b01: begin N1DOTDC <= {28'h0000000,S1B_Q[ 7: 4]}; N1DOTCDP <= NCDP5[NCX[1].INT[5]]; end
						2'b10: begin N1DOTDC <= {28'h0000000,S3B_Q[ 3: 0]}; N1DOTCDP <= NCDP3[NCX[1].INT[5]]; end
						2'b11: begin N1DOTDC <= {28'h0000000,S3B_Q[ 7: 4]}; N1DOTCDP <= NCDP7[NCX[1].INT[5]]; end
					endcase
`endif
				end else if (NSxREG[1].CHCN == 3'b001 && NSxREG[1].ZMHF) begin
					case (NCX[1].INT[3])
						1'b0: begin N1DOTDC <= {24'h000000,S1B_Q[ 7: 0]}; N1DOTCDP <= NCDP1[NCX[1].INT[4]]; end
						1'b1: begin N1DOTDC <= {24'h000000,S3B_Q[ 7: 0]}; N1DOTCDP <= NCDP3[NCX[1].INT[4]]; end
					endcase
				end else begin
					N1DOTDC <= {16'h0000,S3B_Q,S1B_Q};
					N1DOTCDP <= NCDP1[NCX[1].INT[3]];
				end
			end
				
			if (NxDOT_FETCH[2]) begin
				N2DOTDC <= {24'h000000,S2B_Q};
				N2DOTCDP <= NCDP2[NCX[2].INT[3]];
			end
			
			if (NxDOT_FETCH[3]) begin
				N3DOTDC <= {24'h000000,S3C_Q};
				N3DOTCDP <= NCDP3[NCX[3].INT[3]];
			end
			
			if (R0DOT_FETCH) begin
				R0DOTDC <= RxDC[0];
				R0DOTCDP <= RxCDP[0];
			end
		end
	end
	
`ifdef CUT_NBG_QTR
	wire N0_REDUCE = NSxREG[0].CHCN[0] && NSxREG[0].ZMHF;	//CUT_NBG_QTR: no ZMQT term
	wire N1_REDUCE = NSxREG[1].CHCN[0] && NSxREG[1].ZMHF;
`else
	wire N0_REDUCE = (NSxREG[0].CHCN[0] && NSxREG[0].ZMHF) || NSxREG[0].ZMQT;
	wire N1_REDUCE = (NSxREG[1].CHCN[0] && NSxREG[1].ZMHF) || NSxREG[1].ZMQT;
`endif
	assign R0DOT = MakeDotData(R0DOTDC, R0DOTCDP, RSxREG[0].CHCN, RSxREG[0].TPON);
	assign N0DOT = MakeDotData(N0DOTDC, N0DOTCDP, NSxREG[0].CHCN, NSxREG[0].TPON);
	assign N1DOT = MakeDotData(N1DOTDC, N1DOTCDP, NSxREG[1].CHCN, NSxREG[1].TPON);
	assign N2DOT = MakeDotData(N2DOTDC, N2DOTCDP, NSxREG[2].CHCN, NSxREG[2].TPON);
	assign N3DOT = MakeDotData(N3DOTDC, N3DOTCDP, NSxREG[3].CHCN, NSxREG[3].TPON);
								 
	//Sprite data
	SpriteDotData_t SDOT;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			// synopsys translate_off
			SDOT <= SDD_NULL;
			// synopsys translate_on
		end
		else if (DOT_CE_R || (DOT_CE_F & HRES[1])) begin
			SDOT <= SpriteData(REGS.SPCTL, FBDI, REGS.SDCTL.TPSDSL);
		end
	end
	
	//Priority
	wire TW0_HIT = HRES[1] ? W0_HIT_PIPE[16*2+0] : W0_HIT_PIPE[16*2+1];
	wire TW1_HIT = HRES[1] ? W1_HIT_PIPE[16*2+0] : W1_HIT_PIPE[16*2+1];
`ifdef CUT_VDP2_SPWIN
	//U8 CUT_VDP2_SPWIN: the sprite window is no input of the window tests (SWE = 0 everywhere: WCTLA-C SWE / SWA,
	//WCTLD CCSWE / CCSWA and SDOT.WN have no reader; WCTLx is write-only). SPCTL.SPWINEN stays (sprite data decode).
	wire NxW_EN[4] = '{WinTest(TW0_HIT ^ REGS.WCTLA.N0W0A,TW1_HIT ^ REGS.WCTLA.N0W1A,1'b0,REGS.WCTLA.N0W0E,REGS.WCTLA.N0W1E,1'b0,REGS.WCTLA.N0LOG),
	                   WinTest(TW0_HIT ^ REGS.WCTLA.N1W0A,TW1_HIT ^ REGS.WCTLA.N1W1A,1'b0,REGS.WCTLA.N1W0E,REGS.WCTLA.N1W1E,1'b0,REGS.WCTLA.N1LOG),
	                   WinTest(TW0_HIT ^ REGS.WCTLB.N2W0A,TW1_HIT ^ REGS.WCTLB.N2W1A,1'b0,REGS.WCTLB.N2W0E,REGS.WCTLB.N2W1E,1'b0,REGS.WCTLB.N2LOG),
	                   WinTest(TW0_HIT ^ REGS.WCTLB.N3W0A,TW1_HIT ^ REGS.WCTLB.N3W1A,1'b0,REGS.WCTLB.N3W0E,REGS.WCTLB.N3W1E,1'b0,REGS.WCTLB.N3LOG)};
	wire RxW_EN[2] = '{WinTest(TW0_HIT ^ REGS.WCTLC.R0W0A,TW1_HIT ^ REGS.WCTLC.R0W1A,1'b0,REGS.WCTLC.R0W0E,REGS.WCTLC.R0W1E,1'b0,REGS.WCTLC.R0LOG),
	                   0};
	wire SW_EN     =   WinTest(TW0_HIT ^ REGS.WCTLC.SPW0A,TW1_HIT ^ REGS.WCTLC.SPW1A,1'b0,REGS.WCTLC.SPW0E,REGS.WCTLC.SPW1E,1'b0,REGS.WCTLC.SPLOG);
	wire CCW_EN    =   WinTest(TW0_HIT ^ REGS.WCTLD.CCW0A,TW1_HIT ^ REGS.WCTLD.CCW1A,1'b0,REGS.WCTLD.CCW0E,REGS.WCTLD.CCW1E,1'b0,REGS.WCTLD.CCLOG);
`else
	wire NxW_EN[4] = '{WinTest(TW0_HIT ^ REGS.WCTLA.N0W0A,TW1_HIT ^ REGS.WCTLA.N0W1A,SDOT.WN ^ REGS.WCTLA.N0SWA,REGS.WCTLA.N0W0E,REGS.WCTLA.N0W1E,REGS.WCTLA.N0SWE & REGS.SPCTL.SPWINEN,REGS.WCTLA.N0LOG),
	                   WinTest(TW0_HIT ^ REGS.WCTLA.N1W0A,TW1_HIT ^ REGS.WCTLA.N1W1A,SDOT.WN ^ REGS.WCTLA.N1SWA,REGS.WCTLA.N1W0E,REGS.WCTLA.N1W1E,REGS.WCTLA.N1SWE & REGS.SPCTL.SPWINEN,REGS.WCTLA.N1LOG),
	                   WinTest(TW0_HIT ^ REGS.WCTLB.N2W0A,TW1_HIT ^ REGS.WCTLB.N2W1A,SDOT.WN ^ REGS.WCTLB.N2SWA,REGS.WCTLB.N2W0E,REGS.WCTLB.N2W1E,REGS.WCTLB.N2SWE & REGS.SPCTL.SPWINEN,REGS.WCTLB.N2LOG),
	                   WinTest(TW0_HIT ^ REGS.WCTLB.N3W0A,TW1_HIT ^ REGS.WCTLB.N3W1A,SDOT.WN ^ REGS.WCTLB.N3SWA,REGS.WCTLB.N3W0E,REGS.WCTLB.N3W1E,REGS.WCTLB.N3SWE & REGS.SPCTL.SPWINEN,REGS.WCTLB.N3LOG)};
	wire RxW_EN[2] = '{WinTest(TW0_HIT ^ REGS.WCTLC.R0W0A,TW1_HIT ^ REGS.WCTLC.R0W1A,SDOT.WN ^ REGS.WCTLC.R0SWA,REGS.WCTLC.R0W0E,REGS.WCTLC.R0W1E,REGS.WCTLC.R0SWE & REGS.SPCTL.SPWINEN,REGS.WCTLC.R0LOG),
	                   0};
	wire SW_EN     =   WinTest(TW0_HIT ^ REGS.WCTLC.SPW0A,TW1_HIT ^ REGS.WCTLC.SPW1A,SDOT.WN ^ REGS.WCTLC.SPSWA,REGS.WCTLC.SPW0E,REGS.WCTLC.SPW1E,REGS.WCTLC.SPSWE & REGS.SPCTL.SPWINEN,REGS.WCTLC.SPLOG);
	wire CCW_EN    =   WinTest(TW0_HIT ^ REGS.WCTLD.CCW0A,TW1_HIT ^ REGS.WCTLD.CCW1A,SDOT.WN ^ REGS.WCTLD.CCSWA,REGS.WCTLD.CCW0E,REGS.WCTLD.CCW1E,REGS.WCTLD.CCSWE & REGS.SPCTL.SPWINEN,REGS.WCTLD.CCLOG);
`endif
							 
	ScreenDot_t DOT_FST, DOT_SEC, DOT_THD, DOT_FTH;
	always @(posedge CLK or negedge RST_N) begin
		bit         SON, R0ON, N0ON, N1ON, N2ON, N3ON;
		bit   [2:0] SCAOS, R0CAOS, N0CAOS, N1CAOS, N2CAOS, N3CAOS;
		bit         R0SFC, N0SFC, N1SFC, N2SFC, N3SFC;
		bit   [2:0] SPRIN, R0PRIN, N0PRIN, N1PRIN, N2PRIN, N3PRIN;
		bit         SCCEN, R0CCEN, N0CCEN, N1CCEN, N2CCEN, N3CCEN, LCCCEN;
		bit         SCCM3, R0CCM3, N0CCM3, N1CCM3, N2CCM3, N3CCM3;
		bit   [4:0] SCCRT, R0CCRT, N0CCRT, N1CCRT, N2CCRT, N3CCRT, BKCCRT, LCCCRT;
		bit         SCOEN, R0COEN, N0COEN, N1COEN, N2COEN, N3COEN, BKCOEN;
		bit         SCOSL, R0COSL, N0COSL, N1COSL, N2COSL, N3COSL, BKCOSL;
		bit         SSDEN, R0SDEN, N0SDEN, N1SDEN, N2SDEN, N3SDEN, BKSDEN;
		bit         SBOKEN, R0BOKEN, N0BOKEN, N1BOKEN, N2BOKEN, N3BOKEN;
		bit         SLCEN, R0LCEN, N0LCEN, N1LCEN, N2LCEN, N3LCEN;
		ScreenDot_t FST, SEC, THD, FTH;
		bit   [2:0] FST_PRI, SEC_PRI, THD_PRI, FTH_PRI;
		ScreenDot_t SDA[9];
		bit   [3:0] FI, SI, TI;
		bit         FBOK, SBOK, FLC;
		ScreenDot_t RF, RS, RT;
		bit         NkBOK[4], NkLC[4];
		bit         NkON[4];
		bit   [2:0] NkPRIN[4];
		bit         LV[7], LB[7], LL[7];   // (A2) per layer index 1-6: valid (takes part), BOKEN, LCEN
		bit   [2:0] LP[7];                 // (A2) per layer index 1-6: priority
		bit   [6:1] BT;                    // (A2) the layers that come before layer i
		bit         P0, P1, P2;            // (A2) layer i takes the first / second / third place
		
		if (!RST_N) begin
			// synopsys translate_off
			DOT_FST <= SD_NULL;
			DOT_SEC <= SD_NULL;
			DOT_THD <= SD_NULL;
			DOT_FTH <= SD_NULL;
			// synopsys translate_on
		end
		else if (DOT_CE_R || (DOT_CE_F & HRES[1])) begin
			SON  =                                                                                        ~SDOT.TP  & SCRN_EN[5] & ~(SW_EN     & SCRN_EN[6]);
			R0ON = (               RSxREG[0].ON) &                                                        ~R0DOT.TP & SCRN_EN[4] & ~(RxW_EN[0] & SCRN_EN[6]);
			N0ON = (NSxREG[0].ON | RSxREG[1].ON) &                                                        ~N0DOT.TP & SCRN_EN[0] & ~(NxW_EN[0] & SCRN_EN[6]);
			N1ON = (NSxREG[1].ON               ) & ~NSxREG[0].CHCN[2] &                                   ~N1DOT.TP & SCRN_EN[1] & ~(NxW_EN[1] & SCRN_EN[6]);
			N2ON = (NSxREG[2].ON               ) & ~NSxREG[0].CHCN[2] & ~NSxREG[0].CHCN[1] & ~N0_REDUCE & ~N2DOT.TP & SCRN_EN[2] & ~(NxW_EN[2] & SCRN_EN[6]);
			N3ON = (NSxREG[3].ON               ) & ~NSxREG[0].CHCN[2] & ~NSxREG[1].CHCN[1] & ~N1_REDUCE & ~N3DOT.TP & SCRN_EN[3] & ~(NxW_EN[3] & SCRN_EN[6]);
			
			SCAOS = REGS.CRAOFB.SPCAOS;
			R0CAOS = REGS.CRAOFB.R0CAOS;
			N0CAOS = NSxREG[0].CAOS;
			N1CAOS = NSxREG[1].CAOS;
			N2CAOS = NSxREG[2].CAOS;
			N3CAOS = NSxREG[3].CAOS;
			
			R0SFC = SFCMatch(REGS.SFSEL.R0SFCS,REGS.SFCODE,R0DOT.DC[3:0]);
			N0SFC = SFCMatch(REGS.SFSEL.N0SFCS,REGS.SFCODE,N0DOT.DC[3:0]);
			N1SFC = SFCMatch(REGS.SFSEL.N1SFCS,REGS.SFCODE,N1DOT.DC[3:0]);
			N2SFC = SFCMatch(REGS.SFSEL.N2SFCS,REGS.SFCODE,N2DOT.DC[3:0]);
			N3SFC = SFCMatch(REGS.SFSEL.N3SFCS,REGS.SFCODE,N3DOT.DC[3:0]);
			
			case (SDOT.PR)
				3'h0: SPRIN = REGS.PRISA.S0PRIN;
				3'h1: SPRIN = REGS.PRISA.S1PRIN;
				3'h2: SPRIN = REGS.PRISB.S2PRIN;
				3'h3: SPRIN = REGS.PRISB.S3PRIN;
				3'h4: SPRIN = REGS.PRISC.S4PRIN;
				3'h5: SPRIN = REGS.PRISC.S5PRIN;
				3'h6: SPRIN = REGS.PRISD.S6PRIN;
				3'h7: SPRIN = REGS.PRISD.S7PRIN;
			endcase
			R0PRIN = RSxREG[0].SPRM == 2'b01 ? {RSxREG[0].PRIN[2:1],R0DOT.PR} : RSxREG[0].SPRM == 2'b10 ? {RSxREG[0].PRIN[2:1],R0DOT.PR & R0SFC} : RSxREG[0].PRIN;
			N0PRIN = NSxREG[0].SPRM == 2'b01 ? {NSxREG[0].PRIN[2:1],N0DOT.PR} : NSxREG[0].SPRM == 2'b10 ? {NSxREG[0].PRIN[2:1],N0DOT.PR & N0SFC} : NSxREG[0].PRIN; 
			N1PRIN = NSxREG[1].SPRM == 2'b01 ? {NSxREG[1].PRIN[2:1],N1DOT.PR} : NSxREG[1].SPRM == 2'b10 ? {NSxREG[1].PRIN[2:1],N1DOT.PR & N1SFC} : NSxREG[1].PRIN;
			N2PRIN = NSxREG[2].SPRM == 2'b01 ? {NSxREG[2].PRIN[2:1],N2DOT.PR} : NSxREG[2].SPRM == 2'b10 ? {NSxREG[2].PRIN[2:1],N2DOT.PR & N2SFC} : NSxREG[2].PRIN;
			N3PRIN = NSxREG[3].SPRM == 2'b01 ? {NSxREG[3].PRIN[2:1],N3DOT.PR} : NSxREG[3].SPRM == 2'b10 ? {NSxREG[3].PRIN[2:1],N3DOT.PR & N3SFC} : NSxREG[3].PRIN;
			
			SCCEN = REGS.CCCTL.SPCCEN & ~(CCW_EN & SCRN_EN[6]) & ((REGS.SPCTL.SPCCCS == 2'b00 & SPRIN <= REGS.SPCTL.SPCCN) | 
			                                                      (REGS.SPCTL.SPCCCS == 2'b01 & SPRIN == REGS.SPCTL.SPCCN) |
												                           (REGS.SPCTL.SPCCCS == 2'b10 & SPRIN >= REGS.SPCTL.SPCCN) |
												                           (REGS.SPCTL.SPCCCS == 2'b11));
			R0CCEN = (RSxREG[0].SCCM == 2'b01 ? R0DOT.CC : RSxREG[0].SCCM == 2'b10 ? R0SFC & R0DOT.CC : 1'b1) & RSxREG[0].CCEN & ~(CCW_EN & SCRN_EN[6]);
			N0CCEN = (NSxREG[0].SCCM == 2'b01 ? N0DOT.CC : NSxREG[0].SCCM == 2'b10 ? N0SFC & N0DOT.CC : 1'b1) & NSxREG[0].CCEN & ~(CCW_EN & SCRN_EN[6]);
			N1CCEN = (NSxREG[1].SCCM == 2'b01 ? N1DOT.CC : NSxREG[1].SCCM == 2'b10 ? N1SFC & N1DOT.CC : 1'b1) & NSxREG[1].CCEN & ~(CCW_EN & SCRN_EN[6]);
			N2CCEN = (NSxREG[2].SCCM == 2'b01 ? N2DOT.CC : NSxREG[2].SCCM == 2'b10 ? N2SFC & N2DOT.CC : 1'b1) & NSxREG[2].CCEN & ~(CCW_EN & SCRN_EN[6]);
			N3CCEN = (NSxREG[3].SCCM == 2'b01 ? N3DOT.CC : NSxREG[3].SCCM == 2'b10 ? N3SFC & N3DOT.CC : 1'b1) & NSxREG[3].CCEN & ~(CCW_EN & SCRN_EN[6]);
			LCCCEN = REGS.CCCTL.LCCCEN & ~(CCW_EN & SCRN_EN[6]);
			
			SCCM3 = REGS.SPCTL.SPCCCS == 2'b11;
			R0CCM3 = RSxREG[0].SCCM == 2'b11;
			N0CCM3 = NSxREG[0].SCCM == 2'b11;
			N1CCM3 = NSxREG[1].SCCM == 2'b11;
			N2CCM3 = NSxREG[2].SCCM == 2'b11;
			N3CCM3 = NSxREG[3].SCCM == 2'b11;
			
			case (SDOT.CC)
				3'h0: SCCRT = REGS.CCRSA.S0CCRT;
				3'h1: SCCRT = REGS.CCRSA.S1CCRT;
				3'h2: SCCRT = REGS.CCRSB.S2CCRT;
				3'h3: SCCRT = REGS.CCRSB.S3CCRT;
				3'h4: SCCRT = REGS.CCRSC.S4CCRT;
				3'h5: SCCRT = REGS.CCRSC.S5CCRT;
				3'h6: SCCRT = REGS.CCRSD.S6CCRT;
				3'h7: SCCRT = REGS.CCRSD.S7CCRT;
			endcase
			R0CCRT = RSxREG[0].CCRT;
			N0CCRT = NSxREG[0].CCRT;
			N1CCRT = NSxREG[1].CCRT;
			N2CCRT = NSxREG[2].CCRT;
			N3CCRT = NSxREG[3].CCRT;
			BKCCRT = REGS.CCRLB.BKCCRT;
			LCCCRT = REGS.CCRLB.LCCCRT;
			
			SCOEN = REGS.CLOFEN.SPCOEN; SCOSL = REGS.CLOFSL.SPCOSL;
			R0COEN = RSxREG[0].COEN;    R0COSL = RSxREG[0].COSL;
			N0COEN = NSxREG[0].COEN;    N0COSL = NSxREG[0].COSL;
			N1COEN = NSxREG[1].COEN;    N1COSL = NSxREG[1].COSL;
			N2COEN = NSxREG[2].COEN;    N2COSL = NSxREG[2].COSL;
			N3COEN = NSxREG[3].COEN;    N3COSL = NSxREG[3].COSL;
			BKCOEN = REGS.CLOFEN.BKCOEN;BKCOSL = REGS.CLOFSL.BKCOSL;
			
			BKSDEN = REGS.SDCTL.BKSDEN & SDOT.SD &                 & SCRN_EN[7];
			SSDEN  =                     SDOT.SD                   & SCRN_EN[7];
			R0SDEN = REGS.SDCTL.R0SDEN & SDOT.SD & SPRIN >= R0PRIN & SCRN_EN[7];
			N0SDEN = REGS.SDCTL.N0SDEN & SDOT.SD & SPRIN >= N0PRIN & SCRN_EN[7];
			N1SDEN = REGS.SDCTL.N1SDEN & SDOT.SD & SPRIN >= N1PRIN & SCRN_EN[7];
			N2SDEN = REGS.SDCTL.N2SDEN & SDOT.SD & SPRIN >= N2PRIN & SCRN_EN[7];
			N3SDEN = REGS.SDCTL.N3SDEN & SDOT.SD & SPRIN >= N3PRIN & SCRN_EN[7];
			
`ifdef CUT_VDP2_GRAD
			//U8 CUT_VDP2_GRAD: gradation (CCCTL.BOKEN / BOKN) is cut: no layer's dots are marked for it (the cut reads
			//neither BOKEN nor BOKN; CCCTL is write-only: REG_DO returns TVMD, EXTEN, TVSTAT, VRSIZE, HCNT, VCNT, RAMCTL)
			SBOKEN  = 1'b0;
			R0BOKEN = 1'b0;
			N0BOKEN = 1'b0;
			N1BOKEN = 1'b0;
			N2BOKEN = 1'b0;
			N3BOKEN = 1'b0;
`else
			SBOKEN  = (REGS.CCCTL.BOKN == 3'h0) & REGS.CCCTL.BOKEN & ~|REGS.RAMCTL.CRMD;
			R0BOKEN = (REGS.CCCTL.BOKN == 3'h1) & REGS.CCCTL.BOKEN & ~|REGS.RAMCTL.CRMD;
			N0BOKEN = (REGS.CCCTL.BOKN == 3'h2) & REGS.CCCTL.BOKEN & ~|REGS.RAMCTL.CRMD;
			N1BOKEN = (REGS.CCCTL.BOKN == 3'h4) & REGS.CCCTL.BOKEN & ~|REGS.RAMCTL.CRMD;
			N2BOKEN = (REGS.CCCTL.BOKN == 3'h5) & REGS.CCCTL.BOKEN & ~|REGS.RAMCTL.CRMD;
			N3BOKEN = (REGS.CCCTL.BOKN == 3'h6) & REGS.CCCTL.BOKEN & ~|REGS.RAMCTL.CRMD;
`endif
			
			SLCEN = REGS.LNCLEN.SPLCEN;
			R0LCEN = REGS.LNCLEN.R0LCEN;
			N0LCEN = REGS.LNCLEN.N0LCEN;
			N1LCEN = REGS.LNCLEN.N1LCEN;
			N2LCEN = REGS.LNCLEN.N2LCEN;
			N3LCEN = REGS.LNCLEN.N3LCEN;
			
			// Sort (priority, layer index) pairs only, then select the dot records once. Index: 0 back screen, 1 sprite,
			// 2 RBG0, 3-6 NBG0-3; 7 line colour screen, 8 zero (final stage only). Same insertion rules as before.
			NkON = '{N0ON, N1ON, N2ON, N3ON};
			NkPRIN = '{N0PRIN, N1PRIN, N2PRIN, N3PRIN};
			NkBOK = '{N0BOKEN, N1BOKEN, N2BOKEN, N3BOKEN};
			NkLC = '{N0LCEN, N1LCEN, N2LCEN, N3LCEN};
			SDA[0] = {3'b000,1'b0,1'b0,BKCCRT,BKCOEN,BKCOSL,BKSDEN,1'b0,1'b0,1'b0,BACK_DC};
			SDA[1] = {SCAOS,SCCEN,SCCM3,SCCRT,SCOEN,SCOSL,SSDEN,SBOKEN,SLCEN,SDOT.P,SDOT.DC};
			SDA[2] = {R0CAOS,R0CCEN,R0CCM3,R0CCRT,R0COEN,R0COSL,R0SDEN,R0BOKEN,R0LCEN,R0DOT.P,R0DOT.DC};
			SDA[3] = {N0CAOS,N0CCEN,N0CCM3,N0CCRT,N0COEN,N0COSL,N0SDEN,N0BOKEN,N0LCEN,N0DOT.P,N0DOT.DC};
			SDA[4] = {N1CAOS,N1CCEN,N1CCM3,N1CCRT,N1COEN,N1COSL,N1SDEN,N1BOKEN,N1LCEN,N1DOT.P,N1DOT.DC};
			SDA[5] = {N2CAOS,N2CCEN,N2CCM3,N2CCRT,N2COEN,N2COSL,N2SDEN,N2BOKEN,N2LCEN,N2DOT.P,N2DOT.DC};
			SDA[6] = {N3CAOS,N3CCEN,N3CCM3,N3CCRT,N3COEN,N3COSL,N3SDEN,N3BOKEN,N3LCEN,N3DOT.P,N3DOT.DC};
			SDA[7] = {3'b000,LCCCEN,1'b0,LCCCRT,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,{13'b0000000000000,LINE_PAL}};
			SDA[8] = '0;
			// The BOKEN/LCEN flags of the first two places travel with the indices (FBOK/SBOK/FLC), so the final
			// selection does not wait for an index-to-record lookup.
			// (A2, timing) the three places of the insertion sort that was here, computed in parallel: a layer takes part when
			// DISP is set, it is on and its priority is not 0 (LV); layer j comes before layer i when it takes part and has a
			// higher priority, or the same priority and a lower index (the insertion kept the earlier layer ahead on a tie:
			// its compares were strict). Layer i takes place r (0 first, 1 second, 2 third) when it takes part and exactly r
			// layers come before it; the places of the taking-part layers are all different, so at most one layer takes each
			// place and the places can be OR-ed together. An empty place keeps index 0 (back screen) with BOK / LC 0, as the
			// insertion left them (FI / SI / TI, FBOK, SBOK, FLC: the same values in every case).
			LV[0] = 0; LP[0] = 3'd0; LB[0] = 0; LL[0] = 0;
			LV[1] = DISP && SON  && (SPRIN  != 3'd0); LP[1] = SPRIN;  LB[1] = SBOKEN;  LL[1] = SLCEN;
			LV[2] = DISP && R0ON && (R0PRIN != 3'd0); LP[2] = R0PRIN; LB[2] = R0BOKEN; LL[2] = R0LCEN;
			for (int k = 0; k < 4; k++) begin
				LV[3+k] = DISP && NkON[k] && (NkPRIN[k] != 3'd0); LP[3+k] = NkPRIN[k]; LB[3+k] = NkBOK[k]; LL[3+k] = NkLC[k];
			end
			FI = 4'd0; FBOK = 0; FLC = 0;
			SI = 4'd0; SBOK = 0;
			TI = 4'd0;
			for (int i = 1; i <= 6; i++) begin
				for (int j = 1; j <= 6; j++)
					BT[j] = (j != i) && LV[j] && ((j < i) ? (LP[j] >= LP[i]) : (LP[j] > LP[i]));
				P0 = LV[i] && (BT == 6'b000000);
				P1 = LV[i] && (BT == 6'b000001 || BT == 6'b000010 || BT == 6'b000100 || BT == 6'b001000 || BT == 6'b010000 ||
				               BT == 6'b100000);
				P2 = LV[i] && (BT == 6'b000011 || BT == 6'b000101 || BT == 6'b001001 || BT == 6'b010001 || BT == 6'b100001 ||
				               BT == 6'b000110 || BT == 6'b001010 || BT == 6'b010010 || BT == 6'b100010 ||
				               BT == 6'b001100 || BT == 6'b010100 || BT == 6'b100100 ||
				               BT == 6'b011000 || BT == 6'b101000 || BT == 6'b110000);
				FI = FI | (P0 ? 4'(i) : 4'd0); FBOK = FBOK | (P0 && LB[i]); FLC = FLC | (P0 && LL[i]);
				SI = SI | (P1 ? 4'(i) : 4'd0); SBOK = SBOK | (P1 && LB[i]);
				TI = TI | (P2 ? 4'(i) : 4'd0);
			end
			
			RF = SDA[FI]; RS = SDA[SI]; RT = SDA[TI];
			DOT_FST <= RF;
`ifdef CUT_VDP2_GRAD
			if (FLC) begin	//CUT_VDP2_GRAD: no gradation selections (FBOK / SBOK)
`else
			if (FBOK) begin
				DOT_SEC <= RF; DOT_THD <= RF; DOT_FTH <= RF;
			end else if (SBOK) begin
				DOT_SEC <= RS; DOT_THD <= RS; DOT_FTH <= RS;
			end else if (FLC) begin
`endif
				DOT_SEC <= SDA[7]; DOT_THD <= RS; DOT_FTH <= RT;
			end else begin
				DOT_SEC <= RS; DOT_THD <= RT; DOT_FTH <= '0;
			end
		end
	end
	
	//Dots color
	bit [10:0] PAL_N;
	always_comb begin
		bit [10: 0] PAL;
		bit [ 2: 0] CAOS;
		
		case (DOTCLK_DIV & {~HRES[1],1'b1})
			2'b00: {CAOS,PAL} = {DOT_FST.CAOS,DOT_FST.DC[10:0]};
			2'b01: {CAOS,PAL} = {DOT_SEC.CAOS,DOT_SEC.DC[10:0]};
			2'b10: {CAOS,PAL} = {DOT_THD.CAOS,DOT_THD.DC[10:0]};
			2'b11: {CAOS,PAL} = {DOT_FTH.CAOS,DOT_FTH.DC[10:0]};
		endcase
		PAL_N = {CAOS,8'b00000000} + PAL;
	end
	
	DotColor_t CFST, CSEC;
	bit  [4:0] CCRT;
	bit        CCENFST;
	bit        COEN;
	bit        COSL;
	bit        SDEN;
	bit        HB_INT2;
	always @(posedge CLK or negedge RST_N) begin
		bit [23:0] DC;
		bit        CC;
		DotColor_t DC_FST_LATCH, DC_SEC_LATCH, DC_THD_LATCH;
		bit        CC_FST;
		bit        BOKEN_PREV1,BOKEN_PREV2;
		DotColor_t CSEC_PREV1, CSEC_PREV2;
		DotColor_t CSEC_DC, CTHD_DC, CFTH_DC;
		DotColor_t CSEC_ECC;
		
		if (!RST_N) begin
			// synopsys translate_off
			DC_FST_LATCH <= DC_NULL;
			DC_SEC_LATCH <= DC_NULL;
			DC_THD_LATCH <= DC_NULL;
			CC_FST <= 0;
			CFST <= DC_NULL;
			CSEC <= DC_NULL;
			CCRT <= '0;
			CCENFST <= 0;
			SDEN <= 0;
			COEN <= 0;
			COSL <= 0;
			// synopsys translate_on
		end
		else begin
			if (CE_R) begin
				case (REGS.RAMCTL.CRMD)
					2'b00: begin DC = Color555To888(PAL0_Q);                       CC =              PAL0_Q[15]; end
					2'b01: begin DC = Color555To888(!PAL_N[10] ? PAL0_Q : PAL1_Q); CC = !PAL_N[10] ? PAL0_Q[15] : PAL1_Q[15]; end
					default: begin DC = {PAL0_Q[7:0],PAL1_Q};                      CC =              PAL0_Q[15]; end
				endcase
				case (DOTCLK_DIV & {~HRES[1],1'b1})
					2'd0: {CC_FST,DC_FST_LATCH} <= {CC,DC};
					2'd1: DC_SEC_LATCH <= DC;
					2'd2: DC_THD_LATCH <= DC;
					2'd3: ;
				endcase
			end
			
			CSEC_DC = !DOT_SEC.P ? DOT_SEC.DC : DC_SEC_LATCH;
`ifdef CUT_VDP2_GRAD
			CTHD_DC = !DOT_THD.P ? DOT_THD.DC : DC_THD_LATCH;	//CUT_VDP2_GRAD: no previous-dot colours (gradation)
			CFTH_DC = !DOT_FTH.P ? DOT_FTH.DC : DC;
			CSEC_ECC = ExtColorCalc(CSEC_DC, DOT_SEC.CCEN, CTHD_DC, DOT_THD.P, DOT_THD.CCEN, CFTH_DC, DOT_FST.LCEN, 1'b0, REGS.RAMCTL.CRMD, REGS.CCCTL.EXCCEN);
`else
			CTHD_DC = BOKEN_PREV1 ? CSEC_PREV1 : !DOT_THD.P ? DOT_THD.DC : DC_THD_LATCH;
			CFTH_DC = BOKEN_PREV2 ? CSEC_PREV2 : !DOT_FTH.P ? DOT_FTH.DC : DC;
			CSEC_ECC = ExtColorCalc(CSEC_DC, DOT_SEC.CCEN, CTHD_DC, DOT_THD.P, DOT_THD.CCEN, CFTH_DC, DOT_FST.LCEN, DOT_SEC.BOKEN, REGS.RAMCTL.CRMD, REGS.CCCTL.EXCCEN & ~REGS.CCCTL.BOKEN);
`endif
			if (!HRES[1] && DOT_CE_R) begin
				CFST <= !DOT_FST.P ? DOT_FST.DC : DC_FST_LATCH;
				CSEC <= CSEC_ECC;
				CCRT <= !REGS.CCCTL.CCRTMD ? DOT_FST.CCRT : DOT_SEC.CCRT;
				CCENFST <= !DOT_FST.CCM3 ? DOT_FST.CCEN : DOT_FST.CCEN & (CC_FST | ~DOT_FST.P);
				COEN <= DOT_FST.COEN; 
				COSL <= DOT_FST.COSL;
				SDEN <= DOT_FST.SDEN;
				
`ifdef CUT_VDP2_GRAD
				//CUT_VDP2_GRAD: no previous-dot pipeline (CSEC_PREV1/2, BOKEN_PREV1/2)
`else
				CSEC_PREV2 <= CSEC_PREV1; CSEC_PREV1 <= !DOT_SEC.P ? DOT_SEC.DC : DC_SEC_LATCH;
				BOKEN_PREV2 <= BOKEN_PREV1; BOKEN_PREV1 <= DOT_SEC.BOKEN;
`endif
			end
			else if (HRES[1] && (DOT_CE_R || DOT_CE_F)) begin
				CFST <= !DOT_FST.P ? DOT_FST.DC : DC_FST_LATCH;
				CSEC <= !DOT_SEC.P ? DOT_SEC.DC : DC;
				CCRT <= !REGS.CCCTL.CCRTMD ? DOT_FST.CCRT : DOT_SEC.CCRT;
				CCENFST <= |REGS.RAMCTL.CRMD && DOT_SEC.P ? 1'b0 : !DOT_FST.CCM3 ? DOT_FST.CCEN : DOT_FST.CCEN & (CC_FST | ~DOT_FST.P);
				COEN <= DOT_FST.COEN; 
				COSL <= DOT_FST.COSL;
				SDEN <= DOT_FST.SDEN;
			end
			
			if (DOT_CE_R) begin
				HB_INT2 <= HB_INT;
			end
			if (HB_INT2 && DOT_CE_F) begin
				CFST <= DC_NULL;
				CSEC <= DC_NULL;
				CCENFST <= 0;
				SDEN <= 0;
				COEN <= 0;
				COSL <= 0;
`ifdef CUT_VDP2_GRAD
				//CUT_VDP2_GRAD: (BOKEN_PREV1/2 cleared here)
`else
				BOKEN_PREV1 <= 0;
				BOKEN_PREV2 <= 0; 
`endif
			end
		end
	end
	
	DotColor_t DCOL;
	bit        HB_INT3;
	always @(posedge CLK or negedge RST_N) begin
		DotColor_t C;
		
		if (!RST_N) begin
			// synopsys translate_off
			DCOL <= DC_NULL;
			// synopsys translate_on
		end else begin
			C <= ColorCalc(CFST, CSEC, CCRT, CCENFST, REGS.CCCTL.CCMD);
			if (DOT_CE_R || DOT_CE_F) begin
				DCOL.B <= Shadow(ColorOffset(C.B, REGS.COAB.COBL, REGS.COBB.COBL, COEN, COSL), SDEN); 
				DCOL.G <= Shadow(ColorOffset(C.G, REGS.COAG.COGR, REGS.COBG.COGR, COEN, COSL), SDEN); 
				DCOL.R <= Shadow(ColorOffset(C.R, REGS.COAR.CORD, REGS.COBR.CORD, COEN, COSL), SDEN); 
			end
			
			if (DOT_CE_R) begin
				HB_INT3 <= HB_INT2;
			end
			
			if (!DISP) begin
				DCOL <= BACK_DC;
			end else if (HB_INT3 && DOT_CE_F) begin
				DCOL <= DC_NULL;
			end
		end
	end

	assign R = DCOL.R;
	assign G = DCOL.G;
	assign B = DCOL.B;
	assign VBL_N = ~VBLANK;
	assign HBL_N = ~HB_INT3;
	assign VS_N = ~VSYNC;
	assign HS_N = ~HSYNC;
	assign FIELD = ~ODD && INTERLACE_INT;
	assign INTERLACE = INTERLACE_INT;
	
	
	//Color RAM
	wire         PAL_SEL = (A[20:19] == 2'b10) && !CS_N && !AD_N;	//100000-17FFFF
	wire         PAL_WE = PAL_SEL && !WE_N && !DTEN_N && !REQ_N;
	wire [11: 1] IO_PAL_ADDR = AD_N ? {A[11:9],DI[7:0]} : A[11:1];
	wire [10: 1] IO_PAL_A   = REGS.RAMCTL.CRMD >= 2'b10 ? IO_PAL_ADDR[11:2] : IO_PAL_ADDR[10:1];
	wire         IO_PAL0_WE = (REGS.RAMCTL.CRMD == 2'b01 ? ~A[11] : REGS.RAMCTL.CRMD >= 2'b10 ? ~A[1] : 1'b1) & PAL_WE;
	wire         IO_PAL1_WE = (REGS.RAMCTL.CRMD == 2'b01 ?  A[11] : REGS.RAMCTL.CRMD >= 2'b10 ?  A[1] : 1'b1) & PAL_WE;
	wire [10: 1] PAL_A = PAL_N[9:0];
	
	wire         IO_PAL_RD = REGS.RAMCTL.CRMD >= 2'b10 ? A[1] : A[11];
	
	VDP2_PAL_RAM pal1
	(
		.CLK(CLK),
		
		.ADDR_A(PAL_A),
		.DATA_A(16'h0000),
		.WREN_A(2'b00),
		.Q_A(PAL0_Q),
		
		.ADDR_B(IO_PAL_A),
		.DATA_B(DI),
		.WREN_B({2{IO_PAL0_WE}}),
		.Q_B(PAL0_DO)
	);
	
	VDP2_PAL_RAM pal2
	(
		.CLK(CLK),
		
`ifdef CUT_VDP2_CRKTE
		.ADDR_A(PAL_A),	//CUT_VDP2_CRKTE: never the coefficient address
`else
		.ADDR_A(!REGS.RAMCTL.CRKTE ? PAL_A : (CT_CRAM_A + DOTCLK_DIV[0])),
`endif
		.DATA_A(16'h0000),
		.WREN_A(2'b00),
		.Q_A(PAL1_Q),
		
		.ADDR_B(IO_PAL_A),
		.DATA_B(DI),
		.WREN_B({2{IO_PAL1_WE}}),
		.Q_B(PAL1_DO)
	);
	
`ifdef CUT_VDP2_CRKTE
	//CUT_VDP2_CRKTE: no CRAM coefficient address / data registers (CT_CRAM_A, CT_CRAM_Q)
`else
	bit  [10:1] CT_CRAM_A;
	bit  [31:0] CT_CRAM_Q;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			// synopsys translate_off
			CT_CRAM_A <= '0;
			CT_CRAM_Q <= '0;
			// synopsys translate_on
		end else begin
			if (RBG_PIPE[0].RxCRCT[0] && DOT_CE_R) begin
				CT_CRAM_A <= RxCT_ADDR[0][10:1];
			end
			if (RBG_PIPE[0].RxCRCT[1] && DOT_CE_R) begin
				CT_CRAM_A <= RxCT_ADDR[1][10:1];
			end
			
			if (CE_R) begin
				case (DOTCLK_DIV)
					2'd0: CT_CRAM_Q[31:16] <= PAL1_Q;
					2'd1: CT_CRAM_Q[15: 0] <= PAL1_Q;
					2'd2: ;
					2'd3: ;
				endcase
			end
		end
	end
`endif
	
	//Registers
	wire VRAM_SEL = ~A[20] & ~CS_N & ~AD_N ;	//000000-0FFFFF
	wire VRAM_REQ = VRAM_SEL & ~REQ_N;
	wire REG_SEL = (A[20:18] == 3'b110) & ~CS_N & ~AD_N;
	
	bit [20: 1] A;
	bit         WE_N;
	bit [ 1: 0] DQM;
	bit         BURST;
	bit [15: 0] REG_DO;
	bit         REG_RRDY;
	bit [ 8: 1] REG_RA;
	bit [15: 0] PAL_DO;
	always @(posedge CLK or negedge RST_N) begin
		bit         EXLAT_N_OLD;
		bit [ 3: 0] REG_RD_DELAY;
		
		if (!RST_N) begin
			// synopsys translate_off
			REGS.TVMD <= '0;
			REGS.EXTEN <= '0;
			REGS.TVSTAT <= '0;
			REGS.VRSIZE <= '0;
//			REGS.HCNT <= '0;
//			REGS.VCNT <= '0;
			REGS.RSRV0 <= '0;
			REGS.RAMCTL <= '0;
			REGS.CYCA0L <= '0;
			REGS.CYCA0U <= '0;
			REGS.CYCA1L <= '0;
			REGS.CYCA1U <= '0;
			REGS.CYCB0L <= '0;
			REGS.CYCB0U <= '0;
			REGS.CYCB1L <= '0;
			REGS.CYCB1U <= '0;
			REGS.BGON <= '0;
			REGS.MZCTL <= '0;
			REGS.SFSEL <= '0;
			REGS.SFCODE <= '0;
			REGS.CHCTLA <= '0;
			REGS.CHCTLB <= '0;
			REGS.BMPNA <= '0;
			REGS.BMPNB <= '0;
			REGS.PNCN0 <= '0;
			REGS.PNCN1 <= '0;
			REGS.PNCN2 <= '0;
			REGS.PNCN3 <= '0;
			REGS.PNCR <= '0;
			REGS.PLSZ <= '0;
			REGS.MPOFN <= '0;
			REGS.MPOFR <= '0;
			REGS.MPABN0 <= '0;
			REGS.MPCDN0 <= '0;
			REGS.MPABN1 <= '0;
			REGS.MPCDN1 <= '0;
			REGS.MPABN2 <= '0;
			REGS.MPCDN2 <= '0;
			REGS.MPABN3 <= '0;
			REGS.MPCDN3 <= '0;
			REGS.MPABRA <= '0;
			REGS.MPCDRA <= '0;
			REGS.MPEFRA <= '0;
			REGS.MPGHRA <= '0;
			REGS.MPIJRA <= '0;
			REGS.MPKLRA <= '0;
			REGS.MPMNRA <= '0;
			REGS.MPOPRA <= '0;
			REGS.MPABRB <= '0;
			REGS.MPCDRB <= '0;
			REGS.MPEFRB <= '0;
			REGS.MPGHRB <= '0;
			REGS.MPIJRB <= '0;
			REGS.MPKLRB <= '0;
			REGS.MPMNRB <= '0;
			REGS.MPOPRB <= '0;
			REGS.SCXIN0 <= '0;
			REGS.SCXDN0 <= '0;
			REGS.SCYIN0 <= '0;
			REGS.SCYDN0 <= '0;
			REGS.ZMXIN0 <= '0;
			REGS.ZMXDN0 <= '0;
			REGS.ZMYIN0 <= '0;
			REGS.ZMYDN0 <= '0;
			REGS.SCXIN1 <= '0;
			REGS.SCXDN1 <= '0;
			REGS.SCYIN1 <= '0;
			REGS.SCYDN1 <= '0;
			REGS.ZMXIN1 <= '0;
			REGS.ZMXDN1 <= '0;
			REGS.ZMYIN1 <= '0;
			REGS.ZMYDN1 <= '0;
			REGS.SCXN2 <= '0;
			REGS.SCYN2 <= '0;
			REGS.SCXN3 <= '0;
			REGS.SCYN3 <= '0;
			REGS.ZMCTL <= '0;
			REGS.SCRCTL <= '0;
			REGS.VCSTAU <= '0;
			REGS.VCSTAL <= '0;
			REGS.LSTA0U <= '0;
			REGS.LSTA0L <= '0;
			REGS.LSTA1U <= '0;
			REGS.LSTA1L <= '0;
			REGS.LCTAU <= '0;
			REGS.LCTAL <= '0;
			REGS.BKTAU <= '0;
			REGS.BKTAL <= '0;
			REGS.RPMD <= '0;
			REGS.RPRCTL <= '0;
			REGS.KTCTL <= '0;
			REGS.KTAOF <= '0;
			REGS.OVPNRA <= '0;
			REGS.OVPNRB <= '0;
			REGS.RPTAU <= '0;
			REGS.RPTAL <= '0;
			REGS.WPSX0 <= '0;
			REGS.WPSY0 <= '0;
			REGS.WPEX0 <= '0;
			REGS.WPEY0 <= '0;
			REGS.WPSX1 <= '0;
			REGS.WPSY1 <= '0;
			REGS.WPEX1 <= '0;
			REGS.WPEY1 <= '0;
			REGS.WCTLA <= '0;
			REGS.WCTLB <= '0;
			REGS.WCTLC <= '0;
			REGS.WCTLD <= '0;
			REGS.LWTA0U <= '0;
			REGS.LWTA0L <= '0;
			REGS.LWTA1U <= '0;
			REGS.LWTA1L <= '0;
			REGS.SPCTL <= '0;
			REGS.SDCTL <= '0;
			REGS.CRAOFA <= '0;
			REGS.CRAOFB <= '0;
			REGS.LNCLEN <= '0;
			REGS.SFPRMD <= '0;
			REGS.CCCTL <= '0;
			REGS.SFCCMD <= '0;
			REGS.PRISA <= '0;
			REGS.PRISB <= '0;
			REGS.PRISC <= '0;
			REGS.PRISD <= '0;
			REGS.PRINA <= '0;
			REGS.PRINB <= '0;
			REGS.PRIR <= '0;
			REGS.RSRV1 <= '0;
			REGS.CCRSA <= '0;
			REGS.CCRSB <= '0;
			REGS.CCRSC <= '0;
			REGS.CCRSD <= '0;
			REGS.CCRNA <= '0;
			REGS.CCRNB <= '0;
			REGS.CCRR <= '0;
			REGS.CCRLB <= '0;
			REGS.CLOFEN <= '0;
			REGS.CLOFSL <= '0;
			REGS.COAR <= '0;
			REGS.COAG <= '0;
			REGS.COAB <= '0;
			REGS.COBR <= '0;
			REGS.COBG <= '0;
			REGS.COBB <= '0;

			REG_DO <= '0;
			REG_RRDY <= 0;
			// synopsys translate_on
		end else if (!RES_N) begin
			REGS.TVMD <= '0;
			REGS.EXTEN <= '0;
			REGS.TVSTAT <= '0;
			REGS.VRSIZE <= '0;
//			REGS.HCNT <= '0;
//			REGS.VCNT <= '0;
			REGS.RSRV0 <= '0;
			REGS.RAMCTL <= '0;
			REGS.CYCA0L <= '0;
			REGS.CYCA0U <= '0;
			REGS.CYCA1L <= '0;
			REGS.CYCA1U <= '0;
			REGS.CYCB0L <= '0;
			REGS.CYCB0U <= '0;
			REGS.CYCB1L <= '0;
			REGS.CYCB1U <= '0;
			REGS.BGON <= '0;
			REGS.MZCTL <= '0;
			REGS.SFSEL <= '0;
			REGS.SFCODE <= '0;
			REGS.CHCTLA <= '0;
			REGS.CHCTLB <= '0;
			REGS.BMPNA <= '0;
			REGS.BMPNB <= '0;
			REGS.PNCN0 <= '0;
			REGS.PNCN1 <= '0;
			REGS.PNCN2 <= '0;
			REGS.PNCN3 <= '0;
			REGS.PNCR <= '0;
			REGS.PLSZ <= '0;
			REGS.MPOFN <= '0;
			REGS.MPOFR <= '0;
			REGS.MPABN0 <= '0;
			REGS.MPCDN0 <= '0;
			REGS.MPABN1 <= '0;
			REGS.MPCDN1 <= '0;
			REGS.MPABN2 <= '0;
			REGS.MPCDN2 <= '0;
			REGS.MPABN3 <= '0;
			REGS.MPCDN3 <= '0;
			REGS.MPABRA <= '0;
			REGS.MPCDRA <= '0;
			REGS.MPEFRA <= '0;
			REGS.MPGHRA <= '0;
			REGS.MPIJRA <= '0;
			REGS.MPKLRA <= '0;
			REGS.MPMNRA <= '0;
			REGS.MPOPRA <= '0;
			REGS.MPABRB <= '0;
			REGS.MPCDRB <= '0;
			REGS.MPEFRB <= '0;
			REGS.MPGHRB <= '0;
			REGS.MPIJRB <= '0;
			REGS.MPKLRB <= '0;
			REGS.MPMNRB <= '0;
			REGS.MPOPRB <= '0;
			REGS.SCXIN0 <= '0;
			REGS.SCXDN0 <= '0;
			REGS.SCYIN0 <= '0;
			REGS.SCYDN0 <= '0;
			REGS.ZMXIN0 <= '0;
			REGS.ZMXDN0 <= '0;
			REGS.ZMYIN0 <= '0;
			REGS.ZMYDN0 <= '0;
			REGS.SCXIN1 <= '0;
			REGS.SCXDN1 <= '0;
			REGS.SCYIN1 <= '0;
			REGS.SCYDN1 <= '0;
			REGS.ZMXIN1 <= '0;
			REGS.ZMXDN1 <= '0;
			REGS.ZMYIN1 <= '0;
			REGS.ZMYDN1 <= '0;
			REGS.SCXN2 <= '0;
			REGS.SCYN2 <= '0;
			REGS.SCXN3 <= '0;
			REGS.SCYN3 <= '0;
			REGS.ZMCTL <= '0;
			REGS.SCRCTL <= '0;
			REGS.VCSTAU <= '0;
			REGS.VCSTAL <= '0;
			REGS.LSTA0U <= '0;
			REGS.LSTA0L <= '0;
			REGS.LSTA1U <= '0;
			REGS.LSTA1L <= '0;
			REGS.LCTAU <= '0;
			REGS.LCTAL <= '0;
			REGS.BKTAU <= '0;
			REGS.BKTAL <= '0;
			REGS.RPMD <= '0;
			REGS.RPRCTL <= '0;
			REGS.KTCTL <= '0;
			REGS.KTAOF <= '0;
			REGS.OVPNRA <= '0;
			REGS.OVPNRB <= '0;
			REGS.RPTAU <= '0;
			REGS.RPTAL <= '0;
			REGS.WPSX0 <= '0;
			REGS.WPSY0 <= '0;
			REGS.WPEX0 <= '0;
			REGS.WPEY0 <= '0;
			REGS.WPSX1 <= '0;
			REGS.WPSY1 <= '0;
			REGS.WPEX1 <= '0;
			REGS.WPEY1 <= '0;
			REGS.WCTLA <= '0;
			REGS.WCTLB <= '0;
			REGS.WCTLC <= '0;
			REGS.WCTLD <= '0;
			REGS.LWTA0U <= '0;
			REGS.LWTA0L <= '0;
			REGS.LWTA1U <= '0;
			REGS.LWTA1L <= '0;
			REGS.SPCTL <= '0;
			REGS.SDCTL <= '0;
			REGS.CRAOFA <= '0;
			REGS.CRAOFB <= '0;
			REGS.LNCLEN <= '0;
			REGS.SFPRMD <= '0;
			REGS.CCCTL <= '0;
			REGS.SFCCMD <= '0;
			REGS.PRISA <= '0;
			REGS.PRISB <= '0;
			REGS.PRISC <= '0;
			REGS.PRISD <= '0;
			REGS.PRINA <= '0;
			REGS.PRINB <= '0;
			REGS.PRIR <= '0;
			REGS.RSRV1 <= '0;
			REGS.CCRSA <= '0;
			REGS.CCRSB <= '0;
			REGS.CCRSC <= '0;
			REGS.CCRSD <= '0;
			REGS.CCRNA <= '0;
			REGS.CCRNB <= '0;
			REGS.CCRR <= '0;
			REGS.CCRLB <= '0;
			REGS.CLOFEN <= '0;
			REGS.CLOFSL <= '0;
			REGS.COAR <= '0;
			REGS.COAG <= '0;
			REGS.COAB <= '0;
			REGS.COBR <= '0;
			REGS.COBG <= '0;
			REGS.COBB <= '0;
		end else begin
			if (REG_SEL && !WE_N && !DTEN_N && !REQ_N) begin
				case ({A[8:1],1'b0})
					9'h000: REGS.TVMD <= DI & TVMD_MASK;
					9'h002: REGS.EXTEN <= DI & EXTEN_MASK;
					9'h006: REGS.VRSIZE <= DI & VRSIZE_MASK;
					9'h00C: REGS.RSRV0 <= DI & RSRV_MASK;
					9'h00E: REGS.RAMCTL <= DI & RAMCTL_MASK;
					9'h010: REGS.CYCA0L <= DI & CYCx0L_MASK;
					9'h012: REGS.CYCA0U <= DI & CYCx0U_MASK;
					9'h014: REGS.CYCA1L <= DI & CYCx1L_MASK;
					9'h016: REGS.CYCA1U <= DI & CYCx1U_MASK;
					9'h018: REGS.CYCB0L <= DI & CYCx0L_MASK;
					9'h01A: REGS.CYCB0U <= DI & CYCx0U_MASK;
					9'h01C: REGS.CYCB1L <= DI & CYCx1L_MASK;
					9'h01E: REGS.CYCB1U <= DI & CYCx1U_MASK;
					9'h020: REGS.BGON <= DI & BGON_MASK;
					9'h022: REGS.MZCTL <= DI & MZCTL_MASK;
					9'h024: REGS.SFSEL <= DI & SFSEL_MASK;
					9'h026: REGS.SFCODE <= DI & SFCODE_MASK;
					9'h028: REGS.CHCTLA <= DI & CHCTLA_MASK;
					9'h02A: REGS.CHCTLB <= DI & CHCTLB_MASK;
					9'h02C: REGS.BMPNA <= DI & BMPNA_MASK;
					9'h02E: REGS.BMPNB <= DI & BMPNB_MASK;
					9'h030: REGS.PNCN0 <= DI & PNCNx_MASK;
					9'h032: REGS.PNCN1 <= DI & PNCNx_MASK;
					9'h034: REGS.PNCN2 <= DI & PNCNx_MASK;
					9'h036: REGS.PNCN3 <= DI & PNCNx_MASK;
					9'h038: REGS.PNCR <= DI & PNCR_MASK;
					9'h03A: REGS.PLSZ <= DI & PLSZ_MASK;
					9'h03C: REGS.MPOFN <= DI & MPOFN_MASK;
					9'h03E: REGS.MPOFR <= DI & MPOFR_MASK;
					9'h040: REGS.MPABN0 <= DI & MPABNx_MASK;
					9'h042: REGS.MPCDN0 <= DI & MPCDNx_MASK;
					9'h044: REGS.MPABN1 <= DI & MPABNx_MASK;
					9'h046: REGS.MPCDN1 <= DI & MPCDNx_MASK;
					9'h048: REGS.MPABN2 <= DI & MPABNx_MASK;
					9'h04A: REGS.MPCDN2 <= DI & MPCDNx_MASK;
					9'h04C: REGS.MPABN3 <= DI & MPABNx_MASK;
					9'h04E: REGS.MPCDN3 <= DI & MPCDNx_MASK;
					9'h050: REGS.MPABRA <= DI & MPABRx_MASK;
					9'h052: REGS.MPCDRA <= DI & MPCDRx_MASK;
					9'h054: REGS.MPEFRA <= DI & MPEFRx_MASK;
					9'h056: REGS.MPGHRA <= DI & MPGHRx_MASK;
					9'h058: REGS.MPIJRA <= DI & MPIJRx_MASK;
					9'h05A: REGS.MPKLRA <= DI & MPKLRx_MASK;
					9'h05C: REGS.MPMNRA <= DI & MPMNRx_MASK;
					9'h05E: REGS.MPOPRA <= DI & MPOPRx_MASK;
					9'h060: REGS.MPABRB <= DI & MPABRx_MASK;
					9'h062: REGS.MPCDRB <= DI & MPCDRx_MASK;
					9'h064: REGS.MPEFRB <= DI & MPEFRx_MASK;
					9'h066: REGS.MPGHRB <= DI & MPGHRx_MASK;
					9'h068: REGS.MPIJRB <= DI & MPIJRx_MASK;
					9'h06A: REGS.MPKLRB <= DI & MPKLRx_MASK;
					9'h06C: REGS.MPMNRB <= DI & MPMNRx_MASK;
					9'h06E: REGS.MPOPRB <= DI & MPOPRx_MASK;
					9'h070: REGS.SCXIN0 <= DI & SCXINx_MASK;
					9'h072: REGS.SCXDN0 <= DI & SCXDNx_MASK;
					9'h074: REGS.SCYIN0 <= DI & SCYINx_MASK;
					9'h076: REGS.SCYDN0 <= DI & SCYDNx_MASK;
					9'h078: REGS.ZMXIN0 <= DI & ZMXINx_MASK;
					9'h07A: REGS.ZMXDN0 <= DI & ZMXDNx_MASK;
					9'h07C: REGS.ZMYIN0 <= DI & ZMYINx_MASK;
					9'h07E: REGS.ZMYDN0 <= DI & ZMYDNx_MASK;
					9'h080: REGS.SCXIN1 <= DI & SCXINx_MASK;
					9'h082: REGS.SCXDN1 <= DI & SCXDNx_MASK;
					9'h084: REGS.SCYIN1 <= DI & SCYINx_MASK;
					9'h086: REGS.SCYDN1 <= DI & SCYDNx_MASK;
					9'h088: REGS.ZMXIN1 <= DI & ZMXINx_MASK;
					9'h08A: REGS.ZMXDN1 <= DI & ZMXDNx_MASK;
					9'h08C: REGS.ZMYIN1 <= DI & ZMYINx_MASK;
					9'h08E: REGS.ZMYDN1 <= DI & ZMYDNx_MASK;
					9'h090: REGS.SCXN2 <= DI & SCXNx_MASK;
					9'h092: REGS.SCYN2 <= DI & SCYNx_MASK;
					9'h094: REGS.SCXN3 <= DI & SCXNx_MASK;
					9'h096: REGS.SCYN3 <= DI & SCYNx_MASK;
					9'h098: REGS.ZMCTL <= DI & ZMCTL_MASK;
					9'h09A: REGS.SCRCTL <= DI & SCRCTL_MASK;
					9'h09C: REGS.VCSTAU <= DI & VCSTAU_MASK;
					9'h09E: REGS.VCSTAL <= DI & VCSTAL_MASK;
					9'h0A0: REGS.LSTA0U <= DI & LSTAxU_MASK;
					9'h0A2: REGS.LSTA0L <= DI & LSTAxL_MASK;
					9'h0A4: REGS.LSTA1U <= DI & LSTAxU_MASK;
					9'h0A6: REGS.LSTA1L <= DI & LSTAxL_MASK;
					9'h0A8: REGS.LCTAU <= DI & LCTAU_MASK;
					9'h0AA: REGS.LCTAL <= DI & LCTAL_MASK;
					9'h0AC: REGS.BKTAU <= DI & BKTAU_MASK;
					9'h0AE: REGS.BKTAL <= DI & BKTAL_MASK;
					9'h0B0: REGS.RPMD <= DI & RPMD_MASK;
					9'h0B2: REGS.RPRCTL <= DI & RPRCTL_MASK;
					9'h0B4: REGS.KTCTL <= DI & KTCTL_MASK;
					9'h0B6: REGS.KTAOF <= DI & KTAOF_MASK;
					9'h0B8: REGS.OVPNRA <= DI & OVPNRx_MASK;
					9'h0BA: REGS.OVPNRB <= DI & OVPNRx_MASK;
					9'h0BC: REGS.RPTAU <= DI & RPTAU_MASK;
					9'h0BE: REGS.RPTAL <= DI & RPTAL_MASK;
					9'h0C0: REGS.WPSX0 <= DI & WPSXx_MASK;
					9'h0C2: REGS.WPSY0 <= DI & WPSYx_MASK;
					9'h0C4: REGS.WPEX0 <= DI & WPEXx_MASK;
					9'h0C6: REGS.WPEY0 <= DI & WPEYx_MASK;
					9'h0C8: REGS.WPSX1 <= DI & WPSXx_MASK;
					9'h0CA: REGS.WPSY1 <= DI & WPSYx_MASK;
					9'h0CC: REGS.WPEX1 <= DI & WPEXx_MASK;
					9'h0CE: REGS.WPEY1 <= DI & WPEYx_MASK;
					9'h0D0: REGS.WCTLA <= DI & WCTLA_MASK;
					9'h0D2: REGS.WCTLB <= DI & WCTLB_MASK;
					9'h0D4: REGS.WCTLC <= DI & WCTLC_MASK;
					9'h0D6: REGS.WCTLD <= DI & WCTLD_MASK;
					9'h0D8: REGS.LWTA0U <= DI & LWTAxU_MASK;
					9'h0DA: REGS.LWTA0L <= DI & LWTAxL_MASK;
					9'h0DC: REGS.LWTA1U <= DI & LWTAxU_MASK;
					9'h0DE: REGS.LWTA1L <= DI & LWTAxL_MASK;
					9'h0E0: REGS.SPCTL <= DI & SPCTL_MASK;
					9'h0E2: REGS.SDCTL <= DI & SDCTL_MASK;
					9'h0E4: REGS.CRAOFA <= DI & CRAOFA_MASK;
					9'h0E6: REGS.CRAOFB <= DI & CRAOFB_MASK;
					9'h0E8: REGS.LNCLEN <= DI & LNCLEN_MASK;
					9'h0EA: REGS.SFPRMD <= DI & SFPRMD_MASK;
					9'h0EC: REGS.CCCTL <= DI & CCCTL_MASK;
					9'h0EE: REGS.SFCCMD <= DI & SFCCMD_MASK;
					9'h0F0: REGS.PRISA <= DI & PRISA_MASK;
					9'h0F2: REGS.PRISB <= DI & PRISB_MASK;
					9'h0F4: REGS.PRISC <= DI & PRISC_MASK;
					9'h0F6: REGS.PRISD <= DI & PRISD_MASK;
					9'h0F8: REGS.PRINA <= DI & PRINA_MASK;
					9'h0FA: REGS.PRINB <= DI & PRINB_MASK;
					9'h0FC: REGS.PRIR <= DI & PRIR_MASK;
					9'h0FE: REGS.RSRV1 <= DI & RSRV_MASK;
					9'h100: REGS.CCRSA <= DI & CCRSA_MASK;
					9'h102: REGS.CCRSB <= DI & CCRSB_MASK;
					9'h104: REGS.CCRSC <= DI & CCRSC_MASK;
					9'h106: REGS.CCRSD <= DI & CCRSD_MASK;
					9'h108: REGS.CCRNA <= DI & CCRNA_MASK;
					9'h10A: REGS.CCRNB <= DI & CCRNA_MASK;
					9'h10C: REGS.CCRR <= DI & CCRR_MASK;
					9'h10E: REGS.CCRLB <= DI & CCRLB_MASK;
					9'h110: REGS.CLOFEN <= DI & CLOFEN_MASK;
					9'h112: REGS.CLOFSL <= DI & CLOFSL_MASK;
					9'h114: REGS.COAR <= DI & COxR_MASK;
					9'h116: REGS.COAG <= DI & COxG_MASK;
					9'h118: REGS.COAB <= DI & COxB_MASK;
					9'h11A: REGS.COBR <= DI & COxR_MASK;
					9'h11C: REGS.COBG <= DI & COxG_MASK;
					9'h11E: REGS.COBB <= DI & COxB_MASK; 
					default:;
				endcase
			end
				
			if (CE_F) begin
				if (REG_SEL && WE_N && !REQ_N) begin
					REG_RA <= A[8:1];
					REG_RRDY <= 0;
				end
				
				if (PAL_SEL && WE_N && !REQ_N) begin
					PAL_DO <= !IO_PAL_RD ? PAL0_DO : PAL1_DO;
				end
			end
			if (CE_R) begin
				if (!CS_N && AD_N) begin
					if (!REG_RD_DELAY) begin
						REG_RD_DELAY <= 4'd2;
					end
				end
			end
			
			if (DOT_CE_F) begin
				if (REG_SEL && WE_N && REG_RD_DELAY == 4'd0 && !REG_RRDY) begin
					case ({REG_RA,1'b0})
						9'h000: REG_DO <= REGS.TVMD & TVMD_MASK;
						9'h002: REG_DO <= REGS.EXTEN & EXTEN_MASK;
						9'h004: REG_DO <= {REGS.TVSTAT[15:8], 4'h0, VBLANK|~DISP, HBLANK, ODD, PAL} & TVSTAT_MASK;
						9'h006: REG_DO <= REGS.VRSIZE & VRSIZE_MASK;
						9'h008: REG_DO <= REGS.HCNT & HCNT_MASK;
						9'h00A: REG_DO <= REGS.VCNT & VCNT_MASK;
						9'h00E: REG_DO <= REGS.RAMCTL & RAMCTL_MASK;
						default: REG_DO <= '0;
					endcase
					if ({REG_RA,1'b0} == 9'h002 && !REGS.EXTEN.EXLTEN) begin	//EXTEN
						REGS.HCNT.HCT = !REGS.TVMD.HRESO[2] ? {HCT,DOTCLK_DIV[1]&REGS.TVMD.HRESO[1]} : {HCT9,HCT};
						REGS.VCNT.VCT = REGS.TVMD.LSMD != 2'b11 && !REGS.TVMD.HRESO[2] ? {1'b0,VCT} : REGS.TVMD.LSMD == 2'b11 && ((!ODD && !NNI) || !REGS.TVMD.HRESO[2]) ? {VCT,~ODD&~NNI} : {VCT,VCT0};
						REGS.TVSTAT.EXLTFG <= 1;
					end
					if ({REG_RA,1'b0} == 9'h004) begin								//TVSTAT
						REGS.TVSTAT.EXLTFG <= 0;
						REGS.TVSTAT.EXSYFG <= 0;
					end
				end
			end
			if (DOT_CE_F || DOT_CE_R) begin
				EXLAT_N_OLD <= EXLAT_N;
				if (!EXLAT_N && EXLAT_N_OLD && REGS.EXTEN.EXLTEN) begin	//EXTEN
					REGS.HCNT.HCT = !REGS.TVMD.HRESO[2] ? {HCT,DOTCLK_DIV[1]&REGS.TVMD.HRESO[1]} : {HCT9,HCT};
					REGS.VCNT.VCT = REGS.TVMD.LSMD != 2'b11 && !REGS.TVMD.HRESO[2] ? {1'b0,VCT} : REGS.TVMD.LSMD == 2'b11 && ((!ODD && !NNI) || !REGS.TVMD.HRESO[2]) ? {VCT,~ODD&~NNI} : {VCT,VCT0};
					REGS.TVSTAT.EXLTFG <= 1;
				end
			end
			if (DOT_CE_R) begin
				if (REG_RD_DELAY) begin
					REG_RD_DELAY <= REG_RD_DELAY - 4'd1;
				end
				if (!REG_RD_DELAY && !REG_RRDY) REG_RRDY <= 1;
			end
		end
	end
	
	
	bit         REG_RD,PAL_RD;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			// synopsys translate_off
			A <= '1;
			WE_N <= 1;
			DQM <= '1;
			BURST <= 0;
			// synopsys translate_on
		end else if (!RES_N) begin
			A <= '1;
			WE_N <= 1;
			DQM <= '1;
			BURST <= 0;
			REG_RD <= 0;
			PAL_RD <= 0;
		end else begin
			if (!CS_N && DTEN_N && AD_N && CE_R) begin
				if (!DI[15]) begin
					A[20:9] <= DI[11:0];
					WE_N <= DI[14];
					BURST <= DI[13];
				end else begin
					A[8:1] <= DI[7:0];
					DQM <= DI[13:12];
				end
			end
			if ((VRAM_SEL || REG_SEL || PAL_SEL) && !REQ_N) begin
				A <= A + 20'd1;
				REG_RD <= REG_SEL;
				PAL_RD <= PAL_SEL;
			end
		end
	end
	
	
	assign RDY_N = ~REG_RRDY | ~VRAM_RRDY | ~VRAM_WRDY | VRAM_WLOCK | (FIFO_FULL & BURST);
	
	assign DO = REG_RD ? REG_DO : 
	            PAL_RD ? PAL_DO : 
					VRAM_DO;
	
	//debug
`ifdef DEBUG
	assign VA_PIPE0 = VA_PIPE[0];
	assign NBG_A0VA_DBG = NBG_A0VA;
	assign R0NP_ADDR_DBG = RxPN_ADDR[0];
	assign Xsp_DBG = Xsp;
	assign Ysp_DBG = Ysp;
	assign Xp_DBG = Xp;
	assign Yp_DBG = Yp;
	assign dX_DBG = dX;
	assign dY_DBG = dY;
	assign Xst_DBG = Xst;
	assign Yst_DBG = Yst;
//	assign N0SCX = SCX[0];
//	assign N0SCY = SCY[0];
//	assign CH_PIPE0 = RBG_CH_PIPE[0];
//	assign CH_PIPE1 = RBG_CH_PIPE[1];
//	assign CH_PIPE2 = RBG_CH_PIPE[2];
	assign NBG_CDC0_DBG = '{8{'0}};	//NBG_CDC is CDC_RAM now (R2)
	assign NBG_CDC1_DBG = '{8{'0}};
	assign NBG_CDC2_DBG = '{8{'0}};
	assign NBG_CDC3_DBG = '{8{'0}};
	assign NBG_CDP0_DBG = NBG_CDP[0];
	assign RBG0_CDC0_DBG = RBG_DC[0][0];
	assign RBG0_CDC1_DBG = RBG_DC[0][1];
	assign RBG0_CDC2_DBG = RBG_DC[0][2];
	assign RBG0_CDC3_DBG = RBG_DC[0][3];
	assign RBG0_CDP_DBG = RBG_CDP[0];
	assign RBG1_CDC0_DBG = RBG_DC[1][0];
	assign RBG1_CDC1_DBG = RBG_DC[1][1];
	assign RBG1_CDC2_DBG = RBG_DC[1][2];
	assign RBG1_CDC3_DBG = RBG_DC[1][3];
	assign RBG1_CDP_DBG = RBG_CDP[1];
//	assign N0DOTN_DBG = N0DOTN;
	assign R0DOT_DBG = R0DOT;
	assign N0DOT_DBG = N0DOT;
	assign N1DOT_DBG = N1DOT;
	assign N2DOT_DBG = N2DOT;
	assign N3DOT_DBG = N3DOT;
//	assign DOT_FST_DBG = DOT_FST;
//	assign DOT_SEC_DBG = DOT_SEC;
//	assign DOT_THD_DBG = DOT_THD;
	assign KAx0_DBG = KAx[0];
	assign RA_D_ERR = {RA_D[63:48] != 16'd0,RA_D[47:32] != 16'd0,RA_D[31:16] != 16'd0,RA_D[15:0] != 16'd0};
	assign RB_D_ERR = {RB_D[47:32] != 16'd0,RB_D[47:32] != 16'd0,RB_D[31:16] != 16'd0,RB_D[15:0] != 16'd0};

`endif

endmodule

// 16 x 12 MLAB, registered write, asynchronous read (the rotation map registers)
module VDP2_RMAP_RAM (
	input         CLK,
	input  [ 3:0] WA,
	input  [11:0] D,
	input         WE,
	input  [ 3:0] RA,
	output [11:0] Q
);
	(* ramstyle = "MLAB, no_rw_check" *) reg [11:0] mem [0:15];
	always @(posedge CLK) if (WE) mem[WA] <= D;
	assign Q = mem[RA];
endmodule

// 8 x 32 MLAB, registered write every clock, asynchronous read (NBG_CDC: word j = byte j of NBG3..NBG0)
module VDP2_CDC_RAM (
	input         CLK,
	input  [ 2:0] WA,
	input  [31:0] D,
	input  [ 2:0] RA,
	output [31:0] Q
);
	(* ramstyle = "MLAB, no_rw_check" *) reg [31:0] mem [0:7];
	always @(posedge CLK) mem[WA] <= D;
	assign Q = mem[RA];
endmodule

// 32 x W MLAB, registered write, asynchronous read (one read port of VDP2 cell dot buffer rings, W/8 rings side by side)
module VDP2_NDC_RAM #(parameter W = 8) (
	input          CLK,
	input  [  4:0] WA,
	input  [W-1:0] D,
	input          WE,
	input  [  4:0] RA,
	output [W-1:0] Q
);
	(* ramstyle = "MLAB, no_rw_check" *) reg [W-1:0] mem [0:31];
	always @(posedge CLK) if (WE) mem[WA] <= D;
	assign Q = mem[RA];
endmodule
