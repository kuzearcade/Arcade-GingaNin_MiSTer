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
	output     [15:0] dbg_spr_overruns,
	// savestate (rtl/savestate/savestate.sv, fixed read latency RD_LAT = 4).
	// The image, 16-bit words (docs/PLAN.md Appendix C as built):
	//   0000-1FFF work RAM           2000-23FF text VRAM   2400-27FF sprite RAM
	//   2800-2BFF palette            2C00-4BFF FG VRAM     4C00-4C07 vregs
	//   4C40-4C7F palette-written flags (GN-1)
	//   4C80-4C85 main: SSP, USP (68000 park), IRQ1, the sound command
	//   5000-5947 the sound board (gn_sound's map)
	// The raster is not in the image: a save parks at a vblank edge and the
	// engine releases at one, so both CPUs resume at the same frame phase.
	input             ss_freeze,
	input             ss_resume,
	input             ss_active,
	input      [19:0] ss_addr,
	input             ss_wr,
	input      [15:0] ss_wdata,
	output reg [15:0] ss_rdata,
	output            ss_frozen,
	output            ss_parked,
	input             ss_replay,
	output            ss_replay_done
);
	// ---------------------------------------------------------------- savestate decode
	wire ssr_ram  = ss_addr[19:13] == 7'd0;                              // 0000-1FFF
	wire ssr_txt  = ss_addr[19:10] == 10'h008;                           // 2000-23FF
	wire ssr_spr  = ss_addr[19:10] == 10'h009;                           // 2400-27FF
	wire ssr_pal  = ss_addr[19:10] == 10'h00A;                           // 2800-2BFF
	wire ssr_fg   = ss_addr >= 20'h02C00 && ss_addr < 20'h04C00;         // 2C00-4BFF
	wire ssr_reg  = ss_addr[19:3] == 17'h00980;                          // 4C00-4C07
	wire ssr_pw   = ss_addr[19:6] == 14'h0131;                           // 4C40-4C7F
	wire ssr_main = ss_addr[19:3] == 17'h00990 && ss_addr[2:0] < 3'd6;   // 4C80-4C85
	wire ssr_snd  = ss_addr[19:12] == 8'h05;                             // 5000-5FFF
	wire ssr_vid  = ssr_txt | ssr_spr | ssr_pal | ssr_fg | ssr_reg;
	wire [12:0] ss_fga = 13'(ss_addr - 20'h02C00);

	// park: the 68000 first; the 6809 only once it is parked (so no command
	// can reach the sound board while its monitor takes the NMI). The sound
	// board's clock then stops at the 6809's loop head (gn_sound `held`)
	// until the release; the image is taken only once it has.
	wire m_parked, s_parked, s_held;
	reg  m_seen = 1'b0;
	always @(posedge clk) begin
		if (!ss_freeze) m_seen <= 1'b0; else if (m_parked) m_seen <= 1'b1;
	end
	wire hold = ss_freeze & ~ss_resume & m_parked & s_parked;
	assign ss_frozen = m_parked & s_held;
	assign ss_parked = m_parked | s_parked;

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
		.ram2_sel(ss_active | ram2_sel), .ram2_addr(ss_active ? ss_addr[12:0] : ram2_addr),
		.ram2_we(ss_active ? (ss_wr & ssr_ram) : ram2_we), .ram2_be(ss_active ? 2'b11 : ram2_be),
		.ram2_din(ss_active ? ss_wdata : ram2_din), .ram2_dout(ram2_dout),
		.dbg_addr(dbg_addr), .dbg_wr(dbg_wr), .dbg_irq1(dbg_irq1), .dbg_iack1(dbg_iack1),
		.park_req(ss_freeze), .parked(m_parked), .resume(ss_resume),
		.ss_sel(ss_addr[2:0]), .ss_wr(ss_wr & ssr_main), .ss_wdata(ss_wdata), .ss_rdata(main_ss));
	wire [15:0] main_ss;

	gn_video u_video (
		.clk(clk), .reset(reset), .flip_osd(flip_osd),
		.ce_pix(ce_pix), .hcount(hcount), .vcount(vcount), .hblank(hblank), .vblank(vblank),
		.hsync(hsync), .vsync(vsync), .vblank_start(vblank_start),
		// the engine owns the CPU port while it streams (the 68000 is parked)
		.sel_txt(ss_active ? ssr_txt : v_txt), .sel_spr(ss_active ? ssr_spr : v_spr),
		.sel_pal(ss_active ? ssr_pal : v_pal), .sel_reg(ss_active ? ssr_reg : v_reg),
		.sel_fg(ss_active ? ssr_fg : v_fg),
		.cpu_addr(ss_active ? (ssr_fg ? ss_fga : {3'd0, ss_addr[9:0]}) : v_addr),
		.cpu_we(ss_active ? ss_wr : v_we), .cpu_be(ss_active ? 2'b11 : v_be),
		.cpu_din(ss_active ? ss_wdata : v_din), .cpu_dout(v_dout),
		.layer_ctrl_dbg(), .vreg_out(),
		.dl_we(dl_vid), .dl_bgmap(dl_addr >= 20'h34000), .dl_addr(dl_addr >= 20'h34000 ? 15'(dl_addr - 20'h34000) : 15'(dl_addr - 20'h30000)), .dl_data(dl_data),
		.bg_req(bg_req), .bg_addr(bg_addr), .bg_ack(bg_ack), .bg_data(bg_data),
		.fg_req(fg_req), .fg_addr(fg_addr), .fg_ack(fg_ack), .fg_data(fg_data),
		.spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_data(spr_data),
		.rgb(rgb), .dbg_spr_overruns(dbg_spr_overruns),
		.ss_pw_idx(ss_addr[5:0]), .ss_pw_wr(ss_wr & ssr_pw), .ss_wdata(ss_wdata), .ss_pw_rdata(pw_ss));
	wire [15:0] pw_ss;

	gn_sound u_sound (
		.clk(clk), .reset(reset), .pause(pause),
		.rom_addr(srom_a), .rom_data(srom_q),
		.cmd_we(cmd_we), .cmd(cmd),
		.adpcm_req(adpcm_req), .adpcm_addr(adpcm_addr), .adpcm_ack(adpcm_ack), .adpcm_data(adpcm_data),
		.snd(snd), .dbg_opl(), .dbg_psg(),
		.dbg_pc_addr(), .dbg_nmi(), .dbg_irq(), .dbg_ptm_writes(), .dbg_latch_reads(),
		.dbg_wr(), .dbg_waddr(), .dbg_wdata(), .dbg_rnw(), .dbg_di(), .dbg_fallE(), .dbg_nmi_n(),
		.hold(hold), .held(s_held), .park_req(ss_freeze & m_seen), .parked(s_parked), .resume(ss_resume),
		.ss_act(ss_active), .ss_a(ss_addr[11:0]), .ss_wr(ss_wr & ssr_snd), .ss_wdata(ss_wdata),
		.ss_rdata(snd_ss), .ss_replay(ss_replay), .ss_replay_done(ss_replay_done));
	wire [15:0] snd_ss;

	// the read data: every source is valid within three clocks of the
	// address (video: two, the sound board: two, the rest: one or none)
	always @(posedge clk) begin
		if (ssr_ram)       ss_rdata <= ram2_dout;
		else if (ssr_vid)  ss_rdata <= v_dout;
		else if (ssr_pw)   ss_rdata <= pw_ss;
		else if (ssr_main) ss_rdata <= main_ss;
		else if (ssr_snd)  ss_rdata <= snd_ss;
		else               ss_rdata <= 16'h0000;
	end
endmodule
