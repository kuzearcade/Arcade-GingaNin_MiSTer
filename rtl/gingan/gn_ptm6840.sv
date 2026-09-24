// Motorola MC6840 programmable timer module, written against MAME's
// machine/6840ptm.cpp (the oracle; no existing HDL was found, docs/PLAN.md
// fact 6). Clocked by the E enable only: this board has no external timer
// clocks and no gate inputs (MAME: set_external_clocks(0, 0, 0)).
//
// Registers (A2:A0), as MAME:
//   W 0  CR1 if CR2 bit 0, else CR3        R 0  -
//   W 1  CR2                                R 1  status (bit 7 = any IRQ)
//   W 2/4/6  MSB buffer (shared)            R 2/4/6  counter MSB (LSB latched)
//   W 3/5/7  latch n = {MSB buffer, data}   R 3/5/7  the latched counter LSB
// Control bits: 0 CR1: hold every timer in reset (CR2: CR1 select;
// CR3: T3 /8 prescale), 1 internal clock, 2 dual 8-bit, 5:3 mode (bit 4:
// a latch write does not reload), 6 IRQ enable, 7 output enable.
//
// Counting follows MAME's reload_counter / state_changed:
//   16-bit continuous (modes 0, 2): expire after latch+1 E; the output toggles
//   dual 8-bit: (lsb+1)*msb E with the output low, lsb+1 with it high
//   one-shot (modes 4, 6): 1 E with the output low, latch E with it high; the
//     output changes once, then stays until the timer is reinitialised
// An expiry sets the timer's status bit at the end of a full cycle. The
// output pins are MAME's out_cb: they follow a toggle only while the output
// is enabled, and go low when a control write clears the enable.
//
// Ginga Ninkyouden (Q1, docs/known-issues.md GN-3) uses timer 1 only: the
// handler holds reset (CR1 = 1), loads 0x4800, and releases with CR1 = 0x92
// (continuous, internal clock, output enabled, no IRQ); output 1 is the
// 6809's IRQ (MAME: o1_callback -> M6809_IRQ_LINE).
module gn_ptm6840 (
	input            clk,
	input            reset,
	input            ce_e,         // one clock per E cycle
	input            cs,
	input            wr,           // one clock, E-aligned
	input            rd,           // one clock, E-aligned (side effects)
	input      [2:0] addr,
	input      [7:0] din,
	output reg [7:0] dout,
	output reg [2:0] out,          // O1..O3 pins
	output           irq_n
);
	reg  [7:0]  cr [0:2];
	reg  [7:0]  msb_buf, lsb_read;
	reg  [15:0] latch [0:2];
	reg  [16:0] cnt [0:2];        // E ticks left to the next expiry
	reg  [2:0]  outp;             // MAME's m_output
	reg  [2:0]  run;              // MAME's timer armed
	reg  [2:0]  fired;            // one-shot fired
	reg  [2:0]  status;
	reg  [2:0]  pre;              // T3 prescaler
	wire        hold = cr[0][0];
	wire        any_irq = |(status & {cr[2][6], cr[1][6], cr[0][6]});
	assign irq_n = ~any_irq;

	function [16:0] period(input [7:0] c, input [15:0] l, input o);
		reg one_shot;
		begin
			one_shot = c[5:3] == 3'd4 || c[5:3] == 3'd6;
			if (c[2])            period = o ? {9'd0, l[7:0]} + 17'd1 : ({9'd0, l[7:0]} + 17'd1) * l[15:8];
			else if (one_shot)   period = o ? {1'b0, l} : 17'd1;
			else                 period = {1'b0, l} + 17'd1;
		end
	endfunction

	integer i;
	reg [2:0] tick;
	always @(*) begin
		for (i = 0; i < 3; i = i + 1)
			tick[i] = ce_e && run[i] && !hold && cr[i][1] && (i != 2 || !cr[2][0] || pre == 3'd7);
	end

	always @(posedge clk) begin
		if (reset) begin
			for (i = 0; i < 3; i = i + 1) begin cr[i] <= 8'd0; latch[i] <= 16'hFFFF; cnt[i] <= 17'h10000; end
			cr[0] <= 8'h01;           // MAME's reset: CR1 = 1 (timers held)
			msb_buf <= 8'd0; lsb_read <= 8'd0; outp <= 3'd0; run <= 3'd0; fired <= 3'd0;
			status <= 3'd0; pre <= 3'd0; out <= 3'd0;
		end else begin
			if (ce_e && cr[2][0] && !hold) pre <= pre + 3'd1;
			// counting and expiry (MAME's state_changed)
			for (i = 0; i < 3; i = i + 1) if (tick[i]) begin
				if (cnt[i] > 17'd1) cnt[i] <= cnt[i] - 17'd1;
				else begin
					if ((!cr[i][2] && !(cr[i][5:3] == 3'd4 || cr[i][5:3] == 3'd6)) || outp[i]) status[i] <= 1'b1;
					outp[i] <= ~outp[i];
					if (cr[i][5:3] == 3'd4 || cr[i][5:3] == 3'd6) begin
						if (!fired[i]) begin
							if (cr[i][7]) out[i] <= ~outp[i];
							if (outp[i]) fired[i] <= 1'b1;   // the output is going low: done
						end else out[i] <= 1'b0;
					end else out[i] <= cr[i][7] ? ~outp[i] : 1'b0;
					cnt[i] <= period(cr[i], latch[i], ~outp[i]);
				end
			end
			// register writes (MAME's write)
			if (cs && wr) case (addr)
				3'd0, 3'd1: begin : ctrl
					integer idx;
					reg [7:0] diffs;
					idx = (addr == 3'd1) ? 1 : (cr[1][0] ? 0 : 2);
					diffs = din ^ cr[idx];
					cr[idx] <= din;
					if (!din[7]) out[idx] <= 1'b0;
					if (idx == 0 && diffs[0]) begin
						status <= 3'd0;
						if (din[0]) begin
							// holding reset: stop, reload, outputs low
							for (i = 0; i < 3; i = i + 1) begin
								run[i] <= 1'b0; outp[i] <= 1'b0; out[i] <= 1'b0;
								cnt[i] <= period(i == 0 ? din : cr[i], latch[i], 1'b0);
							end
						end else begin
							// releasing reset: every timer restarts from its latch
							for (i = 0; i < 3; i = i + 1) begin
								fired[i] <= 1'b0; run[i] <= 1'b1;
								cnt[i] <= period(i == 0 ? din : cr[i], latch[i], outp[i]);
							end
						end
					end
				end
				3'd2, 3'd4, 3'd6: msb_buf <= din;
				default: begin : lsb
					integer idx;
					idx = (addr - 3'd3) >> 1;
					latch[idx] <= {msb_buf, din};
					status[idx] <= 1'b0;
					if (!cr[idx][4] || hold) begin
						cnt[idx] <= period(cr[idx], {msb_buf, din}, outp[idx]);
						run[idx] <= 1'b1;
					end
				end
			endcase
			// reads: status, and the counter's MSB latching its LSB
			if (cs && rd && (addr == 3'd2 || addr == 3'd4 || addr == 3'd6))
				lsb_read <= cnt[(addr >> 1) - 1][7:0];
		end
	end
	always @(*) begin
		case (addr)
			3'd1: dout = {any_irq, 4'd0, status};
			3'd2, 3'd4, 3'd6: dout = cnt[(addr >> 1) - 1][15:8];
			3'd3, 3'd5, 3'd7: dout = lsb_read;
			default: dout = 8'h00;
		endcase
	end
endmodule
