# Arcade-GingaNin_MiSTer

A MiSTer FPGA core for **Ginga Ninkyouden** (Jaleco, 1987): one bitstream
for both MAME sets, `ginganin` and `ginganina`.

**In development.** See `docs/PLAN.md` for the plan and its gates, and
`docs/known-issues.md` for every finding (GN-n).

The board has:
- a 68000 at 6 MHz (fx68k);
- a sound MC6809 (mc6809is) with an MC6840 timer, a YM2149, and a Y8950
  (OPL FM plus DELTA-T ADPCM);
- a ROM-resident 16x16 background, a 16x16 foreground and an 8x8 text layer,
  and 256 16x16 sprites.

MAME's `jaleco/ginganin.cpp` (Luca Elia) is the behavioural reference, and
every claim is a measurement against it.

## Credits

- MAME's driver: Luca Elia. MAME's ymfm (Aaron Giles) and 6840 PTM as
  references.
- fx68k: Jorge Cwik. mc6809: Greg Miller (synchronous version by Sorgelig).
- YM2149: MikeJ, Sorgelig. YM3526 (jtopl) and ADPCM-B (jt12): Jose Tejada
  (Jotego).
- CRT Adjust: Umberto Parisi (rmonic79). Hiscore module: Alan Steremberg, Jim
  Gregory. MiSTer framework: Sorgelig and contributors.

GPL-3.0 (see `LICENSE`); third-party files keep their own notices.
