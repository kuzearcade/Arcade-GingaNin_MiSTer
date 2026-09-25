// M3: the core on its real memory path (docs/PLAN.md M3). gn_core with
// gn_rom_hw, rtl/sdram.sv at 96 MHz against sim/models/sdram_model.sv, and the
// download through the ioctl interface (the testbench plays Main_MiSTer).
// The ROM streams are brought out for the testbench's response check.
module hw_top (
	input             clk_sys,
	input             clk_ram,
	input             pwr_reset,
	input             reset,
	input             pause,
	input             ioctl_download,
	input             ioctl_wr,
	input      [26:0] ioctl_addr,
	input      [7:0]  ioctl_dout,
	output            ioctl_wait,
	input      [15:0] p1p2,
	input      [15:0] dsw,
	input             ram2_sel,
	input      [12:0] ram2_addr,
	input             ram2_we,
	input      [1:0]  ram2_be,
	input      [15:0] ram2_din,
	output     [15:0] ram2_dout,
	output            ce_pix,
	output     [8:0]  hcount, vcount,
	output     [23:0] rgb,
	output signed [15:0] snd,
	output            sdram_ready,
	output     [23:0] dbg_addr,
	output     [31:0] dbg_irq1, dbg_iack1, dbg_dl_bytes,
	output     [15:0] dbg_spr_overruns, dbg_dropped,
	// the streams, for the response check
	output            t_bg_req, t_bg_ack, t_fg_req, t_fg_ack, t_spr_req, t_spr_ack, t_adp_req, t_adp_ack,
	output     [16:0] t_bg_addr, t_fg_addr,
	output     [18:0] t_spr_addr,
	output     [23:0] t_adp_addr,
	output     [31:0] t_bg_data, t_fg_data, t_spr_data,
	output     [7:0]  t_adp_data
);
	wire [15:0] SDRAM_DQ; wire [12:0] SDRAM_A; wire [1:0] SDRAM_BA;
	wire SDRAM_DQML, SDRAM_DQMH, SDRAM_nCS, SDRAM_nWE, SDRAM_nRAS, SDRAM_nCAS, SDRAM_CLK, SDRAM_CKE;
	sdram_model u_model (.SDRAM_CLK(SDRAM_CLK), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA), .SDRAM_DQ(SDRAM_DQ),
		.SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nCAS(SDRAM_nCAS),
		.SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_CKE(SDRAM_CKE));
	wire [24:1] sd0_addr, sd1_addr, sd2_addr, sd3_addr;
	wire        sd0_wrl, sd0_wrh, sd1_wrl, sd1_wrh, sd2_wrl, sd2_wrh, sd3_wrl, sd3_wrh;
	wire [15:0] sd0_din, sd1_din, sd2_din, sd3_din, sd0_dout, sd1_dout, sd2_dout, sd3_dout;
	wire [31:0] sd0_pair, sd1_pair, sd2_pair, sd3_pair;
	wire        sd0_req, sd1_req, sd2_req, sd3_req, sd0_ack, sd1_ack, sd2_ack, sd3_ack;
	sdram #(.REFRESH_CYCLES(10'd740)) u_sdram (
		.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
		.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
		.SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE), .ready(sdram_ready),
		.init(pwr_reset), .clk(clk_ram), .clk_sdram(1'b0), .prio_mode(2'd0),
		.addr0(sd0_addr), .wrl0(sd0_wrl), .wrh0(sd0_wrh), .din0(sd0_din), .dout0(sd0_dout), .dout0_pair(sd0_pair), .req0(sd0_req), .ack0(sd0_ack),
		.addr1(sd1_addr), .wrl1(sd1_wrl), .wrh1(sd1_wrh), .din1(sd1_din), .dout1(sd1_dout), .dout1_pair(sd1_pair), .req1(sd1_req), .ack1(sd1_ack),
		.addr2(sd2_addr), .wrl2(sd2_wrl), .wrh2(sd2_wrh), .din2(sd2_din), .dout2(sd2_dout), .dout2_pair(sd2_pair), .req2(sd2_req), .ack2(sd2_ack),
		.addr3(sd3_addr), .wrl3(sd3_wrl), .wrh3(sd3_wrh), .din3(sd3_din), .dout3(sd3_dout), .dout3_pair(sd3_pair), .req3(sd3_req), .ack3(sd3_ack));

	wire        bg_req, bg_ack, fg_req, fg_ack, spr_req, spr_ack, adp_req, adp_ack;
	wire [16:0] bg_addr, fg_addr;
	wire [18:0] spr_addr;
	wire [23:0] adp_addr;
	wire [31:0] bg_data, fg_data, spr_data;
	wire [7:0]  adp_data;
	gn_rom_hw u_rom (
		.clk(clk_sys), .reset(reset), .pwr_reset(pwr_reset),
		.ioctl_download(ioctl_download), .ioctl_index(16'd0), .ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr),
		.ioctl_dout(ioctl_dout), .ioctl_wait(ioctl_wait),
		.bg_req(bg_req), .bg_addr(bg_addr), .bg_ack(bg_ack), .bg_data(bg_data),
		.fg_req(fg_req), .fg_addr(fg_addr), .fg_ack(fg_ack), .fg_data(fg_data),
		.spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_data(spr_data),
		.adpcm_req(adp_req), .adpcm_addr(adp_addr), .adpcm_ack(adp_ack), .adpcm_data(adp_data),
		.sdram_addr0(sd0_addr), .sdram_addr1(sd1_addr), .sdram_addr2(sd2_addr), .sdram_addr3(sd3_addr),
		.sdram_wrl0(sd0_wrl), .sdram_wrl1(sd1_wrl), .sdram_wrl2(sd2_wrl), .sdram_wrl3(sd3_wrl),
		.sdram_wrh0(sd0_wrh), .sdram_wrh1(sd1_wrh), .sdram_wrh2(sd2_wrh), .sdram_wrh3(sd3_wrh),
		.sdram_din0(sd0_din), .sdram_din1(sd1_din), .sdram_din2(sd2_din), .sdram_din3(sd3_din),
		.sdram_dout0(sd0_dout), .sdram_dout1(sd1_dout), .sdram_dout2(sd2_dout), .sdram_dout3(sd3_dout),
		.sdram_pair0(sd0_pair), .sdram_pair1(sd1_pair), .sdram_pair2(sd2_pair), .sdram_pair3(sd3_pair),
		.sdram_req0(sd0_req), .sdram_req1(sd1_req), .sdram_req2(sd2_req), .sdram_req3(sd3_req),
		.sdram_ack0(sd0_ack), .sdram_ack1(sd1_ack), .sdram_ack2(sd2_ack), .sdram_ack3(sd3_ack),
		.dbg_dl_bytes(dbg_dl_bytes), .dbg_dropped(dbg_dropped));

	// the BRAM part of the download: every byte the SDRAM side accepts
	wire dl_we = ioctl_download & ioctl_wr & ~ioctl_wait;
	wire hb, vb, hs, vs, dwr;
	gn_core u_core (
		.clk(clk_sys), .reset(reset | ~sdram_ready), .pause(pause), .flip_osd(1'b0),
		.dl_we(dl_we), .dl_addr(ioctl_addr[19:0]), .dl_data(ioctl_dout),
		.bg_req(bg_req), .bg_addr(bg_addr), .bg_ack(bg_ack), .bg_data(bg_data),
		.fg_req(fg_req), .fg_addr(fg_addr), .fg_ack(fg_ack), .fg_data(fg_data),
		.spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_data(spr_data),
		.adpcm_req(adp_req), .adpcm_addr(adp_addr), .adpcm_ack(adp_ack), .adpcm_data(adp_data),
		.p1p2(p1p2), .dsw(dsw),
		.ram2_sel(ram2_sel), .ram2_addr(ram2_addr), .ram2_we(ram2_we), .ram2_be(ram2_be), .ram2_din(ram2_din), .ram2_dout(ram2_dout),
		.ce_pix(ce_pix), .hcount(hcount), .vcount(vcount), .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs),
		.rgb(rgb), .snd(snd),
		.dbg_addr(dbg_addr), .dbg_wr(dwr), .dbg_wdata(), .dbg_be(), .dbg_irq1(dbg_irq1), .dbg_iack1(dbg_iack1),
		.dbg_spr_overruns(dbg_spr_overruns));

	assign t_bg_req = bg_req;   assign t_bg_ack = bg_ack;   assign t_bg_addr = bg_addr;   assign t_bg_data = bg_data;
	assign t_fg_req = fg_req;   assign t_fg_ack = fg_ack;   assign t_fg_addr = fg_addr;   assign t_fg_data = fg_data;
	assign t_spr_req = spr_req; assign t_spr_ack = spr_ack; assign t_spr_addr = spr_addr; assign t_spr_data = spr_data;
	assign t_adp_req = adp_req; assign t_adp_ack = adp_ack; assign t_adp_addr = adp_addr; assign t_adp_data = adp_data;
endmodule
