// One line of Ginga Ninkyouden's sprites (docs/PLAN.md 1.4, 2.6).
//
// 256 entries of four words (MAME's draw_sprites): Y and X 9-bit signed
// ((v & 0xFF) - (v & 0x100)), code [13:0] with flip X [14] and flip Y [15],
// colour [15:12] of word 3. Every sprite is 16x16 from the sprite ROM,
// tile = code mod 0xA00 (a true modulo, not a mask: NMK-25), pen 15 clear.
// MAME draws them in index order, so a later entry covers an earlier one;
// the engine walks the entries in the same order and a write simply
// overwrites the line buffer.
//
// The scan reads one whole entry a clock from `ent_q` (the caller keeps a
// 256 x 64 copy of sprite RAM for it). A hit fetches its row as two 32-bit
// ROM reads (the col_2x2 format: left 8 pixels at 4r, right 8 at 64 + 4r)
// and draws 16 pixels. `overrun` counts lines that were not finished by the
// next `start` (MS1-60, MS1Z-12).
module gn_sprline (
	input             clk,
	input             reset,
	input             start,
	input      [7:0]  line,
	output reg        busy,
	output reg [7:0]  ent_addr,
	input      [63:0] ent_q,         // {y, x, code, attr}, 1-clock read
	output reg        rom_req,
	output reg [18:0] rom_addr,      // byte address in the 320 KB region
	input             rom_ack,
	input      [31:0] rom_data,
	output reg        lb_we,
	output reg [7:0]  lb_x,
	output reg [7:0]  lb_d,          // {colour, pen}
	output reg [15:0] overruns
);
	localparam S_IDLE = 3'd0, S_READ = 3'd1, S_TEST = 3'd2, S_ROM = 3'd3, S_DRAW = 3'd4, S_WAIT = 3'd5;
	reg [2:0]  st;
	reg [8:0]  e;                    // entry 0..256
	reg [9:0]  sy;                   // signed Y of the hit
	reg [9:0]  sx;
	reg [3:0]  row;
	reg        fx;
	reg [3:0]  colr;
	reg [11:0] tile;
	reg        half;
	reg [31:0] px;
	reg [3:0]  k;
	function [9:0] s9(input [15:0] v);     // (v & 0xFF) - (v & 0x100), 10-bit two's complement
		s9 = {2'b00, v[7:0]} - {1'b0, v[8], 8'd0};   // - 0x100, not - 0x200 (the first version's bug)
	endfunction
	// code mod 0xA00 for a 14-bit code: subtract multiples of 0xA00
	function [11:0] mod_a00(input [13:0] c);
		reg [13:0] v;
		begin
			v = c;
			if (v >= 14'd10240) v = v - 14'd10240;   // 4 x 0xA00
			if (v >= 14'd5120)  v = v - 14'd5120;    // 2 x
			if (v >= 14'd2560)  v = v - 14'd2560;    // 1 x
			mod_a00 = v[11:0];
		end
	endfunction
	wire [9:0] dy = {2'b00, line} - s9(ent_q[63:48]);          // line - y
	// pixel k of this half on screen: x + 8*half + k (flip x mirrors within the sprite)
	wire [3:0] pk = fx ? (4'd15 - ({half, 3'd0} + k)) : ({half, 3'd0} + k);
	wire [9:0] scr_x = sx + {6'd0, pk};

	always @(posedge clk) begin
		lb_we <= 1'b0;
		if (reset) begin st <= S_IDLE; busy <= 1'b0; rom_req <= 1'b0; overruns <= 16'd0; end
		else begin
			// a start always begins the new line: one still in progress is
			// abandoned and counted (it would otherwise swallow this one)
			if (start) begin
				if (busy) overruns <= overruns + 16'd1;
				busy <= 1'b1; e <= 9'd0; ent_addr <= 8'd0; rom_req <= 1'b0; st <= S_READ;
			end else case (st)
			S_IDLE: ;
			S_READ: st <= S_TEST;            // ent_q is valid in S_TEST
			S_TEST: begin
				if (dy < 10'd16) begin
					sx <= s9(ent_q[47:32]);
					fx <= ent_q[30];
					row <= ent_q[31] ? 4'd15 - dy[3:0] : dy[3:0];
					colr <= ent_q[15:12];
					tile <= mod_a00(ent_q[29:16]);
					half <= 1'b0;
					st <= S_ROM;
				end else if (e == 9'd255) begin st <= S_IDLE; busy <= 1'b0; end
				else begin e <= e + 9'd1; ent_addr <= e[7:0] + 8'd1; st <= S_READ; end
			end
			S_ROM: begin
				if (!rom_req) begin
					rom_req <= 1'b1;
					rom_addr <= {tile, 7'd0} + {12'd0, half, 6'd0} + {13'd0, row, 2'd0};
				end else if (rom_ack) begin
					rom_req <= 1'b0; px <= rom_data; k <= 4'd0; st <= S_DRAW;
				end
			end
			S_DRAW: begin
				if (px[31:28] != 4'hF && scr_x[9:8] == 2'b00) begin
					lb_we <= 1'b1; lb_x <= scr_x[7:0]; lb_d <= {colr, px[31:28]};
				end
				px <= px << 4;
				k <= k + 4'd1;
				if (k == 4'd7) begin
					if (!half) begin half <= 1'b1; st <= S_ROM; end
					else if (e == 9'd255) begin st <= S_IDLE; busy <= 1'b0; end
					else begin e <= e + 9'd1; ent_addr <= e[7:0] + 8'd1; st <= S_READ; end
				end
			end
			default: st <= S_IDLE;
			endcase
		end
	end
endmodule
