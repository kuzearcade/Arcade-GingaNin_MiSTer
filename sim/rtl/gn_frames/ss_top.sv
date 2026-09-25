// SS-13's savestate gate (docs/PLAN.md 2.9): gn_core with the savestate
// engine (fixed read latency 4) and its DDR port brought out to the
// testbench. Built by `make ss`; tb.cpp's MP_SS drives it.
module ss_top (
	input             clk,
	input             reset,
	input             pause,
	input      [15:0] p1p2,
	input      [15:0] dsw,
	input             ram2_sel,
	input      [12:0] ram2_addr,
	input             ram2_we,
	input      [1:0]  ram2_be,
	input      [15:0] ram2_din,
	output     [15:0] ram2_dout,
	input             dl_we,
	input      [19:0] dl_addr,
	input      [7:0]  dl_data,
	output            bg_req,  output [16:0] bg_addr,  input bg_ack,  input [31:0] bg_data,
	output            fg_req,  output [16:0] fg_addr,  input fg_ack,  input [31:0] fg_data,
	output            spr_req, output [18:0] spr_addr, input spr_ack, input [31:0] spr_data,
	output            adpcm_req, output [23:0] adpcm_addr, input adpcm_ack, input [7:0] adpcm_data,
	output            ce_pix,
	output     [8:0]  hcount, vcount,
	output     [23:0] rgb,
	output signed [15:0] snd,
	output     [23:0] dbg_addr,
	output            dbg_wr,
	output     [15:0] dbg_wdata,
	output     [1:0]  dbg_be,
	output     [31:0] dbg_irq1, dbg_iack1,
	output     [15:0] dbg_spr_overruns,
	// the engine
	input             save_req,
	input             load_req,
	input      [1:0]  slot,
	output            ss_busy, ss_done_ok, ss_done_fail,
	output     [1:0]  ss_fail_code,
	output            ddr_we, ddr_rd,
	output     [28:0] ddr_addr,
	output     [63:0] ddr_din,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready
);
	wire        ss_freeze, ss_resume, ss_active, ss_wr, ss_frozen, ss_parked, ss_replay, ss_replay_done;
	wire [19:0] ss_addr;
	wire [15:0] ss_rdata, ss_wdata;
	wire        hb, vb, hs, vs;
	gn_core u_core (
		.clk(clk), .reset(reset), .pause(pause & ~ss_busy), .flip_osd(1'b0),
		.dl_we(dl_we), .dl_addr(dl_addr), .dl_data(dl_data),
		.bg_req(bg_req), .bg_addr(bg_addr), .bg_ack(bg_ack), .bg_data(bg_data),
		.fg_req(fg_req), .fg_addr(fg_addr), .fg_ack(fg_ack), .fg_data(fg_data),
		.spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_data(spr_data),
		.adpcm_req(adpcm_req), .adpcm_addr(adpcm_addr), .adpcm_ack(adpcm_ack), .adpcm_data(adpcm_data),
		.p1p2(p1p2), .dsw(dsw),
		.ram2_sel(ram2_sel), .ram2_addr(ram2_addr), .ram2_we(ram2_we), .ram2_be(ram2_be), .ram2_din(ram2_din), .ram2_dout(ram2_dout),
		.ce_pix(ce_pix), .hcount(hcount), .vcount(vcount), .hblank(hb), .vblank(vb), .hsync(hs), .vsync(vs),
		.rgb(rgb), .snd(snd),
		.dbg_addr(dbg_addr), .dbg_wr(dbg_wr), .dbg_wdata(dbg_wdata), .dbg_be(dbg_be),
		.dbg_irq1(dbg_irq1), .dbg_iack1(dbg_iack1), .dbg_spr_overruns(dbg_spr_overruns),
		.ss_freeze(ss_freeze), .ss_resume(ss_resume), .ss_active(ss_active), .ss_addr(ss_addr),
		.ss_wr(ss_wr), .ss_wdata(ss_wdata), .ss_rdata(ss_rdata), .ss_frozen(ss_frozen), .ss_parked(ss_parked),
		.ss_replay(ss_replay), .ss_replay_done(ss_replay_done));
	savestate #(.SS_WORDS(20'h5950), .DDR_BASE(29'd0), .SLOT_STRIDE(29'h10000), .RD_LAT(4)) u_ss (
		.clk(clk), .reset(reset), .save_req(save_req), .load_req(load_req), .slot(slot),
		.vblank(vcount >= 9'd240 || vcount < 9'd16), .allow(!reset),
		.ss_freeze(ss_freeze), .ss_frozen(ss_frozen), .ss_parked(ss_parked), .ss_resume(ss_resume), .ss_active(ss_active),
		.ss_addr(ss_addr), .ss_rdata(ss_rdata), .ss_wr(ss_wr), .ss_rd(), .ss_ack(1'b0), .ss_wdata(ss_wdata),
		.ss_replay(ss_replay), .ss_replay_done(ss_replay_done),
		.busy(ss_busy), .done_ok(ss_done_ok), .done_fail(ss_done_fail), .fail_code(ss_fail_code), .was_load(),
		.clk_ddr(clk), .ddr_busy(1'b0), .rot_we(1'b0), .ddr_we(ddr_we), .ddr_rd(ddr_rd), .ddr_addr(ddr_addr),
		.ddr_din(ddr_din), .ddr_dout(ddr_dout), .ddr_dout_ready(ddr_dout_ready));
endmodule
