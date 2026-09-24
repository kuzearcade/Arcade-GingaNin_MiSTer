// The Y8950's DELTA-T (ADPCM-B) unit: a port of MAME's ymfm adpcm_b_channel
// (3rdparty/ymfm/src/ymfm_adpcm.cpp, Aaron Giles, BSD-3-Clause), the oracle
// this core is measured against (docs/PLAN.md 2.5; GN-5).
//
// Scope: what Ginga Ninkyouden drives (GN-3): playback from external ROM,
// with repeat, EOS and level. Record mode and CPU-fed data are not
// implemented; a register write that would start them is ignored.
//
// Registers (ymfm's numbering; gn_y8950 maps the Y8950's 0x07-0x12 and
// 0x15-0x17 onto them): 0 control (7 execute, 6 record, 5 external, 4 repeat,
// 0 reset), 1 (7:6 pan, 1 8-bit DRAM, 0 ROM), 2/3 start, 4/5 end, 9/10
// Delta-N, 11 level, 12/13 limit (0xFFFF at reset: the Y8950 does not map it).
//
// One `step` per FM sample runs ymfm's clock(): the position advances by
// Delta-N; on overflow one nibble is decoded; with fewer than 3 nibbles
// buffered a byte is fetched (the fetch returns well within the 20 us of a
// sample). `pcm` is ymfm's output(): the linear interpolation of the last two
// outputs, times level, >> (8 + 3).
module gn_adpcmb (
	input                clk,
	input                reset,
	input                step,          // one clock per FM sample
	input                wr,            // register write
	input         [4:0]  wreg,
	input         [7:0]  wdata,
	// external ROM, byte address; held request, one-clock ack with data
	output reg           mem_req,
	output reg    [23:0] mem_addr,
	input                mem_ack,
	input         [7:0]  mem_data,
	output               flag_eos,
	output reg signed [15:0] pcm,
	output               busy           // a step is still being processed
);
	localparam [31:0] LATCH = 32'hFFFFFFFF;
	localparam S_BRDY = 1, S_EOS = 0, S_PLAYING = 2;   // status bits (ymfm: EOS 0x01, BRDY 0x02, PLAYING 0x04)
	reg  [7:0]  r [0:16];
	reg  [7:0]  st;                  // [0] EOS [1] BRDY [2] PLAYING [3] INT_PLAYING [4] INT_DRAIN
	reg  [31:0] buffer;
	reg  [3:0]  nibbles;
	reg  [15:0] position;
	reg  [31:0] cur;                 // LATCH or a byte address
	reg signed [15:0] acc, out, prev;
	reg  [15:0] adstep;
	wire        execute  = r[0][7], record = r[0][6], external = r[0][5], repeat_ = r[0][4];
	wire [4:0]  shift    = (r[1][0] || r[1][1]) ? 5'd5 : 5'd2;
	wire [15:0] start_u  = {r[3], r[2]};
	wire [15:0] end_u    = {r[5], r[4]};
	wire [15:0] limit_u  = {r[13], r[12]};
	wire [15:0] delta_n  = {r[10], r[9]};
	assign flag_eos = st[0];

	function [15:0] clamp16(input signed [31:0] v);
		clamp16 = (v > 32767) ? 16'sd32767 : (v < -32768) ? -16'sd32768 : v[15:0];
	endfunction
	function [7:0] scale(input [2:0] n);
		case (n) 3'd4: scale = 77; 3'd5: scale = 102; 3'd6: scale = 128; 3'd7: scale = 153; default: scale = 57; endcase
	endfunction

	// output: interpolation and level (ymfm's output(), rshift 3)
	// (position ^ 0xFFFF) + 1 = 0x10000 - position, written as a subtraction:
	// `(~position) + 17'd1` widens position to 17 bits before the ~ (Verilog's
	// context sizing) and gave 0x20000 - position (the first port's bug)
	wire [16:0] w_prev = 17'h10000 - {1'b0, position};
	wire signed [33:0] interp = ($signed({{18{prev[15]}}, prev}) * $signed({17'd0, w_prev})
	                           + $signed({{18{out[15]}}, out}) * $signed({18'd0, position})) >>> 16;
	wire signed [41:0] lv = interp * $signed({1'b0, r[11]});
	always @(posedge clk) pcm <= lv >>> 11;

	// step FSM
	localparam P_IDLE = 3'd0, P_FETCH = 3'd1, P_WAIT = 3'd2, P_AFTER = 3'd3;
	reg [2:0]  ph;
	reg        chop;                 // the fetch hit the end: drop 3 nibbles after appending
	assign busy = ph != P_IDLE;
	integer i;

	task automatic append(input [7:0] d);
		begin
			buffer <= buffer | ({24'd0, d} << (24 - 4 * nibbles));
			nibbles <= nibbles + 4'd2;
		end
	endtask

	always @(posedge clk) begin
		if (reset) begin
			for (i = 0; i <= 16; i = i + 1) r[i] <= 8'd0;
			r[12] <= 8'hFF; r[13] <= 8'hFF;
			st <= 8'h02; buffer <= 32'd0; nibbles <= 4'd0; position <= 16'd0; cur <= 32'd0;
			acc <= 16'sd0; out <= 16'sd0; prev <= 16'sd0; adstep <= 16'd127;
			ph <= P_IDLE; mem_req <= 1'b0; chop <= 1'b0;
		end else begin
			// ---------------------------------------------------- register writes (ymfm write())
			if (wr) begin
				r[wreg] <= wdata;
				if (wreg == 5'd0) begin
					if (wdata[0]) begin
						// reset: stop and hold the output; BRDY, and EOS if it was playing
						st[3] <= 1'b0; st[1] <= 1'b1;
						if (st[3]) st[0] <= 1'b1;
					end else begin
						st[1] <= 1'b1; st[2] <= 1'b0; st[4] <= 1'b0; st[3] <= 1'b0;
						cur <= LATCH;
						if (wdata[7] && !wdata[6] && wdata[5]) begin      // execute from external memory
							buffer <= 32'd0; nibbles <= 4'd0; position <= 16'd0;
							acc <= 16'sd0; adstep <= 16'd127; out <= 16'sd0;
							st[2] <= 1'b1; st[3] <= 1'b1; st[0] <= 1'b0;
						end
					end
				end
			end
			// ---------------------------------------------------- one sample (ymfm clock())
			case (ph)
			P_IDLE: if (step) begin
				if (!execute || record || !st[3]) begin
					prev <= out; position <= 16'd0; st[3] <= 1'b0;
				end else begin : adv
					reg [16:0] p;
					p = {1'b0, position} + {1'b0, delta_n};
					position <= p[15:0];
					if (p[16]) begin
						if (nibbles != 0) begin : dec
							reg [3:0]  n;
							reg signed [31:0] d, a2;
							reg [31:0] s2;
							reg [3:0]  left;
							n = buffer[31:28];
							buffer <= buffer << 4;
							left = nibbles - 4'd1;
							nibbles <= left;
							d = ((2 * n[2:0] + 1) * adstep) / 8;
							if (n[3]) d = -d;
							a2 = $signed({{16{acc[15]}}, acc}) + d;
							s2 = (adstep * scale(n[2:0])) / 64;
							prev <= out;
							out <= clamp16(a2);
							if (left == 0) begin
								acc <= 16'sd0; adstep <= 16'd127; st[0] <= 1'b1;
								if (!repeat_) st[3] <= 1'b0;
							end else begin
								acc <= clamp16(a2);
								adstep <= (s2 < 127) ? 16'd127 : (s2 > 24576) ? 16'd24576 : s2[15:0];
							end
							// a fetch follows if still playing with < 3 nibbles
							if ((left == 0 ? repeat_ : 1'b1) && left < 3) ph <= P_FETCH;
						end else if (nibbles < 3) ph <= P_FETCH;
					end
				end
			end
			P_FETCH: begin
				// request_data(): latch, read, append, advance
				if (cur == LATCH) cur <= {8'd0, 24'({start_u, 5'd0} >> (5'd5 - shift))};
				ph <= P_WAIT;
			end
			P_WAIT: begin
				if (!mem_req) begin mem_req <= 1'b1; mem_addr <= cur[23:0]; end
				else if (mem_ack) begin : got
					reg [31:0] mask;
					mem_req <= 1'b0;
					append(mem_data);
					r[8] <= mem_data;
					mask = (32'd1 << shift) - 32'd1;
					chop <= 1'b0;
					if ((cur & mask) == mask && (cur >> shift) == {16'd0, end_u}) chop <= 1'b1;
					else if ((cur & mask) == mask && (cur >> shift) == {16'd0, limit_u}) cur <= 32'd0;
					else cur <= (cur + 32'd1) & 32'h00FFFFFF;
					ph <= P_AFTER;
				end
			end
			P_AFTER: begin
				if (chop) begin
					// the final 3 samples are not played (ymfm: consume_nibbles(3))
					buffer <= buffer << 12;
					nibbles <= (nibbles > 3) ? nibbles - 4'd3 : 4'd0;
					if (repeat_) cur <= {8'd0, 24'({start_u, 5'd0} >> (5'd5 - shift))};
				end
				ph <= P_IDLE;
			end
			default: ph <= P_IDLE;
			endcase
		end
	end
endmodule
