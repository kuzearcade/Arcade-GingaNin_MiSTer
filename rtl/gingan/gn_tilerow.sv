// One line of a 16x16 tilemap (BG or FG; docs/PLAN.md 1.4, 2.6).
//
// The map is NCOLS x 32 tiles in column order (MAME's TILEMAP_SCAN_COLS: tile
// index = col * 32 + row), one word per tile: code [11:0], colour [15:12];
// tile = code mod NTILES (1,024 here, a mask). For source line `line` (0-255
// of MAME's 256-line frame) the engine draws the 17 tiles covering screen
// x 0-255 at scroll (sx, sy): map pixel (x + sx) mod (NCOLS*16), line
// (line + sy) mod 512 (MAME's tilemap scrolling).
//
// Tile rows come from the ROM port as two 32-bit reads (the tile format
// gfx_8x8x4_col_2x2_group_packed_msb: row r is bytes 4r..4r+3 for the left 8
// pixels and 64+4r..64+4r+3 for the right 8, high nibble first). The port is
// a held request; `rom_data` is valid with `rom_ack` for one clock and holds
// {byte a, byte a+1, byte a+2, byte a+3}.
//
// Output: one {colour, pen} write per pixel into the caller's line buffer.
module gn_tilerow #(
	parameter NCOLS = 512,          // 512 for BG, 256 for FG
	parameter MAPW  = 14            // map index width (log2(NCOLS * 32))
) (
	input             clk,
	input             reset,
	input             start,        // one clock: draw `line` now
	input      [7:0]  line,
	input      [15:0] sx,
	input      [15:0] sy,
	output reg        busy,
	// the map (1-clock read)
	output reg [MAPW-1:0] map_addr,
	input      [15:0] map_data,
	// tile ROM: byte address within the region
	output reg        rom_req,
	output reg [16:0] rom_addr,
	input             rom_ack,
	input      [31:0] rom_data,
	// line buffer
	output reg        lb_we,
	output reg [7:0]  lb_x,
	output reg [7:0]  lb_d          // {colour, pen}
);
	localparam S_IDLE = 3'd0, S_MAP = 3'd1, S_MAPQ = 3'd2, S_ROM = 3'd3, S_DRAW = 3'd4;
	reg [2:0]  st;
	reg [4:0]  i;                   // tile column 0..16
	reg [8:0]  my;                  // map line 0..511
	reg [3:0]  fine;
	reg [15:0] lsx;                 // X scroll latched at start: a mid-line write
	                                // lands on the next line, whatever the ROM latency (M3)
	reg [15:0] word;
	reg        half;                // 0 = left 8 px, 1 = right 8 px
	reg [31:0] px;
	reg [3:0]  k;                   // pixel within the half
	wire [15:0] mapx = lsx + {7'd0, i, 4'd0};
	wire [MAPW-6:0] col = mapx[MAPW-2:4];      // mod NCOLS (a power of two)
	// the screen x of pixel k of this half: 16*i + 8*half + k - fine
	wire [9:0] scr_x = {1'b0, i, 4'd0} + {5'd0, half, 3'd0} + {6'd0, k} - {6'd0, fine};

	always @(posedge clk) begin
		lb_we <= 1'b0;
		if (reset) begin st <= S_IDLE; busy <= 1'b0; rom_req <= 1'b0; half <= 1'b0; end
		else case (st)
		S_IDLE: if (start) begin
			busy <= 1'b1; i <= 5'd0; half <= 1'b0; fine <= sx[3:0]; lsx <= sx;
			my <= {1'b0, line} + sy[8:0];
			st <= S_MAP;
		end
		S_MAP: begin
			map_addr <= {col, my[8:4]};        // the map RAM samples it at the next edge
			st <= S_MAPQ;
		end
		S_MAPQ: st <= S_ROM;                  // map_data is valid during the next state
		S_ROM: begin
			if (!rom_req) begin
				if (!half) word <= map_data;
				rom_req <= 1'b1;
				rom_addr <= {(half ? word[9:0] : map_data[9:0]), 7'd0} + {10'd0, half, 6'd0} + {11'd0, my[3:0], 2'd0};
			end else if (rom_ack) begin
				rom_req <= 1'b0; px <= rom_data; k <= 4'd0; st <= S_DRAW;
			end
		end
		S_DRAW: begin
			if (scr_x[9:8] == 2'b00) begin
				lb_we <= 1'b1; lb_x <= scr_x[7:0]; lb_d <= {word[15:12], px[31:28]};
			end
			px <= px << 4;
			k <= k + 4'd1;
			if (k == 4'd7) begin
				if (!half) begin half <= 1'b1; st <= S_ROM; end
				else begin
					half <= 1'b0;
					if (i == 5'd16) begin st <= S_IDLE; busy <= 1'b0; end
					else begin i <= i + 5'd1; st <= S_MAP; end
				end
			end
		end
		default: st <= S_IDLE;
		endcase
	end
endmodule
