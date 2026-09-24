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

## GN-3 — Q1, Q4, Q5: what the sound program actually drives (closed, measured)

`sim/oracle/gn_sndtrace.lua` logged every sound-CPU access to the devices
over 5,400 frames of scripted play (`traces/snd/play.txt`, 245,341 lines).

**MC6840 (Q1).**
- The program never reads the PTM, and uses timer 1 only.
- CR3 is written once (0) and timers 2 and 3 are never loaded.
- Every IRQ the handler writes CR2 = 1, CR1 = 1 (hold reset), loads the
  latch (0x4800 in play, 0x9999 once at boot, other values as the music's
  tempo changes), then CR1 = 0x92: continuous mode, internal E clock,
  output enabled, IRQ disabled.
- MAME wires **output 1** (not the IRQ pin) to the 6809's IRQ, so the IRQ
  is the output level, and the reset write drops it.
- `gn_ptm6840.sv` still implements the whole device as `6840ptm.cpp` models
  it; the traced path is what is measured.

**Y8950 (Q4).**
- Never read (no status polling), no timers, no I/O ports.
- **FM:** all nine channels and rhythm mode (0xBD: 1,708 writes).
- **ADPCM:** 115 sample plays.
  - control 0x07: 0x01 reset, 0xA0 start from memory;
  - 0x08: bit 0 = ROM;
  - start 0x09/0x0A, stop 0x0B/0x0C;
  - Delta-N 0x10/0x11 = 0x28EC or 0x2AEC;
  - level 0x12 = 0x00, 0x80 or 0xFF;
  - 0x04: 0x08 and 0x80 (flag control).

**YM2149 (Q5 input).** Tone A (0/1), tone C (4/5), noise (6), mixer (7) and
the three volumes (8-10). **The envelope registers 11-13 are never
written**, so the two vendored copies can only differ on tone or noise
period 0 and the I/O read mask, which this map never uses.

## GN-4 — The 6809: two latches without a power-up value, and three E cycles of IRQ latency (fixed; the latency is recorded)

`sim/rtl/gn_snd` runs the sound board alone from reset (`gn_sound`:
mc6809is, `gn_ptm6840`, the latch) and replays the main CPU's latch writes
from MAME's trace. `tools/gn_sndcmp.py` compares its device writes with
MAME's.

**1. The first runs were wrong from the first write.** Two causes:
- `gn_sound`'s E/Q phase generator was held in reset along with the CPU.
  mc6809is samples `nRESET` on falling E, so it never saw the reset. The
  generator now free-runs, and reset is held for about 37 E cycles.
- `mc6809is.v` gives `NMILatched` (and the IRQ/FIRQ latches and samples) no
  power-up value, and nothing sets it during reset. At 0, the CPU took an
  NMI at its very first instruction: the trace shows the opcode at 0x5000
  fetched, then registers pushed from S = 0. Upstream `cavnex/mc6809` has
  the same uninitialised latch.

  The vendored file now declares those registers `= 1'b1` (inactive), marked
  "GN-4" in the file. On an FPGA, registers power up at 0 unless told
  otherwise, so any core using this 6809 with a masked NMI could see a
  spurious one at reset.

**2. The result.** Over the first 3 s every write is identical, in the same
order with the same values: 722 PTM, 3,694 Y8950, 8 YM2149. The handler's
own instruction timing is identical: 18 E cycles from the reset write to
the release write, on both sides.

**3. IRQ latency.** The timer period, release to the next handler's first
write, is **18,501-18,503 E in MAME and 18,504-18,506 in the RTL: 3 E cycles
more, every period**. The counting is identical by construction (latch + 1
E from the release write). The difference is interrupt recognition:
- mc6809is models the real 6809's synchronisation (sample on falling Q, two
  falling-E stages, then the next instruction boundary). It was verified
  against a real chip with a logic analyser (its header).
- MAME's 6809 takes the IRQ at the next instruction boundary.

We keep the chip's behaviour. The music runs 3.4 µs per tick later: 0.016 %
slower than MAME, and about 0.17 ms per second of drift against MAME's
timeline. The main CPU never reads the sound board, so video is unaffected.

**4. Over 90 s.** Commands replayed at MAME's absolute times hit the music
code at a different point after about 14 s, and the interleaving diverges.
With `GN_WARP=1` (each command replayed at its MAME offset from the
preceding timer release, on the RTL's own releases):
- **the PTM sequence is identical for the whole 90 s** (31,982 writes);
- the Y8950 and YM2149 streams diverge after about 15 s, only in the order of
  writes around a command (an NMI now finds the IRQ handler 3 cycles less
  far along), not in their values.

The sound gate from here is at the audio level (M2), as on the siblings.

## GN-6 — M1: the video RTL against MAME's pictures (closed: 4,098 / 4,098)

`sim/rtl/video_state` loads a captured state into `gn_video` through its
CPU port:
- VRAMs, sprites and vregs of state F;
- the palette of state F+1 (GN-2), entries never written left unwritten
  (GN-1);
- the text tiles and BG map through the download port.

It renders two frames and compares lines 16-239 with MAME's picture F+1.
The tile ROM ports answer after 20 clocks with every 5th request stalled 5
more (MP-9's lesson).

| capture | frames | exact |
|---|---|---|
| attract | every frame, 1-1,798 | 1,798 |
| scripted play | every 3rd, 1-5,398 | 1,800 |
| Flip Screen DIP | every 3rd, 1-1,498 | 500 |

Zero sprite overruns in all of them. Two bugs were found on the way.

**1. Sprites parked at the top.** Unused sprites sit at Y 0-15, so lines 0-15
cross dozens of entries. The line engine overran on every such line (26 a
frame). The overrun that mattered was at vcount 14, which draws line 16,
the first visible one: its start arrived while line 15 was still being
drawn, was ignored, and line 16 would have had no sprites.
- The engines now draw only visible lines (16-239).
- A start while busy restarts the engine on the new line (counted as an
  overrun), so a slow line can never swallow the next one.

**2. Negative sprite coordinates.** MAME's `(v & 0xFF) - (v & 0x100)`
subtracts 256; the first version subtracted 512 (`{v[8], 9'd0}`). Every
sprite crossing the left or top edge was drawn off screen. Found by the
sweep: 66 frames with 3-176 differing pixels in runs of four (attract
441-444, 857-860, ...), all sprites at negative X or Y. This is also the
checker's negative control: it sees a real, small sprite error.

The board path must also tolerate what the restart does: a ROM request can
be dropped before its acknowledge (M3).
