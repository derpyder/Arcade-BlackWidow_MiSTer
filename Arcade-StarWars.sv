//============================================================================
//  Arcade: Black Widow / Gravitar  -- on the Star Wars DDR-framebuffer chassis
//
//  Re-hosts the MiSTer Black Widow core (Jeroen Domburg; BW + Gravitar) onto the
//  proven vector_fb_ddram DDR rasterizer (Star Wars / Tempest chassis), replacing
//  bwidow_dw.vhd's dithered/trailing M9K drawer.  720-native FB (960x720) for a
//  clean x3 integer upscale to 2160p on 4K.  One core, both games (mod-switched).
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	//if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE, // analog out is off

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

`ifdef MISTER_FB
	// Use framebuffer in DDRAM
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
`endif
`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
	//Secondary SDRAM
	input         SDRAM2_EN,
	output        SDRAM2_CLK,
	output [12:0] SDRAM2_A,
	output  [1:0] SDRAM2_BA,
	inout  [15:0] SDRAM2_DQ,
	output        SDRAM2_nCS,
	output        SDRAM2_nCAS,
	output        SDRAM2_nRAS,
	output        SDRAM2_nWE,
`endif

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_F1    = 0;
assign VGA_SCALER= 1;
assign VGA_DISABLE = 0;
assign VGA_SL = 0;
assign USER_OUT  = '1;
wire [7:0] core_led;
assign LED_USER  = core_led[2] | ioctl_download;
assign LED_DISK  = {1'b1, core_led[1]};
assign LED_POWER = {1'b1, core_led[0]};
assign BUTTONS   = 0;
assign AUDIO_MIX = 0;
assign HDMI_FREEZE = 0;

assign CLK_VIDEO = clk_108; // Direct PLL output (~109 MHz)
assign CE_PIXEL = ce_pix;
assign VGA_HS = hs;
assign VGA_VS = vs;
assign VGA_DE = ~(hblank | vblank);
assign VGA_R = 0;
assign VGA_G = 0;
assign VGA_B = 0;

wire [1:0] ar = status[15:14];

// Auto-detect optimal display size from HDMI output resolution.
// FB is 960x720 (4:3).  Integer scales: x1=960x720, x1.5=1440x1080, x2=1920x1440,
// x3=2880x2160.  720 height makes every step land on a real panel height (x3 = 2160
// = exact 4K fill -- the whole reason for the 720-native FB).  Thresholds gate on
// OUTPUT height and equal the scaled height exactly (x3 needs >=2160, etc.).
reg [12:0] auto_arx, auto_ary;
always @(*) begin
	if (HDMI_HEIGHT >= 2160) begin
		// 4K (3840x2160): x3 integer scale, fills vertical EXACTLY
		auto_arx = 13'h1B40;  // 0x1000 | 2880
		auto_ary = 13'h1870;  // 0x1000 | 2160
	end else if (HDMI_HEIGHT >= 1440) begin
		// 1440p (2560x1440): x2 integer scale
		auto_arx = 13'h1780;  // 0x1000 | 1920
		auto_ary = 13'h15A0;  // 0x1000 | 1440
	end else if (HDMI_HEIGHT >= 1080) begin
		// 1080p (1920x1080): x1.5 scale
		auto_arx = 13'h15A0;  // 0x1000 | 1440
		auto_ary = 13'h1438;  // 0x1000 | 1080
	end else begin
		// 720p (1280x720) or smaller: 1:1 pixel perfect
		auto_arx = 13'h13C0;  // 0x1000 | 960
		auto_ary = 13'h12D0;  // 0x1000 | 720
	end
end

// Aspect menu = {0:Optimized (auto integer scale), 1:Pixel Perfect (1:1)}.
assign VIDEO_ARX = (ar == 0) ? auto_arx : 13'h13C0;  // Pixel Perfect (1:1, 960)
assign VIDEO_ARY = (ar == 0) ? auto_ary : 13'h12D0;  // Pixel Perfect (1:1, 720)

// 120Hz MODE — SAFE ACTIVATION (boot holdoff + HDMI_HEIGHT validation).
reg [26:0] boot_cnt = 0;
reg boot_done = 0;
always @(posedge clk_50) begin
	if (!boot_cnt[26]) boot_cnt <= boot_cnt + 1'd1;
	else               boot_done <= 1;
end

wire is_720p_valid = (HDMI_HEIGHT >= 12'd256) & (HDMI_HEIGHT <= 12'd720);
reg [24:0] stable_720p_cnt = 0;
reg is_720p_stable = 0;
always @(posedge clk_50) begin
	if (!is_720p_valid) begin
		stable_720p_cnt <= 0;
		is_720p_stable <= 0;
	end else if (!stable_720p_cnt[24]) begin
		stable_720p_cnt <= stable_720p_cnt + 1'd1;
	end else begin
		is_720p_stable <= 1;
	end
end

wire osd_120hz_mode = boot_done & status[25] & is_720p_stable;
wire not_720p = ~is_720p_stable;

reg new_vmode_toggle = 0;
reg mode_120_prev = 0;
reg boot_done_prev = 0;
always @(posedge clk_50) begin
	boot_done_prev <= boot_done;
	if (!boot_done) begin
		mode_120_prev <= status[25];
	end else begin
		mode_120_prev <= status[25];
		if (mode_120_prev != status[25]) new_vmode_toggle <= ~new_vmode_toggle;
	end
	if (boot_done & !boot_done_prev & osd_120hz_mode) new_vmode_toggle <= ~new_vmode_toggle;
end

`include "build_id.v"
// Status bit map (BW/Gravitar read game DIPs via the MRA "DIP;" -> sw[] path, NOT
// status bits, so OSD knobs never collide with gameplay DIPs):
//   [0]=Reset  [2]=RasterFlicker  [6:5]=Rotate  [7]=Mirror  [9:8]=VectorScale
//   [10]=FrameGate(bypass)  [11]=Fire mode(BW twin-stick)  [15:14]=Aspect
//   [25]=120Hz  [27]=AutosaveHi  [29:28]=Persistence
localparam CONF_STR = {
	"A.BWIDOW;;",
	"-;",
	"OEF,Aspect ratio,Optimized,Pixel Perfect;",
	"D2OP,120Hz (720p only),Off,On;",
	"-;",
	"O56,Rotate,0,90,180,270;",
	"O7,Mirror,Off,On;",
	"OA,Frame Gate,On,Off;",
	"OST,Persistence,3 (default),4,6,2;",
	"-;",
	"h1OB,Fire,Buttons,Second Joystick;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Fire Right,Fire Left,Fire Up,Fire Down,Start 1P,Start 2P,Coin,Pause;",
	"jn,A,B,X,Y,Start,Select,R,L;",
	"V,v1.00.",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_6, clk_12, clk_50, clk_108;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_50),
	.outclk_1(clk_12),
	.outclk_2(clk_6),
	.outclk_3(clk_108),
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire [21:0] gamma_bus;

wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire        ioctl_wr;
wire        ioctl_rd;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire  [7:0] ioctl_din;
wire  [7:0] ioctl_index;

wire [15:0] joy_0, joy_1;
wire [15:0] joy = joy_0 | joy_1;
wire        rom_download = ioctl_download && !ioctl_index;
wire [24:0] dl_addr = ioctl_addr;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_12),
	.HPS_BUS(HPS_BUS),

	.buttons(buttons),
	.status(status),
	.status_menumask({1'b0, not_720p, mod_bwidow, direct_video}),  // [2]=not_720p (D2 120Hz), [1]=mod_bwidow (h1 Fire mode)
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	.new_vmode(new_vmode_toggle),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_rd(ioctl_rd),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),

	.joystick_0(joy_0),
	.joystick_1(joy_1)
);

// ===== Game select (MRA <rom index="1"> -> ioctl_index=1) =====
reg [7:0] mod_byte = 8'h00;
always @(posedge clk_12) if (ioctl_wr && (ioctl_index == 8'd1)) mod_byte <= ioctl_dout;
wire mod_bwidow   = (mod_byte == 8'd0);
wire mod_gravitar = (mod_byte == 8'd1);

// ===== MRA DIP switches (ioctl_index=254) =====
//   sw[0] -> SW_D4 (coinage),  sw[1] -> SW_B4 (lives/difficulty/bonus),
//   sw[2] -> service bits (read in input_0).
reg [7:0] sw[8];
always @(posedge clk_12) if (ioctl_wr && (ioctl_index==254) && !ioctl_addr[24:3]) sw[ioctl_addr[2:0]] <= ioctl_dout;

// ===== Controls =====
wire m_up     = joy_0[3];
wire m_down   = joy_0[2];
wire m_left   = joy_0[1];
wire m_right  = joy_0[0];

// Fire stick: BW twin-stick can route the FIRE direction to a second joystick's
// d-pad (status[11], shown only for BW), else to the 4 fire buttons (joy_0[7:4]).
wire fire2 = status[11];
wire m_fire_up     = (mod_bwidow && fire2) ? joy_1[3] : joy_0[6];
wire m_fire_down   = (mod_bwidow && fire2) ? joy_1[2] : joy_0[7];
wire m_fire_left   = (mod_bwidow && fire2) ? joy_1[1] : joy_0[5];
wire m_fire_right  = (mod_bwidow && fire2) ? joy_1[0] : joy_0[4];

wire m_start1 = joy[8];
wire m_start2 = joy[9];
wire m_coin   = joy[10];
wire m_coin2  = 1'b0;
wire m_pause  = joy[11];

// Per-game input latches (copied from the shipping Arcade-BlackWidow.sv).
reg [7:0] input_0;
reg [7:0] input_3;
reg [7:0] input_4;
always @(*) begin
	input_0 = 8'hff;
	input_3 = 8'hff;
	input_4 = 8'hff;
	if (mod_bwidow) begin
		input_0 = ~{ 1'b0, 1'b1, sw[2][0], sw[2][1], 2'b0, m_coin, m_coin2 };
		input_3 = ~{ 4'b0, m_up, m_down, m_left, m_right };
		input_4 = ~{ 1'b0, m_start2, m_start1, 1'b0, m_fire_up, m_fire_down, m_fire_left, m_fire_right };
	end
	else if (mod_gravitar) begin
		input_0 = ~{ 1'b0, 1'b1, sw[2][0], sw[2][1], 2'b0, m_coin, m_coin2 };
		input_3 = ~{ 3'b0, m_fire_left, m_left, m_right, m_fire_right, m_fire_down };
		input_4 = ~{ 1'b0, m_start2, m_start1, 5'b0 };
	end
end

// Video signals
wire hblank, vblank;
wire hs, vs;

reg ce_pix;
always @(posedge clk_108) begin
	if (osd_120hz_mode) ce_pix <= 1'b1;       // full ~109 MHz -> 120Hz
	else                ce_pix <= ~ce_pix;    // ~54.5 MHz -> 60Hz
end

wire reset = (RESET | status[0] | buttons[1] | rom_download);
wire [15:0] audio_l, audio_r;
assign AUDIO_L = audio_l;
assign AUDIO_R = audio_r;
assign AUDIO_S = 0;   // BW/Gravitar POKEY audio is UNSIGNED (analog_sound_out 0..255).

bwidow_sw bwidow_core
(
	.clk_12(clk_12),
	.clk_50(clk_50),
	.clk_vid(clk_108),
	.reset(reset),
	.pause_h(1'b0),                // hiscore/pause stubbed this build (render-first); see HANDOFF

	.osd_raster_flicker(status[2]),
	.osd_120hz_mode(osd_120hz_mode),
	.osd_rotate(status[6:5]),
	.osd_flip(status[7]),
	.osd_scale(status[9:8]),       // 0=Half (safe), 1=ThreeQ, 2=Full
	.osd_gate_bypass(status[10]),
	.osd_persist(status[29:28]),   // 0=3(default ~_n),1=4,2=6,3=2 lists/frame

	// DDRAM Framebuffer Interface (proven SW DDR renderer)
	.DDRAM_CLK(DDRAM_CLK),
	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DOUT(DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_RD(DDRAM_RD),
	.DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE),
	.DDRAM_WE(DDRAM_WE),

	.FB_EN(FB_EN),
	.FB_FORMAT(FB_FORMAT),
	.FB_WIDTH(FB_WIDTH),
	.FB_HEIGHT(FB_HEIGHT),
	.FB_BASE(FB_BASE),
	.FB_STRIDE(FB_STRIDE),
	.FB_VBL(FB_VBL),
	.FB_LL(FB_LL),
	.FB_FORCE_BLANK(FB_FORCE_BLANK),
`ifdef MISTER_FB_PALETTE
	.FB_PAL_CLK(FB_PAL_CLK),
	.FB_PAL_ADDR(FB_PAL_ADDR),
	.FB_PAL_DOUT(FB_PAL_DOUT),
	.FB_PAL_DIN(FB_PAL_DIN),
	.FB_PAL_WR(FB_PAL_WR),
`endif

	.audio_out_l(audio_l),
	.audio_out_r(audio_r),

	.video_r(),
	.video_g(),
	.video_b(),
	.hsync(hs),
	.vsync(vs),
	.vblank(vblank),
	.hblank(hblank),

	// Black Widow / Gravitar inputs
	.input_0(input_0),
	.input_3(input_3),
	.input_4(input_4),
	.sw_b4(sw[1]),
	.sw_d4(sw[0]),

	.led(core_led),

	// hiscore NVRAM -- stubbed this build (tie off; wire hiscore.v in a follow-up)
	.hs_address(16'd0),
	.hs_data_out(),
	.hs_data_in(8'd0),
	.hs_write(1'b0),

	// ROM Download
	.dn_addr(dl_addr),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr & rom_download)
);

// hiscore/NVRAM upload path stubbed (no persistence this build).
assign ioctl_upload_req = 1'b0;
assign ioctl_din = 8'h00;

endmodule
