// Ginga Ninkyouden: the whole board (docs/PLAN.md 2.1). The ROM image
// (tools/gn_romdata.py, Appendix D) arrives as a byte stream; the first
// 0x3C000 bytes stay in BRAM here, the rest is served through the tile,
// sprite and ADPCM ports (SDRAM on the board, arrays in the reference sims).
module gn_core (
	input             clk,
	input             reset,
	input             pause,
	input             flip_osd,
	// ROM download (image offsets below 0x3C000 are kept here)
	input             dl_we,
	input      [19:0] dl_addr,
	input      [7:0]  dl_data,
	// ROM ports into the SDRAM part (byte addresses within each region)
	output            bg_req,  output [16:0] bg_addr,  input bg_ack,  input [31:0] bg_data,
	output            fg_req,  output [16:0] fg_addr,  input fg_ack,  input [31:0] fg_data,
	output            spr_req, output [18:0] spr_addr, input spr_ack, input [31:0] spr_data,
	output            adpcm_req, output [23:0] adpcm_addr, input adpcm_ack, input [7:0] adpcm_data,
	// inputs, active low
	input      [15:0] p1p2,
	input      [15:0] dsw,
	// work-RAM back door
	input             ram2_sel,
	input      [12:0] ram2_addr,
	input             ram2_we,
	input      [1:0]  ram2_be,
	input      [15:0] ram2_din,
	output     [15:0] ram2_dout,
	// video
	output            ce_pix,
	output     [8:0]  hcount,
	output     [8:0]  vcount,
	output            hblank, vblank, hsync, vsync,
	output     [23:0] rgb,
	// audio
	output signed [15:0] snd,
	// debug
	output     [23:0] dbg_addr,
	output            dbg_wr,
	output     [15:0] dbg_wdata,
	output     [1:0]  dbg_be,
	output     [31:0] dbg_irq1,
	output     [31:0] dbg_iack1,
	output     [15:0] dbg_spr_overruns
);
	// ---------------------------------------------------------------- download split
	wire dl_main = dl_we && dl_addr < 20'h20000;
	wire dl_snd  = dl_we && dl_addr >= 20'h20000 && dl_addr < 20'h30000;
	wire dl_vid  = dl_we && dl_addr >= 20'h30000 && dl_addr < 20'h3C000;

	// sound program: 64 KB BRAM (the 6809 uses 0x4000-0xFFFF)
	reg  [7:0]  snd_rom [0:65535];
	wire [15:0] srom_a;
	reg  [7:0]  srom_q;
	always @(posedge clk) begin
		if (dl_snd) snd_rom[dl_addr[15:0]] <= dl_data;
		srom_q <= snd_rom[srom_a];
	end

	// ---------------------------------------------------------------- boards
	wire        v_txt, v_spr, v_pal, v_reg, v_fg, v_we, vblank_start;
	wire [12:0] v_addr;
	wire [1:0]  v_be;
	wire [15:0] v_din, v_dout;
	wire        cmd_we;
	assign dbg_wdata = v_din;
	assign dbg_be = v_be;
	wire [7:0]  cmd;
	gn_main u_main (
		.clk(clk), .reset(reset), .pause(pause),
		.dl_we(dl_main), .dl_addr(dl_addr[16:0]), .dl_data(dl_data),
		.v_txt(v_txt), .v_spr(v_spr), .v_pal(v_pal), .v_reg(v_reg), .v_fg(v_fg),
		.v_addr(v_addr), .v_we(v_we), .v_be(v_be), .v_din(v_din), .v_dout(v_dout), .vblank_start(vblank_start),
		.p1p2(p1p2), .dsw(dsw), .cmd_we(cmd_we), .cmd(cmd),
		.ram2_sel(ram2_sel), .ram2_addr(ram2_addr), .ram2_we(ram2_we), .ram2_be(ram2_be), .ram2_din(ram2_din), .ram2_dout(ram2_dout),
		.dbg_addr(dbg_addr), .dbg_wr(dbg_wr), .dbg_irq1(dbg_irq1), .dbg_iack1(dbg_iack1));

	gn_video u_video (
		.clk(clk), .reset(reset), .flip_osd(flip_osd),
		.ce_pix(ce_pix), .hcount(hcount), .vcount(vcount), .hblank(hblank), .vblank(vblank),
		.hsync(hsync), .vsync(vsync), .vblank_start(vblank_start),
		.sel_txt(v_txt), .sel_spr(v_spr), .sel_pal(v_pal), .sel_reg(v_reg), .sel_fg(v_fg),
		.cpu_addr(v_addr), .cpu_we(v_we), .cpu_be(v_be), .cpu_din(v_din), .cpu_dout(v_dout),
		.layer_ctrl_dbg(), .vreg_out(),
		.dl_we(dl_vid), .dl_bgmap(dl_addr >= 20'h34000), .dl_addr(dl_addr >= 20'h34000 ? 15'(dl_addr - 20'h34000) : 15'(dl_addr - 20'h30000)), .dl_data(dl_data),
		.bg_req(bg_req), .bg_addr(bg_addr), .bg_ack(bg_ack), .bg_data(bg_data),
		.fg_req(fg_req), .fg_addr(fg_addr), .fg_ack(fg_ack), .fg_data(fg_data),
		.spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_data(spr_data),
		.rgb(rgb), .dbg_spr_overruns(dbg_spr_overruns));

	gn_sound u_sound (
		.clk(clk), .reset(reset), .pause(pause),
		.rom_addr(srom_a), .rom_data(srom_q),
		.cmd_we(cmd_we), .cmd(cmd),
		.adpcm_req(adpcm_req), .adpcm_addr(adpcm_addr), .adpcm_ack(adpcm_ack), .adpcm_data(adpcm_data),
		.snd(snd), .dbg_opl(), .dbg_psg(),
		.dbg_pc_addr(), .dbg_nmi(), .dbg_irq(), .dbg_ptm_writes(), .dbg_latch_reads(),
		.dbg_wr(), .dbg_waddr(), .dbg_wdata(), .dbg_rnw(), .dbg_di(), .dbg_fallE(), .dbg_nmi_n());
endmodule
