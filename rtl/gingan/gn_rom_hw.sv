// The SDRAM side of the Ginga Ninkyouden core (docs/PLAN.md 2.2, M3): the
// ioctl download into SDRAM and the four ROM streams gn_core reads there.
// Everything below image offset 0x3C000 also lives in gn_core's BRAMs; the
// whole image is written to SDRAM anyway, which keeps the copy check a plain
// word-for-word compare.
//
// Port allocation over rtl/sdram.sv's four physical ports:
//   0   the ioctl download
//   1   BG and FG tile rows
//   2   sprite rows
//   3   ADPCM bytes
//
// The download writes byte 2k to the LOW lane of SDRAM word k (MS1Z rom_hw),
// so a 32-bit pair {word(a|1), word(a&~1)} is bytes {a+3, a+2, a+1, a}; the
// engines want the first byte on top, so the row is byte-reversed here.
module gn_rom_hw (
	input             clk,
	input             reset,
	input             pwr_reset,

	input             ioctl_download,
	input      [15:0] ioctl_index,
	input             ioctl_wr,
	input      [26:0] ioctl_addr,
	input      [7:0]  ioctl_dout,
	output            ioctl_wait,

	// gn_core's ROM ports: a request is held until its ack, or dropped (the
	// sprite engine abandons a line that runs over: GN-6)
	input             bg_req,    input [16:0] bg_addr,    output bg_ack,    output [31:0] bg_data,
	input             fg_req,    input [16:0] fg_addr,    output fg_ack,    output [31:0] fg_data,
	input             spr_req,   input [18:0] spr_addr,   output spr_ack,   output [31:0] spr_data,
	input             adpcm_req, input [23:0] adpcm_addr, output adpcm_ack, output [7:0]  adpcm_data,

	output     [24:1] sdram_addr0, sdram_addr1, sdram_addr2, sdram_addr3,
	output            sdram_wrl0,  sdram_wrl1,  sdram_wrl2,  sdram_wrl3,
	output            sdram_wrh0,  sdram_wrh1,  sdram_wrh2,  sdram_wrh3,
	output     [15:0] sdram_din0,  sdram_din1,  sdram_din2,  sdram_din3,
	input      [15:0] sdram_dout0, sdram_dout1, sdram_dout2, sdram_dout3,
	input      [31:0] sdram_pair0, sdram_pair1, sdram_pair2, sdram_pair3,
	output            sdram_req0,  sdram_req1,  sdram_req2,  sdram_req3,
	input             sdram_ack0,  sdram_ack1,  sdram_ack2,  sdram_ack3,

	output reg [31:0] dbg_dl_bytes,
	output     [15:0] dbg_dropped           // answers discarded because their request was withdrawn
);
	// image layout (tools/gn_romdata.py, Appendix D), SDRAM word addresses
	localparam [23:0] BGT_W = 24'h03C000 >> 1;
	localparam [23:0] FGT_W = 24'h05C000 >> 1;
	localparam [23:0] SPR_W = 24'h07C000 >> 1;
	localparam [23:0] ADP_W = 24'h0CC000 >> 1;

	// ------------------------------------------------------------ download
	// Only index 0 is ROM: <switches> (254) restarts at address 0 and would
	// otherwise overwrite the image's first bytes.
	wire dl_rom = ioctl_download && (ioctl_index == 16'd0);
	reg         dl_req;
	reg  [24:1] dl_addr;
	reg  [15:0] dl_din;
	reg         dl_wrl, dl_wrh;
	wire        dl_valid;
	always @(posedge clk) begin
		if (pwr_reset) begin
			dl_req <= 1'b0; dl_wrl <= 1'b0; dl_wrh <= 1'b0; dbg_dl_bytes <= 32'd0;
		end else begin
			if (dl_valid) dl_req <= 1'b0;
			if (dl_rom && ioctl_wr && !dl_req) begin
				dl_addr <= ioctl_addr[24:1];
				dl_din  <= {ioctl_dout, ioctl_dout};
				dl_wrl  <= ~ioctl_addr[0];
				dl_wrh  <=  ioctl_addr[0];
				dl_req  <= 1'b1;
				dbg_dl_bytes <= dbg_dl_bytes + 32'd1;
			end
		end
	end
	assign ioctl_wait = dl_req;

	wire cache_reset = reset | ioctl_download;

	// ============================================================ port 0
	wire [24:1] p0_addr [0:0]; wire p0_we [0:0]; wire p0_wrl [0:0]; wire p0_wrh [0:0];
	wire [15:0] p0_din [0:0];  wire p0_req [0:0]; wire p0_busy [0:0]; wire p0_valid [0:0];
	wire [15:0] p0_dout [0:0]; wire [31:0] p0_pair [0:0];
	assign p0_addr[0] = dl_addr; assign p0_we[0] = 1'b1; assign p0_wrl[0] = dl_wrl; assign p0_wrh[0] = dl_wrh;
	assign p0_din[0] = dl_din;   assign p0_req[0] = dl_req; assign dl_valid = p0_valid[0];
	sdram_arb #(.N(1)) u_arb0 (
		.clk(clk), .reset(pwr_reset),
		.i_addr(p0_addr), .i_we(p0_we), .i_wrl(p0_wrl), .i_wrh(p0_wrh),
		.i_din(p0_din), .i_req(p0_req), .i_busy(p0_busy),
		.i_valid(p0_valid), .i_dout(p0_dout), .i_dout_pair(p0_pair),
		.sdram_addr(sdram_addr0), .sdram_wrl(sdram_wrl0), .sdram_wrh(sdram_wrh0),
		.sdram_din(sdram_din0), .sdram_dout(sdram_dout0),
		.sdram_dout_pair(sdram_pair0), .sdram_req(sdram_req0), .sdram_ack(sdram_ack0));

	// ============================================================ port 1: BG, FG
	wire [24:1] p1_addr [0:1]; wire p1_we [0:1]; wire p1_wrl [0:1]; wire p1_wrh [0:1];
	wire [15:0] p1_din [0:1];  wire p1_req [0:1]; wire p1_busy [0:1]; wire p1_valid [0:1];
	wire [15:0] p1_dout [0:1]; wire [31:0] p1_pair [0:1];
	wire [3:0]  drop_bg, drop_fg, drop_spr, drop_adp;
	wire [7:0]  bg_b, fg_b, spr_b;
	gn_romport #(.AW(17), .BASE_W(BGT_W)) u_bg (
		.clk(clk), .reset(cache_reset), .req(bg_req), .addr(bg_addr), .ack(bg_ack), .data32(bg_data), .data8(bg_b),
		.a_addr(p1_addr[0]), .a_req(p1_req[0]), .a_valid(p1_valid[0]), .a_dout(p1_dout[0]), .a_pair(p1_pair[0]), .dropped(drop_bg));
	gn_romport #(.AW(17), .BASE_W(FGT_W)) u_fg (
		.clk(clk), .reset(cache_reset), .req(fg_req), .addr(fg_addr), .ack(fg_ack), .data32(fg_data), .data8(fg_b),
		.a_addr(p1_addr[1]), .a_req(p1_req[1]), .a_valid(p1_valid[1]), .a_dout(p1_dout[1]), .a_pair(p1_pair[1]), .dropped(drop_fg));
	assign p1_we[0] = 1'b0; assign p1_wrl[0] = 1'b0; assign p1_wrh[0] = 1'b0; assign p1_din[0] = 16'd0;
	assign p1_we[1] = 1'b0; assign p1_wrl[1] = 1'b0; assign p1_wrh[1] = 1'b0; assign p1_din[1] = 16'd0;
	sdram_arb #(.N(2)) u_arb1 (
		.clk(clk), .reset(cache_reset),
		.i_addr(p1_addr), .i_we(p1_we), .i_wrl(p1_wrl), .i_wrh(p1_wrh),
		.i_din(p1_din), .i_req(p1_req), .i_busy(p1_busy),
		.i_valid(p1_valid), .i_dout(p1_dout), .i_dout_pair(p1_pair),
		.sdram_addr(sdram_addr1), .sdram_wrl(sdram_wrl1), .sdram_wrh(sdram_wrh1),
		.sdram_din(sdram_din1), .sdram_dout(sdram_dout1),
		.sdram_dout_pair(sdram_pair1), .sdram_req(sdram_req1), .sdram_ack(sdram_ack1));

	// ============================================================ port 2: sprites
	// Behind an arbiter even with one consumer: the arbiter's "seen low once"
	// rule is what keeps a held request from being served twice (SS-12 #3).
	wire [24:1] p2_addr [0:0]; wire p2_we [0:0]; wire p2_wrl [0:0]; wire p2_wrh [0:0];
	wire [15:0] p2_din [0:0];  wire p2_req [0:0]; wire p2_busy [0:0]; wire p2_valid [0:0];
	wire [15:0] p2_dout [0:0]; wire [31:0] p2_pair [0:0];
	gn_romport #(.AW(19), .BASE_W(SPR_W)) u_spr (
		.clk(clk), .reset(cache_reset), .req(spr_req), .addr(spr_addr), .ack(spr_ack), .data32(spr_data), .data8(spr_b),
		.a_addr(p2_addr[0]), .a_req(p2_req[0]), .a_valid(p2_valid[0]), .a_dout(p2_dout[0]), .a_pair(p2_pair[0]), .dropped(drop_spr));
	assign p2_we[0] = 1'b0; assign p2_wrl[0] = 1'b0; assign p2_wrh[0] = 1'b0; assign p2_din[0] = 16'd0;
	sdram_arb #(.N(1)) u_arb2 (
		.clk(clk), .reset(cache_reset),
		.i_addr(p2_addr), .i_we(p2_we), .i_wrl(p2_wrl), .i_wrh(p2_wrh),
		.i_din(p2_din), .i_req(p2_req), .i_busy(p2_busy),
		.i_valid(p2_valid), .i_dout(p2_dout), .i_dout_pair(p2_pair),
		.sdram_addr(sdram_addr2), .sdram_wrl(sdram_wrl2), .sdram_wrh(sdram_wrh2),
		.sdram_din(sdram_din2), .sdram_dout(sdram_dout2),
		.sdram_dout_pair(sdram_pair2), .sdram_req(sdram_req2), .sdram_ack(sdram_ack2));

	// ============================================================ port 3: ADPCM
	wire [24:1] p3_addr [0:0]; wire p3_we [0:0]; wire p3_wrl [0:0]; wire p3_wrh [0:0];
	wire [15:0] p3_din [0:0];  wire p3_req [0:0]; wire p3_busy [0:0]; wire p3_valid [0:0];
	wire [15:0] p3_dout [0:0]; wire [31:0] p3_pair [0:0];
	wire [31:0] adp_w;
	gn_romport #(.AW(24), .BASE_W(ADP_W)) u_adp (
		.clk(clk), .reset(cache_reset), .req(adpcm_req), .addr(adpcm_addr), .ack(adpcm_ack), .data32(adp_w), .data8(adpcm_data),
		.a_addr(p3_addr[0]), .a_req(p3_req[0]), .a_valid(p3_valid[0]), .a_dout(p3_dout[0]), .a_pair(p3_pair[0]), .dropped(drop_adp));
	assign p3_we[0] = 1'b0; assign p3_wrl[0] = 1'b0; assign p3_wrh[0] = 1'b0; assign p3_din[0] = 16'd0;
	sdram_arb #(.N(1)) u_arb3 (
		.clk(clk), .reset(cache_reset),
		.i_addr(p3_addr), .i_we(p3_we), .i_wrl(p3_wrl), .i_wrh(p3_wrh),
		.i_din(p3_din), .i_req(p3_req), .i_busy(p3_busy),
		.i_valid(p3_valid), .i_dout(p3_dout), .i_dout_pair(p3_pair),
		.sdram_addr(sdram_addr3), .sdram_wrl(sdram_wrl3), .sdram_wrh(sdram_wrh3),
		.sdram_din(sdram_din3), .sdram_dout(sdram_dout3),
		.sdram_dout_pair(sdram_pair3), .sdram_req(sdram_req3), .sdram_ack(sdram_ack3));

	assign dbg_dropped = {drop_adp, drop_spr, drop_fg, drop_bg};
endmodule

// One ROM stream onto one sdram_arb channel.
//
// The consumer holds `req` with a byte address until `ack` (one clock, data
// held after it). The arbiter wants its request held until `a_valid` and then
// seen low once, so the port keeps its own request: once issued it stays up
// until the answer arrives, whatever the consumer does. An answer is
// delivered only if the consumer still wants that address; a request that
// was withdrawn (the sprite engine's restart) or moved on is discarded, and
// the new address goes out after it. One idle clock after every answer
// covers the clock in which the consumer has seen `ack` but its `req` still
// reads high.
module gn_romport #(
	parameter AW = 17,
	parameter [23:0] BASE_W = 24'd0
) (
	input             clk,
	input             reset,
	input             req,
	input  [AW-1:0]   addr,
	output reg        ack,
	output reg [31:0] data32,          // bytes addr..addr+3, first on top (addr 4-aligned)
	output reg [7:0]  data8,           // the byte at addr
	output [24:1]     a_addr,
	output            a_req,
	input             a_valid,
	input  [15:0]     a_dout,
	input  [31:0]     a_pair,
	output reg [3:0]  dropped          // saturating count of discarded answers
);
	reg          pend, gap;
	reg [AW-1:0] la;
	assign a_req  = pend;
	assign a_addr = BASE_W + {{(24 - AW + 1){1'b0}}, la[AW-1:1]};
	always @(posedge clk) begin
		ack <= 1'b0; gap <= 1'b0;
		if (reset) begin pend <= 1'b0; dropped <= 4'd0; end
		else if (!pend) begin
			if (req && !gap && !ack) begin la <= addr; pend <= 1'b1; end
		end else if (a_valid) begin
			pend <= 1'b0; gap <= 1'b1;
			if (req && addr == la) begin
				ack    <= 1'b1;
				data32 <= {a_pair[7:0], a_pair[15:8], a_pair[23:16], a_pair[31:24]};
				data8  <= la[0] ? a_dout[15:8] : a_dout[7:0];
			end else if (dropped != 4'hF) dropped <= dropped + 4'd1;
		end
	end
endmodule
