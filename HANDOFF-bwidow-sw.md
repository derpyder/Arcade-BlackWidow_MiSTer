# Black Widow / Gravitar on the Star Wars DDR chassis — handoff (2026-06-01)

## UPDATE (2026-06-01, polish pass) — FILL + ORIENTATION + CONTROLS confirmed
- **Screen fill:** vector scale pinned to **11/16** (= shipped tempest_sw; 1024*11/16 = 704 fills
  ~98% of the 720 height, can't clip). The old /2 default was a ~512 letterbox. OSD "Vector Scale"
  line removed (pinned). `bwidow_sw.sv` cxs/cys.
- **Green diagnostic bar REMOVED:** `bwidow_sw.sv` `DIAG_DROPS_BAR = 1'b0`.
- **Orientation CORRECTED to "A" (no flips):** `fxs=480+rx, fys=360+ry`. The original bwidow_dw maps
  screen_x=X_VECTOR(9:1), screen_y=Y_VECTOR(9:1) top->bottom with NO extra flip, so orient A
  reproduces the real BW display (score text at top). The inherited Tempest flip-Y (orient C) was
  upside-down. OSD Rotate/Mirror adjust from here.
- **Controls PROVEN end-to-end (sim):** `sim/tb_bwidow_render.vhd` `-gCOIN_AT_US=110000` drives
  COIN then START; BW registers a credit + starts a game -> the display jumps from the 776-pt
  attract to a **7619-pt full-colour gameplay screen** (the web, score text, the green spider;
  `sim/fb/bw_gameplay_orientA.png`). Input wiring is identical to the upstream base; the joystick is
  inert in ATTRACT by design (coin up first: Coin=R, then Start). Render still 100% golden at fill.
- **Final build: 0 errors, timing MET (setup +0.389 / hold +0.246), SEED 3.** Staged
  `releases/Arcade-BlackWidow.rbf` (this is the keeper — fill + no bar + orient A).

## What this is
A re-release of the MiSTer **Black Widow** core (Jeroen Domburg's 2-in-1: Black Widow **and**
Gravitar) with its dithered/trailing `bwidow_dw.vhd` M9K drawer replaced by the **proven
`vector_fb_ddram` DDR triple-buffer rasterizer** (the renderer shipped in Star Wars + Tempest),
through the phosphor-persistence `present_gate`. Rendered into a **960×720 framebuffer** so the
scaler does a clean **×3 integer upscale to 2880×2160** on 4K. One core, both games (mod-switched).

Built by the same pattern as Tempest-SW / Major Havoc-SW: copy the SW chassis, graft the
`bwidow.vhd` game module's AVG output into the rasterizer. BW is the *cleanest* of the three —
its coord convention is the one Tempest's coord-map was derived from.

## STATUS
- **Black Widow render path: SIM-PROVEN at 100.0% pixel retention** (golden-compare,
  `sim/fb/fb_metric.py`), 0 missing / 0 spurious, robust to 50% AND 75% DDR contention
  (FIFO max_occ 3→306, no overflow). The attract (spider/web) renders solid — same gate Tempest
  passed before shipping.
- **Full Quartus compile: 0 errors, TIMING MET.** First build (SEED 1) had a tiny −0.123 ns setup
  miss on the framework `pll_hdmi` divclk path (NOT game/render logic — `emu|pll` had +1.291 ns);
  **SEED 3 closed it: setup +0.362 / hold +0.242 / recovery +4.268** (all positive, better than
  Tempest's +0.074). **Final rbf staged: `releases/Arcade-BlackWidow.rbf`** (2.6 MB, the SEED-3
  build). `.qsf` SEED=3.
- **Gravitar: built into the same core; render path is BW's (shared module + coord-map = proven).**
  In sim it boots fast (~20 ms) and kicks the AVG every 4 ms, but the attract holds an EMPTY
  display list through 250 ms (ax stuck at 0) — Gravitar's title/demo first-draws beyond a
  practical GHDL window (>1 s real). **Not a render bug** (identical path to BW). Confirm the
  Gravitar attract on HW; if it's blank there too, debug the CPU's display-list setup (EAROM
  high-score state, or coin-up to force gameplay geometry).

## Build / stage
- Core dir: `D:\deck\fpga\blackwidow\Arcade-BlackWidow-SW\` (Quartus project still named `Arcade-StarWars`).
- Build: `"C:/intelFPGA_lite/17.0/quartus/bin64/quartus_sh.exe" --flow compile Arcade-StarWars` (~25 min)
  → `output_files/Arcade-StarWars.rbf` → copy to `releases/Arcade-BlackWidow.rbf`.
- MRAs staged: `releases/Black Widow.mra` + `releases/Gravitar (Ver 3).mra`, both with
  `<rbf>Arcade-BlackWidow</rbf>` and `<rom index="1">` mod byte (0=BW, 1=Gravitar).
- Cab: copy `Arcade-BlackWidow.rbf` to `_Arcade/cores/` (keep exactly ONE Arcade-BlackWidow*.rbf —
  stale-rbf gotcha), MRAs to `_Arcade/`, ROMs `bwidow.zip` + `gravitar.zip` where the MRA finds them.

## What changed vs the chassis copy + the BW base
- `rtl/vector_fb_ddram.sv` — chassis renderer; **FB_WIDTH 980→960** (4:3 ×3→4K). FB_HEIGHT was
  already 720 in the copied chassis; all 720 buffer/clear constants consistent. Tightened the
  pixel bounds check to 960. The 3 render fixes + USE_RMW=0 + burst clear are untouched.
- `rtl/present_gate.sv` — the phosphor-persistence gate (Major Havoc variant, has `degraded`).
- `rtl/bwidow_sw.sv` — **NEW** graft: bwidow.vhd → coord-map (bit-9 flip `{~x[9],x[8:0]}`, scale,
  rotate/mirror, offset to FB centre **(480,360)**, in-bounds gate) → vector_fb_ddram + present_gate.
  Z=z[7:3], beam=|rgb. Default orient = "C" (flip Y only) — HW-tune via OSD.
- `rtl/bwidow.vhd` — copied from blackwidow-base + 4 edits:
  1. NEW outputs `start_frame` (= `avg_go`, the $8840 vggo strobe) + `frame_done` (= `avg_halted`)
     for the present_gate / sim cadence.
  2. Power-up initializers on the un-reset counters **`clkdiv`/`cnt_3khz`/`irqctr`/`ena_1_5M`**
     — WITHOUT these the master clock divider powers up `"UUU"` in GHDL and the whole game freezes
     (matches Cyclone V power-up = 0, so no synth change). **This is why BW now boots in sim.**
- `rtl/pgmrom.vhd`, `rtl/vecrom.vhd` — `: work.dpram` → `: entity work.dpram` (10 sites). The
  bare-selected-name instantiation is non-standard; Quartus accepts it but GHDL rejects it.
  `entity work.dpram` is valid for both.
- `Arcade-StarWars.sv` (emu top) — CONF_STR → BW/Gravitar; `mod_bwidow`/`mod_gravitar` input builds
  + twin-stick `status[11]` Fire-mode toggle + `sw[]` MRA DIPs + per-game inputs (from the shipping
  Arcade-BlackWidow.sv); instantiates `bwidow_sw`; OSD Rotate[6:5]/Mirror[7]/Scale[9:8]/FrameGate[10]/
  Persistence[29:28]; AUDIO_S=0; auto-aspect updated to 960-wide (×3=2880×2160 on 4K).
  **Hiscore + pause are STUBBED this build** (render-first; ports forwarded, tied off) — wire
  `hiscore.v` + `pause.v` (both already in rtl/, just not in files.qip) in a follow-up.
- `files.qip` — BW source set. `.qsf` — Tempest direct-file block removed (files.qip only); SEED 3.

## Sim (the proof) — `sim/`
- `build_bwidow_dl.py` / `build_gravitar_dl.py` — concat the zips (next to the core at
  `fpga/blackwidow/`) in MRA order → `<game>_dl.hex`. (Gravitar zip uses short names 136010.301.)
- `tb_bwidow_render.vhd` — boots `bwidow` on the real ROM, runs the attract, dumps
  `<game>_frame.txt` (ax ay rgb az) + a vggo/IRQ/PC cadence probe. Uses behavioral
  `dpram_sim.vhd` + `ram_2k_sim.vhd` (the altsyncram leaves don't elaborate in GHDL).
- `runcap.sh <hex> <lo_us> <hi_us> <stop>` — GHDL compile+run. **BW attract is live ~97 ms**
  (the self-test runs to ~90 ms first): `runcap.sh bwidow_dl.hex 90000 150000 152ms`.
- `sim/fb/` — the golden-compare kit (copied from Tempest-SW, retuned to 960×720, frame paths →
  bwidow_frame.txt): `tb_fb_replay.sv` (real renderer under `ddr_model` contention), `fb_metric.py`
  (THE judge), `render_orient.py` (4-flip montage → `orient_montage.png`).
  - Replay+metric: `cd sim/fb && vlog -sv ddr_model.sv tb_fb_replay.sv ../../rtl/vector_fb_ddram.sv`
    `&& vsim -c -gBUSY_DUTY=8 -do "run -all; quit -f" tb_fb_replay && python fb_metric.py fb_out.txt`
    → **776/776 = 100.0%**.

## Remaining / HW bring-up
1. **Finish the SEED-3 build** → stage `releases/Arcade-BlackWidow.rbf` (replace provisional).
2. **HW flash + orientation** — pick BW's orientation via OSD Rotate/Mirror (all 4 flips are solid;
   `render_orient.py` montage shows the spider). BW is a HORIZONTAL monitor (unlike Tempest portrait).
3. **Gravitar attract on HW** — confirm it draws (see STATUS); shares BW's proven render path.
4. **Persistence / Frame Gate** — tune on the cab (default N=3, the known-good "_n" accumulation).
5. **Hiscore** — wire `hiscore.v` + `pause.v` (ports already forwarded through bwidow_sw).
6. **Inputs** — verify twin-stick (status[11] Fire mode), coin/start, DIPs (Lives/Difficulty/Bonus
   via SW_B4=sw[1], Coinage via SW_D4=sw[0]).

## Lessons (this session)
- GHDL needs un-reset counters initialized (clkdiv `"UUU"` → game frozen) and `entity work.X`
  (not bare `work.X`). Both are sim-only quirks; the synth build was always fine (A&S 0 errors).
- The render path proved out FAST once BW booted — the Tempest sim kit (contention model +
  golden-compare) ported almost verbatim. Judge by fb_metric numbers, not by eye.
