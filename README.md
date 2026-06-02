# Black Widow + Gravitar (Atari, 1982/1983) for MiSTer FPGA

A MiSTer FPGA core for Atari's **Black Widow** and **Gravitar** — two color-vector
classics on the same Atari AVG hardware. **One `Arcade-BlackWidow.rbf` runs both
games**, selected by which `.mra` you launch.

This is a re-host of the existing MiSTer Black Widow 2-in-1 (Jeroen Domburg's
game logic) onto the proven **Star Wars** DDR vector-framebuffer chassis
([Videodr0me/Arcade-StarWars_MiSTer](https://github.com/Videodr0me/Arcade-StarWars_MiSTer))
— the same vector renderer used by the Tempest core — replacing the original
M9K dithered drawer with a clean DDR3 rasterizer.

> **Status:** confirmed playable on real DE10-Nano hardware — both Black Widow and
> Gravitar render correctly with a stable, flicker-free display that fills the
> screen and scales cleanly up to 4K.

> ⚠️ **ROMs required — not included.** This core does nothing without the romsets.
> Supply **`bwidow.zip`** and/or **`gravitar.zip`** (MAME `bwidow` / `gravitar`)
> in your MiSTer's `games/mame/` folder. No ROMs are distributed here (© Atari).
> See [Install](#install).

---

## Why "Star Wars chassis"?

Black Widow, Gravitar, and Tempest all run on closely related Atari Analog Vector
Generator (AVG) hardware. Rather than ship the original core's M9K line-drawer
(which dithered and trailed), this core feeds the game module's AVG vector output
into the **`vector_fb_ddram`** DDR3 triple-buffered rasterizer from the Star Wars
core, with the same phosphor-persistence present-gate the Tempest core uses.

One consequence: the Quartus project, top-level entity, and bitstream are still
named `Arcade-StarWars` internally. What you flash is renamed to
**`Arcade-BlackWidow.rbf`**, and both MRAs point at `<rbf>Arcade-BlackWidow</rbf>`.

## What's in this core

- **Black Widow (1982)** and **Gravitar (1983)** — one bitstream, chosen at load by
  the MRA (mod byte: Black Widow = 0, Gravitar = 1). Same shared game module
  (6502 / T65 + Atari AVG + dual POKEY + EAROM); only the input map differs per game.
- **DDR3 vector framebuffer** (`vector_fb_ddram`) at **960×720** — 4:3, so it
  integer-scales cleanly (×3 → 2880×2160 within 4K) and the vector image fills the
  screen.
- **Phosphor-persistence present-gate** with an OSD **Persistence** knob (flicker-free
  vectors), inherited from the Tempest core.

## Install

1. Copy **`releases/Arcade-BlackWidow.rbf`** to your MiSTer's `_Arcade/cores/`
   (keep exactly one `Arcade-BlackWidow*.rbf` there).
2. Copy the MRA(s) you want to `_Arcade/`:
   - **`Black Widow.mra`**
   - **`Gravitar (Ver 3).mra`**
3. **Required:** put the romset(s) in `games/mame/` — **`bwidow.zip`** for Black
   Widow, **`gravitar.zip`** for Gravitar (MAME `bwidow` / `gravitar`). **The core
   will not run without the matching zip** — the MRA loads the ROMs from it. ROMs
   are not included here.

Launch the MRA for the game you want from the MiSTer arcade menu.

## Controls

- **Black Widow** — twin-stick: move (joystick / D-pad) + fire in 4 directions
  (face buttons, or a second stick).
- **Gravitar** — rotate, thrust, fire, shield.
- Coin / Start as usual.

Black Widow is a **horizontal** game; set orientation via the OSD if your monitor
is rotated.

## OSD options

Beyond the standard MiSTer video/scaler options:

- **Aspect ratio** — *Optimized* (auto integer scale to your output, up to 4K) or
  *Pixel Perfect*.
- **Rotate / Flip** — orientation for rotated/portrait monitors.
- **Frame Gate** — *On* (normal) presents via the persistence gate; *Off* is a
  native AVG pass-through diagnostic.
- **Persistence** — how many complete vector redraws accumulate per displayed frame.
  Higher = more phosphor-like glow and more resistance to dropped beams; lower =
  crisper but flickerier.

## Known limitations

- **Hi-score persistence** and **pause** are stubbed (the modules are wired but not
  yet active) — scores reset on power cycle.
- Internal project/bitstream identity is `Arcade-StarWars` (see
  [above](#why-star-wars-chassis)).

## Credits & license

- **Jeroen Domburg (Sprite_tm)** — the original Black Widow / Gravitar MiSTer game
  logic and the behavioral Atari AVG this builds on.
- **Videodr0me** — the Star Wars MiSTer port and the `vector_fb_ddram` DDR3 vector
  framebuffer chassis this core is re-hosted onto.
- The broader MiSTer / MAME communities — Atari vector hardware lineage, T65,
  POKEY, EAROM, and reference models.

Original code is **GPLv3** (see `COPYING`); third-party modules retain their own
licenses (see file headers and `LICENSES`). Non-commercial, preservation-oriented,
not affiliated with Atari. Black Widow © 1982 Atari; Gravitar © 1983 Atari.
