// Ginga Ninkyouden sound board (docs/PLAN.md 1.3, 2.5): an MC6809 on the
// 3.579545 MHz crystal (E = /4), 2 KB of RAM, the MC6840 whose output 1 is
// the 6809's IRQ, the sound latch whose write pulses NMI, a YM2149 and a
// Y8950 (both write-only in MAME's map).
//
// Map (ginganin.cpp:390-398):
//   0000-07FF  RAM              0800-0807  MC6840
//   1800       latch read       2000-2001  Y8950 address / data (write)
//   2800-2801  YM2149 address / data (write)
//   4000-FFFF  ROM (rom_* port, gn_05 at the same offsets)
// Unmapped reads return 0 (Q7).
//
// Clocks from clk_sys (48 MHz): ce_q4 is a 3.579545 MHz enable from an exact
// rational accumulator (715909 / 9600000; MS1-28: wide enough); four of them
// make one E cycle, with falling E at phase 0 and falling Q at phase 3, the
// phase generator Time Pilot 84's sound 6809 uses. The Y8950 runs on ce_q4,
// the YM2149 on every second one (1.79 MHz), the PTM on E.
module gn_sound (
	input             clk,
	input             reset,
	input             pause,
	// program ROM, 0x4000-0xFFFF of gn_05: data the clock after the address
	output     [15:0] rom_addr,
	input      [7:0]  rom_data,
	// the latch from the main CPU (vregs[7])
	input             cmd_we,
	input      [7:0]  cmd,
	// the Y8950's ADPCM ROM (byte address in the 128 KB region), held request
	output            adpcm_req,
	output     [23:0] adpcm_addr,
	input             adpcm_ack,
	input      [7:0]  adpcm_data,
	// audio: MAME's mix (Y8950 at 1.0, each YM2149 channel at 0.10)
	output reg signed [15:0] snd,
	output signed [15:0] dbg_opl,    // the Y8950 alone (after its DAC round trip)
	output     [12:0] dbg_psg,       // the YM2149 alone, in WAV units (0-4875)
	// debug
	output     [15:0] dbg_pc_addr,
	output reg [31:0] dbg_nmi,
	output reg [31:0] dbg_irq,
	output reg [31:0] dbg_ptm_writes,
	output reg [31:0] dbg_latch_reads,
	output            dbg_wr,       // one clock per 6809 write (falling E), for bus traces
	output     [15:0] dbg_waddr,
	output     [7:0]  dbg_wdata,
	output            dbg_rnw,
	output     [7:0]  dbg_di,
	output            dbg_fallE,
	output            dbg_nmi_n
);
	// ---------------------------------------------------------------- clocks
	reg  [23:0] acc = 24'd0;
	reg         q4;
	reg  [1:0]  ph = 2'd0;
	reg         fallE, fallQ, eph, ce_e;
	reg         psg_div = 1'b0;
	wire        ce_q4  = q4;
	wire        ce_psg = q4 & psg_div;
	always @(posedge clk) begin
		// free-running, reset included: mc6809is samples nRESET on falling E, so
		// E must keep running while reset is held (the first harness run held
		// the generator in reset too, and the CPU started from random state)
		q4 <= 1'b0; fallE <= 1'b0; fallQ <= 1'b0; ce_e <= 1'b0;
		if (!pause) begin
			if (acc + 24'd715909 >= 24'd9600000) begin
				acc <= acc + 24'd715909 - 24'd9600000; q4 <= 1'b1;
				ph <= ph + 2'd1; psg_div <= ~psg_div;
				if (ph == 2'd0) begin fallE <= 1'b1; ce_e <= 1'b1; end
				if (ph == 2'd3) fallQ <= 1'b1;
			end else acc <= acc + 24'd715909;
		end
	end

	// ---------------------------------------------------------------- 6809
	wire [15:0] a;
	wire [7:0]  cpu_do;
	wire        rnw;
	reg  [7:0]  cpu_di;
	wire        ptm_irq_n;
	wire [2:0]  ptm_out;
	reg  [1:0]  nmi_hold;          // E cycles of NMI low still to go
	mc6809is #(.ILLEGAL_INSTRUCTIONS("GHOST")) u_cpu (
		.CLK(clk), .fallE_en(fallE), .fallQ_en(fallQ),
		.D(cpu_di), .DOut(cpu_do), .ADDR(a), .RnW(rnw), .BS(), .BA(),
		.nIRQ(~ptm_out[0]), .nFIRQ(1'b1), .nNMI(nmi_hold == 2'd0),
		.AVMA(), .BUSY(), .LIC(), .nHALT(1'b1), .nRESET(~reset), .nDMABREQ(1'b1), .RegData());
	assign dbg_pc_addr = a;
	assign dbg_wr = fallE && !rnw;
	assign dbg_waddr = a;
	assign dbg_wdata = cpu_do;
	assign dbg_rnw = rnw;
	assign dbg_di = cpu_di;
	assign dbg_fallE = fallE;
	assign dbg_nmi_n = nmi_hold == 2'd0;

	wire sel_ram   = a[15:11] == 5'b00000;
	wire sel_ptm   = a[15:3] == 13'h0100;              // 0800-0807
	wire sel_latch = a == 16'h1800;
	wire sel_opl   = a[15:1] == 15'h1000;              // 2000-2001
	wire sel_psg   = a[15:1] == 15'h1400;              // 2800-2801
	wire sel_rom   = a[15:14] != 2'b00;
	assign rom_addr = a;

	// RAM
	reg  [7:0] ram [0:2047];
	reg  [7:0] ram_q;
	always @(posedge clk) begin
		if (fallE && !rnw && sel_ram) ram[a[10:0]] <= cpu_do;
		ram_q <= ram[a[10:0]];
	end

	// latch and NMI (MAME: generic_latch_8, pulse_input_line(NMI)); the pulse
	// is held low for two E cycles so the 6809's falling-Q sample sees it
	reg  [7:0] latch;
	always @(posedge clk) begin
		if (reset) begin latch <= 8'd0; nmi_hold <= 2'd0; dbg_nmi <= 32'd0; dbg_latch_reads <= 32'd0; end
		else begin
			if (cmd_we) begin latch <= cmd; nmi_hold <= 2'd2; dbg_nmi <= dbg_nmi + 32'd1; end
			else if (ce_e && nmi_hold != 2'd0) nmi_hold <= nmi_hold - 2'd1;
			if (fallE && rnw && sel_latch) dbg_latch_reads <= dbg_latch_reads + 32'd1;
		end
	end

	// PTM
	wire [7:0] ptm_do;
	gn_ptm6840 u_ptm (
		.clk(clk), .reset(reset), .ce_e(ce_e), .cs(sel_ptm),
		.wr(fallE && !rnw), .rd(fallE && rnw), .addr(a[2:0]), .din(cpu_do), .dout(ptm_do),
		.out(ptm_out), .irq_n(ptm_irq_n));
	reg ptm_o1_d;
	always @(posedge clk) begin
		ptm_o1_d <= ptm_out[0];
		if (reset) begin dbg_irq <= 32'd0; dbg_ptm_writes <= 32'd0; end
		else begin
			if (ptm_out[0] && !ptm_o1_d) dbg_irq <= dbg_irq + 32'd1;
			if (fallE && !rnw && sel_ptm) dbg_ptm_writes <= dbg_ptm_writes + 32'd1;
		end
	end

	// chip writes: one clock at falling E
	reg       opl_wr, opl_a0, psg_wr, psg_a0;
	reg [7:0] wdata;
	always @(posedge clk) begin
		opl_wr <= 1'b0; psg_wr <= 1'b0;
		if (fallE && !rnw && (sel_opl || sel_psg)) begin
			opl_wr <= sel_opl; psg_wr <= sel_psg; opl_a0 <= a[0]; psg_a0 <= a[0]; wdata <= cpu_do;
		end
	end

	// ---------------------------------------------------------------- YM2149
	// ZX-Spectrum_MISTer's copy (it matches MAME's period-0 rule, GN-5): BDIR/BC
	// = 1/1 latches the address, 1/0 writes data; SEL 0 = no /2 (MAME's
	// default YM2149), MODE 0 = the YM's 5-bit volume table
	wire [7:0] psg_a, psg_b, psg_c;
	YM2149 u_psg (
		.CLK(clk), .CE(ce_psg), .RESET(reset), .BDIR(psg_wr), .BC(psg_wr & ~psg_a0),
		.DI(wdata), .DO(), .CHANNEL_A(psg_a), .CHANNEL_B(psg_b), .CHANNEL_C(psg_c),
		.SEL(1'b0), .MODE(1'b0), .ACTIVE(), .IOA_in(8'hFF), .IOA_out(), .IOB_in(8'hFF), .IOB_out());

	// ---------------------------------------------------------------- Y8950
	wire signed [15:0] opl_snd;
	gn_y8950 u_opl (
		.clk(clk), .reset(reset), .cen(ce_q4), .wr(opl_wr), .a0(opl_a0), .din(wdata),
		.mem_req(adpcm_req), .mem_addr(adpcm_addr), .mem_ack(adpcm_ack), .mem_data(adpcm_data),
		.snd(opl_snd), .snd_fm(), .snd_adpcm(), .sample());
	assign dbg_opl = opl_snd;

	// ---------------------------------------------------------------- mix
	// MAME's YM2149 is a resistor model into a 1 kohm load (ay8910.cpp
	// build_single_table, ym2149_param, not normalised): a channel outputs
	// table[volume] (0.4159 at volume 0 up to 0.7125 at 15; a silent phase is
	// volume 0), routed at 0.10. In WAV units that is table x 3277, with a DC
	// floor of 1,363 per channel; the board's output is AC-coupled, so the
	// mixer keeps MAME's AC part, (table[v] - table[0]) x 3277 (GN-5).
	// The ZX core only exports its own 8-bit level; each fixed volume v has a
	// unique one ({v, v[3]} into its YM table), and the game never uses the
	// envelope (GN-3), so the mapping back to v is exact.
	function [10:0] psg_lvl(input [7:0] c);
		case (c)
			8'h00: psg_lvl = 11'd0;   8'h01: psg_lvl = 11'd6;   8'h02: psg_lvl = 11'd11;  8'h03: psg_lvl = 11'd16;
			8'h06: psg_lvl = 11'd24;  8'h09: psg_lvl = 11'd33;  8'h0C: psg_lvl = 11'd48;  8'h11: psg_lvl = 11'd64;
			8'h1B: psg_lvl = 11'd93;  8'h25: psg_lvl = 11'd126; 8'h35: psg_lvl = 11'd181; 8'h47: psg_lvl = 11'd244;
			8'h66: psg_lvl = 11'd355; 8'h88: psg_lvl = 11'd483; 8'hC0: psg_lvl = 11'd710; 8'hFF: psg_lvl = 11'd972;
			default: psg_lvl = 11'd0;     // envelope levels: unused by this game
		endcase
	endfunction
	// Measured against MAME's YM2149-only WAV over 90 s of play (GN-5), the
	// table alone is 4.5 dB low in every band; the level is calibrated to
	// MAME's RMS (x 107/64), as MS1Z-13 calibrated its SSG. The cause is open.
	wire [12:0] psg_raw = {2'b00, psg_lvl(psg_a)} + {2'b00, psg_lvl(psg_b)} + {2'b00, psg_lvl(psg_c)};
	wire [19:0] psg_cal = psg_raw * 20'd107;
	wire [12:0] psg_mix = psg_cal[18:6];
	assign dbg_psg = psg_mix;
	always @(posedge clk) begin : mix
		reg signed [19:0] m;
		m = {{4{opl_snd[15]}}, opl_snd} + {7'd0, psg_mix};
		snd <= (m > 32767) ? 16'sd32767 : (m < -32768) ? -16'sd32768 : m[15:0];
	end

	// read mux: RAM and ROM data are registered from the address, which the
	// 6809 holds for the whole cycle, so they are valid at falling E
	always @(*) begin
		if (sel_ram)        cpu_di = ram_q;
		else if (sel_ptm)   cpu_di = ptm_do;
		else if (sel_latch) cpu_di = latch;
		else if (sel_rom)   cpu_di = rom_data;
		else                cpu_di = 8'h00;
	end
endmodule
