module LUT4 #(
	parameter [15:0] INIT = 0
) (
	input A, B, C, D,
	output Z
);
	wire [3:0] I;
	wire [3:0] I_pd;

	genvar ii;
	generate
		for (ii = 0; ii < 4; ii = ii + 1'b1)
			assign I_pd[ii] = (I[ii] === 1'bz) ? 1'b0 : I[ii];
	endgenerate

	assign I = {D, C, B, A};
	assign Z = INIT[I_pd];
endmodule

module FACADE_FF #(
	parameter GSR = "ENABLED",
	parameter CEMUX = "1",
	parameter CLKMUX = "0",
	parameter LSRMUX = "LSR",
	parameter LSRONMUX = "LSRMUX",
	parameter SRMODE = "LSR_OVER_CE",
	parameter REGSET = "SET",
	parameter REGMODE = "FF"
) (
	input CLK, DI, LSR, CE,
	output reg Q
);

	wire muxce;
	generate
		case (CEMUX)
			"1": assign muxce = 1'b1;
			"0": assign muxce = 1'b0;
			"INV": assign muxce = ~CE;
			default: assign muxce = CE;
		endcase
	endgenerate

	wire muxlsr = (LSRMUX == "INV") ? ~LSR : LSR;
	wire muxlsron = (LSRONMUX == "LSRMUX") ? muxlsr : 1'b0;
	wire muxclk = (CLKMUX == "INV") ? ~CLK : CLK;
	wire srval = (REGSET == "SET") ? 1'b1 : 1'b0;

	initial Q = srval;

	generate
		if (REGMODE == "FF") begin
			if (SRMODE == "ASYNC") begin
				always @(posedge muxclk, posedge muxlsron)
					if (muxlsron)
						Q <= srval;
					else if (muxce)
						Q <= DI;
			end else begin
				always @(posedge muxclk)
					if (muxlsron)
						Q <= srval;
					else if (muxce)
						Q <= DI;
			end
		end else if (REGMODE == "LATCH") begin
			ERROR_UNSUPPORTED_FF_MODE error();
		end else begin
			ERROR_UNKNOWN_FF_MODE error();
		end
	endgenerate
endmodule

/* For consistency with ECP5; represents F0/F1 => OFX0 mux in a slice. */
module PFUMX (input ALUT, BLUT, C0, output Z);
	assign Z = C0 ? ALUT : BLUT;
endmodule

/* For consistency with ECP5; represents FXA/FXB => OFX1 mux in a slice. */
module L6MUX21 (input D0, D1, SD, output Z);
	assign Z = SD ? D1 : D0;
endmodule

/* For consistency, input order matches TRELLIS_SLICE even though the BELs in
prjtrellis were filled in clockwise order from bottom left. */
module FACADE_SLICE #(
	parameter MODE = "LOGIC",
	parameter GSR = "ENABLED",
	parameter SRMODE = "LSR_OVER_CE",
	parameter CEMUX = "1",
	parameter CLKMUX = "0",
	parameter LSRMUX = "LSR",
	parameter LSRONMUX = "LSRMUX",
	parameter LUT0_INITVAL = 16'hFFFF,
	parameter LUT1_INITVAL = 16'hFFFF,
	parameter REG0_SD = "1",
	parameter REG1_SD = "1",
	parameter REG0_REGSET = "SET",
	parameter REG1_REGSET = "SET",
	parameter REG0_REGMODE = "FF",
	parameter REG1_REGMODE = "FF",
	parameter CCU2_INJECT1_0 = "YES",
	parameter CCU2_INJECT1_1 = "YES",
	parameter WREMUX = "INV"
) (
	input A0, B0, C0, D0,
	input A1, B1, C1, D1,
	input M0, M1,
	input FCI, FXA, FXB,

	input CLK, LSR, CE,
	input DI0, DI1,

	input WD0, WD1,
	input WAD0, WAD1, WAD2, WAD3,
	input WRE, WCK,

	output F0, Q0,
	output F1, Q1,
	output FCO, OFX0, OFX1,

	output WDO0, WDO1, WDO2, WDO3,
	output WADO0, WADO1, WADO2, WADO3
);

	generate
		if (MODE == "LOGIC") begin
			L6MUX21 FXMUX (.D0(FXA), .D1(FXB), .SD(M1), .Z(OFX1));

			wire k0;
			wire k1;
			PFUMX K0K1MUX (.ALUT(k1), .BLUT(k0), .C0(M0), .Z(OFX0));

			LUT4 #(.INIT(LUT0_INITVAL)) LUT_0 (.A(A0), .B(B0), .C(C0), .D(D0), .Z(k0));
			LUT4 #(.INIT(LUT1_INITVAL)) LUT_1 (.A(A0), .B(B0), .C(C0), .D(D0), .Z(k1));

			assign F0 = k0;
			assign F1 = k1;
		end else if (MODE == "CCU2") begin
			ERROR_UNSUPPORTED_SLICE_MODE error();
		end else if (MODE == "DPRAM") begin
			ERROR_UNSUPPORTED_SLICE_MODE error();
		end else begin
			ERROR_UNKNOWN_SLICE_MODE error();
		end
	endgenerate

	/* Reg can be fed either by M, or DI inputs; DI inputs muxes OFX and F
	outputs (in other words, feeds back into FACADE_SLICE). */
	wire di0 = (REG0_SD == "1") ? M0 : DI0;
	wire di1 = (REG0_SD == "1") ? M1 : DI1;

	FACADE_FF#(.GSR(GSR), .CEMUX(CEMUX), .CLKMUX(CLKMUX), .LSRMUX(LSRMUX),
		.LSRONMUX(LSRONMUX), .SRMODE(SRMODE), .REGSET(REG0_REGSET),
		.REGMODE(REG0_REGMODE)) REG_0 (.CLK(CLK), .DI(di0), .LSR(LSR), .CE(CE), .Q(Q0));
	FACADE_FF#(.GSR(GSR), .CEMUX(CEMUX), .CLKMUX(CLKMUX), .LSRMUX(LSRMUX),
		.LSRONMUX(LSRONMUX), .SRMODE(SRMODE), .REGSET(REG1_REGSET),
		.REGMODE(REG1_REGMODE)) REG_1 (.CLK(CLK), .DI(di1), .LSR(LSR), .CE(CE), .Q(Q1));
endmodule

module FACADE_IO #(
	parameter DIR = "INPUT"
) (
	inout PAD,
	input I, EN,
	output O
);
	generate
		if (DIR == "INPUT") begin
			assign O = PAD;
		end else if (DIR == "OUTPUT") begin
			assign PAD = EN ? I : 1'bz;
		end else if (DIR == "BIDIR") begin
			assign PAD = EN ? I : 1'bz;
			assign O = PAD;
		end else begin
			ERROR_UNKNOWN_IO_MODE error();
		end
	endgenerate
endmodule
