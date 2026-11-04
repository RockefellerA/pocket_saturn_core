package SCSP_PKG;

	//Slot control registers, offset 100000+n*20
	typedef struct packed		//RW,00
	{
		bit [ 2: 0] UNUSED;
		bit         KX;		//WO
		bit         KB;		//RW
		bit [ 1: 0] SBCTL;	//RW
		bit [ 1: 0] SSCTL;	//RW
		bit [ 1: 0] LPCTL;	//RW
		bit         PCM8B;	//RW
		bit [ 3: 0] SAH;		//RW
	} SCR0_t;
	parameter bit [15:0] SCR0_MASK = 16'h0FFF;
	
	typedef bit [15:0] SA_t;	//RW,02
	parameter bit [15:0] SA_MASK = 16'hFFFF;
	
	typedef bit [15:0] LSA_t;	//RW,04
	parameter bit [15:0] LSA_MASK = 16'hFFFF;
	
	typedef bit [15:0] LEA_t;	//RW,06
	parameter bit [15:0] LEA_MASK = 16'hFFFF;
	
	typedef struct packed		//RW,08
	{
		bit [ 4: 0] D2R;
		bit [ 4: 0] D1R;
		bit         EGHOLD;
		bit [ 4: 0] AR;
	} SCR1_t;
	parameter bit [15:0] SCR1_MASK = 16'hFFFF;
	
	typedef struct packed		//RW,0A
	{
		bit         EGBP;
		bit         LPSLNK;
		bit [ 3: 0] KRS;
		bit [ 4: 0] DL;
		bit [ 4: 0] RR;
	} SCR2_t;
	parameter bit [15:0] SCR2_MASK = 16'hFFFF;
	
	typedef struct packed		//RW,0C
	{
		bit [ 5: 0] UNUSED;
		bit         STWINH;
		bit         SDIR;
		bit [ 7: 0] TL;
	} SCR3_t;
	parameter bit [15:0] SCR3_MASK = 16'h0FFF;
	
	typedef struct packed		//RW,0E
	{
		bit [ 3: 0] MDL;
		bit [ 5: 0] MDXSL;
		bit [ 5: 0] MDYSL;
	} SCR4_t;
	parameter bit [15:0] SCR4_MASK = 16'hFFFF;
	
	typedef struct packed		//RW,10
	{
		bit         MSK;
		bit [ 3: 0] OCT;
		bit [10: 0] FNS;
	} SCR5_t;
	parameter bit [15:0] SCR5_MASK = 16'hFFFF;
	
	typedef struct packed		//RW,12
	{
		bit         LFORE;
		bit [ 4: 0] LFOF;
		bit [ 1: 0] PLFOWS;
		bit [ 2: 0] PLFOS;
		bit [ 1: 0] ALFOWS;
		bit [ 2: 0] ALFOS;
	} SCR6_t;
	parameter bit [15:0] SCR6_MASK = 16'hFFFF;
	
	typedef struct packed		//RW,14
	{
		bit [ 8: 0] UNUSED;
		bit [ 3: 0] ISEL;
		bit [ 2: 0] IMXL;
	} SCR7_t;
	parameter bit [15:0] SCR7_MASK = 16'h00FF;
	
	typedef struct packed		//RW,16
	{
		bit [ 2: 0] DISDL;
		bit [ 4: 0] DIPAN;
		bit [ 2: 0] EFSDL;
		bit [ 4: 0] EFPAN;
	} SCR8_t;
	parameter bit [15:0] SCR8_MASK = 16'hFFFF;
	
	//Control registers
	typedef struct packed		//RW,100400
	{
		bit [ 5: 0] UNUSED;
		bit         M4;
		bit         DB;
		bit [ 3: 0] UNUSED2;
		bit [ 3: 0] MVOL;
	} CR0_t;
	parameter bit [15:0] CR0_MASK = 16'h030F;
	
	typedef struct packed		//RW,100402
	{
		bit [ 6: 0] UNUSED;
		bit [ 1: 0] RBL;
		bit [ 6: 0] RBP;
	} CR1_t;
	parameter bit [15:0] CR1_MASK = 16'h01FF;
	
	typedef struct packed		//RW,100404
	{
		bit [ 2: 0] UNUSED;
		bit         OF;
		bit         OE;
		bit         IO;
		bit         IF;
		bit         IE;
		bit [ 7: 0] MIBUF;
	} CR2_t;
	parameter bit [15:0] CR2_MASK = 16'h1FFF;
	
	typedef struct packed		//RW,100406
	{
		bit [ 7: 0] UNUSED;
		bit [ 7: 0] MOBUF;
	} CR3_t;
	parameter bit [15:0] CR3_MASK = 16'h00FF;
	
	typedef struct packed		//RW,100408
	{
		bit [ 4: 0] MSLC;		//W
		bit [ 3: 0] CA;		//R
		bit [ 1: 0] SGC;		//R
		bit [ 4: 0] EG;		//R
	} CR4_t;
	parameter bit [15:0] CR4_RMASK = 16'h07FF;
	parameter bit [15:0] CR4_WMASK = 16'hF800;
	
	typedef struct packed		//RW,100412
	{
		bit [14: 0] DMEAL;
		bit         UNUSED;
	} CR5_t;
	parameter bit [15:0] CR5_WMASK = 16'hFFFE;
	parameter bit [15:0] CR5_RMASK = 16'h0000;
	
	typedef struct packed		//RW,100414
	{
		bit [ 3: 0] DMEAH;
		bit [10: 0] DRGA;
		bit         UNUSED;
	} CR6_t;
	parameter bit [15:0] CR6_WMASK = 16'hFFFE;
	parameter bit [15:0] CR6_RMASK = 16'h0000;
	
	typedef struct packed		//RW,100416
	{
		bit         UNUSED;
		bit         DGATE;
		bit         DDIR;
		bit         DEXE;
		bit [10: 0] DTLG;
		bit         UNUSED2;
	} CR7_t;
	parameter bit [15:0] CR7_WMASK = 16'h7FFE;
	parameter bit [15:0] CR7_RMASK = 16'h7000;
	
	typedef struct packed		//RW,100418
	{
		bit [ 4: 0] UNUSED;
		bit [ 2: 0] TACTL;
		bit [ 7: 0] TIMA;
	} CR8_t;
	parameter bit [15:0] CR8_MASK = 16'h07FF;
	
	typedef struct packed		//RW,10041A
	{
		bit [ 4: 0] UNUSED;
		bit [ 2: 0] TBCTL;
		bit [ 7: 0] TIMB;
	} CR9_t;
	parameter bit [15:0] CR9_MASK = 16'h07FF;
	
	typedef struct packed		//RW,10041C
	{
		bit [ 4: 0] UNUSED;
		bit [ 2: 0] TCCTL;
		bit [ 7: 0] TIMC;
	} CR10_t;
	parameter bit [15:0] CR10_MASK = 16'h07FF;
	
	typedef struct packed		//RW,10041E
	{
		bit [ 4: 0] UNUSED;
		bit [10: 0] SCIEB;
	} CR11_t;
	parameter bit [15:0] CR11_MASK = 16'h07FF;
	
	typedef struct packed		//RW,100420
	{
		bit [ 4: 0] UNUSED;
		bit [10: 0] SCIPD;
	} CR12_t;
	parameter bit [15:0] CR12_MASK = 16'h07FF;
	
	typedef struct packed		//RW,100422
	{
		bit [ 4: 0] UNUSED;
		bit [10: 0] SCIRE;
	} CR13_t;
	parameter bit [15:0] CR13_MASK = 16'h07FF;
	
	typedef struct packed		//RW,100424
	{
		bit [ 7: 0] UNUSED;
		bit [ 7: 0] SCILV0;
	} CR14_t;
	parameter bit [15:0] CR14_MASK = 16'h00FF;
	
	typedef struct packed		//RW,100426
	{
		bit [ 7: 0] UNUSED;
		bit [ 7: 0] SCILV1;
	} CR15_t;
	parameter bit [15:0] CR15_MASK = 16'h00FF;
	
	typedef struct packed		//RW,100428
	{
		bit [ 7: 0] UNUSED;
		bit [ 7: 0] SCILV2;
	} CR16_t;
	parameter bit [15:0] CR16_MASK = 16'h00FF;
	
	typedef struct packed		//RW,10042A
	{
		bit [ 4: 0] UNUSED;
		bit [10: 0] MCIEB;
	} CR17_t;
	parameter bit [15:0] CR17_MASK = 16'h07FF;
	
	typedef struct packed		//RW,10042C
	{
		bit [ 4: 0] UNUSED;
		bit [10: 0] MCIPD;
	} CR18_t;
	parameter bit [15:0] CR18_MASK = 16'h07FF;
	
	typedef struct packed		//RW,10042E
	{
		bit [ 4: 0] UNUSED;
		bit [10: 0] MCIRE;
	} CR19_t;
	parameter bit [15:0] CR19_MASK = 16'h07FF;
	
	typedef bit [15:0] SOUS_t;		//RW,100600-10067F
	parameter bit [15:0] SOUS_MASK = 16'hFFFF;
	
	typedef struct packed
	{
		SCR0_t      SCR0;
		SA_t        SA;
		LSA_t       LSA;
		LEA_t       LEA;
		SCR1_t      SCR1;
		SCR2_t      SCR2;
		SCR3_t      SCR3;
		SCR4_t      SCR4;
		SCR5_t      SCR5;
		SCR6_t      SCR6;
		SCR7_t      SCR7;
		SCR8_t      SCR8;
	} SCR_t;
	
//	typedef SOUS_t STACK_t[32];
	
	typedef bit [12:0]  COEF_t;		//RW,100700-10077F
	parameter bit [15:0] COEF_MASK = 16'hFFF8;
	
	typedef bit [16:1] MADRS_t;		//RW,100780-1007BF
	parameter bit [16:1] MADRS_MASK = 16'hFFFF;
	
	typedef struct packed				//RW,100800-100BFF
	{
		bit         UNUSED;
		bit [ 6: 0] TRA;
		bit         TWT;
		bit [ 6: 0] TWA;
		bit         XSEL;
		bit [ 1: 0] YSEL;
		bit         UNUSED2;
		bit [ 5: 0] IRA;
		bit         IWT;
		bit [ 4: 0] IWA;
		bit         TABLE;
		bit         MWT;
		bit         MRD;
		bit         EWT;
		bit [ 3: 0] EWA;
		bit         ADRL;
		bit         FRCL;
		bit [ 1: 0] SHFT;
		bit         YRL;
		bit         NEGB;
		bit         ZERO;
		bit         BSEL;
		bit         UNUSED3;
		bit [ 5: 0] COEF;
		bit         NOFL;
		bit         UNUSED4;
		bit [ 4: 0] MASA;
		bit         ADREB;
		bit         NXADR;
	} MPRO_t;
	parameter bit [63:0] MPRO_MASK = 64'hFFFFFFFFFFFFFFFF;
	
	typedef bit [23:0] TEMP_t;		//RW,100C00-100DFF
	parameter bit [31:0] TEMP_MASK = 32'h00FFFFFF;
	
	typedef bit [23:0] MEMS_t;		//RW,100E00-100E7F
	parameter bit [31:0] MEMS_MASK = 32'h00FFFFFF;
	
	typedef bit [19:0] MIXS_t;		//RW,100E80-100EBF
	parameter bit [31:0] MIXS_MASK = 32'h000FFFFF;
	
	typedef bit [15:0] EFREG_t;	//RW,100EC0-100EDF
	parameter bit [15:0] EFREG_MASK = 16'hFFFF;
	
	typedef MIXS_t MIXSS_t[16];
	
	
	typedef bit [1:0] EGState_t;
	parameter EGState_t EST_ATTACK  = 2'b00;
	parameter EGState_t EST_DECAY1  = 2'b01;
	parameter EGState_t EST_DECAY2  = 2'b10;
	parameter EGState_t EST_RELEASE = 2'b11;
	
	typedef struct packed
	{
		bit [ 4: 0] SLOT;	//
		bit         RST;	//
		bit         KON;	//
		bit         KOFF;	//
		bit [22: 0] PHASE;
		bit         MSK;	//
		bit [ 7: 0] ND;
	} OP2_t;
	parameter OP2_t OP2_RESET = '{5'h00,1'b0,1'b0,1'b0,23'h000000,1'b0,8'h00};
	
	typedef struct packed
	{
		bit [ 4: 0] SLOT;	//
		bit         RST;	//
		bit         KON;	//
		bit         KOFF;	//
		bit         ALLOW;
		bit         LOOP;	//Loop processing 
		bit [13: 0] PHASE_FRAC;//Phase fractional
		bit [ 7: 0] ND;
		bit [15: 0] SO;	//Sample offset
		bit [21: 0] MOD;	//Modulation
		bit [16: 0] MASK;	//Wave mask
	} OP3_t;
	parameter OP3_t OP3_RESET = '{5'h00,1'b0,1'b0,1'b0,1'b0,1'b0,14'h0000,8'h00,16'h0000,22'h000000,17'h00000};
	
	typedef struct packed
	{
		bit [ 4: 0] SLOT;	//
		bit         RST;	//
		bit         KON;	//
		bit         KOFF;	//
		bit         LOOP;//Loop processing 
		bit [ 7: 0] ND;
		bit [ 5: 0] MODF;	//Modulation fractional
		bit [ 1: 0] SSCTL;
		bit [ 1: 0] SBCTL;
	} OP4_t;
	parameter OP4_t OP4_RESET = '{5'h00,1'b0,1'b0,1'b0,1'b0,8'h00,6'h00,2'b00,2'b00};
	
	typedef struct packed
	{
		bit [ 4: 0] SLOT;	//
		bit         RST;	//
		bit         KON;	//
		bit         KOFF;	//
		bit [15: 0] WD;	//Wave form data
		bit [ 9: 0] EVOL;	//Envelope volume
		bit [ 7: 0] ALFO; //ALFO wave
	} OP5_t;
	parameter OP5_t OP5_RESET = '{5'h00,1'b0,1'b0,1'b0,16'h0000,10'h000,8'h00};
	
	typedef struct packed
	{
		bit [ 4: 0] SLOT;	//
		bit         RST;	//
		bit         KON;	//
		bit         KOFF;	//
		bit [15: 0] WD;	//Wave form data
		bit [ 9: 0] LEVEL;//Level
	} OP6_t;
	parameter OP6_t OP6_RESET = '{5'h00,1'b0,1'b0,1'b0,16'h0000,10'h000};
	
	typedef struct packed
	{
		bit [ 4: 0] SLOT;	//
		bit         RST;	//
		bit         KON;	//
		bit         KOFF;	//
		bit [15: 0] SD;	//Slot out data
		bit         STWINH;
	} OP7_t;
	parameter OP7_t OP7_RESET = '{5'h00,1'b0,1'b0,1'b0,16'h0000,1'b0};
	
	
	function bit [15:0] Interpolate(input bit [15:0] WAVE0, input bit [15:0] WAVE1, bit [5:0] PHASE);
		bit [ 6:0] PHASE_NEG;
		bit [21:0] TEMP0,TEMP1;
		bit [21:0] SUM;
		
		PHASE_NEG = 7'h40 - PHASE;
		TEMP0 = $signed(WAVE0) * PHASE_NEG;
		TEMP1 = $signed(WAVE1) * PHASE;
		SUM = $signed(TEMP0) + $signed(TEMP1);
	
		return SUM[21:6];
	endfunction
	
	function bit [15:0] SoundSel(input bit [15:0] WAVE0, input bit [15:0] WAVE1, input bit [15:0] NOISE, bit [1:0] SSCTL, bit [1:0] SBCTL, bit [5:0] PHASE);
		bit [15:0] SD;
		
		case (SSCTL)
			2'b00: SD = Interpolate(WAVE0 ^ {SBCTL[1],{15{SBCTL[0]}}}, WAVE1 ^ {SBCTL[1],{15{SBCTL[0]}}}, PHASE);
			2'b01: SD = NOISE ^ {SBCTL[1],{15{SBCTL[0]}}};
			default: SD = {SBCTL[1],{15{SBCTL[0]}}};
		endcase 
	
		return SD;
	endfunction

	// Modulation. MD = {TEMP[16:1],7'b0} >>> (16 - MDL) for MDL 5..15, so MD[16:1] = floor(TEMP[16:1] * 2^(MDL-10))
	// mod 2^16 = P[24:9] with P = TEMP[16:1] * 2^(MDL-1), a multiply by a power of two (a DSP block); MDL <= 4 multiplies
	// by 0, which gives the 0 of that case.
	function bit signed [21:0] MDCalc(bit signed [15:0] X, bit signed [15:0] Y, bit [3:0] MDL);
		bit signed [16:0] TEMP;
		bit signed [15:0] B;
		bit signed [31:0] P;
		
		TEMP = $signed({X[15],X[15:0]}) + $signed({Y[15],Y[15:0]}); 
		B = MDL > 4'd4 ? 16'sd1 << (MDL - 4'd1) : 16'sd0;
		P = $signed(TEMP[16:1]) * B;
		
		return {{5{P[24]}},P[24:9],1'b0};
	endfunction
	
	// LFO step period: ((8 - LFOF[1:0]) * 128 >> LFOF[4:2]) - 5, as a table
	function bit [9:0] LFOFreqDiv(bit [4:0] LFOF);
		bit [9:0] RET;
		
		case (LFOF)
			5'd0: RET = 10'd1019;
			5'd1: RET = 10'd891;
			5'd2: RET = 10'd763;
			5'd3: RET = 10'd635;
			5'd4: RET = 10'd507;
			5'd5: RET = 10'd443;
			5'd6: RET = 10'd379;
			5'd7: RET = 10'd315;
			5'd8: RET = 10'd251;
			5'd9: RET = 10'd219;
			5'd10: RET = 10'd187;
			5'd11: RET = 10'd155;
			5'd12: RET = 10'd123;
			5'd13: RET = 10'd107;
			5'd14: RET = 10'd91;
			5'd15: RET = 10'd75;
			5'd16: RET = 10'd59;
			5'd17: RET = 10'd51;
			5'd18: RET = 10'd43;
			5'd19: RET = 10'd35;
			5'd20: RET = 10'd27;
			5'd21: RET = 10'd23;
			5'd22: RET = 10'd19;
			5'd23: RET = 10'd15;
			5'd24: RET = 10'd11;
			5'd25: RET = 10'd9;
			5'd26: RET = 10'd7;
			5'd27: RET = 10'd5;
			5'd28: RET = 10'd3;
			5'd29: RET = 10'd2;
			5'd30: RET = 10'd1;
			5'd31: RET = 10'd0;
		endcase
		return RET;
	endfunction
	
	function bit [7:0] ALFOCalc(bit [7:0] DATA, bit [7:0] NOISE, bit [1:0] ALFOWS, bit [2:0] ALFOS);
		bit [7:0] WAVE;
		bit [7:0] RET;
		bit [15:0] P;
		
		case (ALFOWS)
			2'b00: WAVE = DATA;
			2'b01: WAVE = {8{DATA[7]}};
			2'b10: WAVE = {DATA[6:0] ^ {7{DATA[7]}},1'b0};
			2'b11: WAVE = NOISE;
		endcase
		
		//(WAVE&FE) >> (7 - ALFOS) as a multiply by 2^ALFOS (a DSP block), the product's bits 14:7; ALFOS = 0 multiplies by 0
		P = (WAVE&8'hFE) * (ALFOS ? 8'd1 << ALFOS : 8'd0);
		RET = P[14:7];
		
		return RET;
	endfunction
	
	function bit [7:0] PLFOCalc(bit [7:0] DATA, bit [7:0] NOISE, bit [1:0] PLFOWS, bit [2:0] PLFOS);
		bit [7:0] WAVE;
		bit [7:0] RET;
		bit signed [16:0] P;
		
		case (PLFOWS)
			2'b00: WAVE = DATA;
			2'b01: WAVE = { DATA[7],{7{~DATA[7]}} };
			2'b10: WAVE = { {1'b0,DATA[5:0]^{6{DATA[6]}}} ^ {7{DATA[7]}},1'b0 };
			2'b11: WAVE = NOISE ^ 8'h80;
		endcase
		
		//the arithmetic shift by 7 - PLFOS as a signed multiply by 2^PLFOS (a DSP block): floor(W * 2^PLFOS / 128), the
		//product's bits 14:7 (|W * 2^PLFOS| <= 2^14); PLFOS = 0 multiplies by 0
		P = $signed(WAVE&8'hFE) * $signed({1'b0,PLFOS ? 8'd1 << PLFOS : 8'd0});
		RET = P[14:7];
		
		return RET;
	endfunction
	
	// PhaseCalc(SCR5, PLFO_WAVE) = PhaseShift(PhaseSum(SCR5, PLFO_WAVE), SCR5.OCT): the frequency with its pitch LFO
	// term (12 bits), and its octave shift, done as a multiply by a power of two (a DSP block).
	function bit [11:0] PhaseSum(SCR5_t SCR5, bit signed [7:0] PLFO_WAVE);
		bit [10:0] F;
		bit [14:0] TEMP;
		bit [11:0] FM;
		
		F = 11'h400 + SCR5.FNS;
		TEMP = $signed(PLFO_WAVE) * F[10:4];
		FM = {{3{TEMP[14]}},TEMP[14:6]};
		
		return {1'b0,F}+FM;
	endfunction
	
	function bit [22:0] PhaseShift(bit [11:0] SUM, bit [3:0] OCT);
		bit [27:0] P;
		
		P = SUM * (16'd1 << (OCT^4'h8));	//{15'b0,SUM}<<S, S = OCT^8; SUM*2^S < 2^27
		
		return P[26:4];
	endfunction
	
	function bit [16:0] WaveMask(bit [15:0] LEA);
		bit [16:0] RET;
		
		RET = 17'h1FFFF;
		if (LEA[10]) RET = 17'h003FF;
		if (LEA[ 9]) RET = 17'h001FF;
		if (LEA[ 8]) RET = 17'h000FF;
		if (LEA[ 7]) RET = 17'h0007F;
		
		return RET;
	endfunction
	
	function bit [5:0] EffRateCalc(bit [4:0] RATE, bit [3:0] KRS, bit [3:0] OCT);
		bit [4:0] RES;
		bit [5:0] TEMP;
		bit [3:0] KEY_EG_SCALE;
		bit [5:0] TEMP2;
		bit [4:0] RATE_SCALE,RATE_SCALE2;
		
		TEMP = {2'b00,KRS} + {OCT[3],OCT[3],OCT};
		if (KRS == 4'hF) 
			KEY_EG_SCALE = '0;
		else
			KEY_EG_SCALE = TEMP[5] ? 4'h0 : TEMP[4] ? 4'hF : TEMP[3:0];
		
		TEMP2 = {1'b0,RATE} + {2'b00,KEY_EG_SCALE};
		RES = TEMP2[5] ? 5'h1F : TEMP2[4:0];
			
		return {TEMP2[5],RES};
	endfunction
	
	function bit [3:0] EffRateBit(bit [4:0] ERATE);
		bit [4:0] TEMP;

		TEMP = 5'h18 - (ERATE > 5'h18 ? 5'h18 : ERATE[4:0]);
			
		return TEMP[4:1];
	endfunction
	
	function bit [9:0] LevelAddALFO(bit [9:0] LEVEL, bit [7:0] ALFO);
		bit [10:0] SUM;
		
		SUM = {1'b0,LEVEL} + {3'b000,ALFO};
		
		return !SUM[10] ? SUM[9:0] : 10'h3FF;
	endfunction
	
	function bit [9:0] LevelAddTL(bit [9:0] LEVEL, bit [7:0] TL);
		bit [10:0] SUM;
		
		SUM = {1'b0,LEVEL} + {1'b0,TL,2'b00};
		
		return !SUM[10] ? SUM[9:0] : 10'h3FF;
	endfunction
	
	// The shift by LEVEL[9:6] is a multiply by a power of two (a DSP block): floor(V / 2^L) = (V * 2^(15-L)) >>> 15.
	function bit signed [15:0] VolCalc(bit signed [15:0] WAVE, bit [9:0] LEVEL);
		bit [22:0] MULT;
		bit signed [16:0] B;
		bit signed [32:0] P;
		
		MULT = $signed(WAVE) * ({2'b01,~LEVEL[5:0]});
		B = 17'sd1 << (4'd15 - LEVEL[9:6]);
		P = $signed(MULT[22:7]) * B;
		
		return P[30:15];
	endfunction
	
	function bit signed [15:0] LevelCalc(bit signed [15:0] WAVE, bit [2:0] SDL);
		return SDL ? $signed($signed(WAVE)>>>(~SDL)) : 16'sh0000;
	endfunction
	
	function bit signed [15:0] PanLCalc(bit signed [15:0] WAVE, bit [4:0] PAN);
		bit [15:0] TEMP;
		
		TEMP = $signed($signed(WAVE)>>>PAN[3:1]);
		return !PAN[4] ? $signed(TEMP) - (PAN[0] ? $signed($signed(TEMP)>>>2) : '0) : WAVE;
	endfunction
	
	function bit signed [15:0] PanRCalc(bit signed [15:0] WAVE, bit [4:0] PAN);
		bit [15:0] TEMP;
		
		TEMP = $signed($signed(WAVE)>>>PAN[3:1]);
		return  PAN[4] ? $signed(TEMP) - (PAN[0] ? $signed($signed(TEMP)>>>2) : '0) : WAVE;
	endfunction
	
	// Level and pan of the OP7 stage: {DSPLevelCalc({WAVE,4'h0},SDL), T, Y} with T = LevelCalc(WAVE,SDL) =
	// DSPLevelCalc({WAVE,4'h0},SDL)[19:4] and Y its attenuated side: PanLCalc(T,PAN) = !PAN[4] ? Y : T,
	// PanRCalc(T,PAN) = PAN[4] ? Y : T. Both shifts are multiplies by powers of two (DSP
	// blocks): {WAVE,4'h0} >>> ~SDL = floor(WAVE * 2^SDL / 2^3) and T >>> PAN[3:1] = floor(WAVE * 2^(SDL+7-PAN[3:1]) / 2^14);
	// SDL = 0 multiplies by 0. X >>> 2 = P2 >>> 16.
	function bit [51:0] LevelPanCalc(bit signed [15:0] WAVE, bit [2:0] SDL, bit [4:0] PAN);
		bit signed [ 8:0] B1;
		bit signed [15:0] B2;
		bit signed [24:0] P1;
		bit signed [31:0] P2;
		bit        [15:0] T,X,Y;
		
		B1 = SDL ? 9'sd1 << SDL : 9'sd0;
		B2 = SDL ? 16'sd1 << ({1'b0,SDL} + 4'd7 - {1'b0,PAN[3:1]}) : 16'sd0;
		P1 = WAVE * B1;
		P2 = WAVE * B2;
		T = P1[22:7];
		X = P2[29:14];
		Y = X - (PAN[0] ? P2[31:16] : 16'h0000);
		
		return {P1[22:3], T, Y};
	endfunction
	
	function bit signed [19:0] DSPLevelCalc(bit signed [19:0] WAVE, bit [2:0] SDL);
		return SDL ? $signed($signed(WAVE)>>>(~SDL)) : 20'sh0000;
	endfunction
	
	// Master volume. The shift is a multiply by a power of two (a DSP block): TEMP1 = DAC18B ? WAVE<<<2 : WAVE is
	// A*4^DAC18B with A = WAVE, or WAVE[15:0] sign-extended when DAC18B (<<<2 drops the top two bits), so
	// TEMP2 = TEMP1 >>> ~MVOL[3:1] = floor(A * 2^(MVOL[3:1] + 2*DAC18B) / 2^7) = P[24:7] (|P| <= 2^24), and
	// TEMP2 >>> 2 = P[26:9]. MVOL = 0 multiplies by 0, which gives the TEMP3 = 0 of that case.
	function bit signed [15:0] MVolCalc(bit signed [17:0] WAVE, bit [3:0] MVOL, bit DAC18B);
		bit signed [17:0] A;
		bit signed [10:0] B;
		bit signed [28:0] P;
		bit [17:0] TEMP3;
		
		A = DAC18B ? {{2{WAVE[15]}},WAVE[15:0]} : WAVE;
		for (int n = 0; n < 11; n++) B[n] = MVOL != 4'd0 && {1'b0,MVOL[3:1]} + {2'b00,DAC18B,1'b0} == n;	//MVOL ? 1 << (MVOL[3:1] + 2*DAC18B) : 0
		P = A * B;
		TEMP3 = P[24:7] - (!MVOL[0] ? P[26:9] : 18'h00000);
		
		return TEMP3[17] && TEMP3[16:15] != 2'b11 ? 16'h8000 : !TEMP3[17] && TEMP3[16:15] != 2'b00 ? 16'h7FFF : TEMP3[15:0];
	endfunction
	
	function bit [25:0] DSPMult(bit [23:0] X, bit [12:0] Y);
		bit [37:0] M;
		
		M = $signed(X) * $signed(Y);
		return M[37:12];
	endfunction
	
	function bit [23:0] DSPShifter(bit [25:0] A, bit [1:0] SHFT);
		bit [25:0] TEMP;
		bit [23:0] RES;
		
		case (SHFT)
			2'b00,
			2'b11: TEMP = A[25:0];
			2'b01,
			2'b10: TEMP = {A[24:0],1'b0};
		endcase
		
		RES = !SHFT[1] && !TEMP[25] && TEMP[24:23] != 2'b00 ? 24'h7FFFFF : 
		      !SHFT[1] &&  TEMP[25] && TEMP[24:23] != 2'b11 ? 24'h800000 : 
				TEMP[23:0];
				
		return RES;
	endfunction
	
	function bit [15:0] DSPItoF(bit [23:0] I);
		bit         SIGN;
		bit [ 3: 0] EXP;
		bit [10: 0] MANT;
		bit [22: 0] T0,T1,T2,T3;
		bit [ 3: 0] E1,E2,E3;
		
		SIGN = I[23];
		
		T0 = I[22:0] ^ {23{SIGN}};
		{E1,T1} = T0[22:19] != 4'b0000 ? {4'h0,T0[22:0]} : T0[18:15] != 4'b0000 ? {4'h4,T0[18:0],4'h0} : {4'h8,T0[14:0],4'h0,4'h0};
		{E2,T2} = T1[22:21] != 2'b00 ? {4'h0,T1[22:0]} : {4'h2,T1[20:0],2'h0};
		{E3,T3} = T2[22:22] != 1'b0 ? {4'h0,T2[22:0]} : T2[21:21] != 1'b0 ? {4'h1,T2[21:0],1'h0} : {4'h2,T2[21:0],1'h0};
		
		EXP = E1 + E2 + E3;
		MANT = T3[21:11] ^ {11{SIGN}};
		
		return {SIGN,EXP,MANT};
	endfunction
	
	// DSP memory input: NOFL ? {F,8'h00} : DSPFtoI(F), as one multiply (a DSP block). DSPFtoI is
	// {SIGN,~SIGN,MANT,11'h000} >>> EXP = {SIGN,~SIGN,MANT} * 2^(11-EXP) for EXP <= 11 (exact), and {SIGN,MANT}
	// sign-extended (* 1) for EXP >= 12; {F,8'h00} is F * 256.
	function bit [23:0] DSPInCalc(bit [15:0] F, bit NOFL);
		bit               SIGN,BIG;
		bit        [ 3:0] EXP;
		bit signed [15:0] A;
		bit signed [12:0] B;
		bit signed [28:0] P;
		
		{SIGN,EXP} = F[15:11];
		BIG = EXP >= 4'd12;
		A = NOFL ? F : {{4{SIGN}},BIG ? SIGN : ~SIGN,F[10:0]};
		B = NOFL ? 13'sd256 : BIG ? 13'sd1 : 13'sd1 << (4'd11 - EXP);
		P = A * B;
		
		return P[23:0];
	endfunction
	
	function bit [23:0] DSPFtoI(bit [15:0] F);
		bit         SIGN;
		bit [ 3: 0] EXP;
		bit [10: 0] MANT;
		bit [23: 0] RES;
	
		{SIGN,EXP,MANT} = F;
		
		if (EXP >= 4'd12)
			RES = {{12{SIGN}},SIGN,MANT};
		else
			RES = $signed($signed({SIGN,~SIGN,MANT,11'h000}) >>> EXP);
	
		return RES;
	endfunction
	
endpackage
