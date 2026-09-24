// Ginga Ninkyouden video (docs/PLAN.md 1.4, 2.2, 2.6): raster, the CPU's
// video memories, the ROM-resident BG map and text tiles, four line engines,
// the mixer and the palette.
//
// Raster (D3): a 6 MHz dot (ce_pix = clk / 8), 400 dots x 250 lines = exactly
// 100,000 dots a frame = 60.000 Hz, MAME's frame period. Lines are numbered as
// MAME's 256-line frame: 16-239 are visible (224), 240 starts vblank (IRQ1),
// the frame wraps after 249. Dots 0-255 are visible.
//
// Each line the engines draw the line after next into back buffers, which
// swap at the end of every line. With flip (vregs[6] bit 0 clear) the whole 256 x 256 frame is
// turned 180 degrees: the engines draw source line 255 - y and the buffers
// are read mirrored (verified against MAME's flipped output, GN-2's sweep).
//
// Composition (GN-2's model, exact against MAME): text over sprites over FG
// over BG; pen 15 is clear on text, sprites and FG; BG disabled shows pen 0.
// Palette RGBx_444 looked up at scan-out; an entry never written shows MAME's
// default colour (GN-1).
//
// CPU map (word addresses within the main bus, 68000 byte lanes on be):
//   sel_txt 030000-0307FF (1,024)   sel_spr 040000-0407FF (1,024)
//   sel_pal 050000-0507FF (1,024)   sel_reg 060000-06000F (8)
//   sel_fg  068000-06BFFF (8,192)
module gn_video (
	input             clk,
	input             reset,
	// raster out
	output reg        ce_pix,
	output reg [8:0]  hcount,
	output reg [8:0]  vcount,
	output            hblank,
	output            vblank,
	output            hsync,
	output            vsync,
	output reg        vblank_start,  // one clock at line 240, dot 0
	// CPU
	input             sel_txt, sel_spr, sel_pal, sel_reg, sel_fg,
	input      [12:0] cpu_addr,      // word address within the selected block
	input             cpu_we,
	input      [1:0]  cpu_be,        // {upper, lower}
	input      [15:0] cpu_din,
	output reg [15:0] cpu_dout,      // valid 2 clocks after the address
	output     [2:0]  layer_ctrl_dbg,
	output     [15:0] vreg_out [0:7],
	// ROM download into the BRAM regions (byte writes)
	input             dl_we,
	input             dl_bgmap,      // 0 = text tiles (16 KB), 1 = BG map (32 KB)
	input      [14:0] dl_addr,
	input      [7:0]  dl_data,
	// tile ROM ports (held request)
	output            bg_req,
	output     [16:0] bg_addr,
	input             bg_ack,
	input      [31:0] bg_data,
	output            fg_req,
	output     [16:0] fg_addr,
	input             fg_ack,
	input      [31:0] fg_data,
	output            spr_req,
	output     [18:0] spr_addr,
	input             spr_ack,
	input      [31:0] spr_data,
	// picture
	output reg [23:0] rgb,
	output     [15:0] dbg_spr_overruns
);
	// ---------------------------------------------------------------- raster
	reg [2:0] div;
	always @(posedge clk) begin
		ce_pix <= 1'b0; vblank_start <= 1'b0;
		if (reset) begin div <= 3'd0; hcount <= 9'd0; vcount <= 9'd0; end
		else begin
			div <= div + 3'd1;
			if (div == 3'd7) begin
				ce_pix <= 1'b1;
				if (hcount == 9'd399) begin
					hcount <= 9'd0;
					vcount <= (vcount == 9'd249) ? 9'd0 : vcount + 9'd1;
					if (vcount == 9'd239) vblank_start <= 1'b1;
				end else hcount <= hcount + 9'd1;
			end
		end
	end
	assign hblank = hcount >= 9'd256;
	assign vblank = vcount < 9'd16 || vcount >= 9'd240;
	assign hsync  = hcount >= 9'd300 && hcount < 9'd332;
	assign vsync  = vcount >= 9'd243 && vcount < 9'd246;

	// ---------------------------------------------------------------- vregs
	reg [15:0] vr [0:7];
	integer ri;
	always @(posedge clk) begin
		if (reset) for (ri = 0; ri < 8; ri = ri + 1) vr[ri] <= 16'd0;
		else if (sel_reg && cpu_we) begin
			if (cpu_be[1]) vr[cpu_addr[2:0]][15:8] <= cpu_din[15:8];
			if (cpu_be[0]) vr[cpu_addr[2:0]][7:0]  <= cpu_din[7:0];
		end
	end
	genvar gi;
	generate for (gi = 0; gi < 8; gi = gi + 1) begin : vo assign vreg_out[gi] = vr[gi]; end endgenerate
	wire [3:0] ctrl = vr[4][3:0];
	wire       flip = ~vr[6][0];
	assign layer_ctrl_dbg = ctrl[2:0];

	// ---------------------------------------------------------------- CPU RAMs
	// byte-lane arrays, the true-dual-port template: port A the CPU, port B video
	wire tw = sel_txt && cpu_we, sw = sel_spr && cpu_we, pw = sel_pal && cpu_we, fw = sel_fg && cpu_we;
	reg [7:0] txt_h [0:1023], txt_l [0:1023], fg_h [0:8191], fg_l [0:8191];
	reg [7:0] pal_h [0:1023], pal_l [0:1023], spr_h [0:1023], spr_l [0:1023];
	reg [7:0] txt_qa_h, txt_qa_l, fg_qa_h, fg_qa_l, pal_qa_h, pal_qa_l, spr_qa_h, spr_qa_l;
	always @(posedge clk) begin if (tw & cpu_be[1]) txt_h[cpu_addr[9:0]] <= cpu_din[15:8]; txt_qa_h <= txt_h[cpu_addr[9:0]]; end
	always @(posedge clk) begin if (tw & cpu_be[0]) txt_l[cpu_addr[9:0]] <= cpu_din[7:0];  txt_qa_l <= txt_l[cpu_addr[9:0]]; end
	always @(posedge clk) begin if (fw & cpu_be[1]) fg_h[cpu_addr]        <= cpu_din[15:8]; fg_qa_h  <= fg_h[cpu_addr]; end
	always @(posedge clk) begin if (fw & cpu_be[0]) fg_l[cpu_addr]        <= cpu_din[7:0];  fg_qa_l  <= fg_l[cpu_addr]; end
	always @(posedge clk) begin if (pw & cpu_be[1]) pal_h[cpu_addr[9:0]] <= cpu_din[15:8]; pal_qa_h <= pal_h[cpu_addr[9:0]]; end
	always @(posedge clk) begin if (pw & cpu_be[0]) pal_l[cpu_addr[9:0]] <= cpu_din[7:0];  pal_qa_l <= pal_l[cpu_addr[9:0]]; end
	always @(posedge clk) begin if (sw & cpu_be[1]) spr_h[cpu_addr[9:0]] <= cpu_din[15:8]; spr_qa_h <= spr_h[cpu_addr[9:0]]; end
	always @(posedge clk) begin if (sw & cpu_be[0]) spr_l[cpu_addr[9:0]] <= cpu_din[7:0];  spr_qa_l <= spr_l[cpu_addr[9:0]]; end
	reg [2:0] rsel;
	always @(posedge clk) begin
		rsel <= sel_txt ? 3'd1 : sel_spr ? 3'd2 : sel_pal ? 3'd3 : sel_fg ? 3'd4 : sel_reg ? 3'd5 : 3'd0;
		case (rsel)
			3'd1: cpu_dout <= {txt_qa_h, txt_qa_l};
			3'd2: cpu_dout <= {spr_qa_h, spr_qa_l};
			3'd3: cpu_dout <= {pal_qa_h, pal_qa_l};
			3'd4: cpu_dout <= {fg_qa_h, fg_qa_l};
			3'd5: cpu_dout <= vr[cpu_addr[2:0]];
			default: cpu_dout <= 16'h0000;
		endcase
	end

	// sprite scan copy: 256 x 64, one entry a clock ({y, x, code, attr}). One
	// byte-lane array per byte, each with a plain write (MS1Z-6: a
	// read-modify-write lane does not infer as RAM in Quartus 17).
	wire [7:0]  ent_addr;
	reg  [63:0] ent_q;
	genvar ge;
	generate for (ge = 0; ge < 8; ge = ge + 1) begin : ent
		// lane ge holds byte (7 - ge) of the entry: word ge/2, upper byte when ge is even
		reg [7:0] m [0:255];
		wire we = sw && cpu_addr[1:0] == ge[2:1] && cpu_be[~ge[0]];
		always @(posedge clk) begin
			if (we) m[cpu_addr[9:2]] <= ge[0] ? cpu_din[7:0] : cpu_din[15:8];
			ent_q[63 - 8 * ge -: 8] <= m[ent_addr];
		end
	end endgenerate

	// palette written flags (GN-1)
	reg [1023:0] pal_wr;
	always @(posedge clk) begin
		if (reset) pal_wr <= '0;
		else if (pw) pal_wr[cpu_addr[9:0]] <= 1'b1;
	end

	// ---------------------------------------------------------------- ROM BRAMs
	reg [7:0]  bgmap [0:32767];
	reg [7:0]  txtt [0:16383];
	always @(posedge clk) begin
		if (dl_we &&  dl_bgmap) bgmap[dl_addr] <= dl_data;
		if (dl_we && !dl_bgmap) txtt[dl_addr[13:0]] <= dl_data;
	end

	// ---------------------------------------------------------------- line engines
	// At the end of line v the buffers swap: the bank drawn during line v is
	// shown during line v+1, and the engines start on line v+2 (drawing the
	// line about to be shown would race the beam). Turned for flip.
	wire [8:0] vnext2 = (vcount >= 9'd248) ? vcount - 9'd248 : vcount + 9'd2;
	wire [7:0] src    = flip ? 8'd255 - vnext2[7:0] : vnext2[7:0];
	wire       line_start = ce_pix && hcount == 9'd399;       // the dot before a new line
	reg        start;
	reg  [7:0] src_q;
	// only visible lines are drawn: unused sprites parked at the top of the
	// screen (lines 0-15) make those lines far too slow, and they are never
	// shown (GN-6)
	wire src_vis = src >= 8'd16 && src < 8'd240;
	always @(posedge clk) begin start <= line_start && src_vis; if (line_start) src_q <= src; end
	reg        bufsel;                                        // the buffer being displayed
	always @(posedge clk) if (reset) bufsel <= 1'b0; else if (line_start) bufsel <= ~bufsel;

	// BG: map from the BRAM (big-endian word), tiles from bg_*
	wire [13:0] bg_map_a;
	reg  [15:0] bg_map_q;
	always @(posedge clk) bg_map_q <= {bgmap[{bg_map_a, 1'b0}], bgmap[{bg_map_a, 1'b1}]};
	wire        bg_we;  wire [7:0] bg_x, bg_d;
	gn_tilerow #(.NCOLS(512), .MAPW(14)) u_bg (
		.clk(clk), .reset(reset), .start(start), .line(src_q), .sx(vr[3]), .sy(vr[2]), .busy(),
		.map_addr(bg_map_a), .map_data(bg_map_q),
		.rom_req(bg_req), .rom_addr(bg_addr), .rom_ack(bg_ack), .rom_data(bg_data),
		.lb_we(bg_we), .lb_x(bg_x), .lb_d(bg_d));
	// FG: map from FG VRAM (port B)
	wire [12:0] fg_map_a;
	reg  [15:0] fg_map_q;
	always @(posedge clk) fg_map_q <= {fg_h[fg_map_a], fg_l[fg_map_a]};
	wire        fg_we;  wire [7:0] fg_x, fg_d;
	gn_tilerow #(.NCOLS(256), .MAPW(13)) u_fg (
		.clk(clk), .reset(reset), .start(start), .line(src_q), .sx(vr[1]), .sy(vr[0]), .busy(),
		.map_addr(fg_map_a), .map_data(fg_map_q),
		.rom_req(fg_req), .rom_addr(fg_addr), .rom_ack(fg_ack), .rom_data(fg_data),
		.lb_we(fg_we), .lb_x(fg_x), .lb_d(fg_d));
	// sprites
	wire        sp_we;  wire [7:0] sp_x, sp_d;
	gn_sprline u_spr (
		.clk(clk), .reset(reset), .start(start), .line(src_q), .busy(),
		.ent_addr(ent_addr), .ent_q(ent_q),
		.rom_req(spr_req), .rom_addr(spr_addr), .rom_ack(spr_ack), .rom_data(spr_data),
		.lb_we(sp_we), .lb_x(sp_x), .lb_d(sp_d), .overruns(dbg_spr_overruns));
	// text: 32 x 32 map in rows, 8x8 tiles from the BRAM (row r of tile t is
	// bytes 32t + 4r .. +3, high nibble first)
	reg  [2:0]  tx_st;
	reg  [4:0]  tx_col;
	reg  [15:0] tx_word;
	reg  [31:0] tx_px;
	reg  [3:0]  tx_k;
	reg         tx_we;  reg [7:0] tx_x, tx_d;
	reg  [9:0]  tx_map_a;
	reg  [15:0] tx_map_q;
	always @(posedge clk) tx_map_q <= {txt_h[tx_map_a], txt_l[tx_map_a]};
	reg  [13:0] tx_rom_a;
	reg  [31:0] tx_rom_q;
	always @(posedge clk) tx_rom_q <= {txtt[{tx_rom_a[13:2], 2'd0}], txtt[{tx_rom_a[13:2], 2'd1}], txtt[{tx_rom_a[13:2], 2'd2}], txtt[{tx_rom_a[13:2], 2'd3}]};
	always @(posedge clk) begin
		tx_we <= 1'b0;
		if (reset) tx_st <= 3'd0;
		else case (tx_st)
		3'd0: if (start) begin tx_col <= 5'd0; tx_st <= 3'd1; end
		3'd1: begin tx_map_a <= {src_q[7:3], tx_col}; tx_st <= 3'd2; end
		3'd2: tx_st <= 3'd3;
		3'd3: begin tx_word <= tx_map_q; tx_rom_a <= {tx_map_q[8:0], src_q[2:0], 2'd0}; tx_st <= 3'd4; end
		3'd4: tx_st <= 3'd5;
		3'd5: begin tx_px <= tx_rom_q; tx_k <= 4'd0; tx_st <= 3'd6; end
		3'd6: begin
			tx_we <= 1'b1; tx_x <= {tx_col, tx_k[2:0]}; tx_d <= {tx_word[15:12], tx_px[31:28]};
			tx_px <= tx_px << 4; tx_k <= tx_k + 4'd1;
			if (tx_k == 4'd7) begin
				if (tx_col == 5'd31) tx_st <= 3'd0;
				else begin tx_col <= tx_col + 5'd1; tx_st <= 3'd1; end
			end
		end
		default: tx_st <= 3'd0;
		endcase
	end

	// ---------------------------------------------------------------- line buffers
	// two banks per layer: the engines write bank ~bufsel, the beam reads bank
	// bufsel. BG, FG and text write every pixel of their line (pen 15
	// included); sprites write only their own pixels, so the beam clears the
	// sprite bank to pen 15 as it reads it (a second port: true dual port).
	reg [7:0] lb_bg [0:511], lb_fg [0:511], lb_sp [0:511], lb_tx [0:511];
	wire [7:0] rx = flip ? 8'd255 - hcount[7:0] : hcount[7:0];
	reg  [7:0] q_bg, q_fg, q_sp, q_tx;
	wire       rd = ce_pix && hcount < 9'd256;
	always @(posedge clk) begin
		if (bg_we) lb_bg[{~bufsel, bg_x}] <= bg_d;
		if (rd) q_bg <= lb_bg[{bufsel, rx}];
	end
	always @(posedge clk) begin
		if (fg_we) lb_fg[{~bufsel, fg_x}] <= fg_d;
		if (rd) q_fg <= lb_fg[{bufsel, rx}];
	end
	always @(posedge clk) if (sp_we) lb_sp[{~bufsel, sp_x}] <= sp_d;
	always @(posedge clk) if (rd) begin q_sp <= lb_sp[{bufsel, rx}]; lb_sp[{bufsel, rx}] <= 8'h0F; end
	always @(posedge clk) begin
		if (tx_we) lb_tx[{~bufsel, tx_x}] <= tx_d;
		if (rd) q_tx <= lb_tx[{bufsel, rx}];
	end

	// ---------------------------------------------------------------- mixer and palette
	reg        rd_d, vis_d;
	reg [9:0]  idx;
	reg [11:0] pal_q;
	reg        pal_wq;
	always @(posedge clk) begin
		rd_d <= rd; vis_d <= rd && !vblank;
		if (rd_d) begin
			if (ctrl[2] && q_tx[3:0] != 4'hF)      idx <= {2'd0, q_tx};
			else if (ctrl[3] && q_sp[3:0] != 4'hF) idx <= {2'd1, q_sp};
			else if (ctrl[1] && q_fg[3:0] != 4'hF) idx <= {2'd2, q_fg};
			else if (ctrl[0])                      idx <= {2'd3, q_bg};
			else                                   idx <= 10'd0;
		end
	end
	reg rd_dd, rd_ddd, vis_dd, vis_ddd;
	always @(posedge clk) begin
		rd_dd <= rd_d; rd_ddd <= rd_dd; vis_dd <= vis_d; vis_ddd <= vis_dd;
		pal_q  <= {pal_h[idx][7:0], pal_l[idx][7:4]};
		pal_wq <= pal_wr[idx];
		if (rd_ddd) begin
			if (!vis_ddd) rgb <= 24'd0;
			else if (pal_wq) rgb <= {pal_q[11:8], pal_q[11:8], pal_q[7:4], pal_q[7:4], pal_q[3:0], pal_q[3:0]};
			else rgb <= {{8{idx[0]}}, {8{idx[1]}}, {8{idx[2]}}};   // MAME's default palette (GN-1)
		end
	end
endmodule
