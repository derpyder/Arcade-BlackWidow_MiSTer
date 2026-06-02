// ============================================================================
// bwidow_sw.sv -- Black Widow / Gravitar game module on the Star Wars MiSTer
// chassis.  Replaces bwidow_top.vhd + bwidow_dw.vhd (the M9K framebuffer drawer
// that produced the dithered / trailing "awful" vectors).  Hosts bwidow.vhd
// (6502 + memory map + avg + colour AVG output) and feeds its vector output into
// the PROVEN vector_fb_ddram DDR framebuffer (the same renderer that ships in
// Star Wars + Tempest), through the phosphor-persistence present_gate.
//
// One module runs BOTH games: bwidow.vhd is shared, only the input map differs
// (mod_bwidow vs mod_gravitar, decoded in the emu top).
//
// Vs tempest_sw.sv / mhavoc_sw.sv:
//   * Game = bwidow (single T65), inputs input_0/3/4 + SW_B4/SW_D4, dn_addr[15:0],
//     hiscore ports forwarded.  Audio is already the summed dual-POKEY (8-bit).
//   * COORD CONVENTION = Tempest's: BW's AVG emits centred-at-0 coords with the
//     sign in bit 9 (bwidow_top.vhd:212 fed {not x(9), x(8:0)} to its drawer), so
//     cx = {~tmp_x[9], tmp_x[8:0]} -- the SAME bit-9 invert Tempest uses (NOT the
//     pre-centred MH path).  BEAM_ON = |rgb, Z blanks on 0: identical to BW's drawer.
//   * 720-NATIVE FRAMEBUFFER: 960x720 (4:3) so the scaler does a clean x3 integer
//     upscale to 2880x2160 on 4K.  Centre = (480, 360).
//   * clk = clk_12 = 12 MHz = BW's native rate (no clock-rate fudge).
//
// !! HW-TUNABLE (resolved in the FB sim first, per the Tempest discipline): the
//    coords->960x720 mapping (orientation + scale, OSD knobs) and the Z intensity.
// ============================================================================

module bwidow_sw (
	input         clk_12,
	input         clk_50,
	input         clk_vid,
	input         reset,
	input         pause_h,

	input         osd_raster_flicker,
	input         osd_120hz_mode,
	input  [1:0]  osd_rotate,       // HW bring-up: 0 / 90 / 180 / 270
	input         osd_flip,         //             horizontal mirror
	input  [1:0]  osd_scale,        //             0=/2 (safe), 1=x3/4, 2=x1
	input         osd_gate_bypass,  //             1 = bypass the gate (native passthrough)
	input  [1:0]  osd_persist,      // vector persistence: lists accumulated/buffer

	// DDRAM framebuffer (straight pass-through to the emu module)
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

	output [15:0] audio_out_l,
	output [15:0] audio_out_r,

	// video timing (RGB zeroed; FB supplies pixels via ascal)
	output  [2:0] video_r,
	output  [2:0] video_g,
	output  [2:0] video_b,
	output        hsync,
	output        vsync,
	output        vblank,
	output        hblank,

	// Black Widow / Gravitar inputs (built per-game in the emu top)
	input   [7:0] input_0,   // latchin_c: coin/start/service (act-low)
	input   [7:0] input_3,   // latchin_b: move stick (act-low)
	input   [7:0] input_4,   // latchin_a: fire stick + start (act-low)
	input   [7:0] sw_b4,     // DIP bank B4: lives/difficulty/bonus (POKEY B PIN)
	input   [7:0] sw_d4,     // DIP bank D4: coinage (POKEY A PIN)

	output  [7:0] led,

	// hiscore NVRAM (HPS), forwarded to bwidow
	input  [15:0] hs_address,
	output  [7:0] hs_data_out,
	input   [7:0] hs_data_in,
	input         hs_write,

	// ROM download
	input  [24:0] dn_addr,
	input   [7:0] dn_data,
	input         dn_wr
);

	// ------------------------------------------------------------------------
	// Black Widow / Gravitar game module (T65 + memory map + avg + vecrom/pgmrom)
	// ------------------------------------------------------------------------
	wire [9:0]  tmp_x, tmp_y;
	wire [7:0]  tmp_z;
	wire [2:0]  tmp_rgb;
	wire        tmp_beam_ena, tmp_frame_done, tmp_start_frame;
	wire [7:0]  tmp_audio;
	wire [15:0] tmp_dbg;

	bwidow bwidow_game (
		.reset_h(reset),
		.clk(clk_12),
		.pause_h(pause_h),
		.analog_sound_out(tmp_audio),
		.analog_x_out(tmp_x),
		.analog_y_out(tmp_y),
		.analog_z_out(tmp_z),
		.BEAM_ENA(tmp_beam_ena),
		.rgb_out(tmp_rgb),
		.start_frame(tmp_start_frame),
		.frame_done(tmp_frame_done),
		.SW_B4(sw_b4),
		.SW_D4(sw_d4),
		.dn_addr(dn_addr[15:0]),
		.dn_data(dn_data),
		.dn_wr(dn_wr),
		.input_0(input_0),
		.input_3(input_3),
		.input_4(input_4),
		.dbg(tmp_dbg),
		.hs_address(hs_address),
		.hs_data_out(hs_data_out),
		.hs_data_in(hs_data_in),
		.hs_write(hs_write)
	);

	// ------------------------------------------------------------------------
	// Coordinate mapping: BW/Gravitar AVG coords -> 960x720 framebuffer, with
	// OSD-tunable orientation + scale (the HW bring-up knobs).  Pipeline:
	//   centre (bit9 invert) -> scale -> centre-about-0 -> rotate/mirror ->
	//   offset to FB centre -> gate beam off when out of bounds (never clamp).
	// Default (status 0): 0deg, no mirror, /2 -> a ~512^2 image centred in
	// 960x720 = GUARANTEED fully on-screen (no clipping).  Dial from the cab.
	// ------------------------------------------------------------------------
	wire [9:0]  cx = {~tmp_x[9], tmp_x[8:0]};        // BW coords, centred 0..1023 (Tempest convention)
	wire [9:0]  cy = {~tmp_y[9], tmp_y[8:0]};

	// FILL scale = 13/16 (0.8125).  SCALE HISTORY (measured, not guessed):
	//  - 11/16 under-filled (HW: ~67%V) -- the original assumed BW used the full 1024^2 field; it
	//    doesn't (lit content is centred, ~700 units).
	//  - 15/16 filled the ATTRACT (92%V) but CLIPPED GAMEPLAY on HW -- gameplay geometry (arena
	//    border) is TALLER than the attract: at 15/16 the gameplay capture ran 330 pts off-top +
	//    793 pts off-bottom (fy -32..773, real border points, not strays).
	//  - 13/16 contains the GAMEPLAY extent (the binding case): gameplay fy ~20..718 in-bounds,
	//    attract ~80%V.  This is the smallest clean step that fits gameplay top+bottom.  The
	//    capture is the worst frame seen; 13/16 is the calibrated fill for BW's 4:3 field.
	// osd_scale is PINNED here (no OSD Vector Scale line); the port stays for interface parity.
	// (Gravitar shares this scale -- it also clipped at 15/16; 13/16 brings it in too. Confirm on HW.)
	wire [13:0] cxs  = cx * 4'd13;                    // cx * 13
	wire [13:0] cys  = cy * 4'd13;
	wire [9:0]  sx   = cxs[13:4];                      // >>4  (= *13/16)
	wire [9:0]  sy   = cys[13:4];
	wire [9:0]  half = 10'd416;                        // scaled centre = 512*13/16 = 416

	wire signed [12:0] scx = $signed({3'b000, sx}) - $signed({3'b000, half});
	wire signed [12:0] scy = $signed({3'b000, sy}) - $signed({3'b000, half});

	reg signed [12:0] rx, ry;
	always @* begin
		case (osd_rotate)
			2'd0:    begin rx =  scx; ry =  scy; end // 0
			2'd1:    begin rx =  scy; ry = -scx; end // 90 CW
			2'd2:    begin rx = -scx; ry = -scy; end // 180
			default: begin rx = -scy; ry =  scx; end // 270
		endcase
		if (osd_flip) rx = -rx;                       // horizontal mirror
	end

	// 960x720 FB centre.  Orient C (flip Y) -- HW-CONFIRMED CORRECT (cab: rotate0/mirror-off gives
	// score text at top, right-side-up).  fxs=480+rx (X not flipped), fys=360-ry (Y flipped).
	// [Note: this matches the cab result of Rotate180+Mirror applied to the no-flip baseline, i.e.
	//  the net flip BW actually needs; my earlier "orient A = no flip" reasoning was inverted.]
	// OSD Rotate/Mirror adjust relative to this; leave them at 0/off for the correct default.
	wire signed [13:0] fxs = 14'sd480 + rx;           // X not flipped
	wire signed [13:0] fys = 14'sd360 - ry;           // flip Y -> right-side-up (HW-confirmed)
	wire in_bounds = (fxs >= 0) && (fxs < 14'sd960) && (fys >= 0) && (fys < 14'sd720);

	wire [9:0]  rast_x   = fxs[9:0];
	wire [9:0]  rast_y   = fys[9:0];
	// Z = real AVG intensity (avg zout[7:3]) -> brightness.  0 on blanked MOVES so a
	// move writes a BLACK pixel = invisible (FB ADD-0 = no-op).  bwidow_dw blanked Z==0.
	wire [4:0]  rast_z   = tmp_z[7:3];
	wire [2:0]  rast_rgb = tmp_rgb;
	// BEAM_ON = |rgb (draw every walked lit point) -- exactly the BW drawer feed
	// (bwidow_top.vhd:219 BEAM_ON = rgb0|rgb1|rgb2); blanked while out of bounds.
	wire        rast_beam= (|tmp_rgb) && in_bounds;

	// ====================================================================
	// PHOSPHOR-PERSISTENCE present-gate (rtl/present_gate.sv) -- accumulate N
	// complete AVG lists (vggo->vggo) into one draw buffer, no clear between (FB
	// clears on EOF only).  N = OSD "Persistence" (default 3).  Same use as Tempest.
	// vggo = bwidow's avg_go ($8840-$887F GO strobe), exposed as start_frame.
	// ====================================================================
	reg vggo_d = 1'b0;
	always @(posedge clk_12) vggo_d <= tmp_start_frame;
	wire vggo_rise = tmp_start_frame & ~vggo_d;

	wire pg_beam_window, pg_eof, pg_start, pg_degraded;
	present_gate pgate (
		.clk         (clk_12),
		.reset       (reset),
		.vggo_rise   (vggo_rise),
		.persist     (osd_persist),
		.beam_window (pg_beam_window),
		.eof         (pg_eof),
		.frame_start (pg_start),
		.degraded    (pg_degraded)
	);

	wire gated_beam  = osd_gate_bypass ? rast_beam       : (rast_beam & pg_beam_window);
	wire gated_done  = osd_gate_bypass ? tmp_frame_done  : pg_eof;
	wire gated_start = osd_gate_bypass ? tmp_start_frame : pg_start;

	// ====================================================================
	// DIAGNOSTIC (drops vs cadence) -- a top bar drawn into every buffer:
	//   RED   = FB FIFO overflowed this buffer (beam drops / list too dense)
	//   BLUE  = present-gate timed out (vggo too slow = cadence/refresh problem)
	//   GREEN = healthy (no overflow, lists arriving fast)
	// Glance at the TOP edge during bring-up.  Set DIAG_DROPS_BAR=0 for the ship
	// build (it is a probe, not gameplay).
	// ====================================================================
	localparam DIAG_DROPS_BAR = 1'b0;   // 1 = draw the R/B/G health bar at the top (bring-up only)
	reg        ff_acc = 1'b0, dg_acc = 1'b0;   // events accumulated during the current buffer
	reg        ff_show = 1'b0, dg_show = 1'b0; // snapshot drawn in the bar (previous buffer)
	reg [10:0] mk = 11'd0;
	reg        marking = 1'b0;
	always @(posedge clk_12) begin
		if (gated_start) begin
			ff_show <= ff_acc;  dg_show <= dg_acc;   // present the buffer we just finished
			ff_acc  <= 1'b0;    dg_acc  <= 1'b0;     // reset for the new buffer
			marking <= 1'b1;    mk      <= 11'd0;    // start drawing the bar
		end else begin
			if (fifo_full_led) ff_acc <= 1'b1;
			if (pg_degraded)   dg_acc <= 1'b1;
			if (marking) begin
				if (mk >= 11'd959) marking <= 1'b0; else mk <= mk + 11'd1;
			end
		end
	end
	wire [2:0] mk_rgb  = ff_show ? 3'b100 : (dg_show ? 3'b001 : 3'b010);  // R / B / G
	wire       diag_on = DIAG_DROPS_BAR & marking;
	wire [9:0] fb_x    = diag_on ? mk[9:0] : rast_x;
	wire [9:0] fb_y    = diag_on ? 10'd8   : rast_y;
	wire [4:0] fb_z    = diag_on ? 5'd31   : rast_z;
	wire [2:0] fb_rgb  = diag_on ? mk_rgb  : rast_rgb;
	wire       fb_beam = diag_on ? 1'b1    : gated_beam;

	// ------------------------------------------------------------------------
	// DDR vector framebuffer -- the proven SW renderer, geometry retuned to 960x720.
	// ------------------------------------------------------------------------
	wire fifo_full_led;
	vector_fb_ddram rasterizer (
		.reset(reset),
		.clk_sys(clk_50),
		.clk_12(clk_12),

		.X_VECTOR(fb_x),       // = rast_x, except the diagnostic top-bar override (DIAG_DROPS_BAR)
		.Y_VECTOR(fb_y),
		.Z_VECTOR(fb_z),
		.RGB(fb_rgb),
		.BEAM_ENA(1'b1),
		.BEAM_ON(fb_beam),

		.START_FRAME(gated_start),
		.FRAME_DONE(gated_done),
		.OSD_FLICKER(osd_raster_flicker),
		.FIFO_FULL_LED(fifo_full_led),

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
		.FB_FORCE_BLANK(FB_FORCE_BLANK)
`ifdef MISTER_FB_PALETTE
		,
		.FB_PAL_CLK(FB_PAL_CLK),
		.FB_PAL_ADDR(FB_PAL_ADDR),
		.FB_PAL_DOUT(FB_PAL_DOUT),
		.FB_PAL_DIN(FB_PAL_DIN),
		.FB_PAL_WR(FB_PAL_WR)
`endif
	);

	// ------------------------------------------------------------------------
	// Audio: bwidow.vhd already sums both POKEYs into analog_sound_out (8-bit,
	// unsigned -> AUDIO_S=0 in the emu top).  Mono -> both channels.
	// ------------------------------------------------------------------------
	assign audio_out_l = {tmp_audio, tmp_audio};
	assign audio_out_r = {tmp_audio, tmp_audio};

	// ------------------------------------------------------------------------
	// Video timing (960x720 raster, 1056x861 total) -- proven SW raster structure,
	// active region moved to 960x720.  RGB zeroed: ascal scans the framebuffer;
	// the core only supplies sync.
	// ------------------------------------------------------------------------
	assign video_r = 3'b000;
	assign video_g = 3'b000;
	assign video_b = 3'b000;

	reg ce_pix;
	always @(posedge clk_vid) begin
		if (osd_120hz_mode) ce_pix <= 1'b1;
		else                ce_pix <= ~ce_pix;
	end

	reg  [10:0] h_cnt = 0;
	reg  [10:0] v_cnt = 0;
	wire [10:0] h_total  = 11'd1055;
	wire [10:0] v_total  = 11'd860;
	wire [10:0] hs_start = 11'd1004;
	wire [10:0] hs_end   = 11'd1036;
	wire [10:0] vs_start = 11'd726;   // within the 720..860 vblank region
	wire [10:0] vs_end   = 11'd732;
	wire h_end = (h_cnt == h_total);
	wire v_end = (v_cnt == v_total);
	always @(posedge clk_vid) begin
		if (ce_pix) begin
			if (h_end) begin
				h_cnt <= 0;
				if (v_end) v_cnt <= 0; else v_cnt <= v_cnt + 1'd1;
			end else h_cnt <= h_cnt + 1'd1;
		end
	end
	assign hsync  = ~(h_cnt >= hs_start && h_cnt < hs_end); // active low
	assign vsync  = ~(v_cnt >= vs_start && v_cnt < vs_end); // active low
	assign hblank = (h_cnt >= 11'd960);
	assign vblank = (v_cnt >= 11'd720);

	assign led = {7'd0, fifo_full_led};

endmodule
