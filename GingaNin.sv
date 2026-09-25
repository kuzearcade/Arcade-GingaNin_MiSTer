// Arcade-GingaNin_MiSTer -- MiSTer top level for Ginga Ninkyouden (Jaleco,
// 1987; ginganin and ginganina).
//
// Derived from Arcade-JalecoMS1Z_MiSTer's MS1Z.sv (docs/provenance.md). The
// OSD, keyboard map, autofire, high scores, cheats, CRT Adjust, orientation,
// the download/reset sequencing and the video chain are MS1Z's. What differs:
//
//   * The board: a 68000 at 6 MHz, a 6809 at 3.58 MHz with a YM2149 and a
//     Y8950 (rtl/gingan). Mono audio.
//   * One 16-bit input word (MAME's P1_P2: both players, coins and starts)
//     and one 16-bit DSW word (<switches> bytes 0 and 1). Byte 2 bit 7
//     unlocks the Autofire menu, as on MS1Z.
//   * The raster is 400 x 250 at 6 MHz (60.000 Hz), lines 16-239 visible.
//   * No savestates yet (docs/PLAN.md M5): gn_core has no park/replay port.
//   * No Service key: the board has none (MAME maps none).
module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1; // signed PCM
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

wire [1:0] ar = status[122:121];
// "Original" aspect follows the orientation: 4:3 as the board outputs it,
// 3:4 once the framebuffer rotation turns the picture.
assign VIDEO_ARX = (!ar) ? (video_rotated ? 12'd3 : 12'd4) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (video_rotated ? 12'd4 : 12'd3) : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"GingaNin;;",
	"-;",
	"HBO[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"HBO[3:1],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	// Both sets are ROT0; the Orientation menu is for rotated cabinets.
	"H0O[9:8],Orientation,Horz,Vert 90,Vert 270;",
	// 180 degrees in the core, composed with the game's own flip bit (the
	// Flip Screen DIP drives that one).
	"O[17],Flip screen,Off,On;",
	"P3,CRT Adjust;",
	"P3O[101],CRT Adjust,Off,On;",
	"P3O[100:96],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P3O[85:79],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,+48,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P3O[78:74],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P3O[107:104],CRT V-Size,0,+1,+2,+3,+4,-4,-3,-2,-1;",
	"P3O[108],CRT V-Size Mode,PVM,Cabinet;",
	// Autofire on button 1, clocked by the game's own vblank. While a player
	// has it on, that player's button 3 is a plain button 1 (the game has only
	// two buttons). Hidden (h1) unless the .mra's third <switches> byte sets
	// bit 7.
	"h1O[12:10],P1 Autofire,Off,10Hz,12Hz,15Hz,20Hz,30Hz;",
	"h1O[15:13],P2 Autofire,Off,10Hz,12Hz,15Hz,20Hz,30Hz;",
	"-;",
	"DIP;",
	"-;",
	"O[29],Pause,Off,On;",
	"P1,Scores;",
	"P1O[39],High Scores,Off,On;",
	"P1-;",
	"dAP1R[30],Save Scores;",
	"dAP1R[31],Reset Scores;",
	// Each slot is hidden until the .mra's <rom index="5"> table supplies it
	// (docs/PLAN.md M5 names them from the cheat database).
	"P2,Cheats;",
	"P2-;",
	"h3P2O[32],Cheat 1,Off,On;",
	"h4P2O[33],Cheat 2,Off,On;",
	"h5P2O[34],Cheat 3,Off,On;",
	"h6P2O[35],Cheat 4,Off,On;",
	"h7P2O[36],Cheat 5,Off,On;",
	"h8P2O[37],Cheat 6,Off,On;",
	"h9P2O[38],Cheat 7,Off,On;",
	"-;",
	"R[0],Reset;",
	// Positionally matched against the <buttons> list the .mra writes.
	"J1,Button 1,Button 2,Button 3,Start,Coin;",
	"V,v",`BUILD_DATE
};

wire         forced_scandoubler;
wire         direct_video;
wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire  [31:0] joystick_0, joystick_1;

wire         ioctl_download;
wire         ioctl_wr;
wire  [26:0] ioctl_addr_full;
wire   [7:0] ioctl_dout;
wire         ioctl_wait;
wire  [15:0] ioctl_index;
wire         ioctl_upload, ioctl_upload_req;
wire   [7:0] ioctl_din;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(vm_gamma_bus),

	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),

	.buttons(buttons),
	.status(status),
	// [11] hides Aspect ratio and Scandoubler Fx under direct video;
	// [10] greys out Save/Reset Scores while High Scores is Off;
	// [9:3] hide the cheat slots the loaded .mra has no cheat for;
	// [1] shows the Autofire options, from <switches> byte 2 bit 7;
	// [0] hides Orientation under direct video.
	.status_menumask({4'd0, direct_video, hs_enable, ch_avail, 1'b0, autofire_unlock, direct_video}),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr_full),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),
	.ioctl_index(ioctl_index),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_upload_index(8'd4),
	.ioctl_din(ioctl_din),

	.ps2_key(ps2_key)
);
wire [24:0] ioctl_addr = ioctl_addr_full[24:0];

///////////////////////   CLOCKS   ///////////////////////////////

// 48 MHz: the 68000 and the pixel clock at 6 MHz (/8). The 6809's
// 3.579545 MHz and the sound chips' clocks come from fractional accumulators
// inside gn_sound.
wire clk_sys;
wire clk_ram;     // 96 MHz, the SDRAM controller's own clock
wire pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_ram),
	.locked(pll_locked)
);

// The GAME reset: held for the whole download, then for a tail restarted by
// every ioctl session, and until the <switches> block has arrived (MS1-53).
reg [23:0] dl_tail = {24{1'b1}};
always @(posedge clk_sys) begin
	if (ioctl_download)              dl_tail <= 24'd0;
	else if (dl_tail != {24{1'b1}})  dl_tail <= dl_tail + 1'd1;
end
wire dl_settling = (dl_tail != {24{1'b1}});

reg         sw_seen  = 1'b0;
reg  [27:0] sw_tmo   = 28'd0;
always @(posedge clk_sys) begin
	if (ioctl_download) begin
		sw_tmo <= 28'd0;
		if (ioctl_wr && ioctl_index == 16'd254) sw_seen <= 1'b1;
	end else if (~&sw_tmo) sw_tmo <= sw_tmo + 1'd1;
end
wire wait_switches = ~sw_seen & ~&sw_tmo;

// "Reset Scores": a short core reset, then the hiscore module held for ~6 s
// so it does not write the old table straight back (SandScrp's chain).
reg [28:0] hs_rst_cnt = 29'd0;
always @(posedge clk_sys) begin
	if (status[31])       hs_rst_cnt <= 29'd288000000;
	else if (|hs_rst_cnt) hs_rst_cnt <= hs_rst_cnt - 1'b1;
end
wire hs_hold     = |hs_rst_cnt;
wire hs_core_rst = (hs_rst_cnt > 29'd283000000);

wire reset = RESET | status[0] | buttons[1] | ioctl_download | dl_settling | wait_switches | ~pll_locked | hs_core_rst;

// The ROM loader's reset is power-on only: gn_rom_hw IS the download and has
// to keep working through the window `reset` covers (SandScrp SS-15). Held
// until the PLL locks.
reg [3:0] por_cnt = 4'd0;
reg       por_rst = 1'b1;
always @(posedge clk_sys) begin
	if (~pll_locked) begin
		por_cnt <= 4'd0;
		por_rst <= 1'b1;
	end else if (por_rst) begin
		if (por_cnt == 4'd15) por_rst <= 1'b0;
		else por_cnt <= por_cnt + 4'd1;
	end
end

// ------------------------------------------------------------------
// The .mra <switches> block, ioctl index 254. Bytes 0 and 1 are the low and
// high bytes of MAME's DSW word at 070002. Byte 2 is not a DIP: bit 7
// unlocks the Autofire menu.
// ------------------------------------------------------------------
reg [7:0] dip_sw [0:7];
integer dip_i;
initial for (dip_i = 0; dip_i < 8; dip_i = dip_i + 1) dip_sw[dip_i] = 8'hFF;
always @(posedge clk_sys) begin
	if (ioctl_download && ioctl_wr && (ioctl_index == 16'd254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end
reg sw_byte2_seen = 1'b0;
always @(posedge clk_sys)
	if (ioctl_download && ioctl_wr && (ioctl_index == 16'd254) && ioctl_addr[24:0] == 25'd2)
		sw_byte2_seen <= 1'b1;
wire autofire_unlock = sw_byte2_seen & dip_sw[2][7];

// ------------------------------------------------------------------
// Keyboard: MAME's default bindings, always live, ORed with the pads.
//   P1: arrows, Left Ctrl = B1, Left Alt = B2, Space = B3 (autofire alias)
//   P2: R/F/D/G, A = B1, S = B2, Q = B3
//   Coin 1 = 5, Coin 2 = 6, Start 1/2 = 1/2
// ------------------------------------------------------------------
reg [6:0] kb_p1 = 7'd0, kb_p2 = 7'd0;   // [0]=R [1]=L [2]=D [3]=U [4]=B1 [5]=B2 [6]=B3
reg kb_start1 = 1'b0, kb_start2 = 1'b0;
reg kb_coin1 = 1'b0, kb_coin2 = 1'b0;
reg kb_toggle_d = 1'b0;
always @(posedge clk_sys) begin
	kb_toggle_d <= ps2_key[10];
	if (kb_toggle_d != ps2_key[10]) begin
		case (ps2_key[8:0])
			9'h175: kb_p1[3] <= ps2_key[9];
			9'h172: kb_p1[2] <= ps2_key[9];
			9'h16B: kb_p1[1] <= ps2_key[9];
			9'h174: kb_p1[0] <= ps2_key[9];
			9'h014: kb_p1[4] <= ps2_key[9];
			9'h011: kb_p1[5] <= ps2_key[9];
			9'h029: kb_p1[6] <= ps2_key[9];
			9'h02D: kb_p2[3] <= ps2_key[9];
			9'h02B: kb_p2[2] <= ps2_key[9];
			9'h023: kb_p2[1] <= ps2_key[9];
			9'h034: kb_p2[0] <= ps2_key[9];
			9'h01C: kb_p2[4] <= ps2_key[9];
			9'h01B: kb_p2[5] <= ps2_key[9];
			9'h015: kb_p2[6] <= ps2_key[9];
			9'h016: kb_start1 <= ps2_key[9];
			9'h01E: kb_start2 <= ps2_key[9];
			9'h02E: kb_coin1  <= ps2_key[9];
			9'h036: kb_coin2  <= ps2_key[9];
			default: ;
		endcase
	end
end

// ------------------------------------------------------------------
// Autofire (MS1Z's): the pattern advances once per game frame and restarts
// on each press. With it on, button 1 is (held & pattern) | button 3.
// ------------------------------------------------------------------
wire        vblank_core;
wire  [6:0] p1_raw = joystick_0[6:0] | kb_p1;
wire  [6:0] p2_raw = joystick_1[6:0] | kb_p2;
reg  vbl_d = 1'b0;
wire frame_tick = vblank_core & ~vbl_d;
always @(posedge clk_sys) vbl_d <= vblank_core;

function automatic [3:0] af_on(input [2:0] m);
	case (m) 3'd1: af_on = 4'd3; 3'd2: af_on = 4'd2; 3'd3: af_on = 4'd2; 3'd4: af_on = 4'd1; 3'd5: af_on = 4'd1; default: af_on = 4'd0; endcase
endfunction
function automatic [3:0] af_len(input [2:0] m);
	case (m) 3'd1: af_len = 4'd6; 3'd2: af_len = 4'd5; 3'd3: af_len = 4'd4; 3'd4: af_len = 4'd3; 3'd5: af_len = 4'd2; default: af_len = 4'd1; endcase
endfunction

reg  [3:0] af1_phase = 4'd0, af2_phase = 4'd0;
reg        af1_held_d = 1'b0, af2_held_d = 1'b0;
wire [2:0] af1_mode = status[12:10];
wire [2:0] af2_mode = status[15:13];
always @(posedge clk_sys) begin
	af1_held_d <= p1_raw[4];
	af2_held_d <= p2_raw[4];
	if (p1_raw[4] & ~af1_held_d) af1_phase <= 4'd0;
	else if (frame_tick) af1_phase <= (af1_phase + 4'd1 >= af_len(af1_mode)) ? 4'd0 : af1_phase + 4'd1;
	if (p2_raw[4] & ~af2_held_d) af2_phase <= 4'd0;
	else if (frame_tick) af2_phase <= (af2_phase + 4'd1 >= af_len(af2_mode)) ? 4'd0 : af2_phase + 4'd1;
end
wire af1_en = (af1_mode != 3'd0);
wire af2_en = (af2_mode != 3'd0);
wire p1_b1 = af1_en ? ((p1_raw[4] & (af1_phase < af_on(af1_mode))) | p1_raw[6]) : p1_raw[4];
wire p2_b1 = af2_en ? ((p2_raw[4] & (af2_phase < af_on(af2_mode))) | p2_raw[6]) : p2_raw[4];

// ------------------------------------------------------------------
// Inputs: MAME's P1_P2 word at 070000, active low (ginganin.cpp):
//   bit 0 up, 1 down, 2 left, 3 right, 4 B1, 5 B2       (player 1)
//   bit 6 up, 7 down, 8 left, 9 right, 10 B1, 11 B2     (player 2)
//   bit 12 coin 1, 13 coin 2, 14 start 1, 15 start 2
// MiSTer numbers pad buttons by position in the .mra's <buttons> list:
// Button 1, Button 2, Button 3, Start, Coin -> bits 4, 5, 6, 7, 8; the
// direction bits are 0 right, 1 left, 2 down, 3 up.
// ------------------------------------------------------------------
wire p1_start = joystick_0[7] | kb_start1;
wire p2_start = joystick_1[7] | kb_start2;
wire p1_coin  = joystick_0[8] | kb_coin1;
wire p2_coin  = joystick_1[8] | kb_coin2;
wire [15:0] in_p1p2 = ~{p2_start, p1_start, p2_coin, p1_coin,
                        p2_raw[5], p2_b1, p2_raw[0], p2_raw[1], p2_raw[2], p2_raw[3],
                        p1_raw[5], p1_b1, p1_raw[0], p1_raw[1], p1_raw[2], p1_raw[3]};
wire [15:0] in_dsw = {dip_sw[1], dip_sw[0]};

// ------------------------------------------------------------------
// SDRAM: one controller on its own 96 MHz clock, fed by gn_rom_hw.
// Port 0 the download, 1 BG and FG tiles, 2 sprites, 3 ADPCM.
// ------------------------------------------------------------------
wire [24:1] sd0_addr, sd1_addr, sd2_addr, sd3_addr;
wire        sd0_wrl, sd0_wrh, sd1_wrl, sd1_wrh, sd2_wrl, sd2_wrh, sd3_wrl, sd3_wrh;
wire [15:0] sd0_din, sd1_din, sd2_din, sd3_din;
wire [15:0] sd0_dout, sd1_dout, sd2_dout, sd3_dout;
wire [31:0] sd0_pair, sd1_pair, sd2_pair, sd3_pair;
wire        sd0_req, sd1_req, sd2_req, sd3_req, sd0_ack, sd1_ack, sd2_ack, sd3_ack;
wire        sdram_ready;

// REFRESH_CYCLES 740 at 96 MHz (~7.7 us); the controller's default 850 was
// measured corrupting reads on silicon in the NMK16 work.
sdram #(.REFRESH_CYCLES(10'd740)) sdram_inst
(
	.SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_BA(SDRAM_BA), .SDRAM_nCS(SDRAM_nCS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nCAS(SDRAM_nCAS), .SDRAM_CLK(SDRAM_CLK), .SDRAM_CKE(SDRAM_CKE), .ready(sdram_ready),
	.init(~pll_locked), .clk(clk_ram), .prio_mode(2'd0),
	.addr0(sd0_addr), .wrl0(sd0_wrl), .wrh0(sd0_wrh), .din0(sd0_din), .dout0(sd0_dout), .dout0_pair(sd0_pair), .req0(sd0_req), .ack0(sd0_ack),
	.addr1(sd1_addr), .wrl1(sd1_wrl), .wrh1(sd1_wrh), .din1(sd1_din), .dout1(sd1_dout), .dout1_pair(sd1_pair), .req1(sd1_req), .ack1(sd1_ack),
	.addr2(sd2_addr), .wrl2(sd2_wrl), .wrh2(sd2_wrh), .din2(sd2_din), .dout2(sd2_dout), .dout2_pair(sd2_pair), .req2(sd2_req), .ack2(sd2_ack),
	.addr3(sd3_addr), .wrl3(sd3_wrl), .wrh3(sd3_wrh), .din3(sd3_din), .dout3(sd3_dout), .dout3_pair(sd3_pair), .req3(sd3_req), .ack3(sd3_ack)
);

wire        bg_req, bg_ack, fg_req, fg_ack, spr_req, spr_ack, adp_req, adp_ack;
wire [16:0] bg_addr, fg_addr;
wire [18:0] spr_addr;
wire [23:0] adp_addr;
wire [31:0] bg_data, fg_data, spr_data;
wire  [7:0] adp_data;

gn_rom_hw rom_hw (
	.clk(clk_sys),
	.reset(reset),
	.pwr_reset(por_rst),   // power-on only -- see por_rst's declaration
	.ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
	.ioctl_addr({2'd0, ioctl_addr}), .ioctl_dout(ioctl_dout), .ioctl_wait(ioctl_wait),
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
	.dbg_dl_bytes(), .dbg_dropped()
);

// ------------------------------------------------------------------
// High scores (rtl/third_party/hiscore) and cheats (rtl/cheats.sv) share
// gn_core's work-RAM back door, which they only drive while they hold the
// CPU paused; hiscore wins a collision (MS1-39). The back door is a 16-bit
// word port and the 68000 is big-endian: the even byte is the high lane.
// ------------------------------------------------------------------
wire [23:0] hs_addr;
wire  [7:0] hs_din, hs_dout;
wire        hs_write, hs_access;
wire [23:0] hi_addr;
wire  [7:0] hi_din;
wire        hi_write;
wire        hs_pause_raw, hs_upload_req_raw;
wire        hs_enable = status[39];
wire        hs_active = hs_enable & ~hs_hold;
wire        hs_pause  = hs_pause_raw & hs_active;
reg  [23:0] hs_save_cnt = 24'd0;
always @(posedge clk_sys) begin
	if (status[30])        hs_save_cnt <= 24'd4800000;   // ~100 ms at 48 MHz
	else if (|hs_save_cnt) hs_save_cnt <= hs_save_cnt - 1'b1;
end
wire hs_saving = |hs_save_cnt;
wire hs_osd = OSD_STATUS & ~hs_saving & hs_active;
assign ioctl_upload_req = hs_upload_req_raw & hs_active;

hiscore #(
	.HS_ADDRESSWIDTH(24),
	.HS_SCOREWIDTH(8),
	.CFG_ADDRESSWIDTH(4),
	.CFG_LENGTHWIDTH(2)
) hi (
	.clk(clk_sys),
	.reset(reset | hs_hold | ~hs_enable),
	.paused(hs_pause_raw),
	.autosave(1'b1),
	.OSD_STATUS(hs_osd),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(hs_upload_req_raw),
	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_index(ioctl_index[7:0]),
	.data_from_hps(ioctl_dout),
	.data_to_hps(ioctl_din),
	.data_from_ram(hs_dout),
	.data_to_ram(hi_din),
	.ram_address(hi_addr),
	.ram_write(hi_write),
	.ram_intent_read(),
	.ram_intent_write(),
	.pause_cpu(hs_pause_raw),
	.configured()
);

wire [23:0] ch_addr;
wire  [7:0] ch_din;
wire        ch_write, ch_access, ch_pause;
wire  [6:0] ch_avail;

cheats ch (
	.clk(clk_sys),
	.reset(reset),
	.ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr), .ioctl_index(ioctl_index), .ioctl_dout(ioctl_dout),
	.enable(status[38:32]),
	.available(ch_avail),
	.vblank(vblank_core),
	.ram_addr(ch_addr), .ram_din(ch_din), .ram_write(ch_write),
	.ram_access(ch_access), .ram_dout(hs_dout), .pause_cpu(ch_pause)
);

assign hs_addr   = hs_pause ? hi_addr  : ch_addr;
assign hs_din    = hs_pause ? hi_din   : ch_din;
assign hs_write  = hs_pause ? hi_write : ch_write;
assign hs_access = hs_pause ? 1'b1     : ch_access;

wire [15:0] ram2_dout;
reg         hs_a0_d;
always @(posedge clk_sys) hs_a0_d <= hs_addr[0];
assign hs_dout = hs_a0_d ? ram2_dout[7:0] : ram2_dout[15:8];

// ------------------------------------------------------------------
// The board
// ------------------------------------------------------------------
wire [23:0] core_rgb;
wire        ce_pix_core;
wire  [8:0] hcount_core, vcount_core;
wire signed [15:0] snd;

// the BRAM part of the download (program ROMs, sound ROM, text tiles, BG
// map): every ROM byte the SDRAM side accepts
wire dl_bram = ioctl_download & ioctl_wr & (ioctl_index == 16'd0) & ~ioctl_wait;

gn_core core (
	.clk(clk_sys),
	// held in reset for the download and until the SDRAM controller is up
	.reset(reset | ~sdram_ready),
	.pause(status[29] | hs_pause | ch_pause),
	.flip_osd(status[17]),
	.dl_we(dl_bram), .dl_addr(ioctl_addr[19:0]), .dl_data(ioctl_dout),
	.bg_req(bg_req), .bg_addr(bg_addr), .bg_ack(bg_ack), .bg_data(bg_data),
	.fg_req(fg_req), .fg_addr(fg_addr), .fg_ack(fg_ack), .fg_data(fg_data),
	.spr_req(spr_req), .spr_addr(spr_addr), .spr_ack(spr_ack), .spr_data(spr_data),
	.adpcm_req(adp_req), .adpcm_addr(adp_addr), .adpcm_ack(adp_ack), .adpcm_data(adp_data),
	.p1p2(in_p1p2), .dsw(in_dsw),
	.ram2_sel(hs_access), .ram2_addr(hs_addr[13:1]), .ram2_we(hs_write),
	.ram2_be(hs_addr[0] ? 2'b01 : 2'b10), .ram2_din({hs_din, hs_din}), .ram2_dout(ram2_dout),
	.ce_pix(ce_pix_core), .hcount(hcount_core), .vcount(vcount_core),
	.hblank(), .vblank(), .hsync(), .vsync(),
	.rgb(core_rgb),
	.snd(snd),
	.dbg_addr(), .dbg_wr(), .dbg_wdata(), .dbg_be(), .dbg_irq1(), .dbg_iack1(), .dbg_spr_overruns()
);

assign AUDIO_L = snd;
assign AUDIO_R = snd;

// visible is rows 16..239 of 250; autofire and the cheats are the consumers
assign vblank_core = (vcount_core < 9'd16) | (vcount_core >= 9'd240);

// ------------------------------------------------------------------
// Video. The core renders in real time on clk_sys; video_retime moves that
// raster onto the 96 MHz video clock, crt_chain applies the analog geometry
// controls, and video_mixer drives VGA_*.
//
// The raster is 400 x 250 at 6 MHz (clk_sys / 8). LINE_CLKS is the video-clock
// count of one line: 96 MHz / (6 MHz / 400) = 6400. DIV is 96 / 6 = 16. HSync
// sits in the blanking as on MS1Z (front porch 32 px, sync 28 px = 4.7 us).
//
// gn_video's pixel lags its raster position by one pixel tick: `rgb` while
// ce_pix is high is the pixel of the PREVIOUS dot (the sims sample it that
// way: sim/rtl/video_state and gn_frames). The position is delayed to match
// (MS1-59's fix).
// ------------------------------------------------------------------
wire clk_vid = clk_ram;

localparam integer RGB_LAT = 1;
reg [8:0] hc_lat [0:RGB_LAT-1];
reg [8:0] vc_lat [0:RGB_LAT-1];
integer rl;
always @(posedge clk_sys) if (ce_pix_core) begin
	hc_lat[0] <= hcount_core;
	vc_lat[0] <= vcount_core;
	for (rl = 1; rl < RGB_LAT; rl = rl + 1) begin
		hc_lat[rl] <= hc_lat[rl-1];
		vc_lat[rl] <= vc_lat[rl-1];
	end
end
wire [8:0] hcount_vid = hc_lat[RGB_LAT-1];
wire [8:0] vcount_vid = vc_lat[RGB_LAT-1];

wire        rt_ce, rt_hs, rt_vs, rt_hb, rt_vb, rt_vb_hs;
wire [23:0] rt_rgb;
video_retime #(
	.M0_X0(10'd0), .M0_HT(10'd400), .M0_HS(10'd288), .M0_HW(10'd28), .M0_AW(10'd256), .M0_DIV(5'd16),
	.M1_X0(10'd0), .M1_HT(10'd400), .M1_HS(10'd288), .M1_HW(10'd28), .M1_AW(10'd256), .M1_DIV(5'd16),
	.LINE_CLKS(6400), .VTOTAL_P(250)
) video_retime (
	.clk_w(clk_sys), .reset_w(reset), .ce_w(ce_pix_core),
	.hcount_w({1'b0, hcount_vid}), .vcount_w({1'b0, vcount_vid}), .rgb_w(core_rgb),
	.mode1(1'b0), .tall240(1'b0),
	.clk_r(clk_vid),
	.ce_r(rt_ce), .rgb_r(rt_rgb), .hs_r(rt_hs), .vs_r(rt_vs), .de_r(),
	.hb_r(rt_hb), .vb_r(rt_vb), .vb_hs_r(rt_vb_hs)
);
assign CLK_VIDEO = clk_vid;

// The scandoubler must be off whenever the rotation framebuffer is active
// (NMK-28).
wire       fb_rotating = ~((status[9:8] == 2'd0) | direct_video);
wire [2:0] fx = direct_video ? 3'd0 : status[3:1];
wire       scandoubler_en = ((fx != 3'd0) || forced_scandoubler) && ~fb_rotating;
wire [1:0] sl = fx[2:1];
assign VGA_SL = sl;

wire        vm_ce_pix, vm_hs, vm_vs, vm_hb, vm_vb;
wire [23:0] retimed_rgb;
wire [21:0] vm_gamma_bus;
wire        crt_on = status[101] & ~scandoubler_en & ~fb_rotating;
crt_chain #(
	.HTOTAL0(10'd400), .HTOTAL1(10'd400), .DIV0(5'd16), .DIV1(5'd16),
	.VTOTAL(250), .LINE_PX(272), .VSIZE_MAX(4)
) crt_chain (
	.clk(clk_vid), .ce_in(rt_ce), .rgb_in(rt_rgb),
	.hs_in(rt_hs), .vs_in(rt_vs), .hb_in(rt_hb), .vb_in(rt_vb), .vb_hs_in(rt_vb_hs),
	.mode1(1'b0), .enable(crt_on),
	.hsize($signed(status[100:96])), .hpos_raw(status[85:79]),
	.vshift($signed(status[78:74])), .vsize_code(status[107:104]),
	.vsize_mode(status[108]),
	.ce_out(vm_ce_pix), .rgb_out(retimed_rgb),
	.hs_out(vm_hs), .vs_out(vm_vs), .hb_out(vm_hb), .vb_out(vm_vb)
);

video_mixer #(.LINE_LENGTH(272), .HALF_DEPTH(0), .GAMMA(0)) video_mixer (
	.CLK_VIDEO(CLK_VIDEO),
	.ce_pix(vm_ce_pix),
	.CE_PIXEL(CE_PIXEL),
	.scandoubler(scandoubler_en),
	.hq2x(fx == 3'd1),
	.gamma_bus(vm_gamma_bus),
	.R(retimed_rgb[23:16]), .G(retimed_rgb[15:8]), .B(retimed_rgb[7:0]),
	.HSync(vm_hs), .VSync(vm_vs), .HBlank(vm_hb), .VBlank(vm_vb),
	.HDMI_FREEZE(1'b0), .freeze_sync(),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
	.VGA_VS(VGA_VS), .VGA_HS(VGA_HS), .VGA_DE(VGA_DE)
);

// ------------------------------------------------------------------
// Orientation. Both sets are ROT0 and want Horz; "Vert 90" and "Vert 270"
// are for cabinets whose monitor is mounted on its side.
// ------------------------------------------------------------------
wire  [1:0] orientation = status[9:8];
wire        video_rotated;
wire        no_rotate = (orientation == 2'd0) | direct_video;
wire        rotate_ccw = (orientation == 2'd2);
screen_rotate screen_rotate (
	.CLK_VIDEO(CLK_VIDEO), .CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B), .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_DE(VGA_DE),
	.rotate_ccw(rotate_ccw), .no_rotate(no_rotate), .flip(1'b0), .video_rotated(video_rotated),
	.FB_EN(FB_EN), .FB_FORMAT(FB_FORMAT), .FB_WIDTH(FB_WIDTH), .FB_HEIGHT(FB_HEIGHT),
	.FB_BASE(FB_BASE), .FB_STRIDE(FB_STRIDE), .FB_VBL(FB_VBL), .FB_LL(FB_LL),
	.DDRAM_CLK(DDRAM_CLK), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE), .DDRAM_RD(DDRAM_RD)
);
assign FB_FORCE_BLANK = 1'b0;

reg [26:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
assign LED_USER = act_cnt[26] ? act_cnt[25:18] > act_cnt[7:0] : act_cnt[25:18] <= act_cnt[7:0];

endmodule
