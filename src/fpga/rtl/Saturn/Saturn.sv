`ifdef CUT_SSH_WDT
`define U3_ANY
`elsif CUT_SSH_FRT_OC
`define U3_ANY
`elsif CUT_SSH_FRT_FICR
`define U3_ANY
`elsif CUT_SSH_DMAC1
`define U3_ANY
`elsif CUT_SSH_DMAC_MODES
`define U3_ANY
`elsif CUT_SSH_DIVU_OVF
`define U3_ANY
`elsif CUT_SSH_VECMD
`define U3_ANY
`elsif CUT_SSH_SBY
`define U3_ANY
`elsif CUT_SSH_CACHE_AARD
`define U3_ANY
`endif
`ifdef CUT_MSH_DIVU_OVF
`define U4_ANY
`elsif CUT_MSH_DMAC_DREQ_IE
`define U4_ANY
`elsif CUT_MSH_WDT_RST
`define U4_ANY
`elsif CUT_MSH_CACHE_TW
`define U4_ANY
`elsif CUT_MSH_FRT_FICR
`define U4_ANY
`endif
`ifdef CUT_MSH_BSC_FIX
`define U5_ANY
`elsif CUT_MSH_BSC_MCR
`define U5_ANY
`elsif CUT_MSH_BSC_RTC
`define U5_ANY
`elsif CUT_SSH_BSC_FIX
`define U5_ANY
`elsif CUT_SSH_BSC_MCR
`define U5_ANY
`elsif CUT_SSH_BSC_RTC
`define U5_ANY
`endif
module Saturn
#(parameter bit RAMH_SLOW=0)
(
	input              CLK,
	input              RST_N,
	input              EN,
	
	input              SYS_CE_F,
	input              SYS_CE_R,
	
	input              SRES_N,
	
	input              PAL,
	
	output     [24: 0] MEM_A,
	input      [31: 0] MEM_DI,
	output     [31: 0] MEM_DO,
	output             ROM_CS_N,
	output             SRAM_CS_N,
	output             RAML_CS_N,
	output             RAMH_CS_N,
	output             RAMH_BURST,
	output             RAMH_RFS,
	output     [ 3: 0] MEM_DQM_N,
	output             MEM_RD_N,
	input              MEM_WAIT_N,
	
	output     [18: 1] VDP1_VRAM_A,
	output     [15: 0] VDP1_VRAM_D,
	input      [15: 0] VDP1_VRAM_Q,
	output     [ 1: 0] VDP1_VRAM_WE,
	output             VDP1_VRAM_RD,
	output     [ 8: 0] VDP1_VRAM_BLEN,
	input              VDP1_VRAM_RDY,
	
`ifdef VDP1_FB_EXT
	// VDP1 frame buffers off-chip (Pocket; rtl/Saturn/VDP1/VDP1.sv `VDP1_FB_EXT): ports by role, all on CLK; the glue
	// (glue/rtl/vdp1fb_ext.sv) maps the roles to its two memories with VDP1_FB_SEL and answers on VDP1_FB_RDY
	output     [17: 1] VDP1_FBD_A,     // draw / CPU side (the draw buffer): request in a clock with FBD_WE or FBD_RD
	output     [15: 0] VDP1_FBD_D,
	output     [ 1: 0] VDP1_FBD_WE,
	output             VDP1_FBD_RD,
	input      [15: 0] VDP1_FBD_Q,     // the read word, valid when VDP1_FB_RDY is back
	output     [17: 1] VDP1_FBV_A,     // display side (the display buffer): raster address; VDP1_FBV_Q = its word one clock later
	input      [15: 0] VDP1_FBV_Q,
	output             VDP1_FBE_WE,    // erase write of VDP1_FBE_D to the display buffer at VDP1_FBV_A
	output     [15: 0] VDP1_FBE_D,
	output             VDP1_FB_SEL,    // 1: buffer 0 is the draw buffer (swaps at the frame change)
	output             VDP1_FBV_VB,    // vertical blank: no display reads (VDP1_FBV_A only sweeps V-blank erases)
`else
	output     [17: 1] VDP1_FB0_A,
	output     [15: 0] VDP1_FB0_D,
	input      [15: 0] VDP1_FB0_Q,
	output     [ 1: 0] VDP1_FB0_WE,
	output             VDP1_FB0_RD,
	
	output     [17: 1] VDP1_FB1_A,
	output     [15: 0] VDP1_FB1_D,
	input      [15: 0] VDP1_FB1_Q,
	output     [ 1: 0] VDP1_FB1_WE,
	output             VDP1_FB1_RD,
`endif
	
	input              VDP1_FB_RDY,
	output             VDP1_FB_MODE3,
	
	output     [18: 1] VDP2_RA0_A,
	output     [16: 1] VDP2_RA1_A,
	output     [63: 0] VDP2_RA_D,
	output     [ 7: 0] VDP2_RA_WE,
	output             VDP2_RA_RD,
	input      [31: 0] VDP2_RA0_Q,
	input      [31: 0] VDP2_RA1_Q,
	
	output     [18: 1] VDP2_RB0_A,
	output     [16: 1] VDP2_RB1_A,
	output     [63: 0] VDP2_RB_D,
	output     [ 7: 0] VDP2_RB_WE,
	output             VDP2_RB_RD,
	input      [31: 0] VDP2_RB0_Q,
	input      [31: 0] VDP2_RB1_Q,

	input              SCSP_CE,
	output     [18: 1] SCSP_RAM_A,
	output     [15: 0] SCSP_RAM_D,
	output     [ 1: 0] SCSP_RAM_WE,
	output             SCSP_RAM_RD,
	output             SCSP_RAM_CS,
	input      [15: 0] SCSP_RAM_Q,
	output             SCSP_RAM_RFS,
	input              SCSP_RAM_RDY,
	
	input              SMPC_CE,
	input              TIME_SET,
	input      [64: 0] RTC,
	input      [ 3: 0] SMPC_AREA,
	output             SMPC_DOTSEL,
	
	input      [ 6: 0] SMPC_PDR1I,
	output     [ 6: 0] SMPC_PDR1O,
	output     [ 6: 0] SMPC_DDR1,
	input      [ 6: 0] SMPC_PDR2I,
	output     [ 6: 0] SMPC_PDR2O,
	output     [ 6: 0] SMPC_DDR2,
	
	input              CD_CE,
`ifdef CD_HLE
	input              CD_DISC_IN,     // CD block HLE: the disc source (rtl/Saturn/CD/CDB_HLE.sv)
	output             CD_SEC_REQ,
	output     [23: 0] CD_SEC_LBA,
	input              CD_SEC_WR,
	input      [15: 0] CD_SEC_DATA,
	output             CD_SEC_WAIT,
`ifdef CD_EXTIO
	// the CD block HLE's EXT I/O port (Pocket disc source, glue/rtl/cd_src_b.sv; needs SMPC_FW), on CLK: the firmware's
	// write of I/O word 0x60 + 4 * CD_EXT_A = CD_EXT_WE for one clock with CD_EXT_A / CD_EXT_WD; its read samples CD_EXT_RD
	output     [ 2: 0] CD_EXT_A,
	output             CD_EXT_WE,
	output     [31: 0] CD_EXT_WD,
	input      [31: 0] CD_EXT_RD,
`endif
`else
	input              CD_CDATA,
	output             CD_HDATA,
	output             CD_COMCLK,
	input              CD_COMREQ_N,
	input              CD_COMSYNC_N,
	output             CD_DEMP,
	input      [15: 0] CD_D,
	input              CD_CK,
	input              CD_AUDIO,
`endif
	output     [18: 1] CD_RAM_A,
	output     [15: 0] CD_RAM_D,
	output     [ 1: 0] CD_RAM_WE,
	output             CD_RAM_RD,
	output             CD_RAM_CS,
	input      [15: 0] CD_RAM_Q,
	input              CD_RAM_RDY,
	
	input      [ 2: 0] CART_MODE,
	output      [25:1] CART_MEM_A,
	output      [15:0] CART_MEM_D,
	output      [ 1:0] CART_MEM_WE,
	output             CART_MEM_RD,
	input       [15:0] CART_MEM_Q,
	input              CART_MEM_RDY,
	
	
	
	output     [ 7: 0] R,
	output     [ 7: 0] G,
	output     [ 7: 0] B,
	output reg         DCLK,
	output reg         HS_N,
	output reg         VS_N,
	output reg         HBL_N,
	output reg         VBL_N,
	
	output             FIELD,
	output             INTERLACE,
	output     [ 1: 0] HRES,
	output     [ 1: 0] VRES,
	output             DCE_R,
	output             DCE_F,
	
	output     [15: 0] SOUND_L,
	output     [15: 0] SOUND_R,
	
	input              FAST,
	input              BLUR_MESH,
	
	input      [ 7: 0] SCRN_EN,
	input      [ 2: 0] SND_EN,
	input              DBG_PAUSE,
	input              DBG_BREAK,
	input              DBG_RUN,
	input      [ 7: 0] DBG_EXT
);

	bit BREAK;
	bit START;
`ifdef DEBUG
	bit VDP1_CMD_END,VDP1_START;
`endif
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			BREAK <= 0;
			START <= 0;
		end
		else begin
`ifdef DEBUG
			if (VDP1_START) begin
				BREAK <= DBG_BREAK;
				START <= 1;
			end else if (VDP1_CMD_END && START) begin
				BREAK <= DBG_BREAK;
			end else 
`endif
			if (DBG_RUN) begin
				BREAK <= 0;
			end 
		end
	end
	wire PAUSE = DBG_PAUSE | BREAK;
	
	
	//MSH
	bit  [26:0] MSHA;
	bit  [31:0] MSHDO;
	bit  [31:0] MSHDI;
	bit         MSHBS_N;
	bit         MSHCS0_N;
	bit         MSHCS1_N;
	bit         MSHCS2_N;
	bit         MSHCS3_N;
	bit         MSHRD_WR_N;
	bit   [3:0] MSHDQM_N;
	bit         MSHRD_N;
	bit         MSHWAIT_N;
	bit         MSHIVECF_N;
	bit   [3:0] MSHIRL_N;
	bit         MSHRES_N;
	bit         MSHNMI_N;
	bit         MSHBGR_N;
	bit         MSHBRLS_N;
	bit         MSRFS;
	
	//SSH
	bit  [26:0] SSHA;
	bit  [31:0] SSHDO;
	bit  [31:0] SSHDI;
	bit         SSHBS_N;
	bit         SSHCS0_N;
	bit         SSHCS1_N;
	bit         SSHCS2_N;
	bit         SSHCS3_N;
	bit         SSHRD_WR_N;
	bit   [3:0] SSHDQM_N;
	bit         SSHRD_N;
	bit         SSHWAIT_N;
	bit   [3:0] SSHIRL_N;
	bit         SSHRES_N;
	bit         SSHNMI_N;
	bit         SSHBREQ_N;
	bit         SSHBACK_N;
	
	//SCU
	bit  [24:0] CA;
	bit  [31:0] CDO;
	bit  [31:0] CDI;
	bit         CBS_N;
	bit         CCS0_N;
	bit         CCS1_N;
	bit         CCS2_N;
	bit         CCS3_N;
	bit         CRD_WR_N;
	bit   [3:0] CDQM_N;
	bit         CRD_N;
	bit         CWAIT_N;
	bit         CWATIN_N;
	bit         CIVECF_N;
	bit   [3:0] CIRL_N;
	bit         CBREQ_N;
	bit         CBACK_N;
	
	bit  [24:0] ECA;
	bit  [31:0] ECDI;
	bit  [31:0] ECDO;
	bit   [3:0] ECDQM_N;
	bit         ECRD_WR_N;
	bit         ECCS3_N;
	bit         ECRD_N;
	bit         ECBURST;
	bit         ECRFS;
	bit         ECWAIT_N;

	bit  [25:0] AA;
	bit  [15:0] ADI;
	bit  [15:0] ADO;
	bit   [1:0] AFC;
	bit         AAS_N;
	bit         ACS0_N;
	bit         ACS1_N;
	bit         ACS2_N;
	bit         AWAIT_N;
	bit         AIRQ_N;
	bit         ARD_N;
	bit         AWRL_N;
	bit         AWRU_N;
	bit         ATIM0_N;
	bit         ATIM1_N;
	bit         ATIM2_N;
	
	bit  [15:0] BDI;
	bit  [15:0] BDO;
	bit         BADDT_N;
	bit         BDTEN_N;
	bit         BREQ_N;
	bit         BCS1_N;
	bit         BRDY1_N;
	bit         IRQ1_N;
	bit         BCS2_N;
	bit         BRDY2_N;
	bit         IRQV_N;
	bit         IRQH_N;
	bit         BCSS_N;
	bit         BRDYS_N;
	bit         IRQS_N;
	
	bit         MIRQ_N;
	
	bit  [31:0] SCU_DO;
	
	//DCC
	bit         DRAMCE_N;
	bit         ROMCE_N;
	bit         SMPCCE_N;
	bit         SRAMCE_N;
	bit         MWR_N;
	bit   [1:0] BIRL;
	bit         MFTI;
	bit         SFTI;
	
	//SMPC
	bit   [7:0] SMPC_DO;
	bit         SYSRES_N;
	bit         SNDRES_N;
	bit         CDRES_N;
	bit         EXL_N;
	
	//VDP1
	bit  [15:0] VDP1_DO;
	
	//VDP2
	bit  [15:0] VDP2_DO;
	bit  [15:0] FBDI;
	bit  [15:0] FBDO;
	bit         HTIM_N;
	bit         VTIM_N;
	
	//SCSP
	bit  [15:0] SCSP_DO;
	
	//CD
	bit  [15:0] CD_DO;
	bit         ARQT_N;
	bit  [15:0] CD_SL;
	bit  [15:0] CD_SR;
	
`ifdef U5_ANY
	// U5: the bus-state-controller registers each CPU only ever wrote with one value (BIOS boot, BIOS menus, every game;
	// work/usage logs) are fixed to it, one macro per CPU (CUT_MSH_BSC_* for MSH, CUT_SSH_BSC_* for SSH) and group:
	// _FIX = BCR1 / BCR2 / WCR, _MCR = MCR (the master keeps MCR.RMD writable: it writes 0078 and 007C), _RTC = the
	// refresh timer RTCSR / RTCNT / RTCOR. A fixed register reads and acts as its reset value until its first write and
	// as the value below from then on (rtl/SH/SH7604/BSC.sv, the U5 comment); the values are what the BIOS writes on
	// each CPU (the slave never writes its refresh timer: 0 = its reset values).
`ifdef CUT_MSH_BSC_FIX
	localparam bit U5_MSH_BSC_FIX = 1'b1;
`else
	localparam bit U5_MSH_BSC_FIX = 1'b0;
`endif
`ifdef CUT_MSH_BSC_MCR
	localparam bit U5_MSH_BSC_MCR = 1'b1;
`else
	localparam bit U5_MSH_BSC_MCR = 1'b0;
`endif
`ifdef CUT_MSH_BSC_RTC
	localparam bit U5_MSH_BSC_RTC = 1'b1;
`else
	localparam bit U5_MSH_BSC_RTC = 1'b0;
`endif
`ifdef CUT_SSH_BSC_FIX
	localparam bit U5_SSH_BSC_FIX = 1'b1;
`else
	localparam bit U5_SSH_BSC_FIX = 1'b0;
`endif
`ifdef CUT_SSH_BSC_MCR
	localparam bit U5_SSH_BSC_MCR = 1'b1;
`else
	localparam bit U5_SSH_BSC_MCR = 1'b0;
`endif
`ifdef CUT_SSH_BSC_RTC
	localparam bit U5_SSH_BSC_RTC = 1'b1;
`else
	localparam bit U5_SSH_BSC_RTC = 1'b0;
`endif
`endif
`ifdef SH2_SHARED_CORE
	// SH2_SHARED_CORE: one SH-2 core for both CPUs (rtl/SH/core/SH_core_cs.sv): thread 0 = the master (MSH), executing in
	// the SYS_CE_R clocks as before; thread 1 = the slave (SSH), executing in the SYS_CE_F clocks: the whole slave runs
	// one clk_sys later (its CE_R / CE_F are swapped below), half a CPU clock out of phase with the rest of the system.
	wire  [49:0] MSH_CORE_CI, SSH_CORE_CI;
	wire [119:0] MSH_CORE_CO, SSH_CORE_CO;
`ifdef DEBUG
	wire   [4:0] MSH_CORE_DBG_REGN, SSH_CORE_DBG_REGN;
	wire  [31:0] MSH_CORE_DBG_REGQ, SSH_CORE_DBG_REGQ;
	wire         MSH_CORE_DBG_RUN, SSH_CORE_DBG_RUN, MSH_CORE_DBG_BREAK, SSH_CORE_DBG_BREAK;
`endif
	SH_core_cs SH_CORE
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.PH(SYS_CE_R),
		.EN(EN),
		.CI0(MSH_CORE_CI),
		.CI1(SSH_CORE_CI),
		.CO0(MSH_CORE_CO),
		.CO1(SSH_CORE_CO)
`ifdef DEBUG
		,
		.DBG_REGN0(MSH_CORE_DBG_REGN),
		.DBG_REGQ0(MSH_CORE_DBG_REGQ),
		.DBG_RUN0(MSH_CORE_DBG_RUN),
		.DBG_BREAK0(MSH_CORE_DBG_BREAK),
		.DBG_REGN1(SSH_CORE_DBG_REGN),
		.DBG_REGQ1(SSH_CORE_DBG_REGQ),
		.DBG_RUN1(SSH_CORE_DBG_RUN),
		.DBG_BREAK1(SSH_CORE_DBG_BREAK)
`endif
	);
`endif
`ifdef SH2_SHARE_DIVU
`ifndef SH2_SHARED_CORE
	SH2_SHARE_DIVU_needs_SH2_SHARED_CORE error_no_shared_core();	//deliberate elaboration error: the two CPUs must be out of phase
`endif
`ifndef DIVU_LEAN
	SH2_SHARE_DIVU_needs_DIVU_LEAN error_no_divu_lean();	//deliberate elaboration error: the shared DIVU is DIVU_LEAN's
`endif
`ifdef CUT_MSH_DIVU_OVF
	localparam bit R8_DIVU_OVF0 = 1'b1;
`else
	localparam bit R8_DIVU_OVF0 = 1'b0;
`endif
`ifdef CUT_SSH_DIVU_OVF
	localparam bit R8_DIVU_OVF1 = 1'b1;
`else
	localparam bit R8_DIVU_OVF1 = 1'b0;
`endif
	// SH2_SHARE_DIVU: one C-slowed DIVU for both CPUs (rtl/SH/SH7604/DIVU.sv, SH7604_DIVUX): in every clock its CE_R logic
	// serves the CPU whose CE_R clock it is (the master when SYS_CE_R) and its CE_F logic the other one; each CPU keeps
	// its own CUT_DIVU_OVF (the CUT_MSH / CUT_SSH macros, as Saturn.sv gives the two SH7604s below)
	wire [44:0] MSH_DIVUX_O, SSH_DIVUX_O;
	wire [41:0] MSH_DIVUX_I, SSH_DIVUX_I;
`ifdef SH2_SHARE_DIVU_EXACT
	localparam bit R8_DIVU_EXACT = 1'b1;	//each CPU's read data / BUSY selected by PH in every clock, not only where used
`else
	localparam bit R8_DIVU_EXACT = 1'b0;
`endif
	SH7604_DIVUX #(.CUT_OVFIE0(R8_DIVU_OVF0), .CUT_OVFIE1(R8_DIVU_OVF1), .EXACT_OUT(R8_DIVU_EXACT)) DIVUX (.CLK(CLK), .RST_N(RST_N), .PH(SYS_CE_R), .EN(EN),
		.XO0(MSH_DIVUX_O), .XO1(SSH_DIVUX_O), .XI0(MSH_DIVUX_I), .XI1(SSH_DIVUX_I));
`endif
`ifdef SH2_SHARE_MULTCS
`ifndef SH2_SHARED_CORE
	SH2_SHARE_MULTCS_needs_SH2_SHARED_CORE error_no_shared_core();	//deliberate elaboration error: the two CPUs must be out of phase
`endif
	// SH2_SHARE_MULTCS: one C-slowed MULT for both CPUs (rtl/SH/SH7604/MULT.sv, SH7604_MULTCS): its CE_R logic serves the
	// CPU whose CE_R clock it is (the master when SYS_CE_R), its exec logic the other one
	wire [40:0] MSH_MULTCS_O, SSH_MULTCS_O;
	wire [64:0] MSH_MULTCS_I, SSH_MULTCS_I;
	SH7604_MULTCS MULTCS (.CLK(CLK), .RST_N(RST_N), .PH(SYS_CE_R), .EN(EN), .XO0(MSH_MULTCS_O), .XO1(SSH_MULTCS_O), .XI0(MSH_MULTCS_I), .XI1(SSH_MULTCS_I));
`endif
`ifdef SH2_SHARE_MULT
`ifndef SH2_SHARED_CORE
	SH2_SHARE_MULT_needs_SH2_SHARED_CORE error_no_shared_core();	//deliberate elaboration error: the two CPUs must be out of phase
`endif
`ifdef SH2_SHARE_MULTCS
	SH2_SHARE_MULT_and_SH2_SHARE_MULTCS_exclude_each_other error_two_mults();	//deliberate elaboration error: pick one
`endif
	// SH2_SHARE_MULT: one multiply / accumulate datapath for both CPUs' MULT units (rtl/SH/SH7604/MULT.sv, SH7604_MULTX).
	// A CPU executes a multiply only in its CE_F clocks; with SH2_SHARED_CORE those are the SYS_CE_F clocks for the
	// master and the SYS_CE_R clocks for the slave, so PH = SYS_CE_R picks the slave's operands, else the master's.
	wire [133:0] MSH_MULTX_O, SSH_MULTX_O;
	wire  [63:0] MULTX_I;
	SH7604_MULTX MULTX (.PH(SYS_CE_R), .XO0(MSH_MULTX_O), .XO1(SSH_MULTX_O), .XI(MULTX_I));
`endif
`ifdef U4_ANY
	// U4: features no game (nor the BIOS boot or menus) used on the master are cut on the master only, one CUT_MSH_*
	// macro each (rtl/SH/SH7604, the U4 comments); the slave (SSH below) keeps all of them (it has its own U3 cuts).
`ifdef CUT_MSH_DIVU_OVF
	localparam bit U4_DIVU_OVF = 1'b1;
`else
	localparam bit U4_DIVU_OVF = 1'b0;
`endif
`ifdef CUT_MSH_FRT_FICR
	localparam bit U4_FRT_FICR = 1'b1;
`else
	localparam bit U4_FRT_FICR = 1'b0;
`endif
`ifdef CUT_MSH_DMAC_DREQ_IE
	localparam bit U4_DMAC_DREQ_IE = 1'b1;
`else
	localparam bit U4_DMAC_DREQ_IE = 1'b0;
`endif
`ifdef CUT_MSH_WDT_RST
	localparam bit U4_WDT_RST = 1'b1;
`else
	localparam bit U4_WDT_RST = 1'b0;
`endif
`ifdef CUT_MSH_CACHE_TW
	localparam bit U4_CACHE_TW = 1'b1;
`else
	localparam bit U4_CACHE_TW = 1'b0;
`endif
`ifdef U5_ANY
	SH7604 #(.UBC_DISABLE(1), .SCI_DISABLE(1), .BUS_AREA_TIMIMG({RAMH_SLOW,3'b111}), .BUS_SIZE_BYTE_DISABLE(1),
	         .CUT_DIVU_OVF(U4_DIVU_OVF), .CUT_FRT_FICR(U4_FRT_FICR), .CUT_DMAC_DREQ_IE(U4_DMAC_DREQ_IE),
	         .CUT_WDT_RST(U4_WDT_RST), .CUT_CACHE_TW(U4_CACHE_TW),
	         .CUT_BSC_FIX(U5_MSH_BSC_FIX), .CUT_BSC_MCR(U5_MSH_BSC_MCR), .CUT_BSC_RTC(U5_MSH_BSC_RTC),	//U5
	         .BSC_BCR1(16'h03F1), .BSC_BCR2(16'h00FC), .BSC_WCR(16'h5555), .BSC_MCR(16'h0078), .BSC_MCR_VAR(16'h0004),
	         .BSC_RTCSR(16'h0008), .BSC_RTCOR(8'h36)) MSH
`else
	SH7604 #(.UBC_DISABLE(1), .SCI_DISABLE(1), .BUS_AREA_TIMIMG({RAMH_SLOW,3'b111}), .BUS_SIZE_BYTE_DISABLE(1),
	         .CUT_DIVU_OVF(U4_DIVU_OVF), .CUT_FRT_FICR(U4_FRT_FICR), .CUT_DMAC_DREQ_IE(U4_DMAC_DREQ_IE),
	         .CUT_WDT_RST(U4_WDT_RST), .CUT_CACHE_TW(U4_CACHE_TW)) MSH
`endif
`else
`ifdef U5_ANY
	SH7604 #(.UBC_DISABLE(1), .SCI_DISABLE(1), .BUS_AREA_TIMIMG({RAMH_SLOW,3'b111}), .BUS_SIZE_BYTE_DISABLE(1),
	         .CUT_BSC_FIX(U5_MSH_BSC_FIX), .CUT_BSC_MCR(U5_MSH_BSC_MCR), .CUT_BSC_RTC(U5_MSH_BSC_RTC),	//U5
	         .BSC_BCR1(16'h03F1), .BSC_BCR2(16'h00FC), .BSC_WCR(16'h5555), .BSC_MCR(16'h0078), .BSC_MCR_VAR(16'h0004),
	         .BSC_RTCSR(16'h0008), .BSC_RTCOR(8'h36)) MSH
`else
	SH7604 #(.UBC_DISABLE(1), .SCI_DISABLE(1), .BUS_AREA_TIMIMG({RAMH_SLOW,3'b111}), .BUS_SIZE_BYTE_DISABLE(1)) MSH
`endif
`endif
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(SYS_CE_R),
		.CE_F(SYS_CE_F),
		.EN(EN),
		
		.RES_N(MSHRES_N),
		.NMI_N(MSHNMI_N),
		
		.IRL_N(MSHIRL_N),
		
		.A(MSHA),
		.DI(MSHDI),
		.DO(MSHDO),
		.BS_N(MSHBS_N),
		.CS0_N(MSHCS0_N),
		.CS1_N(MSHCS1_N),
		.CS2_N(MSHCS2_N),
		.CS3_N(MSHCS3_N),
		.RD_WR_N(MSHRD_WR_N),
		.WE_N(MSHDQM_N),
		.RD_N(MSHRD_N),
		.IVECF_N(MSHIVECF_N),
		.RFS(MSRFS),
		
		.EA(SSHA),
		.EDI(SSHDI),
		.EDO(SSHDO),
		.EBS_N(SSHBS_N),
		.ECS0_N(SSHCS0_N),
		.ECS1_N(SSHCS1_N),
		.ECS2_N(SSHCS2_N),
		.ECS3_N(SSHCS3_N),
		.ERD_WR_N(SSHRD_WR_N),
		.EWE_N(SSHDQM_N),
		.ERD_N(SSHRD_N),
		.ECE_N(1'b1),
		.EOE_N(1'b1),
		.EIVECF_N(1'b1),
		
		.WAIT_N(MSHWAIT_N),
		.IVECF_N(),
		.BRLS_N(MSHBRLS_N),
		.BGR_N(MSHBGR_N),
		
		.DREQ0(1'b1),
		.DREQ1(1'b1),
		
		.FTCI(1'b1),
		.FTI(MFTI),
		
		.RXD(1'b1),
		.TXD(),
		.SCKO(),
		.SCKI(1'b1),
		
		.MD(6'b001000),
		
		.FAST(FAST)
`ifdef SH2_SHARED_CORE
		,
		.CORE_CI(MSH_CORE_CI),
		.CORE_CO(MSH_CORE_CO)
`ifdef DEBUG
		,
		.CORE_DBG_REGN(MSH_CORE_DBG_REGN),
		.CORE_DBG_RUN(MSH_CORE_DBG_RUN),
		.CORE_DBG_REGQ(MSH_CORE_DBG_REGQ),
		.CORE_DBG_BREAK(MSH_CORE_DBG_BREAK)
`endif
`endif
`ifdef SH2_SHARE_DIVU
		,
		.DIVUX_O(MSH_DIVUX_O),
		.DIVUX_I(MSH_DIVUX_I)
`endif
`ifdef SH2_SHARE_MULTCS
		,
		.MULTCS_O(MSH_MULTCS_O),
		.MULTCS_I(MSH_MULTCS_I)
`endif
`ifdef SH2_SHARE_MULT
		,
		.MULTX_O(MSH_MULTX_O),
		.MULTX_I(MULTX_I)
`endif
`ifdef DEBUG
		,
		.DBG_REGN('0),
		.DBG_REGQ(),
		.DBG_RUN(1),
		.DBG_BREAK()
`endif
	);
	
`ifdef U3_ANY
	// U3: features no game used on the slave are cut on the slave only, one CUT_SSH_* macro each (rtl/SH/SH7604,
	// the U3 comments); the master (MSH above) keeps all of them.
`ifdef CUT_SSH_WDT
	localparam bit U3_WDT = 1'b1;
`else
	localparam bit U3_WDT = 1'b0;
`endif
`ifdef CUT_SSH_FRT_OC
	localparam bit U3_FRT_OC = 1'b1;
`else
	localparam bit U3_FRT_OC = 1'b0;
`endif
`ifdef CUT_SSH_FRT_FICR
	localparam bit U3_FRT_FICR = 1'b1;
`else
	localparam bit U3_FRT_FICR = 1'b0;
`endif
`ifdef CUT_SSH_DMAC1
	localparam bit U3_DMAC1 = 1'b1;
`else
	localparam bit U3_DMAC1 = 1'b0;
`endif
`ifdef CUT_SSH_DMAC_MODES
	localparam bit U3_DMAC_MODES = 1'b1;
`else
	localparam bit U3_DMAC_MODES = 1'b0;
`endif
`ifdef CUT_SSH_DIVU_OVF
	localparam bit U3_DIVU_OVF = 1'b1;
`else
	localparam bit U3_DIVU_OVF = 1'b0;
`endif
`ifdef CUT_SSH_VECMD
	localparam bit U3_VECMD = 1'b1;
`else
	localparam bit U3_VECMD = 1'b0;
`endif
`ifdef CUT_SSH_SBY
	localparam bit U3_SBY = 1'b1;
`else
	localparam bit U3_SBY = 1'b0;
`endif
`ifdef CUT_SSH_CACHE_AARD
	localparam bit U3_CACHE_AARD = 1'b1;
`else
	localparam bit U3_CACHE_AARD = 1'b0;
`endif
`ifdef U5_ANY
	SH7604 #(.UBC_DISABLE(1), .SCI_DISABLE(1), .BUS_AREA_TIMIMG({RAMH_SLOW,3'b111}), .BUS_SIZE_BYTE_DISABLE(1),
	         .CUT_WDT(U3_WDT), .CUT_FRT_OC(U3_FRT_OC), .CUT_FRT_FICR(U3_FRT_FICR), .CUT_DMAC1(U3_DMAC1),
	         .CUT_DMAC_MODES(U3_DMAC_MODES), .CUT_DIVU_OVF(U3_DIVU_OVF), .CUT_VECMD(U3_VECMD), .CUT_SBY(U3_SBY),
	         .CUT_CACHE_AARD(U3_CACHE_AARD),
	         .CUT_BSC_FIX(U5_SSH_BSC_FIX), .CUT_BSC_MCR(U5_SSH_BSC_MCR), .CUT_BSC_RTC(U5_SSH_BSC_RTC),	//U5
	         .BSC_BCR1(16'h03F1), .BSC_BCR2(16'h00FC), .BSC_WCR(16'h5555), .BSC_MCR(16'h0070), .BSC_MCR_VAR(16'h0000),
	         .BSC_RTCSR(16'h0000), .BSC_RTCOR(8'h00)) SSH
`else
	SH7604 #(.UBC_DISABLE(1), .SCI_DISABLE(1), .BUS_AREA_TIMIMG({RAMH_SLOW,3'b111}), .BUS_SIZE_BYTE_DISABLE(1),
	         .CUT_WDT(U3_WDT), .CUT_FRT_OC(U3_FRT_OC), .CUT_FRT_FICR(U3_FRT_FICR), .CUT_DMAC1(U3_DMAC1),
	         .CUT_DMAC_MODES(U3_DMAC_MODES), .CUT_DIVU_OVF(U3_DIVU_OVF), .CUT_VECMD(U3_VECMD), .CUT_SBY(U3_SBY),
	         .CUT_CACHE_AARD(U3_CACHE_AARD)) SSH
`endif
`else
`ifdef U5_ANY
	SH7604 #(.UBC_DISABLE(1), .SCI_DISABLE(1), .BUS_AREA_TIMIMG({RAMH_SLOW,3'b111}), .BUS_SIZE_BYTE_DISABLE(1),
	         .CUT_BSC_FIX(U5_SSH_BSC_FIX), .CUT_BSC_MCR(U5_SSH_BSC_MCR), .CUT_BSC_RTC(U5_SSH_BSC_RTC),	//U5
	         .BSC_BCR1(16'h03F1), .BSC_BCR2(16'h00FC), .BSC_WCR(16'h5555), .BSC_MCR(16'h0070), .BSC_MCR_VAR(16'h0000),
	         .BSC_RTCSR(16'h0000), .BSC_RTCOR(8'h00)) SSH
`else
	SH7604 #(.UBC_DISABLE(1), .SCI_DISABLE(1), .BUS_AREA_TIMIMG({RAMH_SLOW,3'b111}), .BUS_SIZE_BYTE_DISABLE(1)) SSH
`endif
`endif
	(
		.CLK(CLK),
		.RST_N(RST_N),
`ifdef SH2_SHARED_CORE
		.CE_R(SYS_CE_F),	//SH2_SHARED_CORE: the slave one clk_sys later (its core is thread 1 of SH_core_cs)
		.CE_F(SYS_CE_R),
`else
		.CE_R(SYS_CE_R),
		.CE_F(SYS_CE_F),
`endif
		.EN(EN),
		
		.RES_N(SSHRES_N),
		.NMI_N(SSHNMI_N),
		
		.IRL_N(SSHIRL_N),
		
		.A(SSHA),
		.DI(SSHDI),
		.DO(SSHDO),
		.BS_N(SSHBS_N),
		.CS0_N(SSHCS0_N),
		.CS1_N(SSHCS1_N),
		.CS2_N(SSHCS2_N),
		.CS3_N(SSHCS3_N),
		.RD_WR_N(SSHRD_WR_N),
		.WE_N(SSHDQM_N),
		.RD_N(SSHRD_N),
		.IVECF_N(),
		
		.EA({2'b00,ECA}),
		.EDI(ECDI),
		.EDO(ECDO),
		.EBS_N(1'b1),
		.ECS0_N(1'b1),
		.ECS1_N(1'b1),
		.ECS2_N(1'b1),
		.ECS3_N(ECCS3_N),
		.ERD_WR_N(ECRD_WR_N),
		.EWE_N(ECDQM_N),
		.ERD_N(ECRD_N),
		.ECE_N(1'b1),
		.EOE_N(1'b1),
		.EIVECF_N(1'b1),
		
		.WAIT_N(SSHWAIT_N),
		.BRLS_N(SSHBACK_N),
		.BGR_N(SSHBREQ_N),
		
		.DREQ0(1'b1),
		.DREQ1(1'b1),
		
		.FTCI(1'b1),
		.FTI(SFTI),
		
		.RXD(1'b1),
		.TXD(),
		.SCKO(),
		.SCKI(1'b1),
		
		.MD(6'b101000),
		
		.FAST(FAST)
`ifdef SH2_SHARED_CORE
		,
		.CORE_CI(SSH_CORE_CI),
		.CORE_CO(SSH_CORE_CO)
`ifdef DEBUG
		,
		.CORE_DBG_REGN(SSH_CORE_DBG_REGN),
		.CORE_DBG_RUN(SSH_CORE_DBG_RUN),
		.CORE_DBG_REGQ(SSH_CORE_DBG_REGQ),
		.CORE_DBG_BREAK(SSH_CORE_DBG_BREAK)
`endif
`endif
`ifdef SH2_SHARE_DIVU
		,
		.DIVUX_O(SSH_DIVUX_O),
		.DIVUX_I(SSH_DIVUX_I)
`endif
`ifdef SH2_SHARE_MULTCS
		,
		.MULTCS_O(SSH_MULTCS_O),
		.MULTCS_I(SSH_MULTCS_I)
`endif
`ifdef SH2_SHARE_MULT
		,
		.MULTX_O(SSH_MULTX_O),
		.MULTX_I(MULTX_I)
`endif
`ifdef DEBUG
		,
		.DBG_REGN('0),
		.DBG_REGQ(),
		.DBG_RUN(1),
		.DBG_BREAK()
`endif
	);
	
	assign MSHIRL_N  = CIRL_N;
	assign SSHIRL_N  = {1'b1,BIRL,1'b1};
	
	bit [31:0] OPEN_BUS;
	always @(posedge CLK or negedge RST_N) begin
	bit         MSHDQM_N_OLD;
	
		if (!RST_N) begin
			OPEN_BUS <= '1;
		end else if (!SYSRES_N) begin
			
		end else begin
			MSHDQM_N_OLD <= &MSHDQM_N;
			if (&MSHDQM_N_OLD & MSHDQM_N_OLD) begin
				if (!MSHDQM_N[3]) OPEN_BUS[31:24] <= MSHDO[31:24];
				if (!MSHDQM_N[2]) OPEN_BUS[23:16] <= MSHDO[23:16];
				if (!MSHDQM_N[1]) OPEN_BUS[15: 8] <= MSHDO[15: 8];
				if (!MSHDQM_N[0]) OPEN_BUS[ 7: 0] <= MSHDO[ 7: 0];
			end
			
			if (!MSHRD_N && MSHWAIT_N) begin
				OPEN_BUS <= MSHDI;
			end
		end
	end

	assign MSHDI     = CDO;
	assign MSHWAIT_N = CWAIT_N & (MEM_WAIT_N | (MSHCS3_N & DRAMCE_N & ROMCE_N & SRAMCE_N));
	assign SSHWAIT_N = CWAIT_N & (MEM_WAIT_N | (MSHCS3_N & DRAMCE_N & ROMCE_N & SRAMCE_N));
	
	assign CA       = MSHA[24:0];
	assign CDO      = !MSHCS3_N || !DRAMCE_N || !ROMCE_N || !SRAMCE_N ? MEM_DI :
                     !SMPCCE_N                                       ? {16'h0000,8'hFF,SMPC_DO} :
							!MSHCS1_N || !MSHCS2_N || !MSHIVECF_N           ? SCU_DO :
							OPEN_BUS;
	assign CDI      = {!MSHDQM_N[3] ? MSHDO[31:24] : OPEN_BUS[31:24],
	                   !MSHDQM_N[2] ? MSHDO[23:16] : OPEN_BUS[23:16],
							 !MSHDQM_N[1] ? MSHDO[15: 8] : OPEN_BUS[15: 8],
							 !MSHDQM_N[0] ? MSHDO[ 7: 0] : OPEN_BUS[ 7: 0]};
	assign CBS_N    = MSHBS_N;
	assign CCS0_N   = MSHCS0_N;
	assign CCS1_N   = MSHCS1_N;
	assign CCS2_N   = MSHCS2_N;
	assign CCS3_N   = MSHCS3_N;
	assign CRD_WR_N = MSHRD_WR_N;
	assign CDQM_N   = MSHDQM_N;
	assign CRD_N    = MSHRD_N;
	assign CIVECF_N = MSHIVECF_N;
	assign ECWAIT_N = MEM_WAIT_N;
	
	
	
	assign ADI      = !ACS0_N || !ACS1_N ? CART_DO  : 
	                  !ACS2_N            ? CD_DO    : 
							16'hFFFF;
	assign AWAIT_N  = YGR019_AWAIT_N & CART_AWAIT_N;
	assign AIRQ_N   = ARQT_N;
	
	assign BDI      = !BCS1_N ? VDP1_DO :
	                  !BCS2_N ? VDP2_DO :
							!BCSS_N ? SCSP_DO : 16'h0000;

	bit DBG_ABUS_END;
	SCU #(RAMH_SLOW) SCU
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(SYS_CE_R),
		.CE_F(SYS_CE_F),
		
		.RES_N(SYSRES_N),
		
		.CA(CA),
		.CDI(CDI),
		.CDO(SCU_DO),
		.CCS1_N(CCS1_N),
		.CCS2_N(CCS2_N),
		.CCS3_N(CCS3_N),
		.CRD_WR_N(CRD_WR_N),
		.CDQM_N(CDQM_N),
		.CRD_N(CRD_N),
		.CWAIT_N(CWATIN_N),
		.CIVECF_N(CIVECF_N),
		.CIRL_N(CIRL_N),
		.CBREQ_N(CBREQ_N),
		.CBACK_N(CBACK_N),
		
		.ECA(ECA),
		.ECDI(ECDI),
		.ECDO(ECDO),
		.ECDQM_N(ECDQM_N),
		.ECRD_WR_N(ECRD_WR_N),
		.ECCS3_N(ECCS3_N),
		.ECRD_N(ECRD_N),
		.ECBURST(ECBURST),
		.ECRFS(ECRFS),
		.ECWAIT_N(ECWAIT_N),
		
		.AA(AA),
		.ADI(ADI),
		.ADO(ADO),
		.AFC(AFC),
		.AAS_N(AAS_N),
		.ACS0_N(ACS0_N),
		.ACS1_N(ACS1_N),
		.ACS2_N(ACS2_N),
		.AWAIT_N(AWAIT_N),
		.AIRQ_N(AIRQ_N),
		.ARD_N(ARD_N),
		.AWRL_N(AWRL_N),
		.AWRU_N(AWRU_N),
		.ATIM0_N(ATIM0_N),
		.ATIM1_N(ATIM1_N),
		.ATIM2_N(ATIM2_N),
		
		.BDI(BDI),
		.BDO(BDO),
		.BADDT_N(BADDT_N),
		.BDTEN_N(BDTEN_N),
		.BREQ_N(BREQ_N),
		.BCS1_N(BCS1_N),
		.BRDY1_N(BRDY1_N),
		.IRQ1_N(IRQ1_N),
		.BCS2_N(BCS2_N),
		.BRDY2_N(BRDY2_N),
		.IRQV_N(IRQV_N),
		.IRQH_N(IRQH_N),
		.IRQL_N(EXL_N),
		.BCSS_N(BCSS_N),
		.BRDYS_N(BRDYS_N),
		.IRQS_N(IRQS_N),
	
		.MIREQ_N(MIRQ_N),
		
		.FAST(FAST)
	);
	
	
	DCC DCC
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(SYS_CE_R),
		.CE_F(SYS_CE_F),
		
		.RES_N(SYSRES_N),
		
		.A(CA[24:1]),
		.BS_N(CBS_N),
		.CS0_N(CCS0_N),
		.CS1_N(CCS1_N),
		.CS2_N(CCS2_N),
		.RD_WR_N(CRD_WR_N),
		.WE_N(CDQM_N[1:0]),
		.RD_N(CRD_N),
		.WAIT_N(CWAIT_N),
		
		.BRLS_N(MSHBRLS_N),
		.BGR_N(MSHBGR_N),
		.BREQ_N(SSHBREQ_N),
		.BACK_N(SSHBACK_N),
		.EXBREQ_N(CBREQ_N),
		.EXBACK_N(CBACK_N),
		
		.WTIN_N(CWATIN_N),
		.IVECF_N(1'b1),
		
		.HINT_N(IRQH_N),
		.VINT_N(IRQV_N),
		.IREQ_N(BIRL),
		
		.MFTI(MFTI),
		.SFTI(SFTI),
		
		.DCE_N(DRAMCE_N),
		.DOE_N(),
		.DWE_N(),
		.DWAIT_N(MEM_WAIT_N),
		
		.ROMCE_N(ROMCE_N),
		.SRAMCE_N(SRAMCE_N),
		.SMPCCE_N(SMPCCE_N),
		.MOE_N(),
		.MWR_N(MWR_N),
		
		.FAST(FAST)
	);
	
	assign MEM_A     = CA[24:0];
	assign MEM_DO    = CDI;
	assign MEM_DQM_N = CDQM_N;
	assign MEM_RD_N  = CRD_N;
	assign ROM_CS_N  = ROMCE_N;
	assign SRAM_CS_N = SRAMCE_N;
	assign RAML_CS_N = DRAMCE_N;
	assign RAMH_CS_N = MSHCS3_N;
	assign RAMH_BURST = ECBURST;
	assign RAMH_RFS = MSRFS | ECRFS;
	
	
	bit MRES_N;
	bit CE32K;
	always @(posedge CLK or negedge RST_N) begin
		bit  [ 7: 0] CLK_DIV;
		
		if (!RST_N) begin
			MRES_N <= 0;
			CLK_DIV <= '0;
		end else begin
			if (SMPC_CE) begin
				MRES_N <= 1;
				
				CE32K <= 0;
				CLK_DIV <= CLK_DIV + 8'd1;
				if (CLK_DIV == 8'd121) begin
					CLK_DIV <= '0;
					CE32K <= 1;
				end
			end
		end
	end
	
`ifdef CD_EXTIO
`ifndef SMPC_FW
	// the CD block HLE's EXT port (the Pocket's disc source) is driven by the SMPC_FW firmware image (cdb_hle_pocket_fw)
	CD_EXTIO_needs_SMPC_FW error_CD_EXTIO_without_SMPC_FW();
`endif
`endif
`ifdef SMPC_FW
	// the SMPC's MCU as firmware on the CD block HLE's CPU (rtl/Saturn/SMPC/SMPC_FW.sv, fw/cdb smpc_*.c)
`ifndef CD_HLE
	SMPC_FW_needs_CD_HLE error_SMPC_FW_without_CD_HLE();
`endif
	wire [ 4: 0] SMPC_FW_A;
	wire         SMPC_FW_WE;
	wire [31: 0] SMPC_FW_WD, SMPC_FW_RD;
	SMPC_FW SMPC
`else
	SMPC #("rtl/Saturn/SMPC/smpc.mif") SMPC
`endif
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.EN(1'b1),
		
		.CE(SMPC_CE),
		.CE32K(CE32K & SMPC_CE),
		
		.RESET_N(MRES_N),
		
		.A(CA[6:1]),
		.DBI(CDI[7:0]),
		.DBO(SMPC_DO),
		.CS_N(SMPCCE_N),
		.RW_N(MWR_N),
		
		.D0(MIRQ_N),
		.D1(1'b1),
		.D2(1'b0),
		.D3(SRES_N),
		.D4(SNDRES_N),
		.D5(SYSRES_N),
		.D6(MSHRES_N),
		.D7(MSHNMI_N),
		.D8(SSHRES_N),
		.D9(SSHNMI_N),
		.D10(SMPC_DOTSEL),
		.D13_INT0(1'b1),
		
		.R01_INT2(IRQV_N),
		
		.PIOA_I(SMPC_PDR1I),
		.PIOA_O(SMPC_PDR1O),
		.PIOA_D(SMPC_DDR1),
		.PIOB_I(SMPC_PDR2I),
		.PIOB_O(SMPC_PDR2O),
		.PIOB_D(SMPC_DDR2),
		
		.R5(SMPC_AREA),
		
		.R60_D(),
		.R60_O(),
		.R60_I(1'b0),
		
		.R61_D(),
		.R61_O(),
		.R61_I(1'b1),
		
		.R62_I(1'b0),
		.R63_I(1'b0),
		
		.R70_I(1'b0),
		.R71_I(1'b0),
		.R72_O(CDRES_N),
		.R73_O(),
		
		.EXL_N(EXL_N),
		
		.EXT_RTC(RTC)
`ifdef SMPC_FW
		,
		.FW_A(SMPC_FW_A),
		.FW_WE(SMPC_FW_WE),
		.FW_WD(SMPC_FW_WD),
		.FW_RD(SMPC_FW_RD)
`endif
	);
	
	
`ifdef VDP1_FB_EXT
`ifndef CUT_VDP1_ROT
	// the off-chip frame buffers' display side prefetches raster lines: the rotation read-out (random reads) is cut
	VDP1_FB_EXT_needs_CUT_VDP1_ROT error_VDP1_FB_EXT_without_CUT_VDP1_ROT();
`endif
`endif
	VDP1 VDP1
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(SYS_CE_R),
		.CE_F(SYS_CE_F),
		.EN(EN),
		
		.RES_N(SYSRES_N),
		
		.DI(BDO),
		.DO(VDP1_DO),
		.CS_N(BCS1_N),
		.AD_N(BADDT_N),
		.DTEN_N(BDTEN_N),
		.REQ_N(BREQ_N),
		.RDY_N(BRDY1_N),
		
		.IRQ_N(IRQ1_N), 
		
		.DCE_R(DCE_R),
		.DCE_F(DCE_F),
		.VTIM_N(VTIM_N),
		.HTIM_N(HTIM_N),
		.VOUTI(FBDO),
		.VOUTO(FBDI),
		
		.VRAM_A(VDP1_VRAM_A),
		.VRAM_D(VDP1_VRAM_D),
		.VRAM_WE(VDP1_VRAM_WE),
		.VRAM_RD(VDP1_VRAM_RD),
		.VRAM_BLEN(VDP1_VRAM_BLEN),
		.VRAM_Q(VDP1_VRAM_Q),
		.VRAM_RDY(VDP1_VRAM_RDY),
		
`ifdef VDP1_FB_EXT
		.FBD_A(VDP1_FBD_A),
		.FBD_D(VDP1_FBD_D),
		.FBD_WE(VDP1_FBD_WE),
		.FBD_RD(VDP1_FBD_RD),
		.FBD_Q(VDP1_FBD_Q),
		.FBV_A(VDP1_FBV_A),
		.FBV_Q(VDP1_FBV_Q),
		.FBE_WE(VDP1_FBE_WE),
		.FBE_D(VDP1_FBE_D),
		.FB_SEL_O(VDP1_FB_SEL),
		.FBV_VB(VDP1_FBV_VB),
`else
		.FB0_A(VDP1_FB0_A),
		.FB0_D(VDP1_FB0_D),
		.FB0_WE(VDP1_FB0_WE),
		.FB0_RD(VDP1_FB0_RD),
		.FB0_Q(VDP1_FB0_Q),
		
		.FB1_A(VDP1_FB1_A),
		.FB1_D(VDP1_FB1_D),
		.FB1_WE(VDP1_FB1_WE),
		.FB1_RD(VDP1_FB1_RD),
		.FB1_Q(VDP1_FB1_Q),
`endif
		.FB_RDY(VDP1_FB_RDY),
		.FB_MODE3(VDP1_FB_MODE3),
		
		.FAST(FAST),
		.BLUR_MESH(BLUR_MESH),
		
		.DBG_EXT(DBG_EXT)
		
`ifdef DEBUG
		,
		.DBG_START(VDP1_START),
		.DBG_CMD_END(VDP1_CMD_END)
`endif
	);
	
	VDP2 VDP2
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(SYS_CE_R),
		.CE_F(SYS_CE_F),
		
		.RES_N(SYSRES_N),
		
		.DI(BDO),
		.DO(VDP2_DO),
		.CS_N(BCS2_N),
		.AD_N(BADDT_N),
		.DTEN_N(BDTEN_N),
		.REQ_N(BREQ_N),
		.RDY_N(BRDY2_N),
		
		.VINT_N(IRQV_N),
		.HINT_N(IRQH_N),
		
		.DCE_R(DCE_R),
		.DCE_F(DCE_F),
		.HTIM_N(HTIM_N),
		.VTIM_N(VTIM_N),
		.FBDI(FBDI),
		.FBDO(FBDO),
		
		.PAL(PAL),
		
		.EXLAT_N(EXL_N),
		
		.RA0_A(VDP2_RA0_A),
		.RA1_A(VDP2_RA1_A),
		.RA_D(VDP2_RA_D),
		.RA_WE(VDP2_RA_WE),
		.RA_RD(VDP2_RA_RD),
		.RA0_Q(VDP2_RA0_Q),
		.RA1_Q(VDP2_RA1_Q),
		
		.RB0_A(VDP2_RB0_A),
		.RB1_A(VDP2_RB1_A),
		.RB_D(VDP2_RB_D),
		.RB_WE(VDP2_RB_WE),
		.RB_RD(VDP2_RB_RD),
		.RB0_Q(VDP2_RB0_Q),
		.RB1_Q(VDP2_RB1_Q),
		
		.R(R),
		.G(G),
		.B(B),
		.DCLK(DCLK),
		.VS_N(VS_N),
		.HS_N(HS_N),
		.HBL_N(HBL_N),
		.VBL_N(VBL_N),
	
		.FIELD(FIELD),
		.INTERLACE(INTERLACE),
		.HRES(HRES),
		.VRES(VRES),
		
		.SCRN_EN(SCRN_EN),
		
		.DBG_EXT(DBG_EXT)
	);

	bit         SCCE_R;
	bit         SCCE_F;
	bit  [23:1] SCA;
	bit  [15:0] SCDI;
	bit  [15:0] SCDO;
	bit         SCRW_N;
	bit         SCAS_N;
	bit         SCLDS_N;
	bit         SCUDS_N;
	bit         SCDTACK_N;
	bit   [2:0] SCFC;
	bit         SCAVEC_N;
	bit   [2:0] SCIPL_N;
	
	wire SCSP_RES_N = SYSRES_N;
	wire SCPU_RES_N = SNDRES_N;
	SCSP SCSP
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE(SCSP_CE),
		
		.RES_N(SCSP_RES_N),
		
		.CE_R(SYS_CE_R),
		.CE_F(SYS_CE_F),
		.DI(BDO),
		.DO(SCSP_DO),
		.CS_N(BCSS_N),
		.AD_N(BADDT_N),
		.DTEN_N(BDTEN_N),
		.REQ_N(BREQ_N),
		.RDY_N(BRDYS_N),
		.INT_N(IRQS_N),
		
		.SCCE_R(SCCE_R),
		.SCCE_F(SCCE_F),
		.SCA(SCA),
		.SCDI(SCDI),
		.SCDO(SCDO),
		.SCRW_N(SCRW_N),
		.SCAS_N(SCAS_N),
		.SCLDS_N(SCLDS_N),
		.SCUDS_N(SCUDS_N),
		.SCDTACK_N(SCDTACK_N),
		.SCFC(SCFC),
		.SCAVEC_N(SCAVEC_N),
		.SCIPL_N(SCIPL_N),
		
		.RAM_A(SCSP_RAM_A),
		.RAM_D(SCSP_RAM_D),
		.RAM_WE(SCSP_RAM_WE),
		.RAM_RD(SCSP_RAM_RD),
		.RAM_CS(SCSP_RAM_CS),
		.RAM_Q(SCSP_RAM_Q),
		.RAM_RFS(SCSP_RAM_RFS),
		.RAM_RDY(SCSP_RAM_RDY),
		
		.ESL(CD_SL),
		.ESR(CD_SR),
		
		.SOUND_L(SOUND_L),
		.SOUND_R(SOUND_R),
		
		
		.SND_EN(SND_EN)
	);
	
	bit M68K_RESO_N;
	fx68k M68K
	(
		.clk(CLK),
		.extReset(~SCPU_RES_N | ~M68K_RESO_N),
		.pwrUp(~RST_N),
		.enPhi1(SCCE_R),
		.enPhi2(SCCE_F),

		.eab(SCA),
		.iEdb(SCDO),
		.oEdb(SCDI),
		.eRWn(SCRW_N),
		.ASn(SCAS_N),
		.LDSn(SCLDS_N),
		.UDSn(SCUDS_N),
		.DTACKn(SCDTACK_N),

		.IPL0n(SCIPL_N[0]),
		.IPL1n(SCIPL_N[1]),
		.IPL2n(SCIPL_N[2]),

		.VPAn(SCAVEC_N),
		
		.FC0(SCFC[0]),
		.FC1(SCFC[1]),
		.FC2(SCFC[2]),

		.BGn(),
		.BRn(1),
		.BGACKn(1),

		.BERRn(1),
		.HALTn(1),
		
		.oRESETn(M68K_RESO_N)
	);

	
	
`ifdef CD_HLE
	//CD: high-level emulation of the CD block (SH-1 and its firmware, YGR019, the drive)
	bit SHCLK;
	always @(posedge CLK) begin
		if (CD_CE) SHCLK <= ~SHCLK;
	end
	wire SHCE_R = SHCLK & CD_CE;

	// the firmware's timer, 44100 x 256 Hz = SCSP_CE / 2, and the CD-DA samples, 44.1 kHz = SCSP_CE / 512
	bit [8:0] CDB_TDIV;
	always @(posedge CLK) begin
		if (SCSP_CE) CDB_TDIV <= CDB_TDIV + 9'd1;
	end
	wire CDB_TCE = SCSP_CE & CDB_TDIV[0];
	wire CDB_ACE = SCSP_CE & (CDB_TDIV == 9'h1FF);

	bit YGR019_AWAIT_N;
	CDB_HLE
`ifdef CD_EXTIO
	// the Pocket: the firmware with the disc source (fw/cdb: build.sh SMPC_FW=1 CD_SRC=1) in two RAM banks, 20480 +
	// 2048 words (88 KB; Quartus maps this byte-enabled RAM in 4096-word groups of 16 M10K: a second bank of 2048 words
	// costs 8 M10K where growing the one RAM would cost 16)
	#(.FW_FILE("rtl/Saturn/CD/cdb_hle_pocket_fw.hex"), .RAM_WORDS(22528),
	  .RAM_BANK0(20480), .FW_FILE1("rtl/Saturn/CD/cdb_hle_pocket_fw_1.hex"))
`else
`ifdef SMPC_FW
	#(.FW_FILE("rtl/Saturn/CD/cdb_hle_smpc_fw.hex"), .RAM_WORDS(20480))
`endif
`endif
	cdb
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.RES_N(CDRES_N),

		.CE_R(SYS_CE_R),
		.CE_F(SYS_CE_F),
		.SHCE_R(SHCE_R),
		.TCE(CDB_TCE),
		.ACE(CDB_ACE),

		.AA(AA[14:1]),
		.ADI(ADO),
		.ADO(CD_DO),
		.ACS2_N(ACS2_N),
		.ARD_N(ARD_N),
		.AWRL_N(AWRL_N),
		.AWRU_N(AWRU_N),
		.AWAIT_N(YGR019_AWAIT_N),
		.ARQT_N(ARQT_N),

		.DISC_IN(CD_DISC_IN),
		.SEC_REQ(CD_SEC_REQ),
		.SEC_LBA(CD_SEC_LBA),
		.SEC_WR(CD_SEC_WR),
		.SEC_DATA(CD_SEC_DATA),
		.SEC_WAIT(CD_SEC_WAIT),

		.CD_RAM_A(CD_RAM_A),
		.CD_RAM_D(CD_RAM_D),
		.CD_RAM_WE(CD_RAM_WE),
		.CD_RAM_RD(CD_RAM_RD),
		.CD_RAM_CS(CD_RAM_CS),
		.CD_RAM_Q(CD_RAM_Q),
		.CD_RAM_RDY(CD_RAM_RDY),

		.CD_SL(CD_SL),
		.CD_SR(CD_SR),

`ifdef SMPC_FW
		.SMPC_A(SMPC_FW_A),
		.SMPC_WE(SMPC_FW_WE),
		.SMPC_WD(SMPC_FW_WD),
		.SMPC_RD(SMPC_FW_RD),
`endif
`ifdef CD_EXTIO
		.EXT_A(CD_EXT_A),
		.EXT_WE(CD_EXT_WE),
		.EXT_WD(CD_EXT_WD),
		.EXT_RD(CD_EXT_RD),
`endif
		.FAST(FAST)
	);
`else
`ifdef CDB_FEMTORV
	// CDB_FEMTORV selects the CPU of the CD block HLE (rtl/Saturn/CD/CDB_HLE.sv)
	CDB_FEMTORV_needs_CD_HLE error_CDB_FEMTORV_without_CD_HLE();
`endif
	//CD
	bit [21:0] SA;
	bit [15:0] SDI;
	bit [15:0] SDO;
	bit        SWRL_N;
	bit        SWRH_N;
	bit        SRD_N;
	bit        SCS1_N;
	bit        SCS2_N;
	bit        SCS6_N;
	bit        SWAIT_N;
	bit        DACK0;
	bit        DACK1;
	bit        DREQ0_N;
	bit        DREQ1_N;
	bit        SIRQL_N;
	bit        SIRQH_N;
	
	bit [15:0] YGR019_SDO;
	
	bit SHCLK;
	bit SHCE_R, SHCE_F;
	always @(posedge CLK) begin
		if (CD_CE) SHCLK <= ~SHCLK;
	end
	assign SHCE_R =  SHCLK & CD_CE;
	assign SHCE_F = ~SHCLK & CD_CE;
	
	SH1 #("rtl/cdb105m.mif") sh1
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(SHCE_R),
		.CE_F(SHCE_F),
		.EN(EN),
		
		.RES_N(CDRES_N),
		
		.A(SA),
		.DI(SDI),
		.DO(SDO),
		
		.CS1N_CASHN(SCS1_N),//in original CASH_N
		.CS2N(SCS2_N),
		.CS6N(SCS6_N),
		.WRLN(SWRL_N),
		.WRHN(SWRH_N),
		.RDN(SRD_N),
		.WAITN(SWAIT_N),
		
		.IRQ6N(SIRQL_N),
		.IRQ7N(SIRQH_N),
		
		.DACK0(DACK0),
		.DACK1(DACK1),
		.DREQ0N(DREQ0_N),
		.DREQ1N(DREQ1_N),
		
		.RXD0(CD_CDATA),
		.TXD0(CD_HDATA),
		.SCK0O(CD_COMCLK),
		.PB2I(CD_COMSYNC_N),
		.TIOCB3(CD_COMREQ_N),
		.PB6O(CD_DEMP),
		
		.TIOCA0(1'b0),//MPEG
		.TIOCA1(1'b0),//MPEG
		.TIOCA2(1'b1),//MPEGA_IRQ_N
		.TIOCB2(1'b1)//MPEGV_IRQ_N
	);
	
	assign SDI = !SCS1_N ? CD_RAM_Q : YGR019_SDO;
	
	bit YGR019_AWAIT_N;
	bit [15:0] DBG_SEC_SUM;
	bit DBG_SEC_END;
	YGR019 ygr 
	(
		.CLK(CLK),
		.RST_N(RST_N),
		
		.RES_N(CDRES_N),
		
		.CE_R(SYS_CE_R),
		.CE_F(SYS_CE_F),
		.AA(AA[14:1]),
		.ADI(ADO),
		.ADO(CD_DO),
		.AFC(AFC),
		.ACS2_N(ACS2_N),
		.ARD_N(ARD_N),
		.AWRL_N(AWRL_N),
		.AWRU_N(AWRU_N),
		.ATIM0_N(ATIM0_N),
		.ATIM2_N(ATIM2_N),
		.AWAIT_N(YGR019_AWAIT_N),
		.ARQT_N(ARQT_N),
		
		.SHCE_R(SHCE_R),
		.SHCE_F(SHCE_F),
		.SA(SA[21:1]),
		.SDI(SDO),
		.SDO(YGR019_SDO),
		.BDI(CD_RAM_Q),
		.SWRL_N(SWRL_N),
		.SWRH_N(SWRH_N),
		.SRD_N(SRD_N),
		.SCS2_N(SCS2_N),
		.SCS6_N(SCS6_N),
		.SIRQL_N(SIRQL_N),
		.SIRQH_N(SIRQH_N),
		
		.DACK0(DACK0),
		.DACK1(DACK1),
		.DREQ0_N(DREQ0_N),
		.DREQ1_N(DREQ1_N),
		
		.CD_D(CD_D),
		.CD_CK(CD_CK),
		.CD_AUDIO(CD_AUDIO),
		
		.CD_SL(CD_SL),
		.CD_SR(CD_SR),
		
		.FAST(FAST)
	);
	
	assign SWAIT_N = CD_RAM_RDY;
	
	assign CD_RAM_A = SA[18:1];
	assign CD_RAM_D = !DACK0 || !DACK1 ? YGR019_SDO : SDO;
	assign CD_RAM_CS = ~SCS1_N;
	assign CD_RAM_WE = ~{SWRH_N,SWRL_N};
	assign CD_RAM_RD = ~SRD_N;
`endif
	
	
	bit  [15: 0] CART_DO;
	bit          CART_AWAIT_N;
	CART cart 
	(
		.CLK(CLK),
		.RST_N(RST_N),
		
		.MODE(CART_MODE),
		
		.RES_N(SYSRES_N),
		
		.CE_R(SYS_CE_R),
		.CE_F(SYS_CE_F),
		.AA(AA),
		.ADI(ADO),
		.ADO(CART_DO),
		.AFC(AFC),
		.ACS0_N(ACS0_N),
		.ACS1_N(ACS1_N),
		.ACS2_N(ACS2_N),
		.ARD_N(ARD_N),
		.AWRL_N(AWRL_N),
		.AWRU_N(AWRU_N),
		.ATIM0_N(ATIM0_N),
		.ATIM2_N(ATIM2_N),
		.AWAIT_N(CART_AWAIT_N),
		.ARQT_N(),
		
		.MEM_A(CART_MEM_A),
		.MEM_DO(CART_MEM_D),
		.MEM_DI(CART_MEM_Q),
		.MEM_WE(CART_MEM_WE),
		.MEM_RD(CART_MEM_RD),
		.MEM_RDY(CART_MEM_RDY)
		
	);
	
endmodule
`ifdef U3_ANY
`undef U3_ANY
`endif
`ifdef U4_ANY
`undef U4_ANY
`endif
`ifdef U5_ANY
`undef U5_ANY
`endif
