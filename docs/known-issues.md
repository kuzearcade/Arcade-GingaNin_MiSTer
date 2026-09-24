# Known issues and findings — Arcade-GingaNin_MiSTer

Every entry is closed by a measurement, or says what would close it.
Numbering is `GN-n`. The oracle is MAME 0.289 (`~/mame`), driver
`jaleco/ginganin.cpp`. The plan is `docs/PLAN.md`.

## GN-1 — MAME shows its default palette until the game writes an entry (closed, measured; the core matches it)

The driver's first TODO (`:49-51`): "Game doesn't init paletteram /
tilemaps properly, ending up with MAME palette defaults at start-up".

Measured in `sim/oracle/traces/ginganin_attract` (`gn_capture.lua`):
- In frames 1-34 after reset, BG is on, but none of its palette entries
  (768-1023) has been written: palette RAM reads 0 there.
- MAME's picture still shows about 48,000 lit pixels.
- For every index the BG uses, MAME's colour is **MAME's default palette**,
  one colour per index (56 indices, each single-valued): entry i is full
  red if `i & 1`, full green if `i & 2`, full blue if `i & 4`
  (769 → `FF0000`, 770 → `00FF00`, 772 → `0000FF`, 775 → `FFFFFF`).

This is MAME's artefact, not the board's. A real board powers up with
undefined palette RAM. The core reproduces MAME anyway, because it costs
1,024 bits and keeps every frame comparable:
- a "written" flag per entry;
- an unwritten entry shows the default colour;
- reads still return the RAM (0), as in MAME.

The capture records the same mask (a write tap on `050000-0507FF`), since
an entry written with 0 is black, not the default. With it, the model is
exact on frames 1-34 (before: 34 frames, about 48,000 pixels each).

## GN-2 — MAME's picture F+1 is state F's composition with state F+1's palette (closed, measured)

`tools/gn_model.py` renders a captured state (`frame_done` F) by the
driver's rules and compares it with MAME's pictures:
- against picture F+1: exact;
- against pictures F-1 and F: thousands of pixels off on moving frames
  (e.g. play state 1000: 1,868 and 1,777).

The sprite list, scrolls, VRAM and layer enables of frame_done F are what
picture F+1 shows: no extra sprite lag, as MP-1 found on the NMK board.

One frame in 5,399 needed more: play frame 662, just after Start, differed
by 55,432 pixels. The game wrote 95 palette entries between states 662 and
663, and **state 662's layers coloured with state 663's palette match
picture 663 exactly**. MAME's bitmap holds palette indices, and the colours
are applied when the picture is read (MS1Z-5, same finding on the Jaleco
MS1-Z board). The core looks the palette up during scan-out, which is the
same thing.

**The M0 gate.** With GN-1's mask and this pairing, the model is exact on
every captured frame: attract 1,799 / 1,799 and scripted play 5,399 /
5,399 (1,797 and 5,397 non-blank).
