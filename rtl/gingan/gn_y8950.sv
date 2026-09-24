// Yamaha Y8950 (MSX-AUDIO) for Ginga Ninkyouden: no open implementation
// exists (docs/PLAN.md fact 3), so it is composed the way MAME's ymfm builds
// it (ymfm_opl.cpp y8950):
//   FM     jtopl (YM3526, jotego/jtopl, vendored unmodified)
//   ADPCM  gn_adpcmb (a port of ymfm's adpcm_b_channel; GN-5)
//   output FM + ADPCM, then the YM3014 10.3 floating-point round trip
//
// Register routing follows y8950::write_data: every write goes to jtopl (the
// registers it does not decode are ignored there, and 0x08 only uses bits
// 7:6 as the FM's CSM/NOTE-SEL); 0x07, 0x09-0x12 and 0x15-0x17 also go to the
// ADPCM unit as its registers 0, 2-11 and 14-16; 0x08 goes to it as register
// 1 with bits 3:0 and pan-left forced on. Writes to the ADPCM unit wait while
// it is processing a sample (ymfm sees writes only between samples).
//
// The chip is write-only on this board (MAME maps no read), and its IRQ,
// timers and I/O ports are unused (GN-3).
module gn_y8950 (
	input                clk,
	input                reset,
	input                cen,           // 3.579545 MHz
	input                wr,            // one clock
	input                a0,
	input         [7:0]  din,
	// ADPCM ROM (byte address within the 128 KB region)
	output               mem_req,
	output        [23:0] mem_addr,
	input                mem_ack,
	input         [7:0]  mem_data,
	output reg signed [15:0] snd,       // after the DAC round trip
	output reg signed [15:0] snd_fm,    // FM part alone (debug / isolation)
	output reg signed [15:0] snd_adpcm, // ADPCM part alone
	output reg           sample         // one clock per output sample
);
	// ---------------------------------------------------------------- FM
	wire signed [15:0] fm;
	wire               fm_sample;
	jtopl u_fm (
		.rst(reset), .clk(clk), .cen(cen), .din(din), .addr(a0), .cs_n(~wr), .wr_n(~wr),
		.dout(), .irq_n(), .snd(fm), .sample(fm_sample));

	// ---------------------------------------------------------------- ADPCM
	reg  [7:0] areg;
	reg        pw;                       // a write for the ADPCM unit is pending
	reg  [4:0] preg;
	reg  [7:0] pdat;
	wire       ad_busy;
	reg        ad_step;
	wire signed [15:0] ad_pcm;
	function [5:0] map(input [7:0] r);   // {valid, ADPCM register}
		if (r == 8'h07)                  map = {1'b1, 5'd0};
		else if (r == 8'h08)             map = {1'b1, 5'd1};
		else if (r >= 8'h09 && r <= 8'h12) map = {1'b1, 5'(r - 8'h07)};
		else if (r >= 8'h15 && r <= 8'h17) map = {1'b1, 5'(r - 8'h07)};
		else                             map = 6'd0;
	endfunction
	wire [5:0] m = map(areg);
	always @(posedge clk) begin
		if (reset) begin areg <= 8'd0; pw <= 1'b0; end
		else begin
			if (wr && !a0) areg <= din;
			if (wr && a0 && m[5]) begin
				pw <= 1'b1; preg <= m[4:0];
				pdat <= (areg == 8'h08) ? ((din & 8'h0F) | 8'h80) : din;
			end else if (pw && !ad_busy && !ad_step) pw <= 1'b0;
		end
	end
	gn_adpcmb u_adpcm (
		.clk(clk), .reset(reset), .step(ad_step),
		.wr(pw && !ad_busy && !ad_step), .wreg(preg), .wdata(pdat),
		.mem_req(mem_req), .mem_addr(mem_addr), .mem_ack(mem_ack), .mem_data(mem_data),
		.flag_eos(), .pcm(ad_pcm), .busy(ad_busy));

	// ---------------------------------------------------------------- output
	// y8950::generate: clock FM and ADPCM, FM out, + ADPCM, round trip
	function signed [15:0] roundtrip(input signed [31:0] v);
		reg [31:0] scan;
		reg [3:0]  e;
		reg [15:0] mask;
		begin
			if (v < -32768)     roundtrip = -16'sd32768;
			else if (v > 32767) roundtrip = 16'sd32767;
			else begin
				scan = v ^ {32{v[31]}};
				e = scan[14] ? 4'd7 : scan[13] ? 4'd6 : scan[12] ? 4'd5 : scan[11] ? 4'd4 :
				    scan[10] ? 4'd3 : scan[9] ? 4'd2 : 4'd1;
				mask = (16'd1 << (e - 4'd1)) - 16'd1;
				roundtrip = v[15:0] & ~mask;
			end
		end
	endfunction
	// jtopl's `sample` is slot[0]: high for one operator slot (4 cen), so a
	// new sample is its rising edge
	reg [1:0] seq;
	reg       fm_sample_d;
	always @(posedge clk) begin
		ad_step <= 1'b0; sample <= 1'b0;
		fm_sample_d <= fm_sample;
		if (reset) seq <= 2'd0;
		else begin
			if (fm_sample && !fm_sample_d) begin ad_step <= 1'b1; seq <= 2'd1; end
			else if (seq == 2'd1 && !ad_busy && !ad_step) seq <= 2'd2;
			else if (seq == 2'd2) begin
				// ad_pcm is registered from the new ADPCM state one clock later
				snd <= roundtrip($signed({{16{fm[15]}}, fm}) + $signed({{16{ad_pcm[15]}}, ad_pcm}));
				snd_fm <= fm; snd_adpcm <= ad_pcm; sample <= 1'b1; seq <= 2'd0;
			end
		end
	end
endmodule
