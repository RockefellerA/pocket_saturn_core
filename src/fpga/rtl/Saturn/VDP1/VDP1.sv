module VDP1 (
	input              CLK,
	input              RST_N,
	input              CE_R,
	input              CE_F,
	input              EN,
	
	input              RES_N,

	input      [15: 0] DI,
	output     [15: 0] DO,
	input              CS_N,
	input              AD_N,
	input              DTEN_N,
	input              REQ_N,
	output             RDY_N,
	
	output             IRQ_N,
	
	input              DCE_R,
	input              DCE_F,
	input              HTIM_N,
	input              VTIM_N,
	input      [15: 0] VOUTI,
	output     [15: 0] VOUTO,
	
	output reg [18: 1] VRAM_A,
	output reg [15: 0] VRAM_D,
	input      [15: 0] VRAM_Q,
	output reg [ 1: 0] VRAM_WE,
	output reg         VRAM_RD,
	output reg [ 8: 0] VRAM_BLEN,
	input              VRAM_RDY,
	
`ifdef VDP1_FB_EXT
	// frame buffers off-chip (Pocket glue, glue/rtl/vdp1fb_ext.sv): ports by role instead of by buffer
	output     [17: 1] FBD_A,		// draw / CPU side (the draw buffer)
	output     [15: 0] FBD_D,
	output     [ 1: 0] FBD_WE,
	output             FBD_RD,
	input      [15: 0] FBD_Q,
	output     [17: 1] FBV_A,		// display side (the display buffer): raster address, its word one clock later
	input      [15: 0] FBV_Q,
	output             FBE_WE,		// erase writes (EWDR) to the display buffer at FBV_A
	output     [15: 0] FBE_D,
	output             FB_SEL_O,	// 1: buffer 0 is the draw buffer
	output             FBV_VB,		// vertical blank (VTIM_N low): no display reads, FBV_A only sweeps V-blank erases
`else
	output     [17: 1] FB0_A,
	output     [15: 0] FB0_D,
	input      [15: 0] FB0_Q,
	output     [ 1: 0] FB0_WE,
	output             FB0_RD,
	
	output     [17: 1] FB1_A,
	output     [15: 0] FB1_D,
	input      [15: 0] FB1_Q,
	output     [ 1: 0] FB1_WE,
	output             FB1_RD,
`endif
	input              FB_RDY,
	output             FB_MODE3,
	
	input              FAST,
	input              BLUR_MESH,
	
	input      [ 7: 0] DBG_EXT
	
`ifdef DEBUG
	                   ,
	output             DBG_START,
	output             DBG_CMD_END,
	output     [18: 1] DBG_SPR_ADDR,
	output             DBG_LINE_DRAW_STEP,
	output             DBG_TEXT_READ_STEP,
	output             DBG_COL_DRAW_STEP,
	output     [ 8: 0] DBG_TEXT_X,
	output     [ 7: 0] DBG_TEXT_Y,
	output     [15: 0] ORIG_C_DBG,
	output     [11: 0] DRAW_X_DBG,
	output     [11: 0] DRAW_Y_DBG,
	output       RGB_t DBG_ORIG_RGB,
	output Pattern_t   DBG_PAT,
	output             TP_DBG,
	output             SCLIP_DBG,
	output             UCLIP_DBG,
	output             DBG_LINE_OVER,
	output             DBG_DRAW_OVER,
	output     [ 7: 0] FRAMES_DBG,
	output     [ 7: 0] START_DRAW_CNT,
	output     [18: 1] DBG_CMD_ADDR16,
	output     [18: 1] DBG_CMD_ADDR_LAST,
	output   CMDSRCA_t DBG_CMD_CMDSRCA_LAST,
	output     [ 7: 0] DBG_CMD_CNT,
	output     [ 7: 0] DBG_CMD_WAIT_CNT,
	output             DBG_CMD_ADDR_ERR,
	output       RGB_t DBG_GHCOLOR_C,
	output       RGB_t DBG_GHCOLOR_D,
	output reg         DBG_SKIP,
	output             DBG_PENALTY_OVER,
	output reg         DBG_HOOK,
	output             DBG_REG_WR
`endif
);
	import VDP1_PKG::*;
	
	TVMR_t       TVMR;
	FBCR_t       FBCR;
	PTMR_t       PTMR;
	EWDR_t       EWDR;
	EWLR_t       EWLR;
	EWRR_t       EWRR;
	EDSR_t       EDSR;
	LOPR_t       LOPR;
	COPR_t       COPR;
	MODR_t       MODR;
	bit          DIE,DIL;

	bit          FRAME_START;
	bit          FRAME_ERASE;
	bit          VBLANK_ERASE;
	bit          FRAME_ERASE_EN;
	bit          VBLANK_ERASE_EN;
	bit          OUT_EN;
	bit          DRAW_TERMINATE;
	bit          DRAW_END;
	bit          FRAME_ODD;
	
	bit  [15: 0] CLT_Q;
	
	//Frame buffers
	bit          FB_SEL;
	bit  [17: 1] FB_A;
	bit  [15: 0] FB_D;
	bit  [ 1: 0] FB_WE;
	bit          FB_RD;
	bit  [15: 0] FB_DRAW_Q;
	bit          FB_DRAW_WAIT;
	bit  [17: 1] FB_DISP_A;
	bit          FB_DISP_WE;
	bit  [15: 0] FB_DISP_Q;
	bit  [17: 1] FB_ERASE_A;
//	bit          FRAME;
	wire         FB_ERASE_WE = (FRAME_ERASE_EN & DCE_R) | (VBLANK_ERASE_EN & CE_R);
	wire [17: 1] FB_OUT_A = VBLANK_ERASE_EN ? FB_ERASE_A : FB_DISP_A;
	
`ifdef VDP1_FB_EXT
	// the glue maps the roles to the two memories with FB_SEL (the buffer swap stays here)
	assign FBD_A    = FB_A;
	assign FBD_D    = FB_D;
	assign FBD_WE   = FB_WE;
	assign FBD_RD   = FB_RD;
	assign FBV_A    = FB_OUT_A;
	assign FBE_WE   = FB_ERASE_WE;
	assign FBE_D    = EWDR;
	assign FB_SEL_O = FB_SEL;
	assign FBV_VB   = ~VTIM_N;
	
	assign FB_DRAW_Q = FBD_Q;
	assign FB_DISP_Q = FBV_Q;
`else
	assign FB0_A  = FB_SEL ? FB_A             : FB_OUT_A;
	assign FB1_A  = FB_SEL ? FB_OUT_A         : FB_A;
	assign FB0_D  = FB_SEL ? FB_D             : EWDR;
	assign FB1_D  = FB_SEL ? EWDR             : FB_D;
	assign FB0_WE = FB_SEL ? FB_WE /*& CE_R*/ : {2{FB_ERASE_WE}};
	assign FB1_WE = FB_SEL ? {2{FB_ERASE_WE}} : FB_WE /*& CE_R*/;
	assign FB0_RD = FB_SEL ? FB_RD            : 1'b0;
	assign FB1_RD = FB_SEL ? 1'b0             : FB_RD;
	
	assign FB_DRAW_Q = FB_SEL ? FB0_Q : FB1_Q;
	assign FB_DISP_Q = FB_SEL ? FB1_Q : FB0_Q;
`endif
	
`ifdef CUT_VDP1_ROT
	// U1 (CUT_VDP1_ROT): the rotation frame buffer (TVMR.TVM1) is cut. TVM1 is treated as 0 everywhere (display
	// read-out, draw layout, erase timing); it is still stored, and read back in MODR. So TVM = 3 (8-bit rotation
	// layout) never happens.
	assign FB_MODE3 = 0;
`else
	assign FB_MODE3 = (TVMR.TVM[1:0] == 2'b11);
`endif
	
	typedef enum bit [5:0] {
		CMDS_IDLE,  
		CMDS_READ, 
		CMDS_GRD_LOAD,
		CMDS_EXEC,
		CMDS_CLT_LOAD,
		CMDS_DELAY,
		CMDS_GRD_CALC_COL,
		CMDS_GRD_CALC_LEFT,
		CMDS_GRD_CALC_RIGHT,
		CMDS_GRD_CALC_ROW,
		CMDS_GRD_CALC_LINE,
		CMDS_ROW_DRAW,
		CMDS_EDGE_INIT,
		CMDS_LINE_INIT,
		CMDS_PRE_DRAW,CMDS_PRE_DRAW2,
		CMDS_NSPR_CALCX,
		CMDS_NSPR_DRAW,
		CMDS_SSPR_CALCX,
		CMDS_SSPR_CALCTX,
		CMDS_SSPR_DRAW,
		CMDS_POLYGON_CALCE,
		CMDS_POLYGON_CALCH,
		CMDS_POLYGON_CALCTY,
		CMDS_LINE_CALC,
		CMDS_LINE_CALCTX,
		CMDS_LINE_DRAW,
		CMDS_AA_DRAW,
		CMDS_LINE_END,
		CMDS_LINE_NEXT,
		CMDS_ROW_CLIP,
		CMDS_END
	} CMDState_t;
	CMDState_t CMD_ST;
	bit  [18: 1] CMD_ADDR;
	bit          CMD_READ;
	bit          CMD_READ_DONE;
	bit  [18: 1] SPR_ADDR;
	bit          SPR_READ;
	bit  [15: 0] SPR_DATA;
	bit          SPR_DATA_READY;
	bit  [18: 1] CLT_ADDR;
	bit          CLT_READ;
	bit          CLT_READ_DONE;
	bit  [18: 1] GRD_ADDR;
	bit          GRD_READ;
	bit          GRD_READ_DONE;
	bit  [15: 0] GRD_TBL[4];
	
	CMDTBL_t     CMD;
	Clip_t       SYS_CLIP;
	Clip_t       USR_CLIP;
	Coord_t      LOC_COORD;
	Vertex_t     VERTA,VERTB,VERTC,VERTD;
	Pattern_t    PAT;
	bit  [ 8: 0] TEXT_X;
	bit  [ 7: 0] TEXT_Y;
	bit  [16: 3] SPR_OFFSY;
	//edge setup: per edge, min(|dx|,|dy|) and whether |dx| >= |dy| (the height, max(|dx|,|dy|), is LEFT_/RIGHT_HEIGHT)
	bit  [11: 0] LEFT_MIN;
	bit  [11: 0] RIGHT_MIN;
	bit          LEFT_XMAJ;
	bit          RIGHT_XMAJ;
	bit          LEFT_MAJ;	//LEFT_HEIGHT >= RIGHT_HEIGHT
	bit          POLY_LDIRX;
	bit          POLY_LDIRY;
	bit          POLY_RDIRX;
	bit          POLY_RDIRY;
	bit  [ 1: 0] POLY_S;
	
	Coord_t      LINE_VERTA;
	Coord_t      LINE_VERTB;
	Vertex_t     LEFT_VERT;
	Vertex_t     RIGHT_VERT;
	Vertex_t     BOTTOM_VERT;
	bit          LINE_DIRX;
	bit          LINE_DIRY;
	bit          LINE_CLIP;
	bit          LINE_S;
	bit  [11: 0] ROW_WIDTH;
	bit  [11: 0] COL_HEIGHT,LEFT_HEIGHT,RIGHT_HEIGHT;
	bit          COL_DIRY;
	bit          SPR_COL_ENLARGE;
	bit          EC_FIND;
	bit  [11: 0] AA_X;
	bit  [11: 0] AA_Y;
	bit          AA;
	bit  [11: 0] AA_X_INC;
	bit  [11: 0] AA_Y_INC;
	bit  [ 1: 0] DIR;
	bit          HSS_EN;
	bit          DRAW_WAIT;
	bit          DRAW_ENABLE;
	
	bit          LINE_DRAW_STEP;
	bit          LINE_AA_STEP;
	bit          COL_DRAW_STEP;
	bit          TEXT_X_READ_STEP;
	bit          TEXTY_READ_STEP, TEXT_Y_READ_STEP;
	bit          LEFT_COL_X_STEP, LEFT_COL_Y_STEP;
	bit          RIGHT_COL_X_STEP,RIGHT_COL_Y_STEP;
	bit  [ 4: 0] GRD_CALC_STATE;
	bit  [11: 0] GRD_CALC_S;
	RGB_t        GRD_CALC_1,GRD_CALC_2;
	
	bit  [ 8: 0] ORIG_WIDTH;
	bit  [ 7: 0] ORIG_HEIGHT;
	wire         TEXT_DIRX = (CMD.CMDCTRL.DIR[0] ^ DIR[0]);
	wire         TEXT_DIRY = (CMD.CMDCTRL.DIR[1] ^ DIR[1]);
	wire         IS_PAT_EC = (CMD.CMDCTRL.COMM <= 4'h3 && !CMD.CMDPMOD.ECD && PAT.EC && !HSS_EN);
	
	bit  [12: 0] COL_D;
	//Edge steppers. Each edge (left: A->D, right: B->C) has a column error for X and one for Y, each edge a D error. They
	//were six Bresenham steppers E' = (E+INC >= CMP) ? E+INC-ADJ : E+INC, E0 = -H-1 (H = the ADJ/2 of the stepper). A
	//stepper whose INC equals its ADJ (the column error of the edge's major axis: INC = 2*max(|dx|,|dy|) = ADJ; the D
	//error of the taller edge: INC = 2*its height = 2*COL_HEIGHT = ADJ) never changes: E0+2H = H-1 >= CMP holds for
	//H != 0 (and for H = 0 with CMP set), and then E0+2H-2H = E0, else E0+0 = E0. So it steps whenever it is asked to,
	//except when H = 0 and CMP is clear. That exception is never seen: an edge of height 0 under a taller one has its D
	//error E0 = -COL_HEIGHT-1 with INC 0, which never reaches -1, so its column errors are never asked; a D error of
	//height 0 (COL_HEIGHT = 0) only runs in the LINE_NEXT of the last (only) row, after which LEFT_/RIGHT_VERT and the
	//errors are loaded again before they are read. So the major steppers are taken as always stepping, and one stepper per
	//pair is left: the minor axis of each edge (INC = 2*min), and the D error of the shorter edge (INC = 2*its height); an
	//equal pair runs the minor stepper with INC = ADJ, which then behaves as a major one. INC and ADJ come straight from
	//the edge registers (LEFT_/RIGHT_MIN, LEFT_/RIGHT_HEIGHT, COL_HEIGHT), which hold from the edge setup to the end of
	//the command, as the INC/ADJ registers loaded from them did.
	bit  [13: 0] NEXT_LEFT_COL_ERROR, LEFT_COL_ERROR;
	bit  [13: 0] NEXT_RIGHT_COL_ERROR, RIGHT_COL_ERROR;
	bit  [13: 0] NEXT_D_ERROR, D_ERROR;
	wire         LEFT_D_CMP  = LEFT_XMAJ  ? POLY_LDIRX : POLY_LDIRY;	//CMP of the left minor column stepper and of the left D error
	wire         RIGHT_D_CMP = RIGHT_XMAJ ? POLY_RDIRX : POLY_RDIRY;

	//LINE_ERROR_ADJ and the edge steppers' ADJ hold the magnitude of the (negative) adjustment and are subtracted: same
	//14-bit results, without the negators in the setup states.
	bit  [13: 0] NEXT_LINE_ERROR, LINE_ERROR, LINE_ERROR_INC, LINE_ERROR_ADJ;
	bit  [13: 0] NEXT_TEXT_ERROR, TEXT_ERROR, TEXT_ERROR_INC, TEXT_ERROR_ADJ;
	bit  [13: 0] NEXT_TEXT_Y_ERROR, TEXT_Y_ERROR, TEXT_Y_ERROR_INC, TEXT_Y_ERROR_ADJ;
	always_comb begin
		bit COL_STEP;
		bit  [13: 0] TEXT_ERROR_ADJUSTED,LINE_ERROR_ADJUSTED;
		bit  [13: 0] TEXT_Y_ERROR_ADJUSTED;
		bit  [13: 0] D_ERROR_ICREMENTED,LEFT_COL_ERROR_ICREMENTED,RIGHT_COL_ERROR_ICREMENTED;
		bit          D_STEP,LEFT_D_STEP,RIGHT_D_STEP,LEFT_MIN_STEP,RIGHT_MIN_STEP;

		LINE_DRAW_STEP = 0;
		LINE_AA_STEP = 0;
		COL_DRAW_STEP = 0;
		TEXT_X_READ_STEP = 0;
		TEXT_Y_READ_STEP = 0;
		{LEFT_COL_X_STEP,LEFT_COL_Y_STEP} = '0;
		{RIGHT_COL_X_STEP,RIGHT_COL_Y_STEP} = '0;
		
		
		NEXT_TEXT_ERROR = '0;
		NEXT_LINE_ERROR = '0;
		NEXT_TEXT_Y_ERROR = '0;
		NEXT_D_ERROR = '0;
		NEXT_LEFT_COL_ERROR = '0;
		NEXT_RIGHT_COL_ERROR = '0;
		case (CMD_ST)
			CMDS_NSPR_DRAW: begin		
				LINE_DRAW_STEP = 1;		
				TEXT_X_READ_STEP = 1;
			end
			
			CMDS_PRE_DRAW,
			CMDS_SSPR_DRAW,
			CMDS_LINE_DRAW: begin
				if (CMD.CMDCTRL.COMM >= 4'h4) begin
					LINE_DRAW_STEP = 1;
					TEXT_X_READ_STEP = 0;
				end else begin
					//one subtract, one add: a negative error is used as is (its sign then steps, as before)
					TEXT_ERROR_ADJUSTED = !TEXT_ERROR[13] ? TEXT_ERROR - TEXT_ERROR_ADJ : TEXT_ERROR;
					if (TEXT_ERROR_ADJUSTED[13]) begin
						LINE_DRAW_STEP = 1;
						NEXT_TEXT_ERROR = TEXT_ERROR_ADJUSTED + TEXT_ERROR_INC;
					end else begin
						NEXT_TEXT_ERROR = TEXT_ERROR_ADJUSTED;
					end
					
					if (!NEXT_TEXT_ERROR[13]) begin
						TEXT_X_READ_STEP = 1;
					end
				end
					
				if (LINE_DRAW_STEP && CMD_ST == CMDS_LINE_DRAW) begin
					//LINE_ERROR holds E + INC - 1 (see LINE_CALC): E + INC >= 1 is its sign, and the next value is the
					//stepped error plus INC, minus 1
					LINE_ERROR_ADJUSTED = !LINE_ERROR[13] ? LINE_ERROR - LINE_ERROR_ADJ : LINE_ERROR;
					NEXT_LINE_ERROR = LINE_ERROR_ADJUSTED + LINE_ERROR_INC;
					LINE_AA_STEP = !LINE_ERROR[13];
				end
			end
			
			CMDS_AA_DRAW,
			CMDS_LINE_END: begin
				LINE_DRAW_STEP = AA;
			end
			
			CMDS_ROW_DRAW: begin
				if (CMD.CMDCTRL.COMM >= 4'h4) begin
					COL_DRAW_STEP = 1;
				end else begin
					//same two-adder form as the text X error
					TEXT_Y_ERROR_ADJUSTED = !TEXT_Y_ERROR[13] ? TEXT_Y_ERROR - TEXT_Y_ERROR_ADJ : TEXT_Y_ERROR;
					if (!TEXT_Y_ERROR_ADJUSTED[13]) begin
						NEXT_TEXT_Y_ERROR = TEXT_Y_ERROR_ADJUSTED;
					end else begin
						COL_DRAW_STEP = 1;
						NEXT_TEXT_Y_ERROR = TEXT_Y_ERROR_ADJUSTED + TEXT_Y_ERROR_INC;
					end
					TEXT_Y_READ_STEP = !TEXT_Y_ERROR[13];
				end
			end
			
			CMDS_LINE_NEXT: begin
				//D error of the shorter edge (INC = 2*its height, CMP its D compare); the taller edge's D error steps
				D_ERROR_ICREMENTED = D_ERROR + (LEFT_MAJ ? {1'b0,RIGHT_HEIGHT,1'b0} : {1'b0,LEFT_HEIGHT,1'b0});
				D_STEP = $signed(D_ERROR_ICREMENTED) >= $signed({14{LEFT_MAJ ? RIGHT_D_CMP : LEFT_D_CMP}});
				NEXT_D_ERROR = D_STEP ? D_ERROR_ICREMENTED - {1'b0,COL_HEIGHT,1'b0} : D_ERROR_ICREMENTED;
				LEFT_D_STEP = LEFT_MAJ | D_STEP;
				RIGHT_D_STEP = !LEFT_MAJ | D_STEP;

				//column errors: the minor axis of each edge (INC = 2*min), stepped when the edge's D error steps
				LEFT_COL_ERROR_ICREMENTED = LEFT_COL_ERROR + {1'b0,LEFT_MIN,1'b0};
				LEFT_MIN_STEP = $signed(LEFT_COL_ERROR_ICREMENTED) >= $signed({14{LEFT_D_CMP}});
				NEXT_LEFT_COL_ERROR = !LEFT_D_STEP ? LEFT_COL_ERROR : LEFT_MIN_STEP ? LEFT_COL_ERROR_ICREMENTED - {1'b0,LEFT_HEIGHT,1'b0} : LEFT_COL_ERROR_ICREMENTED;
				LEFT_COL_X_STEP = LEFT_D_STEP & (LEFT_XMAJ | LEFT_MIN_STEP);
				LEFT_COL_Y_STEP = LEFT_D_STEP & (!LEFT_XMAJ | LEFT_MIN_STEP);

				RIGHT_COL_ERROR_ICREMENTED = RIGHT_COL_ERROR + {1'b0,RIGHT_MIN,1'b0};
				RIGHT_MIN_STEP = $signed(RIGHT_COL_ERROR_ICREMENTED) >= $signed({14{RIGHT_D_CMP}});
				NEXT_RIGHT_COL_ERROR = !RIGHT_D_STEP ? RIGHT_COL_ERROR : RIGHT_MIN_STEP ? RIGHT_COL_ERROR_ICREMENTED - {1'b0,RIGHT_HEIGHT,1'b0} : RIGHT_COL_ERROR_ICREMENTED;
				RIGHT_COL_X_STEP = RIGHT_D_STEP & (RIGHT_XMAJ | RIGHT_MIN_STEP);
				RIGHT_COL_Y_STEP = RIGHT_D_STEP & (!RIGHT_XMAJ | RIGHT_MIN_STEP);
			end

			default:;
		endcase
	end
	

	bit  [16: 0] DIV_R_Q,DIV_G_Q,DIV_B_Q;//5.12
	wire DIV_START = (CMD_ST == CMDS_GRD_CALC_LEFT || CMD_ST == CMDS_GRD_CALC_RIGHT || CMD_ST == CMDS_GRD_CALC_LINE) && GRD_CALC_STATE == 0;
	
	//{sign, |C2 - C1|} per channel: one 6-bit subtract and a conditional negate (same values as compare-and-select)
	wire [ 5: 0] DIV_D_R = {1'b0,GRD_CALC_2.R} - {1'b0,GRD_CALC_1.R};
	wire [ 5: 0] DIV_D_G = {1'b0,GRD_CALC_2.G} - {1'b0,GRD_CALC_1.G};
	wire [ 5: 0] DIV_D_B = {1'b0,GRD_CALC_2.B} - {1'b0,GRD_CALC_1.B};
	wire [ 5: 0] DIV_A_R = {DIV_D_R[5],(DIV_D_R[4:0] ^ {5{DIV_D_R[5]}}) + {4'b0000,DIV_D_R[5]}};
	wire [ 5: 0] DIV_A_G = {DIV_D_G[5],(DIV_D_G[4:0] ^ {5{DIV_D_G[5]}}) + {4'b0000,DIV_D_G[5]}};
	wire [ 5: 0] DIV_A_B = {DIV_D_B[5],(DIV_D_B[4:0] ^ {5{DIV_D_B[5]}}) + {4'b0000,DIV_D_B[5]}};
					
	VDP1_DIV_24_12 GRD_DIV_R(CLK, {DIV_A_R[4:0],12'b000000000000}, GRD_CALC_S, DIV_START, DIV_R_Q);
	VDP1_DIV_24_12 GRD_DIV_G(CLK, {DIV_A_G[4:0],12'b000000000000}, GRD_CALC_S, DIV_START, DIV_G_Q);
	VDP1_DIV_24_12 GRD_DIV_B(CLK, {DIV_A_B[4:0],12'b000000000000}, GRD_CALC_S, DIV_START, DIV_B_Q);
	
	RGB_t        GHCOLOR_A,GHCOLOR_B,GHCOLOR_C,GHCOLOR_D;
	assign {GHCOLOR_A,GHCOLOR_B,GHCOLOR_C,GHCOLOR_D} = {GRD_TBL[0][14:0],GRD_TBL[1][14:0],GRD_TBL[2][14:0],GRD_TBL[3][14:0]};
	RGBFP_t      LEFT_GHCOLOR,RIGHT_GHCOLOR,LINE_GHCOLOR;
	RGBFP_t      LEFT_GHCOLOR_STEP,RIGHT_GHCOLOR_STEP;
	//The gouraud step of a division: the dividers hold their quotient from the end of a division (DONE, GRD_CALC_STATE 19)
	//until the next DIV_START, and GRD_CALC_DIR_* hold from that START, so this equals the GRD_CALC_STEP register the
	//division used to load at GRD_CALC_STATE 19 for the copy at 20, and, while a row is drawn, the LINE_GHCOLOR_STEP
	//copied at the end of its GRD_CALC_LINE: no division starts between GRD_CALC_LINE and the end of the row's draw states.
	bit          GRD_CALC_DIR_R,GRD_CALC_DIR_G,GRD_CALC_DIR_B;
	RGBFP_t      GRD_STEP;
	assign GRD_STEP = {GRD_CALC_DIR_B,DIV_B_Q,GRD_CALC_DIR_G,DIV_G_Q,GRD_CALC_DIR_R,DIV_R_Q};
	
`ifdef DEBUG
	assign DBG_GHCOLOR_C = GRD_TBL[2][14:0];
	assign DBG_GHCOLOR_D = GRD_TBL[3][14:0];
	assign DBG_LINE_DRAW_STEP = LINE_DRAW_STEP;
	assign DBG_TEXT_READ_STEP = TEXT_X_READ_STEP;
	assign DBG_COL_DRAW_STEP = COL_DRAW_STEP;
	assign DBG_TEXT_X = TEXT_X;
	assign DBG_TEXT_Y = TEXT_Y;
`endif
	
`ifdef DEBUG
	bit  [ 9: 0] CMD_CURR,CMD_SKIP;
	bit  [ 8: 0] CMD_PIX_XPOS,CMD_PIX_YPOS;
	bit          CMD_SKIP_EN,CMD_PIX_EN,DBG_DRAW_EN;
`endif
	bit  [ 8: 0] CMD_DELAY;
	bit  [ 9: 0] PENALTY_CNT;
	
	//+-1 steppers shared by the line vertex (draw states: NSPR/SSPR/LINE/AA_DRAW, and DRAW_X/Y while in them) and the
	//left edge vertex (LINE_NEXT): the users are in different CMD_ST states, CMD_ST picks the operands.
	wire         VSTEP_EDGE = (CMD_ST == CMDS_LINE_NEXT);
	wire [12: 0] VSTEP_X = (VSTEP_EDGE ? LEFT_VERT.X : {1'b0,LINE_VERTA.X}) + {{12{VSTEP_EDGE ? POLY_LDIRX : LINE_DIRX}},1'b1};
	wire [12: 0] VSTEP_Y = (VSTEP_EDGE ? LEFT_VERT.Y : {1'b0,LINE_VERTA.Y}) + {{12{VSTEP_EDGE ? POLY_LDIRY : LINE_DIRY}},1'b1};
	wire [11: 0] LINE_VERTA_X_STEP = VSTEP_X[11:0];
	wire [11: 0] LINE_VERTA_Y_STEP = VSTEP_Y[11:0];
	//shared the same way: the right edge vertex's +-1 (LINE_NEXT) and the anti-aliasing point, line vertex + AA_X/Y_INC
	//(LINE_DRAW)
	wire [12: 0] RSTEP_X = (VSTEP_EDGE ? RIGHT_VERT.X : {1'b0,LINE_VERTA.X}) + (VSTEP_EDGE ? {{12{POLY_RDIRX}},1'b1} : {1'b0,AA_X_INC});
	wire [12: 0] RSTEP_Y = (VSTEP_EDGE ? RIGHT_VERT.Y : {1'b0,LINE_VERTA.Y}) + (VSTEP_EDGE ? {{12{POLY_RDIRY}},1'b1} : {1'b0,AA_Y_INC});
	
	//Row / line setup arithmetic shared by the CALCX states (NSPR_CALCX, SSPR_CALCX, LINE_CALC): the same values
	//the states computed each for themselves.
	wire [12: 0] NEW_LINE_SX = RIGHT_VERT.X - LEFT_VERT.X;
	wire [12: 0] NEW_LINE_SY = RIGHT_VERT.Y - LEFT_VERT.Y;
	wire [11: 0] NEW_LINE_ASX = Abs(NEW_LINE_SX);
	wire [11: 0] NEW_LINE_ASY = Abs(NEW_LINE_SY);
	wire         NEW_LINE_YMAJ = NEW_LINE_ASY > NEW_LINE_ASX;
	wire [11: 0] NEW_LINE_MAJ = NEW_LINE_YMAJ ? NEW_LINE_ASY : NEW_LINE_ASX;
	wire [11: 0] NEW_LINE_MIN = NEW_LINE_YMAJ ? NEW_LINE_ASX : NEW_LINE_ASY;
	//ROW_WIDTH: |dx| + 1 for sprite rows, major + 1 for lines (12-bit wrap as before)
	wire [11: 0] NEW_ROW_WIDTH = (CMD_ST == CMDS_LINE_CALC ? NEW_LINE_MAJ : NEW_LINE_ASX) + 12'd1;
	
	//Text X error setup, shared by SSPR_CALCTX and LINE_CALCTX (the formulas were the same in both states; only
	//the high-speed-shrink condition differs)
	wire         TX_X    = !TEXT_DIRX || ORIG_WIDTH == 8'd1 ? 1'b0 : 1'b1;
	wire         TX_LTW  = ROW_WIDTH < {4'b0000,ORIG_WIDTH};
	wire         TX_LTWH = ROW_WIDTH < {5'b00000,ORIG_WIDTH[8:1]};
	//(the line state's RW <= W - 1 is RW < W: ORIG_WIDTH is never 0 in the CALCTX states, see ORIG_WIDTH's load)
	wire         TX_HSS  = TX_LTW && CMD.CMDPMOD.HSS && (CMD_ST == CMDS_SSPR_CALCTX || !CMD.CMDCTRL.COMM[2]);
	wire         TX_LT   = TX_HSS ? TX_LTWH : TX_LTW;
	wire [13: 0] TX_INC  = TX_HSS ? (TX_LTWH ? {5'b00000,ORIG_WIDTH} : ({6'b000000,ORIG_WIDTH[8:1] - 8'd1} << 1)) :
	                                (TX_LTW  ? ({5'b00000,ORIG_WIDTH} << 1) : ({5'b00000,ORIG_WIDTH - 9'd1} << 1));
	//(W or W/2) - 2*RW - x, and -RW + x, each one adder with a carry-in
	//the start error picked by TX_LT, one adder: TX_LT: (W or W/2) + ~{RW,0} + ~x; else x + ~RW + 1 (= -RW + x)
	wire [13: 0] TX_E    = (TX_LT ? (TX_HSS ? {6'b000000,ORIG_WIDTH[8:1]} : {5'b00000,ORIG_WIDTH}) : {13'd0,TX_X}) +
	                       (TX_LT ? ~{1'b0,ROW_WIDTH,1'b0} : ~{2'b00,ROW_WIDTH}) + {13'd0,~TX_LT | ~TX_X};
	
	always @(posedge CLK or negedge RST_N) begin
//	   bit         FRAME_START_PEND;
		bit [18: 1] NEXT_ADDR;
		bit [18: 1] CMD_RET_ADDR;
		bit         CMD_SUB_RUN;
		bit         TY_X,TY_LT;
		bit         LINE_VERTA_X_OVR,LINE_VERTA_Y_OVR;
		bit         AA_DRAW;
		bit         LINE_SWAP;
		bit [16: 3] SPR_OFFSY_NEXT;
		bit         CLIP_H;
		bit [ 1: 0] SYS_CLIP_STATE;
		bit [12: 0] SYS_CLIP_A,SYS_CLIP_B,SYS_CLIP_RES;
		bit [12: 0] SYS_CLIP_X1,SYS_CLIP_X2,SYS_CLIP_Y1,SYS_CLIP_Y2;
		bit [13: 0] LINE_DIFF_LEFT_CLIPX1,LINE_DIFF_LEFT_CLIPX2,LINE_DIFF_RIGHT_CLIPX1,LINE_DIFF_RIGHT_CLIPX2;
		bit         LINE_EQ_LEFT_CLIPX1,LINE_EQ_LEFT_CLIPX2,LINE_EQ_RIGHT_CLIPX1,LINE_EQ_RIGHT_CLIPX2;
		bit         LINE_GT_LEFT_CLIPX1,LINE_GT_LEFT_CLIPX2,LINE_GT_RIGHT_CLIPX1,LINE_GT_RIGHT_CLIPX2;
		bit         LINE_LT_LEFT_CLIPX1,LINE_LT_LEFT_CLIPX2,LINE_LT_RIGHT_CLIPX1,LINE_LT_RIGHT_CLIPX2;
		bit         LINE_LEFT_OVER,LINE_RIGHT_OVER,LINE_TOP_OVER,LINE_BOTTOM_OVER;
		bit [ 3: 0] CLIP_DELAY;
`ifdef DEBUG
		bit [ 7: 0] DBG_EXT_OLD;
`endif
		
		if (!RST_N) begin
			CMD_ST <= CMDS_IDLE;
			CMD_ADDR <= '0;
			CMD_READ <= 0;
			SPR_READ <= 0;
			CLT_READ <= 0;
			GRD_READ <= 0;
			CMD_SUB_RUN <= 0;
			
`ifdef DEBUG
			CMD_SKIP <= '1;
			
			{CMD_SKIP_EN,CMD_PIX_EN,DBG_DRAW_EN} <= '0;
`endif
		end else if (FRAME_START) begin
			CMD_ADDR <= '0;
			CMD_READ <= 1;
			SPR_READ <= 0;
			CLT_READ <= 0;
			GRD_READ <= 0;
			CMD_SUB_RUN <= 0;
			CMD_ST <= CMDS_READ;
		end else if (DRAW_TERMINATE) begin
			CMD_READ <= 0;
			SPR_READ <= 0;
			CLT_READ <= 0;
			GRD_READ <= 0;
			CMD_ST <= CMDS_IDLE;
		end else if (EN) begin
			SPR_OFFSY_NEXT = TEXT_DIRY ? SPR_OFFSY - ORIG_WIDTH[8:3] : SPR_OFFSY + ORIG_WIDTH[8:3];
			
			if (CMD.CMDPMOD.CLIP && !CMD.CMDPMOD.CMOD) begin
				case (SYS_CLIP_STATE)
					2'd0: SYS_CLIP_A = {{2{USR_CLIP.X1[10]}},USR_CLIP.X1};
					2'd1: SYS_CLIP_A = {{2{USR_CLIP.Y1[10]}},USR_CLIP.Y1};
					2'd2: SYS_CLIP_A = {{2{USR_CLIP.X2[10]}},USR_CLIP.X2};
					2'd3: SYS_CLIP_A = {{2{USR_CLIP.Y2[10]}},USR_CLIP.Y2};
				endcase
			end else begin
				case (SYS_CLIP_STATE)
					2'd0: SYS_CLIP_A = 13'd0;
					2'd1: SYS_CLIP_A = 13'd0;
					2'd2: SYS_CLIP_A = {{2{SYS_CLIP.X2[10]}},SYS_CLIP.X2};
					2'd3: SYS_CLIP_A = {{2{SYS_CLIP.Y2[10]}},SYS_CLIP.Y2};
				endcase
			end
			case (SYS_CLIP_STATE)
				2'd0: SYS_CLIP_B = {{1{LOC_COORD.X[10]}},LOC_COORD.X};
				2'd1: SYS_CLIP_B = {{1{LOC_COORD.Y[10]}},LOC_COORD.Y};
				2'd2: SYS_CLIP_B = {{1{LOC_COORD.X[10]}},LOC_COORD.X};
				2'd3: SYS_CLIP_B = {{1{LOC_COORD.Y[10]}},LOC_COORD.Y};
			endcase
				
			SYS_CLIP_RES = $signed(SYS_CLIP_A) - $signed(SYS_CLIP_B);
			case (SYS_CLIP_STATE)
				2'd0: SYS_CLIP_X1 <= SYS_CLIP_RES;
				2'd1: SYS_CLIP_Y1 <= SYS_CLIP_RES;
				2'd2: SYS_CLIP_X2 <= SYS_CLIP_RES;
				2'd3: SYS_CLIP_Y2 <= SYS_CLIP_RES;
			endcase
			SYS_CLIP_STATE <= SYS_CLIP_STATE + 2'd1;
			
			//14-bit differences: bits 12:0 are the 13-bit differences used before (EQ / GT / LT below), bit 13 is the
			//sign of the exact difference, i.e. the signed compares of the OVER flags
			LINE_DIFF_LEFT_CLIPX1 = {LEFT_VERT.X[12],LEFT_VERT.X} - {SYS_CLIP_X1[12],SYS_CLIP_X1};
			LINE_DIFF_LEFT_CLIPX2 = {LEFT_VERT.X[12],LEFT_VERT.X} - {SYS_CLIP_X2[12],SYS_CLIP_X2};
			LINE_DIFF_RIGHT_CLIPX1 = {RIGHT_VERT.X[12],RIGHT_VERT.X} - {SYS_CLIP_X1[12],SYS_CLIP_X1};
			LINE_DIFF_RIGHT_CLIPX2 = {RIGHT_VERT.X[12],RIGHT_VERT.X} - {SYS_CLIP_X2[12],SYS_CLIP_X2};
			LINE_EQ_LEFT_CLIPX1 = !LINE_DIFF_LEFT_CLIPX1[12:0];
			LINE_EQ_LEFT_CLIPX2 = !LINE_DIFF_LEFT_CLIPX2[12:0];
			LINE_EQ_RIGHT_CLIPX1 = !LINE_DIFF_RIGHT_CLIPX1[12:0];
			LINE_EQ_RIGHT_CLIPX2 = !LINE_DIFF_RIGHT_CLIPX2[12:0];
			LINE_GT_LEFT_CLIPX1 = ~LINE_DIFF_LEFT_CLIPX1[12];
			LINE_GT_LEFT_CLIPX2 = ~LINE_DIFF_LEFT_CLIPX2[12];
			LINE_GT_RIGHT_CLIPX1 = ~LINE_DIFF_RIGHT_CLIPX1[12];
			LINE_GT_RIGHT_CLIPX2 = ~LINE_DIFF_RIGHT_CLIPX2[12];
			LINE_LT_LEFT_CLIPX1 = LINE_DIFF_LEFT_CLIPX1[12];
			LINE_LT_LEFT_CLIPX2 = LINE_DIFF_LEFT_CLIPX2[12];
			LINE_LT_RIGHT_CLIPX1 = LINE_DIFF_RIGHT_CLIPX1[12];
			LINE_LT_RIGHT_CLIPX2 = LINE_DIFF_RIGHT_CLIPX2[12];
																							  
			LINE_LEFT_OVER <= (LINE_DIFF_LEFT_CLIPX1[13] && LINE_DIFF_RIGHT_CLIPX1[13]);
			LINE_RIGHT_OVER <= (!LINE_DIFF_LEFT_CLIPX2[13] && !LINE_EQ_LEFT_CLIPX2 && !LINE_DIFF_RIGHT_CLIPX2[13] && !LINE_EQ_RIGHT_CLIPX2);
			LINE_TOP_OVER <= ($signed(LEFT_VERT.Y) < $signed(SYS_CLIP_Y1) && $signed(RIGHT_VERT.Y) < $signed(SYS_CLIP_Y1));
			LINE_BOTTOM_OVER <= ($signed(LEFT_VERT.Y) > $signed(SYS_CLIP_Y2) && $signed(RIGHT_VERT.Y) > $signed(SYS_CLIP_Y2));
			
`ifdef DEBUG
			DBG_EXT_OLD <= DBG_EXT;
			if (DBG_EXT[0] && !DBG_EXT_OLD[0]) CMD_SKIP <= CMD_SKIP - 8'd1;
			if (DBG_EXT[1] && !DBG_EXT_OLD[1]) CMD_SKIP <= CMD_SKIP + 8'd1;
			if (DBG_EXT[2] && !DBG_EXT_OLD[2]) CMD_SKIP <= CMD_SKIP - 8'd10;
			if (DBG_EXT[3] && !DBG_EXT_OLD[3]) CMD_SKIP <= CMD_SKIP + 8'd10;
			if (DBG_EXT[4] && !DBG_EXT_OLD[4]) CMD_SKIP_EN <= ~CMD_SKIP_EN;
			
			if (DBG_EXT[0] && !DBG_EXT_OLD[0]) CMD_PIX_XPOS <= CMD_PIX_XPOS - 8'd1;
			if (DBG_EXT[1] && !DBG_EXT_OLD[1]) CMD_PIX_XPOS <= CMD_PIX_XPOS + 8'd1;
			if (DBG_EXT[2] && !DBG_EXT_OLD[2]) CMD_PIX_YPOS <= CMD_PIX_YPOS - 8'd1;
			if (DBG_EXT[3] && !DBG_EXT_OLD[3]) CMD_PIX_YPOS <= CMD_PIX_YPOS + 8'd1;
			if (DBG_EXT[5] && !DBG_EXT_OLD[5]) CMD_PIX_EN <= ~CMD_PIX_EN;
			
			if (DBG_EXT[6] && !DBG_EXT_OLD[6]) DBG_DRAW_EN <= ~DBG_DRAW_EN;
			
			if (DBG_EXT[7] && !DBG_EXT_OLD[7]) {CMD_SKIP,CMD_SKIP_EN,CMD_PIX_EN,DBG_DRAW_EN} <= '0;
`endif
			
			if (CMD_ST == CMDS_GRD_CALC_LEFT || CMD_ST == CMDS_GRD_CALC_RIGHT || CMD_ST == CMDS_GRD_CALC_LINE) begin
				GRD_CALC_STATE <= GRD_CALC_STATE + 5'd1;
				if (GRD_CALC_STATE == 5'd0) begin
					GRD_CALC_DIR_R <= DIV_A_R[5];
					GRD_CALC_DIR_G <= DIV_A_G[5];
					GRD_CALC_DIR_B <= DIV_A_B[5];
				end
			end
									
			if (CE_R) DRAW_END <= 0;
			if (FBD_ST == FBDS_WRITE) DRAW_ENABLE <= 0;
			case (CMD_ST) 
				CMDS_IDLE: begin
`ifdef DEBUG
					CMD_CURR <= '0;
`endif
				end
					
				CMDS_READ: begin
`ifdef DEBUG
					DBG_CMD_WAIT_CNT <= DBG_CMD_WAIT_CNT + 1'd1;
`endif
					CMD_READ <= 0;
					
					if (CMD_READ_DONE) begin
`ifdef DEBUG
						CMD_CURR <= CMD_CURR + 1'd1;
						DBG_SKIP <= (CMD_CURR == CMD_SKIP);
`endif
						if (!CMD.CMDCTRL.JP[2] && !CMD.CMDCTRL.END 
`ifdef DEBUG
						    && (CMD_CURR != CMD_SKIP || !CMD_SKIP_EN)
`endif
						                                             ) begin
							case (CMD.CMDCTRL.COMM) 
								4'h0: begin	//normal sprite
									if (CMD.CMDPMOD.CCB[2]) begin
										GRD_READ <= 1;
										CMD_DELAY <= 8'd10;
										CMD_ST <= CMDS_GRD_LOAD;
									end else begin
										CMD_DELAY <= 8'd23;
										CMD_ST <= CMDS_EXEC;
									end
								end
							
								4'h1: begin	//scaled sprite
									if (CMD.CMDPMOD.CCB[2]) begin
										GRD_READ <= 1;
										CMD_DELAY <= 8'd10;
										CMD_ST <= CMDS_GRD_LOAD;
									end else begin
										CMD_DELAY <= 8'd23;
										CMD_ST <= CMDS_EXEC;
									end
								end
								
								4'h2,
								4'h3: begin	//distored sprite
									if (CMD.CMDPMOD.CCB[2]) begin
										GRD_READ <= 1;
										CMD_DELAY <= 8'd10;
										CMD_ST <= CMDS_GRD_LOAD;
									end else begin
										CMD_DELAY <= 8'd23;
										CMD_ST <= CMDS_EXEC;
									end
								end
								
								4'h4,			//polygon
								4'h5,
								4'h7: begin	//polyline
									if (CMD.CMDPMOD.CCB[2]) begin
										GRD_READ <= 1;
										CMD_DELAY <= 8'd0;
										CMD_ST <= CMDS_GRD_LOAD;
									end else begin
										CMD_DELAY <= 8'd0;
										CMD_ST <= CMDS_EXEC;
									end
								end
								
								4'h6: begin	//line
									if (CMD.CMDPMOD.CCB[2]) begin
										GRD_READ <= 1;
										CMD_DELAY <= 8'd0;
										CMD_ST <= CMDS_GRD_LOAD;
									end else begin
										CMD_DELAY <= 8'd0;
										CMD_ST <= CMDS_EXEC;
									end
								end
							
								4'h8,
								4'hB,
								4'h9,
								4'hA,
								4'hB: begin	
									CMD_DELAY <= 8'd0;
									CMD_ST <= CMDS_EXEC;
								end
							
								default: begin	
									CMD_READ <= 1;
									CMD_ST <= CMDS_READ;
								end
							endcase
						end
						else begin
							CMD_ST <= CMDS_END;
						end
						
						COPR <= CMD_ADDR[18:3];
`ifdef DEBUG
						DBG_CMD_WAIT_CNT <= '0;
						DBG_CMD_ADDR_ERR <= (CMD_ADDR > 18'h09000);
`endif
					end
				end
				
				CMDS_GRD_LOAD: begin
					GRD_READ <= 0;
					if (GRD_READ_DONE) begin 
						CMD_ST <= CMDS_EXEC;
					end
				end
				
				CMDS_EXEC: begin
						case (CMD.CMDCTRL.COMM)
							4'h0,			//normal sprite
							4'h1,			//scaled sprite
							4'h2,
							4'h3: begin	//distored sprite
								if (CMD.CMDPMOD.CM == 3'b001) begin
									CLT_READ <= 1;
									CMD_ST <= CMDS_CLT_LOAD;
								end else begin
									if (PENALTY_CNT > CMDS_DELAY) CMD_DELAY <= '0;
									CMD_ST <= CMDS_DELAY;
								end
							end
							
							4'h4: begin	//polygon
								CMD_ST <= CMDS_DELAY;
							end
							
							4'h5,
							4'h7: begin	//polyline
								CMD_ST <= CMDS_DELAY;
							end
							
							4'h6: begin	//line
								CMD_ST <= CMDS_DELAY;
							end
							
							4'h8,
							4'hB: begin	
								SYS_CLIP_STATE <= '0;
								CMD_ST <= CMDS_END;
							end
							
							4'h9: begin	
								SYS_CLIP_STATE <= '0;
								CMD_ST <= CMDS_END;
							end
							
							4'hA: begin	
								SYS_CLIP_STATE <= '0;
								CMD_ST <= CMDS_END;
							end
								
							default: begin	
								CMD_ST <= CMDS_END;
							end
						endcase
`ifdef DEBUG
						if (DBG_CMD_CNT == 16) begin
							DBG_CMD_ADDR16 <= CMD_ADDR;
						end
`endif
				end
				
				CMDS_CLT_LOAD: begin
					CLT_READ <= 0;
					if (CLT_READ_DONE) begin
						CMD_ST <= CMDS_DELAY;
					end
				end
				
				CMDS_DELAY: begin
					//Edge setup: the row-end registers carry the vertex pairs whose differences the setup needs, so that
					//the row-difference arithmetic (NEW_LINE_*) and the clip differences serve it: A / D (left edge, and
					//CLIP_H's A and D compares) into EDGE_INIT, B / C (right edge, CLIP_H's B and C compares) into
					//POLYGON_CALCE, A / B again from POLYGON_CALCH on (as before). LINE_INIT loads A / B for the line
					//commands. Nothing reads LEFT_/RIGHT_VERT here or in EDGE_INIT / CALCE but this setup (and the OVER
					//flags, written again before the CALCTX states read them).
					LEFT_VERT <= VERTA;
					RIGHT_VERT <= VERTD;
					if (CE_R) begin
						CMD_DELAY <= CMD_DELAY - 1'd1;
						if (!CMD_DELAY) begin
							case (CMD.CMDCTRL.COMM) 
								4'h0: CMD_ST <= CMDS_EDGE_INIT;
								4'h1: CMD_ST <= CMDS_EDGE_INIT;
								4'h2,
								4'h3: CMD_ST <= CMDS_EDGE_INIT;
								4'h4: CMD_ST <= CMDS_EDGE_INIT;							
								4'h5,
								4'h7: CMD_ST <= CMDS_LINE_INIT;							
								4'h6: CMD_ST <= CMDS_LINE_INIT;
							endcase
							CMD_DELAY <= 9'd8;
						end
					end
				end
				
				CMDS_EDGE_INIT: begin
					//left edge D - A: LEFT_VERT = VERTA, RIGHT_VERT = VERTD (DELAY), so NEW_LINE_* are its differences,
					//absolute values and major / minor axis (LEFT_HEIGHT = max, as POLYGON_CALCE computed it)
					LEFT_VERT <= VERTB;
					RIGHT_VERT <= VERTC;
					LEFT_MIN <= NEW_LINE_MIN;
					LEFT_HEIGHT <= NEW_LINE_MAJ;
					LEFT_XMAJ <= ~NEW_LINE_YMAJ;
					POLY_LDIRX <= NEW_LINE_SX[12];
					POLY_LDIRY <= NEW_LINE_SY[12];

					DIR <= '0;

					CMD_ST <= CMDS_POLYGON_CALCE;
				end
				
				CMDS_LINE_INIT: begin
					LEFT_VERT <= VERTA;
					RIGHT_VERT <= VERTB;
					POLY_S <= 2'b00;
					TEXT_X <= '0;
					LEFT_GHCOLOR <= RGBItoF(GHCOLOR_A);
					RIGHT_GHCOLOR <= RGBItoF(GHCOLOR_B);
					CMD_ST <= CMDS_LINE_CALC;
				end
				
				CMDS_POLYGON_CALCE: begin
					//right edge C - B (LEFT_VERT = VERTB, RIGHT_VERT = VERTC from EDGE_INIT), then the row ends A / B
					LEFT_VERT <= VERTA;
					RIGHT_VERT <= VERTB;
					RIGHT_MIN <= NEW_LINE_MIN;
					RIGHT_HEIGHT <= NEW_LINE_MAJ;
					RIGHT_XMAJ <= ~NEW_LINE_YMAJ;
					POLY_RDIRX <= NEW_LINE_SX[12];
					POLY_RDIRY <= NEW_LINE_SY[12];

					//CLIP_H (written in EDGE_INIT before; first read in the CALCX states): B and C are the signs of this
					//clock's 14-bit clip differences (exact signed compares); A and D are LINE_LEFT_/RIGHT_OVER, the same
					//terms from EDGE_INIT (SYS_CLIP_X1/X2 are the same then)
					CLIP_H <= 0;
					if ((LINE_DIFF_LEFT_CLIPX1[13] && LINE_DIFF_RIGHT_CLIPX1[13]) || LINE_LEFT_OVER ||
						 (!LINE_DIFF_LEFT_CLIPX2[13] && !LINE_EQ_LEFT_CLIPX2 && !LINE_DIFF_RIGHT_CLIPX2[13] && !LINE_EQ_RIGHT_CLIPX2) || LINE_RIGHT_OVER) begin
						CLIP_H <= ~CMD.CMDPMOD.PCLP;
					end

					CMD_ST <= CMDS_POLYGON_CALCH;
				end

				CMDS_POLYGON_CALCH: begin
					if (LEFT_HEIGHT >= RIGHT_HEIGHT) begin
						COL_HEIGHT <= LEFT_HEIGHT;
					end else begin
						COL_HEIGHT <= RIGHT_HEIGHT;
					end
					LEFT_MAJ <= LEFT_HEIGHT >= RIGHT_HEIGHT;

					CMD_ST <= CMDS_POLYGON_CALCTY;
				end
				
				CMDS_POLYGON_CALCTY: begin
					//text Y error setup, one adder: H - (2(CH+1) + x) = H + ~{CH+1,x} + 1 when CH+1 <= H-1, else
					//(CH+1) - (2(CH+1) - x) = ~CH + x (14-bit); ADJ 2(CH+1) or 2CH, INC 2H or 2(H-1), as before
					TY_X = !TEXT_DIRY || ORIG_HEIGHT == 8'd1 ? 1'b0 : 1'b1;
					TY_LT = (COL_HEIGHT + 13'd1) <= {5'b00000,ORIG_HEIGHT - 8'd1};
					TEXT_Y_ERROR_INC <= TY_LT ? {5'b00000,ORIG_HEIGHT,1'b0} : {5'b00000,ORIG_HEIGHT - 8'd1,1'b0};
					TEXT_Y_ERROR_ADJ <= TY_LT ? {COL_HEIGHT + 13'd1,1'b0} : {1'b0,COL_HEIGHT,1'b0};
					TEXT_Y_ERROR <= (TY_LT ? {6'b000000,ORIG_HEIGHT} : ~{2'b00,COL_HEIGHT}) + (TY_LT ? ~{COL_HEIGHT + 13'd1,TY_X} : 14'd0) + {13'd0,TY_LT|TY_X};
					
					//the three edge steppers (see LEFT_COL_ERROR): E0 = -H-1
					LEFT_COL_ERROR <= ~LEFT_HEIGHT;
					RIGHT_COL_ERROR <= ~RIGHT_HEIGHT;
					D_ERROR <= ~COL_HEIGHT;

					COL_D <= COL_HEIGHT;
					
					SPR_OFFSY <= TEXT_DIRY ? (ORIG_HEIGHT - 8'd1) * ORIG_WIDTH[8:3] : '0;
					TEXT_Y <= '0;
					TEXT_X <= '0;
					
					CMD_ST <= CMDS_GRD_CALC_COL;
				end
				
				CMDS_GRD_CALC_COL: begin
					LEFT_GHCOLOR <= RGBItoF(GHCOLOR_A);
					RIGHT_GHCOLOR <= RGBItoF(GHCOLOR_B);
					
					GRD_CALC_1 <= GHCOLOR_A;
					GRD_CALC_2 <= GHCOLOR_D;
					GRD_CALC_S <= COL_HEIGHT + 12'd1;
					GRD_CALC_STATE <= '0;
					CMD_ST <= CMDS_GRD_CALC_LEFT;
				end
				
				CMDS_GRD_CALC_LEFT: begin
					if (GRD_CALC_STATE == 5'd20) begin
						GRD_CALC_STATE <= '0;
						LEFT_GHCOLOR_STEP <= GRD_STEP;
						
						GRD_CALC_1 <= GHCOLOR_B;
						GRD_CALC_2 <= GHCOLOR_C;
						GRD_CALC_S <= COL_HEIGHT + 12'd1;
						CMD_ST <= CMDS_GRD_CALC_RIGHT;
					end
				end
				
				CMDS_GRD_CALC_RIGHT: begin
					if (GRD_CALC_STATE == 5'd20) begin
						GRD_CALC_STATE <= '0;
						RIGHT_GHCOLOR_STEP <= GRD_STEP;
						CMD_ST <= CMDS_ROW_DRAW;
					end
				end
				
				CMDS_ROW_DRAW: begin
					if (TEXT_Y_READ_STEP) begin
						TEXT_Y <= TEXT_Y + 8'd1;
						SPR_OFFSY <= SPR_OFFSY_NEXT;
					end
					
					if (COL_DRAW_STEP) begin
						case (CMD.CMDCTRL.COMM) 
							4'h0: CMD_ST <= CMDS_NSPR_CALCX;
							4'h1: CMD_ST <= CMDS_SSPR_CALCX;
							default: CMD_ST <= CMDS_LINE_CALC;
						endcase
					end else begin
						CMD_ST <= CMDS_ROW_DRAW;
					end
					TEXT_Y_ERROR <= NEXT_TEXT_Y_ERROR;
				end
				
				CMDS_NSPR_CALCX: begin
					/*if (LEFT_VERT.Y == RIGHT_VERT.Y && $signed(LEFT_VERT.X) < $signed(SYS_CLIP_X1) && !CMD.CMDPMOD.PCLP) begin
						LINE_VERTA.X <= RIGHT_VERT.X[10:0];
						LINE_VERTA.Y <= RIGHT_VERT.Y[10:0];
						LINE_VERTB.X <= SYS_CLIP_X1[10:0];
						LINE_VERTB.Y <= LEFT_VERT.Y[10:0];
						LINE_DIRX <= 0;
						LINE_DIRY <= 0;
						LINE_CLIP <= 1;
						DIR[0] <= 1;
					end else if (LEFT_VERT.Y == RIGHT_VERT.Y && $signed(LEFT_VERT.X) > $signed(SYS_CLIP_X2) && !CMD.CMDPMOD.PCLP) begin
						LINE_VERTA.X <= RIGHT_VERT.X[10:0];
						LINE_VERTA.Y <= RIGHT_VERT.Y[10:0];
						LINE_VERTB.X <= SYS_CLIP_X2[10:0];
						LINE_VERTB.Y <= LEFT_VERT.Y[10:0];
						LINE_DIRX <= 0;
						LINE_DIRY <= 0;
						LINE_CLIP <= 1;
						DIR[0] <= 1;
					end else*/ begin
						LINE_VERTA.X <= LEFT_VERT.X[11:0];
						LINE_VERTA.Y <= LEFT_VERT.Y[11:0];
						LINE_VERTB.X <= RIGHT_VERT.X[11:0];
						LINE_VERTB.Y <= RIGHT_VERT.Y[11:0];
						LINE_DIRX <= 0;
						LINE_DIRY <= 0;
						LINE_CLIP <= 0;
						DIR[0] <= 0;
					end
					EC_FIND <= 0;
					HSS_EN <= 0;
					
					ROW_WIDTH <= NEW_ROW_WIDTH;
					
					CMD_ST <= CMDS_SSPR_CALCTX;
				end
				
				CMDS_SSPR_CALCX: begin
					if (LINE_LT_LEFT_CLIPX1 && LINE_GT_RIGHT_CLIPX2 && CLIP_H) begin
						LINE_VERTA.X <= LEFT_VERT.X[11:0];
						LINE_VERTA.Y <= LEFT_VERT.Y[11:0];
						LINE_VERTB.X <= SYS_CLIP_X2[11:0];
						LINE_VERTB.Y <= RIGHT_VERT.Y[11:0];
						LINE_DIRX <= NEW_LINE_SX[12];
						LINE_CLIP <= 0;
						DIR[0] <= 0;
					end else if (LINE_GT_LEFT_CLIPX2 && LINE_LT_RIGHT_CLIPX1 && CLIP_H) begin
						LINE_VERTA.X <= LEFT_VERT.X[11:0];
						LINE_VERTA.Y <= LEFT_VERT.Y[11:0];
						LINE_VERTB.X <= SYS_CLIP_X1[11:0];
						LINE_VERTB.Y <= RIGHT_VERT.Y[11:0];
						LINE_DIRX <= NEW_LINE_SX[12];
						LINE_CLIP <= 0;
						DIR[0] <= 0;
					end else if (LINE_LT_LEFT_CLIPX1 && (LINE_LT_RIGHT_CLIPX2 || LINE_EQ_RIGHT_CLIPX2) && CLIP_H) begin
						LINE_VERTA.X <= RIGHT_VERT.X[11:0];
						LINE_VERTA.Y <= RIGHT_VERT.Y[11:0];
						LINE_VERTB.X <= LEFT_VERT.X[11:0];
						LINE_VERTB.Y <= LEFT_VERT.Y[11:0];
						LINE_DIRX <= ~NEW_LINE_SX[12];
						LINE_CLIP <= 1;
						DIR[0] <= 1;
					end else if ((LINE_LT_LEFT_CLIPX2 || LINE_EQ_LEFT_CLIPX2) && LINE_GT_RIGHT_CLIPX1 && CLIP_H) begin
						LINE_VERTA.X <= LEFT_VERT.X[11:0];
						LINE_VERTA.Y <= LEFT_VERT.Y[11:0];
						LINE_VERTB.X <= RIGHT_VERT.X[11:0];
						LINE_VERTB.Y <= RIGHT_VERT.Y[11:0];
						LINE_DIRX <= NEW_LINE_SX[12];
						LINE_CLIP <= 1;
						DIR[0] <= 0;
					end else if (LINE_GT_LEFT_CLIPX2 && (LINE_GT_RIGHT_CLIPX1 || LINE_EQ_RIGHT_CLIPX1) && CLIP_H) begin
						LINE_VERTA.X <= RIGHT_VERT.X[11:0];
						LINE_VERTA.Y <= RIGHT_VERT.Y[11:0];
						LINE_VERTB.X <= LEFT_VERT.X[11:0];
						LINE_VERTB.Y <= LEFT_VERT.Y[11:0];
						LINE_DIRX <= ~NEW_LINE_SX[12];
						LINE_CLIP <= 1;
						DIR[0] <= 1;
					end else if ((LINE_GT_LEFT_CLIPX1 || LINE_EQ_LEFT_CLIPX1) && LINE_GT_RIGHT_CLIPX2 && CLIP_H) begin
						LINE_VERTA.X <= LEFT_VERT.X[11:0];
						LINE_VERTA.Y <= LEFT_VERT.Y[11:0];
						LINE_VERTB.X <= RIGHT_VERT.X[11:0];
						LINE_VERTB.Y <= RIGHT_VERT.Y[11:0];
						LINE_DIRX <= NEW_LINE_SX[12];
						LINE_CLIP <= 1;
						DIR[0] <= 0;
					end else begin
						LINE_VERTA.X <= LEFT_VERT.X[11:0];
						LINE_VERTA.Y <= LEFT_VERT.Y[11:0];
						LINE_VERTB.X <= RIGHT_VERT.X[11:0];
						LINE_VERTB.Y <= RIGHT_VERT.Y[11:0];
						LINE_DIRX <= NEW_LINE_SX[12];
						LINE_CLIP <= 0;
						DIR[0] <= 0;
					end
					LINE_DIRY <= 0;
					EC_FIND <= 0;
					
					ROW_WIDTH <= NEW_ROW_WIDTH;
					
					CMD_ST <= CMDS_SSPR_CALCTX;
				end
				
				CMDS_SSPR_CALCTX: begin
					TEXT_ERROR_INC <= TX_INC;
					TEXT_ERROR_ADJ <= TX_LT ? (ROW_WIDTH << 1) : ((ROW_WIDTH - 13'd1) << 1);
					TEXT_ERROR <= TX_E;
					HSS_EN <= TX_HSS;

					if ((LINE_LEFT_OVER || LINE_RIGHT_OVER || LINE_TOP_OVER || LINE_BOTTOM_OVER) && !CMD.CMDPMOD.PCLP) begin
						CMD_ST <= CMDS_LINE_NEXT;
					end else begin
						SPR_READ <= 1;
						CMD_ST <= CMDS_PRE_DRAW;
					end
				end
				
				CMDS_LINE_CALC: begin
					LINE_SWAP = 0;
					if (LINE_LT_LEFT_CLIPX1 && LINE_GT_RIGHT_CLIPX2 && CLIP_H) begin
						LINE_VERTA.X <= LEFT_VERT.X[11:0];
						LINE_VERTA.Y <= LEFT_VERT.Y[11:0];
						LINE_VERTB.X <= SYS_CLIP_X2[11:0];
						LINE_VERTB.Y <= RIGHT_VERT.Y[11:0];
						LINE_DIRX <= NEW_LINE_SX[12];
						LINE_DIRY <= NEW_LINE_SY[12];
						LINE_CLIP <= 0;
						DIR[0] <= 0;
					end else if (LINE_GT_LEFT_CLIPX2 && LINE_LT_RIGHT_CLIPX1 && CLIP_H) begin
						LINE_VERTA.X <= LEFT_VERT.X[11:0];
						LINE_VERTA.Y <= LEFT_VERT.Y[11:0];
						LINE_VERTB.X <= SYS_CLIP_X1[11:0];
						LINE_VERTB.Y <= RIGHT_VERT.Y[11:0];
						LINE_DIRX <= NEW_LINE_SX[12];
						LINE_DIRY <= NEW_LINE_SY[12];
						LINE_CLIP <= 0;
						DIR[0] <= 0;
					end else if (LINE_LT_LEFT_CLIPX1 && (LINE_LT_RIGHT_CLIPX2 || LINE_EQ_RIGHT_CLIPX2) && CLIP_H) begin
						LINE_VERTA.X <= RIGHT_VERT.X[11:0];
						LINE_VERTA.Y <= RIGHT_VERT.Y[11:0];
						LINE_VERTB.X <= LEFT_VERT.X[11:0];
						LINE_VERTB.Y <= LEFT_VERT.Y[11:0];
						LINE_DIRX <= ~NEW_LINE_SX[12];
						LINE_DIRY <= ~NEW_LINE_SY[12];
						LINE_CLIP <= 1;
						DIR[0] <= 1;
						LINE_SWAP = 1;
					end else if ((LINE_LT_LEFT_CLIPX2 || LINE_EQ_LEFT_CLIPX2) && LINE_GT_RIGHT_CLIPX1 && CLIP_H) begin
						LINE_VERTA.X <= LEFT_VERT.X[11:0];
						LINE_VERTA.Y <= LEFT_VERT.Y[11:0];
						LINE_VERTB.X <= RIGHT_VERT.X[11:0];
						LINE_VERTB.Y <= RIGHT_VERT.Y[11:0];
						LINE_DIRX <= NEW_LINE_SX[12];
						LINE_DIRY <= NEW_LINE_SY[12];
						LINE_CLIP <= 1;
						DIR[0] <= 0;
					end else if (LINE_GT_LEFT_CLIPX2 && (LINE_GT_RIGHT_CLIPX1 || LINE_EQ_RIGHT_CLIPX1) && CLIP_H) begin
						LINE_VERTA.X <= RIGHT_VERT.X[11:0];
						LINE_VERTA.Y <= RIGHT_VERT.Y[11:0];
						LINE_VERTB.X <= LEFT_VERT.X[11:0];
						LINE_VERTB.Y <= LEFT_VERT.Y[11:0];
						LINE_DIRX <= ~NEW_LINE_SX[12];
						LINE_DIRY <= ~NEW_LINE_SY[12];
						LINE_CLIP <= 1;
						DIR[0] <= 1;
						LINE_SWAP = 1;
					end else if ((LINE_GT_LEFT_CLIPX1 || LINE_EQ_LEFT_CLIPX1) && LINE_GT_RIGHT_CLIPX2 && CLIP_H) begin
						LINE_VERTA.X <= LEFT_VERT.X[11:0];
						LINE_VERTA.Y <= LEFT_VERT.Y[11:0];
						LINE_VERTB.X <= RIGHT_VERT.X[11:0];
						LINE_VERTB.Y <= RIGHT_VERT.Y[11:0];
						LINE_DIRX <= NEW_LINE_SX[12];
						LINE_DIRY <= NEW_LINE_SY[12];
						LINE_CLIP <= 1;
						DIR[0] <= 0;
					end else begin
						LINE_VERTA.X <= LEFT_VERT.X[11:0];
						LINE_VERTA.Y <= LEFT_VERT.Y[11:0];
						LINE_VERTB.X <= RIGHT_VERT.X[11:0];
						LINE_VERTB.Y <= RIGHT_VERT.Y[11:0];
						LINE_DIRX <= NEW_LINE_SX[12];
						LINE_DIRY <= NEW_LINE_SY[12];
						LINE_CLIP <= 0;
						DIR[0] <= 0;
					end
					
					//major / minor axis: ADJ = 2*major (subtracted, see LINE_ERROR_ADJ), INC = 2*minor, width = major + 1
					//(the same incrementer as the sprite rows). The Bresenham error E (start -major - 2*minor, steps
					//E' = E + INC >= 1 ? E + INC - ADJ : E + INC) is kept as G = E + INC - 1: start ~major, no adder; the
					//step test E + INC >= 1 is G >= 0. E + INC stays within [1 - 2*major, 2*minor] (major <= 4095), so
					//neither form wraps and the tests agree on every step.
					LINE_ERROR_INC <= (NEW_LINE_MIN << 1);
					LINE_ERROR_ADJ <= (NEW_LINE_MAJ << 1);
					LINE_ERROR <= ~{2'b00,NEW_LINE_MAJ};
					LINE_S <= NEW_LINE_YMAJ;
					ROW_WIDTH <= NEW_ROW_WIDTH;
					if (NEW_LINE_YMAJ) begin
						AA_X_INC <= (NEW_LINE_SY[12]^LINE_SWAP) ? {12{(NEW_LINE_SX[12]^LINE_SWAP)}} : {{11{1'b0}},~(NEW_LINE_SX[12]^LINE_SWAP)};
						AA_Y_INC <= (NEW_LINE_SY[12]^LINE_SWAP) ? {{11{1'b0}},(NEW_LINE_SX[12]^LINE_SWAP)} : {12{~(NEW_LINE_SX[12]^LINE_SWAP)}};
					end else begin
						AA_X_INC <= (NEW_LINE_SX[12]^LINE_SWAP) ? {{11{1'b0}},~(NEW_LINE_SY[12]^LINE_SWAP)} : {12{(NEW_LINE_SY[12]^LINE_SWAP)}};
						AA_Y_INC <= (NEW_LINE_SX[12]^LINE_SWAP) ? {{11{1'b0}},~(NEW_LINE_SY[12]^LINE_SWAP)} : {12{(NEW_LINE_SY[12]^LINE_SWAP)}};
					end
					
					CMD_ST <= CMDS_LINE_CALCTX;
				end
				
				CMDS_LINE_CALCTX: begin
					TEXT_ERROR_INC <= TX_INC;
					TEXT_ERROR_ADJ <= TX_LT ? (ROW_WIDTH << 1) : ((ROW_WIDTH - 13'd1) << 1);
					TEXT_ERROR <= TX_E;
					HSS_EN <= TX_HSS;
					
					EC_FIND <= 0;
					AA <= 0;
				
					if ((LINE_LEFT_OVER || LINE_RIGHT_OVER || LINE_TOP_OVER || LINE_BOTTOM_OVER) && !CMD.CMDPMOD.PCLP) begin
						CMD_ST <= CMDS_LINE_NEXT;
					end else begin
						SPR_READ <= ~CMD.CMDCTRL.COMM[2];
						CMD_ST <= CMDS_PRE_DRAW;
					end
				end
				
				CMDS_PRE_DRAW: begin
					TEXT_X <= '0;
					if (!TEXT_ERROR[12]) begin
						if (TEXT_X_READ_STEP) begin
							TEXT_X <= (HSS_EN ? 2'd2 : 2'd1);
						end
						TEXT_ERROR <= NEXT_TEXT_ERROR;
					end
					CMD_ST <= CMDS_GRD_CALC_ROW;
				end
				
				CMDS_GRD_CALC_ROW: begin
					LINE_GHCOLOR <= DIR[0] ? RIGHT_GHCOLOR : LEFT_GHCOLOR;
					GRD_CALC_1 <= RGBFtoI(LEFT_GHCOLOR);
					GRD_CALC_2 <= RGBFtoI(RIGHT_GHCOLOR);
					GRD_CALC_S <= ROW_WIDTH;
					CMD_ST <= CMDS_GRD_CALC_LINE;
				end
				
				CMDS_GRD_CALC_LINE: begin
					if (GRD_CALC_STATE == 5'd20) begin
						GRD_CALC_STATE <= '0;
						
						case (CMD.CMDCTRL.COMM) 
							4'h0: CMD_ST <= CMDS_NSPR_DRAW;
							4'h1: CMD_ST <= CMDS_SSPR_DRAW;
							default: CMD_ST <= CMDS_LINE_DRAW;
						endcase
					end
				end
				
				CMDS_NSPR_DRAW,
				CMDS_SSPR_DRAW: if (!DRAW_WAIT && SPR_DATA_READY) begin
					DRAW_ENABLE <= LINE_DRAW_STEP;
					
					if (TEXT_X_READ_STEP) begin
						TEXT_X <= TEXT_X + (HSS_EN ? 2'd2 : 2'd1);
						if (IS_PAT_EC) EC_FIND <= 1;
					end
					TEXT_ERROR <= NEXT_TEXT_ERROR;
					
					if (LINE_DRAW_STEP) begin
						LINE_VERTA.X <= LINE_VERTA_X_STEP;
						
						{LINE_GHCOLOR.R.INT,LINE_GHCOLOR.R.FRAC} <= {LINE_GHCOLOR.R.INT,LINE_GHCOLOR.R.FRAC} + ({GRD_STEP.R.INT,GRD_STEP.R.FRAC}^{17{DIR[0]^GRD_STEP.R.DIR}}) + (DIR[0]^GRD_STEP.R.DIR);
						{LINE_GHCOLOR.G.INT,LINE_GHCOLOR.G.FRAC} <= {LINE_GHCOLOR.G.INT,LINE_GHCOLOR.G.FRAC} + ({GRD_STEP.G.INT,GRD_STEP.G.FRAC}^{17{DIR[0]^GRD_STEP.G.DIR}}) + (DIR[0]^GRD_STEP.G.DIR);
						{LINE_GHCOLOR.B.INT,LINE_GHCOLOR.B.FRAC} <= {LINE_GHCOLOR.B.INT,LINE_GHCOLOR.B.FRAC} + ({GRD_STEP.B.INT,GRD_STEP.B.FRAC}^{17{DIR[0]^GRD_STEP.B.DIR}}) + (DIR[0]^GRD_STEP.B.DIR);
					end
					  
					if ((LINE_VERTA.X == LINE_VERTB.X && LINE_DRAW_STEP) || (IS_PAT_EC && EC_FIND && TEXT_X_READ_STEP)) begin
						SPR_READ <= 0;
						CMD_ST <= CMDS_LINE_NEXT;
					end
				end
				
				CMDS_LINE_DRAW: if (!DRAW_WAIT && (SPR_DATA_READY || CMD.CMDCTRL.COMM >= 4'h4)) begin
					DRAW_ENABLE <= LINE_DRAW_STEP;
					
					if (TEXT_X_READ_STEP) begin
						TEXT_X <= TEXT_X + (HSS_EN ? 2'd2 : 2'd1);
						if (IS_PAT_EC) EC_FIND <= 1;
					end
					TEXT_ERROR <= NEXT_TEXT_ERROR;
					
					{LINE_VERTA_X_OVR,LINE_VERTA_Y_OVR} = '0;
					AA_DRAW = 0;
					AA_X <= RSTEP_X[11:0];
					AA_Y <= RSTEP_Y[11:0];
					if (LINE_DRAW_STEP) begin
						if (LINE_AA_STEP) begin
							if (!LINE_S) begin
								LINE_VERTA.Y <= LINE_VERTA_Y_STEP;
							end else begin
								LINE_VERTA.X <= LINE_VERTA_X_STEP;
							end
							AA <= 1;
							AA_DRAW = 1;
						end else begin
							if (!LINE_S) begin
								LINE_VERTA.X <= LINE_VERTA_X_STEP;
								LINE_VERTA_X_OVR = (LINE_VERTA.X == LINE_VERTB.X) || ($signed(LINE_VERTA.X) < $signed(SYS_CLIP_X1) && LINE_DIRX && !CMD.CMDPMOD.PCLP) || ($signed(LINE_VERTA.X) > $signed(SYS_CLIP_X2) && !LINE_DIRX && !CMD.CMDPMOD.PCLP);
								LINE_VERTA_Y_OVR = ($signed(LINE_VERTA.Y) < $signed(SYS_CLIP_Y1) && LINE_DIRY && !CMD.CMDPMOD.PCLP) || ($signed(LINE_VERTA.Y) > $signed(SYS_CLIP_Y2) && !LINE_DIRY && !CMD.CMDPMOD.PCLP);
							end else begin
								LINE_VERTA.Y <= LINE_VERTA_Y_STEP;
								LINE_VERTA_X_OVR = ($signed(LINE_VERTA.X) < $signed(SYS_CLIP_X1) && LINE_DIRX && !CMD.CMDPMOD.PCLP) || ($signed(LINE_VERTA.X) > $signed(SYS_CLIP_X2) && !LINE_DIRX && !CMD.CMDPMOD.PCLP);
								LINE_VERTA_Y_OVR = (LINE_VERTA.Y == LINE_VERTB.Y) || ($signed(LINE_VERTA.Y) < $signed(SYS_CLIP_Y1) && LINE_DIRY && !CMD.CMDPMOD.PCLP) || ($signed(LINE_VERTA.Y) > $signed(SYS_CLIP_Y2) && !LINE_DIRY && !CMD.CMDPMOD.PCLP);
							end
						end
						LINE_ERROR <= NEXT_LINE_ERROR;
					
						{LINE_GHCOLOR.R.INT,LINE_GHCOLOR.R.FRAC} <= {LINE_GHCOLOR.R.INT,LINE_GHCOLOR.R.FRAC} + ({GRD_STEP.R.INT,GRD_STEP.R.FRAC}^{17{DIR[0]^GRD_STEP.R.DIR}}) + (DIR[0]^GRD_STEP.R.DIR);
						{LINE_GHCOLOR.G.INT,LINE_GHCOLOR.G.FRAC} <= {LINE_GHCOLOR.G.INT,LINE_GHCOLOR.G.FRAC} + ({GRD_STEP.G.INT,GRD_STEP.G.FRAC}^{17{DIR[0]^GRD_STEP.G.DIR}}) + (DIR[0]^GRD_STEP.G.DIR);
						{LINE_GHCOLOR.B.INT,LINE_GHCOLOR.B.FRAC} <= {LINE_GHCOLOR.B.INT,LINE_GHCOLOR.B.FRAC} + ({GRD_STEP.B.INT,GRD_STEP.B.FRAC}^{17{DIR[0]^GRD_STEP.B.DIR}}) + (DIR[0]^GRD_STEP.B.DIR);
					end

					if (IS_PAT_EC && EC_FIND && TEXT_X_READ_STEP) begin
						CMD_ST <= AA_DRAW ? CMDS_LINE_END : CMDS_LINE_NEXT;
					end else if ((LINE_VERTA_X_OVR || LINE_VERTA_Y_OVR) && LINE_DRAW_STEP) begin
						CMD_ST <= AA_DRAW ? CMDS_LINE_END : CMDS_LINE_NEXT;
					end else if (AA_DRAW) begin
						CMD_ST <= CMDS_AA_DRAW;
					end
				end
				
				CMDS_AA_DRAW: if (!DRAW_WAIT && (SPR_DATA_READY || CMD.CMDCTRL.COMM >= 4'h4)) begin
					DRAW_ENABLE <= 1;
					AA <= 0;
					
					{LINE_VERTA_X_OVR,LINE_VERTA_Y_OVR} = '0;
					if (!LINE_S) begin
						LINE_VERTA.X <= LINE_VERTA_X_STEP;
						LINE_VERTA_X_OVR = (LINE_VERTA.X == LINE_VERTB.X);
					end else begin
						LINE_VERTA.Y <= LINE_VERTA_Y_STEP;
						LINE_VERTA_Y_OVR = (LINE_VERTA.Y == LINE_VERTB.Y);
					end
					if ((LINE_VERTA_X_OVR || LINE_VERTA_Y_OVR) && LINE_DRAW_STEP) 
						CMD_ST <= CMDS_LINE_NEXT;
					else
						CMD_ST <= CMDS_LINE_DRAW;
				end
				
				CMDS_LINE_END: if (!DRAW_WAIT && (SPR_DATA_READY || CMD.CMDCTRL.COMM >= 4'h4)) begin
					DRAW_ENABLE <= AA;
					AA <= 0;
					CMD_ST <= CMDS_LINE_NEXT;
				end
				
				CMDS_LINE_NEXT: begin
					SPR_READ <= 0;
					TEXT_X <= '0;
					
					if (CMD.CMDCTRL.COMM == 4'h0 || CMD.CMDCTRL.COMM == 4'h1 || CMD.CMDCTRL.COMM == 4'h2 || CMD.CMDCTRL.COMM == 4'h3 || CMD.CMDCTRL.COMM == 4'h4) begin 
						if (LEFT_COL_X_STEP) begin
							LEFT_VERT.X <= VSTEP_X;
						end
						if (LEFT_COL_Y_STEP) begin
							LEFT_VERT.Y <= VSTEP_Y;
						end
						if (RIGHT_COL_X_STEP) begin
							RIGHT_VERT.X <= RSTEP_X;
						end
						if (RIGHT_COL_Y_STEP) begin
							RIGHT_VERT.Y <= RSTEP_Y;
						end
						
						D_ERROR <= NEXT_D_ERROR;
						LEFT_COL_ERROR <= NEXT_LEFT_COL_ERROR;
						RIGHT_COL_ERROR <= NEXT_RIGHT_COL_ERROR;
						
						{LEFT_GHCOLOR.R.INT, LEFT_GHCOLOR.R.FRAC } <= {LEFT_GHCOLOR.R.INT, LEFT_GHCOLOR.R.FRAC } + ({LEFT_GHCOLOR_STEP.R.INT, LEFT_GHCOLOR_STEP.R.FRAC }^{17{LEFT_GHCOLOR_STEP.R.DIR }}) + LEFT_GHCOLOR_STEP.R.DIR;
						{LEFT_GHCOLOR.G.INT, LEFT_GHCOLOR.G.FRAC } <= {LEFT_GHCOLOR.G.INT, LEFT_GHCOLOR.G.FRAC } + ({LEFT_GHCOLOR_STEP.G.INT, LEFT_GHCOLOR_STEP.G.FRAC }^{17{LEFT_GHCOLOR_STEP.G.DIR }}) + LEFT_GHCOLOR_STEP.G.DIR;
						{LEFT_GHCOLOR.B.INT, LEFT_GHCOLOR.B.FRAC } <= {LEFT_GHCOLOR.B.INT, LEFT_GHCOLOR.B.FRAC } + ({LEFT_GHCOLOR_STEP.B.INT, LEFT_GHCOLOR_STEP.B.FRAC }^{17{LEFT_GHCOLOR_STEP.B.DIR }}) + LEFT_GHCOLOR_STEP.B.DIR;
						{RIGHT_GHCOLOR.R.INT,RIGHT_GHCOLOR.R.FRAC} <= {RIGHT_GHCOLOR.R.INT,RIGHT_GHCOLOR.R.FRAC} + ({RIGHT_GHCOLOR_STEP.R.INT,RIGHT_GHCOLOR_STEP.R.FRAC}^{17{RIGHT_GHCOLOR_STEP.R.DIR}}) + RIGHT_GHCOLOR_STEP.R.DIR;
						{RIGHT_GHCOLOR.G.INT,RIGHT_GHCOLOR.G.FRAC} <= {RIGHT_GHCOLOR.G.INT,RIGHT_GHCOLOR.G.FRAC} + ({RIGHT_GHCOLOR_STEP.G.INT,RIGHT_GHCOLOR_STEP.G.FRAC}^{17{RIGHT_GHCOLOR_STEP.G.DIR}}) + RIGHT_GHCOLOR_STEP.G.DIR;
						{RIGHT_GHCOLOR.B.INT,RIGHT_GHCOLOR.B.FRAC} <= {RIGHT_GHCOLOR.B.INT,RIGHT_GHCOLOR.B.FRAC} + ({RIGHT_GHCOLOR_STEP.B.INT,RIGHT_GHCOLOR_STEP.B.FRAC}^{17{RIGHT_GHCOLOR_STEP.B.DIR}}) + RIGHT_GHCOLOR_STEP.B.DIR;
						
						CMD_ST <= !CMD.CMDPMOD.PCLP && !FAST ? CMDS_ROW_CLIP : CMDS_ROW_DRAW;
						COL_D <= COL_D - 12'd1;
						if (COL_D == 12'd0) begin
							CMD_ST <= CMDS_END;
						end
					end else if (CMD.CMDCTRL.COMM == 4'h5 || CMD.CMDCTRL.COMM == 4'h7) begin
						case (POLY_S)
							2'd0: begin
								LEFT_VERT <= VERTB;
								RIGHT_VERT <= VERTC;
								LEFT_GHCOLOR <= RGBItoF(GHCOLOR_B);
								RIGHT_GHCOLOR <= RGBItoF(GHCOLOR_C);
								CMD_ST <= CMDS_ROW_DRAW;
							end
							2'd1: begin
								LEFT_VERT <= VERTC;
								RIGHT_VERT <= VERTD;
								LEFT_GHCOLOR <= RGBItoF(GHCOLOR_C);
								RIGHT_GHCOLOR <= RGBItoF(GHCOLOR_D);
								CMD_ST <= CMDS_ROW_DRAW;
							end
							2'd2: begin
								LEFT_VERT <= VERTD;
								RIGHT_VERT <= VERTA;
								LEFT_GHCOLOR <= RGBItoF(GHCOLOR_D);
								RIGHT_GHCOLOR <= RGBItoF(GHCOLOR_A);
								CMD_ST <= CMDS_ROW_DRAW;
							end
							2'd3: begin
								CMD_ST <= CMDS_END;
							end
						endcase
						POLY_S <= POLY_S + 2'd01;
					end else if (CMD.CMDCTRL.COMM == 4'h6) begin
						CMD_ST <= CMDS_END;
					end else begin
						CMD_ST <= CMDS_END;
					end
				end
				
				CMDS_ROW_CLIP: begin
					CMD_DELAY <= CMD_DELAY - 9'd1;
					if (!CMD_DELAY || PENALTY_CNT >= CMD_DELAY) begin
						CMD_DELAY <= 9'd8;
						CMD_ST <= CMDS_ROW_DRAW;
					end
				end
				
				CMDS_END: begin
`ifdef VDP1_FB_EXT
					// off-chip frame buffer: the command's last pixel may still wait for the memory (READBACK / WRITE);
					// its write enable and colour come from this command (CMD, CLT, clip and local coordinates), so the
					// next command is not read before that pixel's write has been issued
					if (!(FBD_ST == FBDS_READ || FBD_ST == FBDS_READWAIT || FBD_ST == FBDS_READBACK || FBD_ST == FBDS_WRITE)) begin
`endif
					NEXT_ADDR = CMD_ADDR + 18'h10;
					case (CMD.CMDCTRL.JP[1:0])
						2'b00: begin CMD_ADDR <= NEXT_ADDR; end
						2'b01: begin CMD_ADDR <= {CMD.CMDLINK[15:2],2'b00,2'b00}; end
						2'b10: begin CMD_ADDR <= {CMD.CMDLINK[15:2],2'b00,2'b00}; if (!CMD_SUB_RUN) CMD_RET_ADDR <= NEXT_ADDR; CMD_SUB_RUN <= 1; end
						2'b11: begin CMD_ADDR <= CMD_SUB_RUN ? CMD_RET_ADDR : NEXT_ADDR; CMD_SUB_RUN <= 0; end
					endcase
					
					if (CMD.CMDCTRL.END) begin
						DRAW_END <= 1;
						CMD_ST <= CMDS_IDLE;
`ifdef DEBUG
						DBG_CMD_CNT <= '0;
`endif
					end else begin
						CMD_READ <= 1;
						CMD_ST <= CMDS_READ;
`ifdef DEBUG
						DBG_CMD_CNT <= DBG_CMD_CNT + 1'd1;
						DBG_CMD_ADDR_LAST <= CMD_ADDR;
						DBG_CMD_CMDSRCA_LAST <= CMD.CMDSRCA;
`endif
					end
`ifdef VDP1_FB_EXT
					end
`endif
				end
			endcase
		end
	end
`ifdef DEBUG
	assign DBG_START = (CMD_ST == CMDS_IDLE && (FRAME_START /*|| FRAME_START_PEND*/));
	assign DBG_CMD_END = (CMD_ST == CMDS_END);
	assign DBG_LINE_OVER = COL_HEIGHT > 12'h200 || ROW_WIDTH > 12'h200;
	assign DBG_PAT = PAT;
`endif
		
	assign PAT = GetPattern(SPR_DATA, CMD.CMDPMOD.CM);
	
	typedef enum bit [2:0] {
		FBDS_IDLE,
		FBDS_RAS,
		FBDS_READ,
		FBDS_READWAIT,
		FBDS_READBACK,
		FBDS_WRITE,
		FBDS_SKIP
	} FBDrawState_t;
	FBDrawState_t FBD_ST;
	
	bit          CPU_VRAM_BUSY;
	
	bit  [11: 0] DRAW_X;
	bit  [11: 0] DRAW_Y;
	Pattern_t    DRAW_PAT;
	RGB_t        DRAW_GHCOLOR;
	bit  [15: 0] DRAW_BACK_C;
	bit          FB_DRAW_PEND;
	bit          FB_READ_PEND;
	bit          PAT_NEXT;
	always @(posedge CLK or negedge RST_N) begin
		bit  [ 1: 0] RAS_DELAY;
		bit          FBD_RAS;
		bit          PEN_SUB3,PEN_INC,PEN_DEC;
		
		if (!RST_N) begin
			FBD_ST <= FBDS_IDLE;
			FB_DRAW_PEND <= 0;
			FB_READ_PEND <= 0;
			PAT_NEXT <= 0;
			RAS_DELAY <= '0;
			FBD_RAS <= 0;
		end
		else begin
			PAT_NEXT <= 0;
			PEN_SUB3 = 0;
			case (FBD_ST)
				FBDS_IDLE: begin
					if (CPU_VRAM_BUSY) begin
						FBD_ST <= FBDS_SKIP;
					end else if (SPR_DATA_READY || CMD.CMDCTRL.COMM >= 4'h4) begin
						if ((CMD_ST == CMDS_NSPR_DRAW || CMD_ST == CMDS_SSPR_DRAW || CMD_ST == CMDS_LINE_DRAW || CMD_ST == CMDS_AA_DRAW || CMD_ST == CMDS_LINE_END)) begin
							//one adder per axis: LOC + (AA point | stepped vertex | vertex), 12-bit as before
							DRAW_X <= LOC_COORD.X + ((CMD_ST == CMDS_AA_DRAW || CMD_ST == CMDS_LINE_END) ? AA_X :
							                         (LINE_AA_STEP && LINE_S) ? LINE_VERTA_X_STEP : LINE_VERTA.X);
							DRAW_Y <= LOC_COORD.Y + ((CMD_ST == CMDS_AA_DRAW || CMD_ST == CMDS_LINE_END) ? AA_Y :
							                         (LINE_AA_STEP && !LINE_S) ? LINE_VERTA_Y_STEP : LINE_VERTA.Y);
							if (!(CMD_ST == CMDS_AA_DRAW || CMD_ST == CMDS_LINE_END)) begin
								if (!(TEXT_X_READ_STEP && EC_FIND && IS_PAT_EC)) begin
									DRAW_PAT <= PAT;
									DRAW_GHCOLOR <= RGBFtoI(LINE_GHCOLOR);
								end
								FBD_RAS <= LINE_DRAW_STEP && (CMD.CMDCTRL.COMM <= 4'h1) && &LINE_VERTA.X[3:0];
							end
							
							
							if (LINE_DRAW_STEP && !IS_PAT_EC) begin
								if (CMD.CMDPMOD.CCB[0] || CMD.CMDPMOD.MON) begin
									FB_READ_PEND <= 1;
									FBD_ST <= FBDS_READ;
								end else begin
									FB_DRAW_PEND <= 1;
									FBD_ST <= FBDS_WRITE;
								end
							end else begin
								FBD_ST <= FBDS_SKIP;
							end
						end
						if (CMD_ST == CMDS_ROW_DRAW) begin
							FBD_RAS <= 1;
						end
						PAT_NEXT <= TEXT_X_READ_STEP;
					end
					
				end
				
				FBDS_READ: begin
					if (!FB_DRAW_WAIT) begin
						FB_READ_PEND <= 0;
						FBD_ST <= FBDS_READWAIT;
					end
				end
			
				FBDS_READWAIT: begin
					FBD_ST <= FBDS_READBACK;
				end
			
				FBDS_READBACK: begin
`ifdef VDP1_FB_EXT
					// off-chip frame buffer: the read word is there when FB_RDY is back (the on-chip RAM had it now)
					if (FB_RDY) begin
						DRAW_BACK_C <= FB_DRAW_Q;
						FB_DRAW_PEND <= 1;
						FBD_ST <= FBDS_WRITE;
					end
`else
					DRAW_BACK_C <= FB_DRAW_Q;
					FB_DRAW_PEND <= 1;
					FBD_ST <= FBDS_WRITE;
`endif
				end
				
				FBDS_WRITE: begin
					if (!FB_DRAW_WAIT) begin
						FB_DRAW_PEND <= 0;
						if (FBD_RAS)
							if (PENALTY_CNT < 10'd3) begin
								FBD_ST <= FBDS_RAS;
							end else begin
								PEN_SUB3 = 1;
								FBD_ST <= FBDS_IDLE;
							end
						else
							FBD_ST <= FBDS_IDLE;
					end
				end
				
				FBDS_RAS: if (CE_R) begin
					RAS_DELAY <= RAS_DELAY + 2'd1;
					if (RAS_DELAY == 2'd2) begin
						RAS_DELAY <= 2'd0;
						FBD_RAS <= 0;
						FBD_ST <= FBDS_IDLE;
					end
				end
				
				FBDS_SKIP: begin
					FBD_ST <= FBDS_IDLE;
				end
			endcase
			
			//one adder for the three penalty updates; the later statement had priority: - CMD_DELAY, then + 1, then - 3
			PEN_INC = ((CMD_ST == CMDS_LINE_DRAW && CMD.CMDCTRL.COMM <= 4'h3) || CMD_ST == CMDS_NSPR_DRAW || CMD_ST == CMDS_SSPR_DRAW) && PAT_PREREAD_WAIT && !CPU_VRAM_BUSY && CE_R;
			PEN_DEC = (CMD_ST == CMDS_EXEC || CMD_ST == CMDS_ROW_CLIP) && CMD_DELAY && PENALTY_CNT >= CMD_DELAY;
			if (PEN_SUB3 || PEN_INC || PEN_DEC) PENALTY_CNT <= PENALTY_CNT + (PEN_DEC ? ~{1'b0,CMD_DELAY} : PEN_INC ? 10'd1 : 10'h3FD) + {9'd0,PEN_DEC};
		end
	end
	assign DRAW_WAIT = (FBD_ST != FBDS_IDLE) || CPU_VRAM_BUSY;
	
`ifdef DEBUG
	assign DBG_PENALTY_OVER = (PENALTY_CNT >= 10'd256);
`endif

	assign SPR_ADDR = CMD.CMDCTRL.COMM >= 4'h4 ? '1 : SprAddr(SPR_OFFSY, CMD.CMDSRCA, CMD.CMDPMOD.CM);
	assign CLT_ADDR = {CMD.CMDCOLR[15:2],2'b00,2'b00};
	assign GRD_ADDR = {CMD.CMDGRDA,2'b00};
	
	bit  [15: 0] FB_DRAW_D;
	bit          FB_DRAW_WE;
	bit          SCLIP;
	bit          UCLIP;
		bit [15: 0] ORIG_C;
		bit         TP;
	always_comb begin
		bit [15: 0] CALC_C;
		bit         EC;
		bit         MESH;
		bit         IDRAW;
		
		if (!CMD.CMDCTRL.COMM[2]) begin
			case (CMD.CMDPMOD.CM)
				3'b000: ORIG_C = {CMD.CMDCOLR[15:4],DRAW_PAT.C[3:0]};
				3'b001: ORIG_C = CLT_Q;
				3'b010: ORIG_C = {CMD.CMDCOLR[15:6],DRAW_PAT.C[5:0]};
				3'b011: ORIG_C = {CMD.CMDCOLR[15:7],DRAW_PAT.C[6:0]};
				3'b100: ORIG_C = {CMD.CMDCOLR[15:8],DRAW_PAT.C[7:0]};
				default: ORIG_C = DRAW_PAT.C;
			endcase
			TP = DRAW_PAT.TP;
			EC = DRAW_PAT.EC;
		end else begin
			ORIG_C = CMD.CMDCOLR;
			TP = 0;
			EC = 0;
		end
		CALC_C = CMD.CMDPMOD.MON ? DRAW_BACK_C : !TVMR.TVM[0] ? ColorCalc(ORIG_C, DRAW_BACK_C, DRAW_GHCOLOR, CMD.CMDPMOD.CCB) : ORIG_C;
			
		SCLIP = !DRAW_X[11:10]                                    && DRAW_X[9:0] <= SYS_CLIP.X2[9:0] && !DRAW_Y[11:10]                                    && DRAW_Y[9:0] <= SYS_CLIP.Y2[9:0];
		UCLIP = !DRAW_X[11:10] && DRAW_X[9:0] >= USR_CLIP.X1[9:0] && DRAW_X[9:0] <= USR_CLIP.X2[9:0] && !DRAW_Y[11:10] && DRAW_Y[9:0] >= USR_CLIP.Y1[9:0] && DRAW_Y[9:0] <= USR_CLIP.Y2[9:0];
		MESH = ~(DRAW_X[0] ^ DRAW_Y[0]) ^ (FRAME_ODD&BLUR_MESH);
		IDRAW = ~(DIL ^ DRAW_Y[0]);
		FB_DRAW_D = CALC_C;
		FB_DRAW_WE = (~TP | CMD.CMDPMOD.SPD) & (~EC | CMD.CMDPMOD.ECD) & SCLIP & ((UCLIP^CMD.CMDPMOD.CMOD) | ~CMD.CMDPMOD.CLIP) & (MESH | ~CMD.CMDPMOD.MESH) & (IDRAW | ~DIE);
	end
`ifdef DEBUG
	assign ORIG_C_DBG = ORIG_C;
	assign DBG_ORIG_RGB = ORIG_C[14:0];
	assign DRAW_X_DBG = DRAW_X;
	assign DRAW_Y_DBG = DRAW_Y;
	assign TP_DBG = TP;
	assign SCLIP_DBG = SCLIP;
	assign UCLIP_DBG = UCLIP;
	
	assign DBG_DRAW_OVER = DRAW_X[11:8] == 4'b0011 || DRAW_X[11:8] == 4'b1101 || DRAW_Y[11:8] == 4'b0011 || DRAW_Y[11:8] == 4'b1101;
	assign DBG_SPR_ADDR = SPR_ADDR;
`endif

	//FB out
`ifdef CUT_VDP1_ROT
	// U1: no rotation read-out. It captured VDP2's rotation parameters (VOUTI = VDP2 FBDO) each line and stepped the
	// read coordinates OUT_RX/OUT_RY, used only for TVM1 = 1. VOUTI is unused.
`else
	ScrnStart_t  RP_Xst;
	ScrnStart_t  RP_Yst;
	ScrnInc_t    RP_DXst;
	ScrnInc_t    RP_DYst;
	ScrnInc_t    RP_DX;
	ScrnInc_t    RP_DY;
	RotCoord_t   RXst,RYst;
	RotCoord_t   OUT_RX,OUT_RY;
`endif
	bit  [ 8: 0] OUT_X;
	bit  [ 8: 0] OUT_Y;
	bit          FRAME_ERASE_HIT;
	bit  [ 8: 0] ERASE_X;
	bit  [ 8: 0] ERASE_Y;
	bit          ERASE_HIT;
	bit  [15: 0] HTIM_PIPE;
	always @(posedge CLK or negedge RST_N) begin
`ifndef CUT_VDP1_ROT
		bit          HTIM_N_OLD;
`endif
		bit          VTIM_N_OLD;
`ifndef CUT_VDP1_ROT
		bit  [ 2: 0] RP_POS;
		bit          RP_FIRST;
`endif
		
		if (!RST_N) begin
			OUT_X <= '0;
			OUT_Y <= '0;
		end
		else begin
`ifndef CUT_VDP1_ROT
			HTIM_N_OLD <= HTIM_N;
`endif
			VTIM_N_OLD <= VTIM_N;
			
			if (DCE_R) begin
				HTIM_PIPE <= {HTIM_PIPE[14:0],HTIM_N};
			end
			
`ifndef CUT_VDP1_ROT
			if (DCE_R) begin
				if (RP_POS != 3'd7) RP_POS <= RP_POS + 3'd1;
			end
			if (!HTIM_N && HTIM_N_OLD) begin
				RP_POS <= '0;
			end
			if (VTIM_N && !VTIM_N_OLD) begin
				RP_FIRST <= 1;
			end
			if (HTIM_N && !HTIM_N_OLD) begin
				RP_FIRST <= 0;
			end
			
			if (DCE_F) begin
				case (RP_POS)
					3'd0: RP_Xst[31:16] <= VOUTI;	//0x18C/0x1A8
					3'd1: RP_Yst[31:16] <= VOUTI;	//0x18D/0x1A9
					3'd2: RP_DXst[31:16] <= VOUTI;//0x18E/0x1AA
					3'd3: RP_DYst[31:16] <= VOUTI;//0x18F/0x1AB
					3'd4: RP_DX[31:16] <= VOUTI;	//0x190/0x1AC
					3'd5: RP_DY[31:16] <= VOUTI;	//0x191/0x1AD
				endcase
			end
			if (DCE_R) begin
				case (RP_POS)
					3'd0: RP_Xst[15:0] <= VOUTI;
					3'd1: RP_Yst[15:0] <= VOUTI;
					3'd2: RP_DXst[15:0] <= VOUTI;
					3'd3: RP_DYst[15:0] <= VOUTI;
					3'd4: RP_DX[15:0] <= VOUTI;
					3'd5: RP_DY[15:0] <= VOUTI;
					3'd6: begin
						RXst <= $signed(RXst) + $signed(ScrnIncToRC(RP_DXst));
						RYst <= $signed(RYst) + $signed(ScrnIncToRC(RP_DYst));
						if (RP_FIRST) begin
							RXst <= ScrnStartToRC(RP_Xst);
							RYst <= ScrnStartToRC(RP_Yst);
						end
					end
				endcase
			end
			
			if (DCE_R) begin
				OUT_RX <= $signed(OUT_RX) + $signed(ScrnIncToRC(RP_DX));
				OUT_RY <= $signed(OUT_RY) + $signed(ScrnIncToRC(RP_DY));
				if (HTIM_PIPE[8:7] == 2'b01) begin
					OUT_RX <= $signed(RXst);
					OUT_RY <= $signed(RYst);
				end
			end
`endif
			
			if (VTIM_N && DCE_R) begin
				if (HTIM_PIPE[8:7] == 2'b01) begin
					OUT_X <= '0;
					OUT_Y <= OUT_Y + 9'd1;
				end
				else if (OUT_X < 9'd352 + 8) begin
					OUT_X <= OUT_X + 9'd1;
				end
			end
			
			if ((HTIM_N || |HTIM_PIPE) && VBLANK_ERASE && CE_R) begin
				OUT_X <= OUT_X + 9'd1;
				if ({1'b0,OUT_X} + 10'd1 == (!EWRR.X3[9] ? {EWRR.X3,3'b000} : 10'h200)) begin
					OUT_X <= {EWLR.X1,3'b000};
					OUT_Y <= OUT_Y + 9'd1;
				end
			end
			if (!VTIM_N && VTIM_N_OLD) begin
				OUT_X <= {EWLR.X1,3'b000};
				OUT_Y <= EWLR.Y1;
			end
			if (VTIM_N && !VTIM_N_OLD) begin
				OUT_Y <= '1;
			end
			if (CE_F) begin
				ERASE_HIT <= (OUT_X >= {EWLR.X1,3'b000}) && ({1'b0,OUT_X} < {EWRR.X3,3'b000}) && (OUT_Y >= EWLR.Y1) && (OUT_Y <= EWRR.Y3);
			end
		end
	end
	
	assign FRAME_ERASE_EN = ERASE_HIT && FRAME_ERASE && VTIM_N;
	assign VBLANK_ERASE_EN = ERASE_HIT && VBLANK_ERASE && (HTIM_N || |HTIM_PIPE);
	
	assign FB_ERASE_A = {OUT_Y[7:0],OUT_X[8:0]};
`ifdef CUT_VDP1_ROT
	// U1: always read in display order; 8-bit (TVM0) or 16-bit, as for TVM1 = 0
	assign FB_DISP_A = {     OUT_Y[7:0],     OUT_X[8:0]};
`else
	assign FB_DISP_A = TVMR.TVM[1:0] == 2'b10 ? {OUT_RY.INT[7:0],OUT_RX.INT[8:0]} : 
	                   TVMR.TVM[1:0] == 2'b11 ? {OUT_RY.INT[8:0],OUT_RX.INT[8:1]} : 
							                          {     OUT_Y[7:0],     OUT_X[8:0]};
`endif
	bit DCLK;
	always @(posedge CLK) begin
		if      (DCE_R) DCLK <= 1;
		else if (DCE_F) DCLK <= 0;
		
`ifdef CUT_VDP1_ROT
		VOUTO <= TVMR.TVM[0] ? (DCLK ? {8'hFF,FB_DISP_Q[15:8]} : {8'hFF,FB_DISP_Q[7:0]}) :
					FB_DISP_Q;
`else
		VOUTO <= TVMR.TVM[1:0] == 2'b01 ? (DCLK ? {8'hFF,FB_DISP_Q[15:8]} : {8'hFF,FB_DISP_Q[7:0]}) :
	            TVMR.TVM[1:0] == 2'b10 ? (OUT_RX.INT[10:9] || OUT_RY.INT[10:8] ? 16'h0000 : FB_DISP_Q) :
					TVMR.TVM[1:0] == 2'b11 ? (OUT_RX.INT[10:9] || OUT_RY.INT[10:9] ? 16'h0000 : !OUT_X[0] ? {8'h00,FB_DISP_Q[15:8]} : {8'h00,FB_DISP_Q[7:0]}) :
					FB_DISP_Q;
`endif
	end
	
	//VRAM
	typedef enum bit [3:0] {
		VS_IDLE,  
		VS_RAS0,VS_RAS1,VS_RAS2,
		VS_CPU_WRITE,
		VS_CPU_READ,
		VS_CMD_READ,
		VS_PAT_READ,
		VS_CLT_READ,
		VS_GRD_READ
	} VRAMState_t;
	VRAMState_t VRAM_ST;
	
	typedef enum bit [2:0] {
		FS_IDLE,  
		FS_CPU_WRITE,
		FS_CPU_WAIT,
		FS_CPU_READ,
		FS_DRAW
	} FBState_t;
	FBState_t FB_ST;
		
	wire CPU_VRAM_REQ = (A[20:19] == 2'b00) & ~AD_N & ~CS_N & ~REQ_N;	//000000-07FFFF
	wire CPU_FB_REQ = (A[20:19] == 2'b01) & ~AD_N & ~CS_N & ~REQ_N;	//080000-0FFFFF
	
	bit  [20: 1] A;
	bit          WE_N;
	bit  [ 1: 0] DQM;
	bit          BURST;
	bit          READY;
	bit          VRAM_SEL,FBRAM_SEL,REG_SEL;
	
	bit          CPU_VRAM_RRDY;
	bit          CPU_FB_RRDY;
	bit          CPU_VRAM_WRDY;
	bit          CPU_FB_WRDY;
	bit          CPU_FB_RPEND;
	bit          CPU_FB_WPEND;
	
	wire [15: 0] PAT_FIFO_D = GetSprData(VRAM_Q, CMD.CMDPMOD.CM, PAT_CNT[1:0] ^ {2{CMD.CMDCTRL.DIR[0]}} ^ {2{DIR[0]}});
	wire         PAT_FIFO_WRREQ = VRAM_ST == VS_PAT_READ && !PAT_PREREAD && VRAM_RDY;
	wire         PAT_FIFO_RDREQ = PAT_NEXT && SPR_DATA_READY;
	bit  [15: 0] PAT_FIFO_Q;
	bit          PAT_FIFO_EMPTY;
	bit          PAT_FIFO_FULL;
	wire         PAT_FIFO_RST = !SPR_READ;
	VDP1_PAT_FIFO PAT_FIFO(CLK, PAT_FIFO_RST, PAT_FIFO_D, PAT_FIFO_WRREQ, PAT_FIFO_RDREQ, PAT_FIFO_Q, PAT_FIFO_EMPTY, PAT_FIFO_FULL);
	
	assign SPR_DATA = PAT_FIFO_Q;
	assign SPR_DATA_READY = !PAT_FIFO_EMPTY || PAT_CNT >= ORIG_WIDTH;
	
	bit  [15: 0] MEM_DO;
	bit  [ 8: 0] PAT_CNT;
	bit          PAT_PREREAD;
	
	//Pattern read address with one adder: PAT_P / PAT_W are the pattern counter and the width in VRAM words for the
	//color mode (PAT_W is also the burst length). A mirrored row reads at W - P - 1, a 10-bit signed value
	//sign-extended to 18 bits: the value the 18-bit expressions per color mode gave.
	wire [ 8: 0] PAT_P = CMD.CMDPMOD.CM <= 3'b001 ? {2'b00,PAT_CNT[8:2]} : CMD.CMDPMOD.CM <= 3'b100 ? {1'b0,PAT_CNT[8:1]} : PAT_CNT[8:0];
	wire [ 8: 0] PAT_W = CMD.CMDPMOD.CM <= 3'b001 ? {2'b00,ORIG_WIDTH[8:2]} : CMD.CMDPMOD.CM <= 3'b100 ? {1'b0,ORIG_WIDTH[8:1]} : ORIG_WIDTH[8:0];
	wire [ 9: 0] PAT_RDIFF = {1'b0,PAT_W} + {1'b1,~PAT_P};
	//(the first read of a row, PAT_PREREAD, is at SPR_ADDR itself: offset 0)
	wire [18: 1] PAT_ADDR = SPR_ADDR + (PAT_PREREAD ? 18'd0 : !TEXT_DIRX ? {9'b000000000,PAT_P} : {{8{PAT_RDIFF[9]}},PAT_RDIFF});
	bit  [ 3: 0] VRAM_READ_POS;
	bit          CPU_VRAM_RPEND;
	bit          CPU_VRAM_WPEND;
	bit          CPU_VRAM_ACCESS;
	always @(posedge CLK or negedge RST_N) begin
		bit         CS_N_OLD;
		bit         READY2,READY3;
//		bit         VRAM_PAGE_BREAK;
		bit [18: 1] CPU_RA;
		bit [18: 1] CPU_WA,CPU_FB_WA;
		bit [15: 0] CPU_D,CPU_FB_D;
		bit [ 1: 0] CPU_WE,CPU_FB_WE;
		bit [18: 1] SAVE_WA,SAVE_FB_WA;
		bit [15: 0] SAVE_D,SAVE_FB_D;
		bit [ 1: 0] SAVE_WE,SAVE_FB_WE;
		bit         CMD_READ_PEND;
		bit         CLT_READ_PEND;
		bit         GRD_READ_PEND;
		bit [ 8: 0] FB_Y;
		bit         VRAM_FIFO_FULL,FB_FIFO_FULL,VRAM_FIFO_EMPTY,FB_FIFO_EMPTY;
		bit [ 4: 0] CPU_ACCESS_WAIT,DRAW_ACCESS_WAIT;
		bit [ 1: 0] CPU_VRAM_WDELAY;
		
		if (!RST_N) begin
			VRAM_ST <= VS_IDLE;
			VRAM_A <= '0;
			VRAM_D <= '0;
			VRAM_WE <= '0;
			VRAM_RD <= 0;
			FB_ST <= FS_IDLE;
			FB_A <= '0;
			FB_D <= '0;
			FB_WE <= '0;
			FB_RD <= 0;
			{CMD_READ_PEND,CLT_READ_PEND,GRD_READ_PEND} <= 0;
			
			A <= '0;
			WE_N <= 1;
			DQM <= '1;
			BURST <= 0;
			READY <= 1;
			{CPU_VRAM_RPEND,CPU_VRAM_WPEND} <= '0;
			{CPU_VRAM_RRDY,CPU_VRAM_WRDY} <= '1;
			{CPU_FB_RPEND,CPU_FB_WPEND} <= '0;
			{CPU_FB_RRDY,CPU_FB_WRDY} <= '1;
			{VRAM_FIFO_FULL,FB_FIFO_FULL,VRAM_FIFO_EMPTY,FB_FIFO_EMPTY} <= '0;
			
			CPU_ACCESS_WAIT <= '0;
			DRAW_ACCESS_WAIT <= '0;
		end 
		else begin
			CS_N_OLD <= CS_N;
			if (CE_F) begin				
				READY2 <= 1;
				if (VRAM_FIFO_EMPTY && FB_FIFO_EMPTY) begin
					READY3 <= READY2; 
					READY <= READY2 & READY3;	
				end	
			end		
			if (!CS_N && CS_N_OLD) begin
				READY <= 0;
				READY2 <= 0;
				READY3 <= 0;
			end
			
			if (CE_R) begin
				if (!CS_N && DTEN_N && AD_N) begin
					if (!DI[15]) begin
						A[20:9] <= DI[11:0];
						WE_N <= DI[14];
						BURST <= DI[13];
						VRAM_SEL <= (DI[11:10] == 2'b00);
						FBRAM_SEL <= (DI[11:10] == 2'b01);
						REG_SEL <= DI[11];
					end else begin
						A[8:1] <= DI[7:0];
						DQM <= DI[13:12];
					end
				end
			end
			if (CS_N && !CS_N_OLD) begin
				BURST <= 0;
				VRAM_SEL <= 0;
				FBRAM_SEL <= 0;
				REG_SEL <= 0;
			end
			
			if (CMD_READ && !CMD_READ_PEND) begin CMD_READ_PEND <= 1; VRAM_READ_POS <= '0; end
			if (CLT_READ && !CLT_READ_PEND) begin CLT_READ_PEND <= 1; VRAM_READ_POS <= '0; end
			if (GRD_READ && !GRD_READ_PEND) begin GRD_READ_PEND <= 1; VRAM_READ_POS <= '0; end

			if (!SPR_READ) begin PAT_CNT <= {8'b00000000,HSS_EN&(FBCR.EOS^TEXT_DIRX)}; PAT_PREREAD <= 1; end
			
			if ((CPU_VRAM_REQ || CPU_FB_REQ) && WE_N && DTEN_N) begin 
				CPU_RA <= A[18:1];
				if (CPU_VRAM_REQ) begin
					CPU_VRAM_RPEND <= 1;
					CPU_VRAM_RRDY <= 0;
				end 
				if (CPU_FB_REQ) begin
					CPU_FB_RPEND <= 1;
					CPU_FB_RRDY <= 0;
				end
				A <= A + 20'd1;
			end
			
			if (CPU_VRAM_WDELAY && CE_F) CPU_VRAM_WDELAY <= CPU_VRAM_WDELAY - 2'd1;
			if (CPU_VRAM_REQ && !WE_N && !DTEN_N) begin
				if (!CPU_VRAM_WPEND) begin
					CPU_WA <= A[18:1];
					CPU_D <= DI;
					CPU_WE <= ~{2{WE_N}} & ~DQM;
					CPU_VRAM_WPEND <= 1;
					VRAM_FIFO_EMPTY <= 0;
				end else begin
					SAVE_WA <= A[18:1];
					SAVE_D <= DI;
					SAVE_WE <= ~{2{WE_N}} & ~DQM;
					CPU_VRAM_WRDY <= 0;
					VRAM_FIFO_FULL <= 1;
				end
				if (!BURST) CPU_VRAM_WDELAY <= 2'd3;
				A <= A + 20'd1;
			end
			if (!CPU_VRAM_WRDY && !CPU_VRAM_WPEND) begin
				CPU_WA <= SAVE_WA;
				CPU_D <= SAVE_D;
				CPU_WE <= SAVE_WE;
				CPU_VRAM_WPEND <= 1;
				CPU_VRAM_WRDY <= 1;
				VRAM_FIFO_EMPTY <= 0;
				VRAM_FIFO_FULL <= 0;
			end
			if (CPU_VRAM_WRDY && !CPU_VRAM_WPEND && !VRAM_FIFO_EMPTY) begin
				VRAM_FIFO_EMPTY <= 1;
			end
			
			if (CPU_FB_REQ && !WE_N && !DTEN_N) begin
				if (CPU_FB_REQ && !CPU_FB_WPEND) begin
					CPU_FB_WA <= A[18:1];
					CPU_FB_D <= DI;
					CPU_FB_WE <= ~{2{WE_N}} & ~DQM;
					CPU_FB_WPEND <= 1;
					FB_FIFO_EMPTY <= 0;
				end else begin
					SAVE_FB_WA <= A[18:1];
					SAVE_FB_D <= DI;
					SAVE_FB_WE <= ~{2{WE_N}} & ~DQM;
					CPU_FB_WRDY <= 0;
					FB_FIFO_FULL <= 1;
				end
				A <= A + 20'd1;
			end
			if (!CPU_FB_WRDY && !CPU_FB_WPEND) begin
				CPU_FB_WA <= SAVE_FB_WA;
				CPU_FB_D <= SAVE_FB_D;
				CPU_FB_WE <= SAVE_FB_WE;
				CPU_FB_WPEND <= 1;
				CPU_FB_WRDY <= 1;
				FB_FIFO_EMPTY <= 0;
				FB_FIFO_FULL <= 0;
			end
			if (CPU_FB_WRDY && !CPU_FB_WPEND && !FB_FIFO_EMPTY) begin
				FB_FIFO_EMPTY <= 1;
			end
			
			if (CPU_ACCESS_WAIT && CE_R) CPU_ACCESS_WAIT <= CPU_ACCESS_WAIT - 5'd1;
			if (DRAW_ACCESS_WAIT && CE_R) DRAW_ACCESS_WAIT <= DRAW_ACCESS_WAIT - 5'd1;
			case (VRAM_ST)
				VS_IDLE: if (VRAM_RDY) begin
					CPU_VRAM_ACCESS <= 0;
					if (CPU_VRAM_WPEND && !CPU_VRAM_WDELAY) begin
						CPU_VRAM_ACCESS <= 1;
						if (!CPU_ACCESS_WAIT) begin
							VRAM_A <= CPU_WA;
							if (VRAM_A[18:9] != CPU_WA[18:9]) begin
								VRAM_ST <= VS_RAS0;
							end else begin
								VRAM_D <= CPU_D;
								VRAM_WE <= CPU_WE;
								VRAM_RD <= 0;
								VRAM_BLEN <= '0;
								CPU_VRAM_WPEND <= 0;
								VRAM_ST <= VS_CPU_WRITE;
							end
						end
					end else if (CPU_VRAM_RPEND) begin
						CPU_VRAM_ACCESS <= 1;
						if (!CPU_ACCESS_WAIT) begin
							VRAM_A <= CPU_RA;
							VRAM_WE <= '0;
							VRAM_RD <= 1;
							VRAM_BLEN <= '0;
							CPU_VRAM_RPEND <= 0;
							VRAM_ST <= VS_CPU_READ;
						end
					end else if (DRAW_ACCESS_WAIT && !BURST) begin
						CPU_VRAM_ACCESS <= 1;
//					end else if (VRAM_PAGE_BREAK) begin
//						VRAM_ST <= VS_RAS;
					end else if (CMD_READ_PEND && !FRAME_START && !BURST && !VRAM_SEL) begin
						if (VRAM_READ_POS == 4'd15) CMD_READ_PEND <= 0;
						//CMD_ADDR[4:1] is always 0 (it is only ever loaded with 0, CMD_ADDR + 'h10, {CMDLINK[15:2],4'b0000} or the
						//return address, itself CMD_ADDR + 'h10; power-up 0), so the old CMD_ADDR + VRAM_READ_POS is this
						VRAM_A <= {CMD_ADDR[18:5],VRAM_READ_POS};
						VRAM_WE <= '0;
						VRAM_RD <= 1;
						VRAM_BLEN <= '0;
						VRAM_ST <= VS_CMD_READ;
					end else if (SPR_READ && !PAT_FIFO_FULL && PAT_CNT < ORIG_WIDTH && !FRAME_START && !BURST && !VRAM_SEL) begin
						VRAM_A <= PAT_ADDR;
						VRAM_BLEN <= PAT_PREREAD ? PAT_W : 9'd0;
						VRAM_WE <= '0;
						VRAM_RD <= 1;
						VRAM_ST <= VS_PAT_READ;
					end else if (CLT_READ_PEND && !FRAME_START && !BURST && !VRAM_SEL) begin
						if (VRAM_READ_POS == 4'd15) CLT_READ_PEND <= 0;
						VRAM_A <= {CLT_ADDR[18:5],VRAM_READ_POS};	//CLT_ADDR[4:1] = 0
						VRAM_WE <= '0;
						VRAM_RD <= 1;
						VRAM_BLEN <= '0;
						VRAM_ST <= VS_CLT_READ;
					end else if (GRD_READ_PEND && !FRAME_START && !BURST && !VRAM_SEL) begin
						if (VRAM_READ_POS == 4'd3) GRD_READ_PEND <= 0;
						//GRD_ADDR[2:1] = 0, and VRAM_READ_POS <= 3 for every gouraud table read: GRD_READ_PEND is only set
						//together with VRAM_READ_POS <= 0 (no read can complete on that clock: the command read before it
						//has finished, and nothing else is pending), and is cleared when the read at position 3 is issued
						VRAM_A <= {GRD_ADDR[18:3],VRAM_READ_POS[1:0]};
						VRAM_WE <= '0;
						VRAM_RD <= 1;
						VRAM_BLEN <= '0;
						VRAM_ST <= VS_GRD_READ;
					end
				end
				
				VS_RAS0: if (CE_F) begin
					VRAM_ST <= VS_RAS1;
				end
				
				VS_RAS1: if (CE_F) begin
					VRAM_ST <= VS_RAS2;
				end
				
				VS_RAS2: if (CE_F) begin
					VRAM_ST <= VS_IDLE;
				end
				
				VS_CPU_WRITE: begin
					VRAM_WE <= '0;
//					VRAM_PAGE_BREAK <= 1;
					DRAW_ACCESS_WAIT <= FAST ? 5'd5 : 5'd13;
					if (!VRAM_FIFO_FULL && !BURST) CPU_ACCESS_WAIT <= 5'd10;
					VRAM_ST <= VS_IDLE;
				end
				
				VS_CPU_READ: begin
					if (VRAM_RDY && CE_R) begin
						MEM_DO <= VRAM_Q;
						VRAM_RD <= 0;
//						VRAM_PAGE_BREAK <= 1;
						DRAW_ACCESS_WAIT <= FAST ? 5'd5 : 5'd13;
						CPU_VRAM_RRDY <= 1;
						VRAM_ST <= VS_IDLE;
					end
				end
					
				VS_CMD_READ: begin
					VRAM_RD <= 0;
					if (FRAME_START) begin
						VRAM_WE <= '0;
						VRAM_RD <= 0;
						VRAM_ST <= VS_IDLE;
					end else if (VRAM_RDY) begin
						VRAM_READ_POS <= VRAM_READ_POS + 4'd1;
						CPU_ACCESS_WAIT <= 5'd10;
						VRAM_ST <= VS_IDLE;
					end
				end
				
				VS_CLT_READ: begin
					VRAM_RD <= 0;
					if (FRAME_START) begin
						VRAM_RD <= 0;
						VRAM_ST <= VS_IDLE;
					end else if (VRAM_RDY) begin
						VRAM_READ_POS <= VRAM_READ_POS + 4'd1;
						CPU_ACCESS_WAIT <= 5'd10;
						VRAM_ST <= VS_IDLE;
					end
				end
				
				VS_PAT_READ: begin
					VRAM_RD <= 0;
					if (FRAME_START || !SPR_READ) begin
						VRAM_WE <= '0;
						VRAM_RD <= 0;
						VRAM_ST <= VS_IDLE;
					end else if (VRAM_RDY) begin
						if (!PAT_PREREAD) begin
							PAT_CNT <= PAT_CNT + (HSS_EN ? 9'd2 : 9'd1);
							CPU_ACCESS_WAIT <= 5'd10;
						end
						PAT_PREREAD <= 0;
						VRAM_ST <= VS_IDLE;
					end
				end
				
				VS_GRD_READ: begin
					VRAM_RD <= 0;
					if (FRAME_START) begin
						VRAM_RD <= 0;
						VRAM_ST <= VS_IDLE;
					end else if (VRAM_RDY) begin
						VRAM_READ_POS <= VRAM_READ_POS + 4'd1;
						CPU_ACCESS_WAIT <= 5'd10;
						VRAM_ST <= VS_IDLE;
					end
				end
			endcase
			
			if (FRAME_START) begin
				CMD_READ_PEND <= 0;
				CLT_READ_PEND <= 0;
				GRD_READ_PEND <= 0;
			end
			
			case (FB_ST)
				FS_IDLE: begin
					if (CPU_FB_WPEND && !FB_WE) begin
						if (FB_RDY) begin
							FB_A <= CPU_FB_WA[17:1];
							FB_D <= CPU_FB_D;
							FB_WE <= CPU_FB_WE;
							CPU_FB_WPEND <= 0;
							FB_ST <= FS_CPU_WRITE;
						end
					end else if (CPU_FB_RPEND && !FB_RD) begin
						if (FB_RDY) begin
							FB_A <= CPU_RA[17:1];
							FB_RD <= 1;
							CPU_FB_RPEND <= 0;
							FB_ST <= FS_CPU_WAIT;
						end
					end
`ifdef VDP1_FB_EXT
					else if (((FB_READ_PEND && !FB_RD) || (FB_DRAW_PEND && !FB_WE)) && FB_DRAW_WE && !(FBRAM_SEL && BURST) && FB_RDY) begin
`else
					else if (((FB_READ_PEND && !FB_RD) || (FB_DRAW_PEND && !FB_WE)) && FB_DRAW_WE && !(FBRAM_SEL && BURST)) begin
`endif
						FB_Y = !DIE ? DRAW_Y[8:0] : DRAW_Y[9:1];
`ifdef CUT_VDP1_ROT
						casex ({1'b0,TVMR.TVM[0]})	//U1: TVM1 treated as 0 (no 8-bit rotation layout)
`else
						casex (TVMR.TVM[1:0]) 
`endif
							2'bx0: begin
								FB_A <= {FB_Y[7:0],DRAW_X[8:0]};
								FB_D <= FB_DRAW_D | {CMD.CMDPMOD.MON,15'h0000};
								FB_WE <= {2{FB_DRAW_PEND}};
								FB_RD <= FB_READ_PEND;
							end
							2'b01: begin
								FB_A <= {FB_Y[7:0],DRAW_X[9:1]};
								FB_D <= {FB_DRAW_D[7:0],FB_DRAW_D[7:0]} | {CMD.CMDPMOD.MON,15'h0000};
								FB_WE <= ({~DRAW_X[0],DRAW_X[0]} | {2{CMD.CMDPMOD.MON}}) & {2{FB_DRAW_PEND}};
								FB_RD <= FB_READ_PEND;
							end
`ifndef CUT_VDP1_ROT
							2'b11: begin
								FB_A <= {FB_Y[8:0],DRAW_X[8:1]};
								FB_D <= {FB_DRAW_D[7:0],FB_DRAW_D[7:0]} | {CMD.CMDPMOD.MON,15'h0000};
								FB_WE <= ({~DRAW_X[0],DRAW_X[0]} | {2{CMD.CMDPMOD.MON}}) & {2{FB_DRAW_PEND}};
								FB_RD <= FB_READ_PEND;
							end
`endif
						endcase
						FB_ST <= FS_DRAW;
					end
				end
				
				FS_CPU_WRITE: begin
					FB_WE <= '0;
					FB_ST <= FS_IDLE;
				end
				
				FS_CPU_WAIT: begin
					if (FB_RDY && CE_F) begin
						CPU_FB_RRDY <= 1;
						FB_ST <= FS_CPU_READ;
					end
				end
				
				FS_CPU_READ: begin
					FB_RD <= 0;
					FB_ST <= FS_IDLE;
				end
				
				FS_DRAW: begin
					FB_WE <= '0;
					FB_RD <= 0;
					FB_ST <= FS_IDLE;
				end
			endcase
		end
	end
	assign CPU_VRAM_BUSY = VRAM_SEL || CPU_VRAM_RPEND || CPU_VRAM_WPEND || CPU_VRAM_ACCESS;
`ifdef VDP1_FB_EXT
	// the pixel engine also waits while the off-chip frame buffer cannot take a request (FS_IDLE issues none then)
	assign FB_DRAW_WAIT = (FB_ST != FS_IDLE) || CPU_FB_WPEND || CPU_FB_RPEND || !FB_RDY;
`else
	assign FB_DRAW_WAIT = (FB_ST != FS_IDLE) || CPU_FB_WPEND || CPU_FB_RPEND;
`endif
	wire PAT_PREREAD_WAIT = (VRAM_ST == VS_PAT_READ) && PAT_PREREAD && !VRAM_RDY;
	
	bit [ 3: 0] CMD_POS;
	bit [15: 0] CMD_DAT;
	bit         CMD_WE,CLT_WE,GRD_WE;
	
	//Vertex arithmetic of the command read, shared between X (positions 6 / 8) and Y (7 / 9): CMD_POS[0] picks the
	//axis. VTEMP: corner of a normal sprite (D + W - 1 / D + H - 1). VPLUS / VMINUS: scaled sprite zoom points, the
	//A + D or A + (D+1)/2 and A - D or A - D/2 that the position computes (only one of each per position).
	wire [12: 0] VD     = CMD_DAT[12:0];
	wire [12: 0] VBASE  = CMD_POS[0] ? VERTA.Y : VERTA.X;
	wire [ 1: 0] VZP    = CMD_POS[0] ? CMD.CMDCTRL.ZP[3:2] : CMD.CMDCTRL.ZP[1:0];
	wire [12: 0] VTEMP  = VD + (CMD_POS[0] ? {5'b00000,ORIG_HEIGHT} : {4'b0000,ORIG_WIDTH}) - 13'd1;
	//SDiv2(D + 1) without its own incrementer: (D >>> 1) + D[0], except D = 'h0FFF where D + 1 wraps to -4096 and
	//the original gives 'h1800 (bit 12 set): that case flips bit 12 of the operand.
	wire         VD_MAXP = (VD == 13'h0FFF);
	wire [12: 0] VPLUS  = VBASE + (VZP == 2'b10 ? {VD[12] ^ VD_MAXP,VD[12:1]} : VD) + {12'd0,VZP == 2'b10 && VD[0]};
	wire [12: 0] VMINUS = VBASE - (VZP == 2'b10 ? SDiv2(VD) : VD);
	//Vertex loads of the command read, by position (6-D), command (0: normal, 1: scaled, 2-7: distorted / polygon /
	//line) and zoom point, as the per-position case statements had them:
	//  6/7: normal: A = D, B.x = D, C.x / D.y = W/H corner, D.x = D, B.y = D;   scaled: all four = D;   2-7: A = D
	//  8/9: scaled: zoom 01: B.x C.x / C.y D.y = A + D; 10: A.x D.x / A.y B.y = A - D/2 and B.x C.x / C.y D.y =
	//       A + (D+1)/2; 11: A.x D.x / A.y B.y = A - D;   2-7: B = D
	//  A/B: scaled with zoom 00: B.x C.x / C.y D.y = D;   2-7: C = D
	//  C/D: 2-7: D = D
	wire         VC_N  = CMD.CMDCTRL.COMM == 4'h0;
	wire         VC_S  = CMD.CMDCTRL.COMM == 4'h1;
	wire         VC_Q  = CMD.CMDCTRL.COMM >= 4'h2 && CMD.CMDCTRL.COMM <= 4'h7;
	wire [ 1: 0] VZX = CMD.CMDCTRL.ZP[1:0];
	wire [ 1: 0] VZY = CMD.CMDCTRL.ZP[3:2];
	wire         VW_AX = (CMD_POS == 4'h6 && (VC_N || VC_S || VC_Q)) || (CMD_POS == 4'h8 && VC_S && VZX[1]);
	wire         VW_AY = (CMD_POS == 4'h7 && (VC_N || VC_S || VC_Q)) || (CMD_POS == 4'h9 && VC_S && VZY[1]);
	wire         VW_BX = (CMD_POS == 4'h6 && (VC_N || VC_S)) || (CMD_POS == 4'h8 && VC_S && (VZX == 2'b01 || VZX == 2'b10)) ||
	                     (CMD_POS == 4'h8 && VC_Q) || (CMD_POS == 4'hA && VC_S && VZX == 2'b00);
	wire         VW_BY = (CMD_POS == 4'h7 && (VC_N || VC_S)) || (CMD_POS == 4'h9 && VC_S && VZY[1]) || (CMD_POS == 4'h9 && VC_Q);
	wire         VW_CX = (CMD_POS == 4'h6 && (VC_N || VC_S)) || (CMD_POS == 4'h8 && VC_S && (VZX == 2'b01 || VZX == 2'b10)) ||
	                     (CMD_POS == 4'hA && VC_S && VZX == 2'b00) || (CMD_POS == 4'hA && VC_Q);
	wire         VW_CY = (CMD_POS == 4'h7 && (VC_N || VC_S)) || (CMD_POS == 4'h9 && VC_S && (VZY == 2'b01 || VZY == 2'b10)) ||
	                     (CMD_POS == 4'hB && VC_S && VZY == 2'b00) || (CMD_POS == 4'hB && VC_Q);
	wire         VW_DX = (CMD_POS == 4'h6 && (VC_N || VC_S)) || (CMD_POS == 4'h8 && VC_S && VZX[1]) || (CMD_POS == 4'hC && VC_Q);
	wire         VW_DY = (CMD_POS == 4'h7 && (VC_N || VC_S)) || (CMD_POS == 4'h9 && VC_S && (VZY == 2'b01 || VZY == 2'b10)) ||
	                     (CMD_POS == 4'hB && VC_S && VZY == 2'b00) || (CMD_POS == 4'hD && VC_Q);
	wire [12: 0] VL_AX   = CMD_POS == 4'h8 ? VMINUS : VD;
	wire [12: 0] VL_AY   = CMD_POS == 4'h9 ? VMINUS : VD;
	wire [12: 0] VL_BXCX = CMD_POS == 4'h6 && VC_N ? VTEMP : CMD_POS == 4'h8 && VC_S ? VPLUS : VD;
	wire [12: 0] VL_BY   = CMD_POS == 4'h9 && VC_S ? VMINUS : VD;
	wire [12: 0] VL_CYDY = CMD_POS == 4'h7 && VC_N ? VTEMP : CMD_POS == 4'h9 && VC_S ? VPLUS : VD;
	wire [12: 0] VL_DX   = CMD_POS == 4'h8 && VC_S ? VMINUS : VD;
	always @(posedge CLK or negedge RST_N) begin
		bit         CMD_WE,GRD_WE;
		
		if (!RST_N) begin
			CMD_WE <= 0;
			CLT_WE <= 0;
			GRD_WE <= 0;
			SYS_CLIP <= CLIP_NULL;
			USR_CLIP <= CLIP_NULL;
			LOC_COORD <= COORD_NULL;
		end else begin
			CMD_DAT <= VRAM_Q;
			CMD_POS <= VRAM_READ_POS;
			CMD_WE <= (VRAM_ST == VS_CMD_READ && VRAM_RDY);
			if (CMD_WE) begin
				case (CMD_POS)
					4'h0: CMD.CMDCTRL <= CMD_DAT;
					4'h1: CMD.CMDLINK <= CMD_DAT;
					4'h2: CMD.CMDPMOD <= CMD_DAT;
					4'h3: CMD.CMDCOLR <= CMD_DAT;
					4'h4: CMD.CMDSRCA <= CMD_DAT;
//					4'h5: CMD.CMDSIZE <= CMD_DAT;
//					4'h6: CMD.CMDXA <= CMD_DAT;
//					4'h7: CMD.CMDYA <= CMD_DAT;
//					4'h8: CMD.CMDXB <= CMD_DAT;
//					4'h9: CMD.CMDYB <= CMD_DAT;
//					4'hA: CMD.CMDXC <= CMD_DAT;
//					4'hB: CMD.CMDYC <= CMD_DAT;
//					4'hC: CMD.CMDXD <= CMD_DAT;
//					4'hD: CMD.CMDYD <= CMD_DAT;
					4'hE: CMD.CMDGRDA <= CMD_DAT;
				endcase
				
				
				case (CMD_POS)
					4'h5: begin
						ORIG_WIDTH <= {CMD_DAT[13:8],3'b000} | ~|CMD_DAT[13:8];
						ORIG_HEIGHT <= CMD_DAT[7:0] | ~|CMD_DAT[7:0];
					end
					4'h6: begin
						case (CMD.CMDCTRL.COMM)
							4'h8,
							4'hB: USR_CLIP.X1 <= {1'b0,CMD_DAT[9:0]};
							4'hA: LOC_COORD.X <= CMD_DAT[11:0];
						endcase
					end
					4'h7: begin
						case (CMD.CMDCTRL.COMM)
							4'h8,
							4'hB: USR_CLIP.Y1 <= {1'b0,CMD_DAT[9:0]};
							4'hA: LOC_COORD.Y <= CMD_DAT[11:0];
						endcase
					end
					4'hA: begin
						case (CMD.CMDCTRL.COMM)
							4'h8,
							4'hB: USR_CLIP.X2 <= {1'b0,CMD_DAT[9:0]};
							4'h9: begin
								SYS_CLIP.X2 <= {1'b0,CMD_DAT[9:0]};
								USR_CLIP.X2 <= {1'b0,CMD_DAT[9:0]};
							end
						endcase
					end
					4'hB: begin
						case (CMD.CMDCTRL.COMM)
							4'h8,
							4'hB: USR_CLIP.Y2 <= {1'b0,CMD_DAT[9:0]};
							4'h9: begin
								SYS_CLIP.Y2 <= {1'b0,CMD_DAT[9:0]};
								USR_CLIP.Y2 <= {1'b0,CMD_DAT[9:0]};
							end
						endcase
					end
				endcase
				
				//vertices: each field with its load enable and source (see VW_*), the same loads as the per-position
				//case statements gave
				if (VW_AX) VERTA.X <= VL_AX;
				if (VW_AY) VERTA.Y <= VL_AY;
				if (VW_BX) VERTB.X <= VL_BXCX;
				if (VW_BY) VERTB.Y <= VL_BY;
				if (VW_CX) VERTC.X <= VL_BXCX;
				if (VW_CY) VERTC.Y <= VL_CYDY;
				if (VW_DX) VERTD.X <= VL_DX;
				if (VW_DY) VERTD.Y <= VL_CYDY;
			end
			
			CLT_WE <= (VRAM_ST == VS_CLT_READ) && VRAM_RDY;
			
			GRD_WE <= (VRAM_ST == VS_GRD_READ) && VRAM_RDY;
			if (GRD_WE) begin
				GRD_TBL[CMD_POS[1:0]] <= CMD_DAT;
			end
		end
	end
	assign CMD_READ_DONE = (VRAM_ST == VS_CMD_READ) && VRAM_RDY && (VRAM_READ_POS == 4'd15);
	
	wire [ 3: 0] CLT_RA = DRAW_PAT.C[3:0];
	VDP1_COL_TBL CLT(.CLK(CLK), .WRADDR(CMD_POS), .DATA(CMD_DAT), .WREN(CLT_WE), .RDADDR(CLT_RA), .Q(CLT_Q));
	assign CLT_READ_DONE = (VRAM_ST == VS_CLT_READ) && VRAM_RDY && (VRAM_READ_POS == 4'd15);
	
	assign GRD_READ_DONE = (VRAM_ST == VS_GRD_READ) && VRAM_RDY && (VRAM_READ_POS == 4'd3);

	//Registers
	wire REG_REQ = (A[20:19] == 2'b10) & ~AD_N & ~CS_N & ~REQ_N;
	
	assign MODR = {4'h1,3'b000,PTMR.PTM[1],FBCR.EOS,FBCR.DIE,FBCR.DIL,FBCR.FCM,TVMR.VBE,TVMR.TVM};
	
	bit        VBOUT;
	always @(posedge CLK or negedge RST_N) begin
		bit        VTIM_N_OLD;
		bit        FRAME_CHANGE;
		bit        MANUAL_ERASECHANGE_PEND;
		bit        START_DRAW_PEND;
`ifndef CUT_VDP1_ROT
		bit        VBERASE_PEND;
`endif
		
		if (!RST_N) begin
			TVMR <= '0;
			FBCR <= '0;
			PTMR <= '0;
			EWDR <= 16'h0000;
			EWLR <= 16'h0000;
			EWRR <= 16'h0000;
			EDSR <= '0;
			IRQ_N <= 1;
			
			MANUAL_ERASECHANGE_PEND <= 0;
			FRAME_ERASE <= 0;
			VBLANK_ERASE <= 0;
			DRAW_TERMINATE <= 0;
`ifndef CUT_VDP1_ROT
			VBERASE_PEND <= 0;
`endif
		end else if (!RES_N) begin
			TVMR <= '0;
			FBCR <= '0;
			PTMR <= '0;
			EDSR <= '0;
		end else begin
			START_DRAW_PEND <= 0;
			DRAW_TERMINATE <= 0;
			if (REG_REQ && !WE_N && !DTEN_N) begin
				case ({A[5:1],1'b0})
					5'h00: TVMR <= DI & TVMR_MASK;
					5'h02: FBCR <= DI & FBCR_MASK;
					5'h04: PTMR <= DI & PTMR_MASK;
					5'h06: EWDR <= DI & EWDR_MASK;
					5'h08: EWLR <= DI & EWLR_MASK;
					5'h0A: EWRR <= DI & EWRR_MASK;
					default:;
				endcase
				if (A[5:1] == 5'h02>>1 && DI[1]) MANUAL_ERASECHANGE_PEND <= 1;
				if (A[5:1] == 5'h04>>1 && DI[1:0] == 2'b01) begin 
					START_DRAW_PEND <= 1; 
`ifdef DEBUG
					START_DRAW_CNT <= START_DRAW_CNT + 8'd1; 
`endif
				end
				if (A[5:1] == 5'h0C>>1 && DI[1]) DRAW_TERMINATE <= 1;
			end
			
			if (DRAW_END) begin
				EDSR.CEF <= 1;
			end
			if (CE_R) begin
				IRQ_N <= ~EDSR.CEF;
			end

			FRAME_START <= 0;
			if (START_DRAW_PEND) begin
				FRAME_START <= 1;
				EDSR.CEF <= 0;
				DIE <= FBCR.DIE;
				DIL <= FBCR.DIL;
			end
			if (FRAME_CHANGE) begin
				FRAME_ERASE <= 0;
`ifdef DEBUG
				FRAMES_DBG <= FRAMES_DBG + 8'd1;
`endif
				if (!FBCR.FCM) begin
					FB_SEL <= ~FB_SEL;
`ifdef CUT_VDP1_ROT
					FRAME_ERASE <= 1;	//U1: TVM1 treated as 0 (erase while displaying, never the rotation-mode V-blank erase)
`else
					FRAME_ERASE <= ~TVMR.TVM[1];
					VBERASE_PEND <= TVMR.TVM[1];
`endif
					EDSR.CEF <= 0;
					EDSR.BEF <= EDSR.CEF;
					LOPR <= COPR;
					DIE <= FBCR.DIE;
					DIL <= FBCR.DIL;
					if (PTMR.PTM[1]) begin
						FRAME_START <= 1;
					end
					MANUAL_ERASECHANGE_PEND <= 0;
`ifdef DEBUG
					FRAMES_DBG <= 8'd0;
`endif
				end else if (MANUAL_ERASECHANGE_PEND && FBCR.FCT) begin
					FB_SEL <= ~FB_SEL;
					EDSR.CEF <= 0;
					EDSR.BEF <= EDSR.CEF;
					LOPR <= COPR;
					DIE <= FBCR.DIE;
					DIL <= FBCR.DIL;
					if (PTMR.PTM[1]) begin
						FRAME_START <= 1;
					end
					MANUAL_ERASECHANGE_PEND <= 0;
`ifdef DEBUG
					FRAMES_DBG <= 8'd0;
`endif
				end else if (MANUAL_ERASECHANGE_PEND && !FBCR.FCT) begin
`ifdef CUT_VDP1_ROT
					FRAME_ERASE <= 1;
`else
					FRAME_ERASE <= ~TVMR.TVM[1];
					VBERASE_PEND <= TVMR.TVM[1];
`endif
					MANUAL_ERASECHANGE_PEND <= 0;
				end;
			end
			
			FRAME_CHANGE <= 0;
			if (DCE_R) begin
				VTIM_N_OLD <= VTIM_N;
				
				if (VTIM_N && !VTIM_N_OLD) begin
					VBOUT <= 1;
				end
				if (VTIM_N && HTIM_PIPE[11:10] == 2'b10 && VBOUT) begin
					VBOUT <= 0;
					FRAME_CHANGE <= 1;
				end
				
				if (!VTIM_N && VTIM_N_OLD) begin
					if (TVMR.VBE) begin
						VBLANK_ERASE <= 1;
					end
`ifndef CUT_VDP1_ROT
					if (VBERASE_PEND) begin
						VBLANK_ERASE <= 1;
					end
					VBERASE_PEND <= 0;
`endif
				end
				if (VTIM_N && !VTIM_N_OLD) begin
					VBLANK_ERASE <= 0;
					FRAME_ODD <= ~FRAME_ODD;
				end
			end
		end
	end
	
	bit  [15: 0] REG_DO;
	always_comb begin
		case ({A[5:1],1'b0})
			5'h10: REG_DO <= EDSR & EDSR_MASK;
			5'h12: REG_DO <= LOPR & LOPR_MASK;
			5'h14: REG_DO <= COPR & COPR_MASK;
			5'h16: REG_DO <= MODR & MODR_MASK;
			default: REG_DO <= '0;
		endcase
	end
	assign DO = REG_SEL ? REG_DO : FBRAM_SEL ? FB_DRAW_Q : MEM_DO;
	assign RDY_N = ~CPU_VRAM_RRDY | ~CPU_VRAM_WRDY | ~CPU_FB_RRDY | ~CPU_FB_WRDY | ~READY;
	
endmodule


module VDP1_PAT_FIFO #(parameter l = 1) (
	input	         CLK,
	input          RST,
	
	input	 [15: 0] DATA,
	input	         WRREQ,
	input	         RDREQ,
	output [15: 0] Q,
	output	      EMPTY,
	output	      FULL
);

	wire [15: 0] sub_wire0;
	bit  [l-1: 0] RADDR;
	bit  [l-1: 0] WADDR;
	bit  [l: 0] AMOUNT;
	bit         NULL;
	always @(posedge CLK) begin
		if (RST) begin
			AMOUNT <= '0;
			RADDR <= '0;
			WADDR <= '0;
			NULL <= 1;
		end
		else begin
			if (WRREQ && !AMOUNT[l]) begin
				WADDR <= WADDR + 1'd1;
				NULL <= 0;
			end
			if (RDREQ && AMOUNT) begin
				RADDR <= RADDR + 1'd1;
			end
			
			if (WRREQ && !RDREQ && !AMOUNT[l]) begin
				AMOUNT <= AMOUNT + 1'd1;
			end else if (!WRREQ && RDREQ && AMOUNT) begin
				AMOUNT <= AMOUNT - 1'd1;
			end
		end
	end
	assign EMPTY = ~|AMOUNT;
	assign FULL = AMOUNT[l];
	
	altdpram	altdpram_component (
				.data (DATA),
				.inclock (CLK),
				.rdaddress (RADDR),
				.wraddress (WADDR),
				.wren (WRREQ),
				.q (sub_wire0),
				.aclr (1'b0),
				.byteena (1'b1),
				.inclocken (1'b1),
				.rdaddressstall (1'b0),
				.rden (1'b1),
//				.sclr (1'b0),
				.wraddressstall (1'b0));
	defparam
		altdpram_component.indata_aclr = "OFF",
		altdpram_component.indata_reg = "INCLOCK",
		altdpram_component.intended_device_family = "Cyclone V",
		altdpram_component.lpm_type = "altdpram",
		altdpram_component.outdata_aclr = "OFF",
		altdpram_component.outdata_reg = "UNREGISTERED",
		altdpram_component.ram_block_type = "MLAB",
		altdpram_component.rdaddress_aclr = "OFF",
		altdpram_component.rdaddress_reg = "UNREGISTERED",
		altdpram_component.rdcontrol_aclr = "OFF",
		altdpram_component.rdcontrol_reg = "UNREGISTERED",
		altdpram_component.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
		altdpram_component.width = 16,
		altdpram_component.widthad = l,
		altdpram_component.width_byteena = 1,
		altdpram_component.wraddress_aclr = "OFF",
		altdpram_component.wraddress_reg = "INCLOCK",
		altdpram_component.wrcontrol_aclr = "OFF",
		altdpram_component.wrcontrol_reg = "INCLOCK";
		
	assign Q = NULL ? '0 : sub_wire0;

endmodule

module VDP1_COL_TBL (
	input         CLK,
	input	  [3:0] WRADDR,
	input	 [15:0] DATA,
	input	        WREN,
	input	  [3:0] RDADDR,
	output [15:0] Q
);

	wire [15:0] sub_wire0;

	altdpram	altdpram0 (
				.data (DATA),
				.inclock (CLK),
				.rdaddress (RDADDR[3:0]),
				.wraddress (WRADDR[3:0]),
				.wren (WREN),
				.q (sub_wire0),
				.aclr (1'b0),
				.byteena (1'b1),
				.inclocken (1'b1),
				.rdaddressstall (1'b0),
				.rden (1'b1),
				//.sclr (1'b0),
				.wraddressstall (1'b0));
	defparam
		altdpram0.indata_aclr = "OFF",
		altdpram0.indata_reg = "INCLOCK",
		altdpram0.intended_device_family = "Cyclone V",
		altdpram0.lpm_type = "altdpram",
		altdpram0.outdata_aclr = "OFF",
		altdpram0.outdata_reg = "UNREGISTERED",
		altdpram0.ram_block_type = "MLAB",
		altdpram0.rdaddress_aclr = "OFF",
		altdpram0.rdaddress_reg = "UNREGISTERED",
		altdpram0.rdcontrol_aclr = "OFF",
		altdpram0.rdcontrol_reg = "UNREGISTERED",
		altdpram0.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
		altdpram0.width = 16,
		altdpram0.widthad = 4,
		altdpram0.width_byteena = 1,
		altdpram0.wraddress_aclr = "OFF",
		altdpram0.wraddress_reg = "INCLOCK",
		altdpram0.wrcontrol_aclr = "OFF",
		altdpram0.wrcontrol_reg = "INCLOCK";

	assign Q =  sub_wire0;

endmodule

module VDP1_DIV_24_12 
(
	input         CLK,
	input	 [16:0] DVDNT,
	input	 [11:0] DVSR,
	input	        START,
	output [16:0] QUOT,
	output reg    DONE
);
	
	bit  [28: 0] D;
	bit          T;	
	wire [28: 0] SUM = T ? $signed(D) - $unsigned({DVSR,17'h00000}) : $signed(D) + $unsigned({DVSR,17'h00000});
	always @(posedge CLK) begin
		bit  [ 4: 0] STEP;
	
		if (START) begin
			D <= {12'h000,DVDNT};
			T <= ~(1'b0^DVSR[11]);
			STEP <= '0;
			DONE <= 0;
		end
		else if (!DONE) begin
			D <= {SUM[27:0],~(SUM[28]^DVSR[11])};
			T <= ~(SUM[28]^DVSR[11]);
			STEP <= STEP + 5'd1;
			if (STEP == 5'd17) DONE <= 1;
		end
	end
	assign QUOT = D[16:0];

endmodule

