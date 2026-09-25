// Ginga Ninkyouden main board (docs/PLAN.md 1.2, 2.4): the 68000 at 6 MHz,
// its program ROM (BRAM), 16 KB of work RAM, the video memories (gn_video's
// CPU port), the inputs, IRQ1 and the sound latch.
//
// Map (ginganin.cpp:374-387), byte addresses:
//   000000-01FFFF  program ROM (writes ignored: the POST writes 10000-13FFF)
//   020000-023FFF  work RAM            030000-0307FF  text VRAM
//   040000-0407FF  sprite RAM          050000-0507FF  palette
//   060000-06000F  vregs (in gn_video); a write to 06000E also latches the
//                  sound command (its low byte) and pulses the 6809's NMI
//   068000-06BFFF  FG VRAM             070000 P1_P2    070002 DSW
// Unmapped reads return 0 (Q7).
//
// IRQ1 (MAME: irq1_line_hold at vblank) is raised at the start of line 240
// and held until one level-1 interrupt-acknowledge cycle (MS1-23). Every
// autovector points at the same handler (fact 9).
//
// 68000 clocking from clk_sys: phi1/phi2 enables alternating every 4 clocks,
// 6 MHz exactly (the MS1Z glue). Pause stops the phases on a phi2 boundary.
module gn_main (
	input             clk,
	input             reset,
	input             pause,
	// program ROM download (byte stream, image offsets 0-0x1FFFF)
	input             dl_we,
	input      [16:0] dl_addr,
	input      [7:0]  dl_data,
	// video CPU port
	output            v_txt, v_spr, v_pal, v_reg, v_fg,
	output     [12:0] v_addr,
	output            v_we,
	output     [1:0]  v_be,
	output     [15:0] v_din,
	input      [15:0] v_dout,
	input             vblank_start,
	// inputs, active low (MAME's P1_P2 and DSW words)
	input      [15:0] p1p2,
	input      [15:0] dsw,
	// sound latch
	output reg        cmd_we,
	output reg [7:0]  cmd,
	// work-RAM back door (hiscore, cheats, the harness): word address, owns
	// the RAM while ram2_sel
	input             ram2_sel,
	input      [12:0] ram2_addr,
	input             ram2_we,
	input      [1:0]  ram2_be,
	input      [15:0] ram2_din,
	output     [15:0] ram2_dout,
	// debug
	output     [23:0] dbg_addr,
	output            dbg_wr,        // the CPU is in a write cycle
	output reg [31:0] dbg_irq1,
	output reg [31:0] dbg_iack1,
	// savestate: the 68000 park (ss_m68k_park: a level-7 interrupt into a
	// monitor overlay at 0x1E8000, unmapped on this board) and the scalars
	//   ss_sel 0-3 SSP/USP (the park's state registers), 4 {irq1}, 5 cmd
	input             park_req,
	output            parked,
	input             resume,
	input      [2:0]  ss_sel,
	input             ss_wr,
	input      [15:0] ss_wdata,
	output reg [15:0] ss_rdata
);
	// ---------------------------------------------------------------- clocking
	reg pause_68k = 1'b0;
	reg [1:0] phdiv;
	reg enPhi1, enPhi2, phase;
	always @(posedge clk) if (enPhi2) pause_68k <= pause;
	always @(posedge clk) begin
		enPhi1 <= 1'b0; enPhi2 <= 1'b0;
		if (reset) begin phdiv <= 2'd0; phase <= 1'b0; end
		else begin
			phdiv <= phdiv + 2'd1;
			if (phdiv == 2'd3) begin
				phase <= ~phase;
				if (phase) enPhi2 <= 1'b1; else enPhi1 <= 1'b1;
			end
		end
	end

	wire        eRWn, ASn, LDSn, UDSn, VMAn, FC0, FC1, FC2, BGn, oRESETn, oHALTEDn;
	wire [15:0] oEdb;
	wire [23:1] eab;
	reg  [15:0] iEdb;
	wire [23:0] a = {eab, 1'b0};
	assign dbg_addr = a;
	wire as_active = ~ASn & (~LDSn | ~UDSn);
	wire iack = ~ASn & FC0 & FC1 & FC2;
	assign dbg_wr = as_active & ~eRWn;

	// ---------------------------------------------------------------- decode
	wire sel_rom = a < 24'h020000;
	wire sel_ram = a[23:14] == 10'h008;                    // 020000-023FFF
	wire sel_txt = a[23:11] == 13'h0060;                   // 030000-0307FF
	wire sel_spr = a[23:11] == 13'h0080;                   // 040000-0407FF
	wire sel_pal = a[23:11] == 13'h00A0;                   // 050000-0507FF
	wire sel_reg = a[23:4]  == 20'h06000;                  // 060000-06000F
	wire sel_fg  = a[23:14] == 10'h01A;                    // 068000-06BFFF
	wire sel_in  = a[23:2]  == 22'h01C000;                 // 070000-070003
	wire sel_vid = sel_txt | sel_spr | sel_pal | sel_reg | sel_fg;
	wire [1:0] be = {~UDSn, ~LDSn};
	wire rd = as_active & eRWn, wr = as_active & ~eRWn;

	assign v_txt = as_active & ~iack & sel_txt;
	assign v_spr = as_active & ~iack & sel_spr;
	assign v_pal = as_active & ~iack & sel_pal;
	assign v_reg = as_active & ~iack & sel_reg;
	assign v_fg  = as_active & ~iack & sel_fg;
	assign v_addr = a[13:1];
	assign v_we  = wr;
	assign v_be  = be;
	assign v_din = oEdb;

	// ---------------------------------------------------------------- memories
	// program ROM: two byte lanes (even = high), loaded by the download
	reg [7:0] rom_h [0:65535], rom_l [0:65535];
	reg [7:0] rom_qh, rom_ql;
	always @(posedge clk) begin
		if (dl_we && !dl_addr[0]) rom_h[dl_addr[16:1]] <= dl_data;
		rom_qh <= rom_h[a[16:1]];
	end
	always @(posedge clk) begin
		if (dl_we &&  dl_addr[0]) rom_l[dl_addr[16:1]] <= dl_data;
		rom_ql <= rom_l[a[16:1]];
	end
	// work RAM: byte lanes, one port shared with the back door (the back door
	// only drives it while the CPU is held)
	reg [7:0] ram_h [0:8191], ram_l [0:8191];
	reg [7:0] ram_qh, ram_ql;
	wire [12:0] ra   = ram2_sel ? ram2_addr : a[13:1];
	wire [1:0]  rbe  = ram2_sel ? ram2_be : be;
	wire        rwe  = ram2_sel ? ram2_we : (wr & sel_ram);
	wire [15:0] rdin = ram2_sel ? ram2_din : oEdb;
	always @(posedge clk) begin
		if (rwe & rbe[1]) ram_h[ra] <= rdin[15:8];
		ram_qh <= ram_h[ra];
	end
	always @(posedge clk) begin
		if (rwe & rbe[0]) ram_l[ra] <= rdin[7:0];
		ram_ql <= ram_l[ra];
	end
	assign ram2_dout = {ram_qh, ram_ql};

	// ---------------------------------------------------------------- bus cycle
	// DTACK two clocks into a cycle: the BRAMs answer in one, the video port in
	// two (a 6 MHz bus cycle is 32 clocks, so the wait is free).
	reg [1:0] cyc;
	always @(posedge clk) begin
		if (!as_active) cyc <= 2'd0;
		else if (cyc != 2'd3) cyc <= cyc + 2'd1;
	end
	wire ready = cyc >= 2'd2;
	always @(*) begin
		if (sel_mon)       iEdb = mon_data;
		else if (sel_rom)  iEdb = {rom_qh, rom_ql};
		else if (sel_ram)  iEdb = {ram_qh, ram_ql};
		else if (sel_vid)  iEdb = v_dout;
		else if (sel_in)   iEdb = a[1] ? dsw : p1p2;
		else               iEdb = 16'h0000;
	end

	// ---------------------------------------------------------------- park
	reg         irq1;
	wire        sel_mon;
	wire [15:0] mon_data, park_rd;
	wire [2:0]  ipl_park;
	wire        park_stall;
	ss_m68k_park #(.MON_BASE(15'h0F40)) u_park (
		.clk(clk), .reset(reset), .phi(enPhi2),
		.park_req(park_req), .parked(parked), .resume(resume),
		.eab(eab), .ASn(ASn), .eRWn(eRWn), .FC0(FC0), .FC1(FC1), .FC2(FC2), .oEdb(oEdb),
		.ipl_park(ipl_park), .sel_mon(sel_mon), .mon_data(mon_data), .stall(park_stall),
		.ss_sel(ss_sel[1:0]), .ss_wr(ss_wr && !ss_sel[2]), .ss_wdata(ss_wdata), .ss_rdata(park_rd));
	always @(*) begin
		case (ss_sel)
			3'd4:    ss_rdata = {15'd0, irq1};
			3'd5:    ss_rdata = {8'd0, cmd};
			default: ss_rdata = ss_sel[2] ? 16'h0000 : park_rd;
		endcase
	end

	// ---------------------------------------------------------------- latch
	// one pulse per write cycle to 06000E (MAME: m_soundlatch->write(data),
	// then pulse NMI): the low byte of the register after the write
	reg wr_d;
	always @(posedge clk) begin
		wr_d <= wr & sel_reg & (a[3:1] == 3'd7);
		cmd_we <= 1'b0;
		if (wr & sel_reg & (a[3:1] == 3'd7) & ~wr_d & be[0]) begin cmd_we <= 1'b1; cmd <= oEdb[7:0]; end
		else if (wr & sel_reg & (a[3:1] == 3'd7) & ~wr_d) cmd_we <= 1'b1;   // upper byte only: the latch keeps its low byte
		if (ss_wr && ss_sel == 3'd5) cmd <= ss_wdata[7:0];
	end

	// ---------------------------------------------------------------- IRQ1
	reg iack_d;
	always @(posedge clk) begin
		iack_d <= iack;
		if (reset) begin irq1 <= 1'b0; dbg_irq1 <= 32'd0; dbg_iack1 <= 32'd0; end
		else begin
			if (vblank_start) begin irq1 <= 1'b1; dbg_irq1 <= dbg_irq1 + 32'd1; end
			else if (iack & ~iack_d & eab[3:1] == 3'd1) begin irq1 <= 1'b0; dbg_iack1 <= dbg_iack1 + 32'd1; end
			if (ss_wr && ss_sel == 3'd4) irq1 <= ss_wdata[0];
		end
	end

	fx68k u_cpu (
		.clk(clk), .HALTn(1'b1), .extReset(reset), .pwrUp(reset),
		.enPhi1(enPhi1 & ~pause_68k), .enPhi2(enPhi2 & ~pause_68k),
		.eRWn(eRWn), .ASn(ASn), .LDSn(LDSn), .UDSn(UDSn), .E(), .VMAn(VMAn),
		.FC0(FC0), .FC1(FC1), .FC2(FC2), .BGn(BGn),
		.oRESETn(oRESETn), .oHALTEDn(oHALTEDn),
		.DTACKn(~(as_active & ~iack & ready & ~park_stall)), .VPAn(~iack), .BERRn(1'b1), .BRn(1'b1), .BGACKn(1'b1),
		.IPL0n(~(irq1 | ipl_park[0])), .IPL1n(~ipl_park[1]), .IPL2n(~ipl_park[2]),
		.iEdb(iEdb), .oEdb(oEdb), .eab(eab)
	);
endmodule
