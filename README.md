# Arcade-GingaNin_MiSTer

**Ginga Ninkyouden** (Jaleco, 1987) for the MiSTer FPGA platform: one
bitstream for both MAME sets, `ginganin` and `ginganina`.

The board has:
- a 68000 at 6 MHz (fx68k);
- a sound MC6809 at 3.58 MHz (mc6809is) with an MC6840 timer, a YM2149 and a
  Y8950 (an OPL FM part plus a DELTA-T ADPCM unit, composed here: no open
  Y8950 exists);
- a ROM-resident 16x16 background, a 16x16 foreground and an 8x8 text layer,
  and 256 16x16 sprites.

It follows the methodology of Arcade-NMK16_MiSTer, Arcade-SandScrp_MiSTer,
Arcade-JalecoMS1BCD_MiSTer and Arcade-JalecoMS1Z_MiSTer: MAME is the
reference, and every claim in `docs/known-issues.md` (GN-n) is a
measurement. `docs/provenance.md` says where every file came from.

## Status

**Runs on the DE10-Nano.** Measured against MAME 0.289:

- **video block:** 4,098 / 4,098 MAME frames reproduced pixel for pixel from
  MAME's own state (attract, scripted play, Flip Screen; GN-6).
- **whole board from reset:** 841 of 1,508 attract frames are exact. The
  rest are tearing: the game rewrites sprites while the picture is on
  screen, and MAME draws the frame once, afterwards. In GN-7's run a replay of the core's
  own writes explained 649 of the 668 other frames pixel for pixel.
  The attract demo and scripted play diverge from MAME's later (GN-7, open).
- **audio:** the Y8950's ADPCM unit is bit-exact against ymfm. Each chip is
  within 0.21 dB of MAME's level, and the mix has an envelope correlation of
  0.952 (GN-5).
- **memory path:** a real download into SDRAM with the copy exact. Every
  acknowledged ROM read (over 50 million, all four streams) was checked
  against the image with none wrong, and the pictures are identical to the
  array-ROM simulation's (GN-8).
- **savestates:** the SS-13 three-save gate passes in attract and in play,
  0 words different (GN-10).
- **board:** the attract matches MAME's frames on the board. Savestates,
  high scores, cheats, flip, pause, autofire and both sets work (GN-9, GN-11).
  20,574 / 41,910 ALMs, 428 / 553 M10K, timing met.

## Supported games

| set | game | parent |
|---|---|---|
| `ginganin` | Ginga Ninkyouden (set 1) | -- |
| `ginganina` | Ginga Ninkyouden (set 2) | `ginganin` |

## Features

- Video: aspect ratio, Scandoubler Fx, Orientation, Flip screen (in the core,
  combined with the Flip Screen DIP), CRT Adjust.
- DIP switches from the `.mra`, Pause, High Scores (MAME's `hiscore.dat`).
- Six cheats named for the game (Pugsy's cheat database).
- Autofire, hidden unless the `.mra`'s third `<switches>` byte sets bit 7.
- Four savestate slots: Alt+F1-F4 saves, F1-F4 loads.
- MAME's keyboard map: arrows, Left Ctrl, Left Alt, 5 and 6 (coins), 1 and 2
  (starts); player 2 on R/F/D/G, A and S.

## Building

Quartus Prime 17.0 Lite: `./build.sh LOGFILE` (it refuses to report success
unless Quartus does), or open `GingaNin.qpf`.

Simulation needs Verilator 5:
- `sim/rtl/video_state`: the video block against MAME states;
- `sim/rtl/gn_frames`: the whole board, and `make ss` for the savestate gate;
- `sim/rtl/gn_hw`: the SDRAM path;
- `sim/rtl/gn_snd`, `sim/rtl/gn_y8950`: the sound board and the Y8950.

Their ROM images are built from your own romsets by
`tools/gen_gn_mra.py --images`. No ROM data is in this repository or in the
bitstream.

## Attribution

- **MAME** `jaleco/ginganin.cpp` (driver by **Luca Elia**), with MAME's
  **ymfm** (Aaron Giles; `gn_adpcmb.sv` is a port of its ADPCM-B channel)
  and 6840 PTM: the behavioural reference for every part of this core.
- **jtopl** (YM3526): Jose Tejada (Jotego).
- **YM2149**: MikeJ and Sorgelig (ZX-Spectrum_MISTer).
- **mc6809is** (6809): Greg Miller (cavnex/mc6809); the synchronous version
  used by the MiSTer Time Pilot '84 core.
- **fx68k** (68000): Jorge Cwik.
- **Hiscores**: Alan Steremberg and Jim Gregory.
- **CRT Adjust**: Umberto Parisi (rmonic79).
- **sdram.sv**: Sorgelig.
- The MiSTer **Template_MiSTer** / `sys/` framework: Sorgelig and
  contributors.
- Cheats from Pugsy's MAME cheat database; high scores from MAME's
  `hiscore.dat`.

GPL-3.0 (see `LICENSE`); third-party files keep their own notices.
