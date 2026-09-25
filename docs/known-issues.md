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

## GN-5 — The sound chips and the mix against MAME (closed, measured; one calibration open)

Harnesses:
- `sim/rtl/gn_y8950` runs `gn_y8950` against ymfm's Y8950 (`sim/oracle/ymfm_y8950`), register write for register write.
- `sim/rtl/gn_snd` runs the whole sound board from MAME's latch trace (90 s, `GN_WARP=1`). It writes the mix and each chip's own output (`.opl`, `.psg`).
- MAME's reference WAVs come from the same trace with `tools/mame-patches/ginganin-oracle.patch`, which lets `GN_MUTE_PSG` / `GN_MUTE_OPL` silence one chip's route.

Every comparison removes DC first (100 ms moving average), then compares 10 ms RMS envelopes.

**1. ADPCM-B: bit exact.** `gn_adpcmb.sv` is a port of ymfm's DELTA-T unit. It matches ymfm sample for sample in the `adpcm` mode.
- One bug was found this way. The interpolation weight `(~position) + 17'd1` widens `position` before the `~`, so the weight was wrong. It is now written as `17'h10000 - {1'b0, position}`.

**2. FM: jtopl, with a small residue.** The Y8950's FM half is jtopl's YM3526, unmodified. Against ymfm, the FM-only modes reach an envelope correlation of about 0.98, at −0.9 dB.
- The residue is jtopl's envelope and phase arithmetic, not the register traffic, which is identical.
- It is accepted; the siblings use jtopl as well.
- One wiring bug: jtopl's `sample` gated with `cen` gave 4× the samples. `gn_y8950` now takes the rising edge of `sample`.

**3. YM2149: ZX-Spectrum_MISTer's copy (D4, Q5).** The ZX module implements MAME's period-0 rule: a tone or noise period of 0 counts as 1 and toggles at the maximum rate. MSX_MiSTer's copy does not, so it was dropped.
- The volume table became a `localparam` for Verilator.

**4. The PSG mixer: MAME's resistor levels, then ×107/64.**
- The first mapping put the PSG 6.6 dB above MAME.
- The next used the AC part of MAME's resistor network (`psg_lvl` in `gn_sound.sv`). It came out 4.5 dB below MAME in every band, which rules out a filter.
- `gn_sound` therefore scales the three-channel sum by 107/64 (+4.47 dB), calibrated to MAME's RMS. **Where MAME's extra 4.5 dB comes from is still open.** Candidates are the route gains and the resistor network's load.

**5. Result** (90 s of play, calibrated):

| source | envelope correlation | level vs MAME |
|---|---|---|
| Y8950 alone | 0.966 | −0.10 dB |
| YM2149 alone | 0.772 | +0.21 dB |
| mix | 0.952 | −0.08 dB |

The YM2149's lower correlation has not been broken down. The likely cause is its noise channel: the noise is a free-running LFSR whose phase against MAME's is arbitrary, and the PSG alone is quiet (RMS 232), so noise weighs heavily. This is not measured. The music also drifts 3 E cycles per timer period (GN-4), which the envelope comparison absorbs.

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

## GN-7 — M2: the whole board against MAME's pictures; mid-frame sprite writes tear (open, expected: MP-4)

`sim/rtl/gn_frames` runs `gn_core` from reset: fx68k, the sound board and
the video, with the ROM ports answering after 12 clocks. Each picture is
compared with MAME's at the offset where it is uniquely exact (offset 0
throughout). Over the attract capture, 1,799 frames, **840 of 1,508
compared frames are exact, with zero sprite overruns and IRQ1 on every
frame.**

**1. The game rewrites sprites while the picture is on screen.** After the
vblank IRQ its main loop writes sprite RAM on lines 16-79. MAME's own
timing is the same: a write tap there shows the same lines and the same
per-16-line counts as the core (frame 700: 59, 110, 118 and 14 writes).
MAME's `screen_update` draws the whole frame from sprite RAM once, after
those writes; it has no sprite buffer. The core's line engines draw each
line from sprite RAM as it is at that moment, so a sprite rewritten after
the beam passed its top lines shows its old form above the write and its
new one below. This is MP-4's case (NMKBP964).

**2. Measured, not assumed.** `MP_WRALL=1 MP_WRLOG=0,N` logs every CPU
write into video memory with its frame, line, data and byte enables.
`tools/gn_torn.py` replays them:
- The core's sprite and text RAM at the end of each frame equals MAME's
  state word for word, and so does its FG VRAM (checked every frame from 251
  to 1,594).
- A picture rebuilt line by line (line L shows every write made before line
  L-1 began, because the engines draw line L during line L-1) is the core's
  picture exactly.

Of the 668 frames that differ from MAME:

| result | frames |
|---|---|
| the torn rebuild, exactly | 550 |
| within line L-1: every pixel is some cutoff inside the line (the log has line resolution; the engine reads entry by entry within the line) | 99 |
| not explained (below) | 19 |

Frame 802, for example: 549 pixels differ, lines 31-65, all on the spikes
of the attract screen's monster (sprites 6-48). The torn rebuild matches
the core's picture and the whole-frame rebuild matches MAME's.

**3. Two groups the replay does not cover.**
- **Frame 1570** is a scene change. During visible lines the CPU writes
  3,976 FG VRAM words, 176 palette entries and a scroll register, so the
  same tearing hits layers the replay does not rebuild.
- **Frames 1737-1754: the attract demo diverges.** From frame 1595 the
  core's sprite RAM at the end of a frame differs from MAME's state (12
  words, growing to 54 by frame 1653), and the demo plays out differently
  (the fighters stand elsewhere, and energy shows 5 pips against MAME's 4).
  The inputs are constant, so this is a control-flow divergence after 26 s
  of agreement. It is the kind MS1-22 records: a cycle-exact CPU against
  MAME's scheduling. It is **open**. The picture comparison is meaningful
  only up to about frame 1594 of this capture.
- **Scripted play diverges at the Start press.** The harness applies
  `gn_play.lua`'s inputs on the same frame numbering (F counts frame
  boundaries from 1; the same bits). The pictures agree up to the coin
  (frames 591-595 differ by 3-15 pixels, the same tearing), then the
  alignment wanders from frame 665, 5 frames after Start, and only 566 of
  5,108 play frames are exact. Input makes the game sensitive to the same
  timing difference as the attract divergence above, only sooner. Audio
  before that point matches MAME's play WAV: envelope correlation 0.90-0.98
  and level within 0.5 dB over 0.5-11 s.

**What would remove the tearing.** A sprite RAM copy latched at vblank would
not match MAME: MAME's picture includes writes made during the next 64
lines. Only drawing a whole frame late would, which adds a frame of lag to
every layer. The line renderer stays; MAME-exactness is measured on the
M1 harness (GN-6), and here as "exact or explained by tearing".

## GN-8 — M3: the SDRAM path (closed)

`sim/rtl/gn_hw` runs `gn_core` with `gn_rom_hw` and `rtl/sdram.sv` at
96 MHz against `sim/models/sdram_model.sv`. The testbench plays
Main_MiSTer: it sends `image.bin` through the ioctl interface and honours
`ioctl_wait`.

`gn_rom_hw` gives each ROM stream a `gn_romport` in front of an
`sdram_arb` channel:
- port 0 is the download;
- port 1 is BG and FG;
- port 2 is sprites;
- port 3 is ADPCM.

The port holds its own request until the answer arrives. It delivers the
answer only if the consumer still wants that address. An answer to a
request the sprite engine withdrew on a restart (GN-6) is discarded and
counted.

| gate | result |
|---|---|
| download | 966,656 bytes, all accepted, 282 ms |
| copy | 0 of 483,328 words differ |
| response check (every acknowledged read against the image) | BG 13.7 M, FG 13.7 M, sprites 2.68 M reads: 0 bad |
| sprite overruns, dropped answers | 0, 0 |
| pictures against M2's, attract, 1,799 frames | 1,798 identical |
| latency, clk_sys clocks, average / max | BG 15.2 / 23, FG 15.5 / 35, sprites 15.5 / 21 |

The attract never plays an ADPCM sample. Scripted play (`MP_PLAY=1`, 1,300
frames) does:
- ADPCM: 22,075 reads, 0 bad, latency 15.2 average / 25 max;
- the other streams: again 0 bad, 0 overruns, 0 dropped.

**One fix came out of it.** The first run had frame 291 differ from M2 by 1
pixel. The game writes the scroll registers during visible lines. The tile
engine latched the Y scroll and the fine X at a line's start but read the
X tile column from the live register, so a write landed partway along the
row at a point set by the ROM latency. `gn_tilerow` now latches the whole X
scroll at start: a mid-line write takes effect on the next line, whatever
the memory timing. M1 was re-run afterwards, 4,098 / 4,098, and M2's
attract result is unchanged (840 exact).

**The one remaining difference is the sprite window of GN-7.** Frame 583
differs from M2 by 6 pixels on line 56, and the CPU writes sprite RAM on
lines 54-58 of that frame. The sprite engine reads its entries through a
line at a rate the ROM latency sets, so which side of a mid-line write it
sees can move. This is inherent in a live line renderer; it is not a memory
error.

## GN-9 — M4: Quartus and the first board run (closed)

- **M10K.** The first `quartus_map` had 158,441 registers:
  - `gn_video`'s BG map was one array read at two addresses a clock, and
    the text tiles at four. Neither infers as M10K; both are now byte
    lanes, one read each.
  - The sprite line buffer's clear-on-read was a second write port. Each
    bank now keeps 256 "written" flags in registers, cleared at the swap,
    and the RAM is one write and one read.

  After both changes: 23,743 registers, with every array in M10K.
- **Full compile** (seed 1, `build.sh`): 45 % of ALMs, 427 / 553 M10K,
  timing met with no violations.
- **Board** (192.168.1.138; `.rbf` md5 `418aee15...`; the `.mra` files and
  the ROM zips were deployed and checked by md5):
  - set 1 boots into the attract;
  - a screenshot of the static character roster is **pixel-identical to
    MAME's frames 1316-1320**;
  - screenshots of later scenes are correct pictures (the space scene,
    the temple stage) but fall outside the 30 s MAME capture;
  - HDMI audio through the capture box has music at an RMS of about 470,
    varying second to second.
- **The .mra button list** was "Button 1,Button 2,Start,Coin". MiSTer
  places `<buttons>` entry k on joystick bit 4+k, and the core (like MS1Z)
  expects "Button 1,Button 2,Button 3,Start,Coin", with Button 3 as the
  autofire plain-fire alias. `tools/gen_gn_mra.py` now writes that list.
- **Savestates** are not in this build: `gn_core` has no park/replay port
  yet (M5).

## GN-10 — Savestates: both CPUs parked, the sound board frozen, the chips replayed (closed: SS-13 passes in attract and play)

The engine is NMKBP964's `savestate.sv` with a fixed read latency (RD_LAT 4:
every source here is a BRAM or a register, so the VARLAT handshake the plan
named is not needed). The image is 0x5950 words (map in `gn_core.sv`); 4
slots of 0x80000 bytes at 0x3E000000; Alt+F1-F4 save, F1-F4 load.

**Parking.**
- The 68000 parks with `ss_m68k_park`: a level-7 interrupt into a monitor
  overlay at 0x1E8000, unmapped here.
- The 6809 parks with the new `ss_m6809_park`:
  - an NMI whose vector fetch (0xFFFC, BS=1 BA=0) is substituted with a
    19-byte monitor at 0x3800, unmapped on the sound board;
  - the NMI stacks every register (E=1), so the monitor only keeps S;
  - it is requested only after the 68000 has parked, and only when the
    game's own NMI (the sound latch) is neither in progress nor outstanding,
    so the park never swallows a sound command.
- Unit test (`sim/rtl/gn_snd`, `GN_PARK=3000`): park at 3 s, hold 2 ms,
  resume. S = 0x07F1 (in sound RAM), and the device write sequence over 6 s
  is identical to the unparked run (8,701 writes). The monitor's entry and
  exit shift later writes by at most 65 us, the same after a save as after a
  load.

**Freezing.** The raster keeps running: the engine saves at a vblank edge
and releases at one. The sound board's clock (6809 E, PTM, chips) stops from
the moment both CPUs are parked until the release. The PTM, the NMI hold and
the clock accumulator are therefore saved and restored exactly, and the
sound board resumes at the same phase after a save as after a load.

**Sound state.**
- PTM: all timer state through a port (11 words).
- ADPCM unit: its whole state through a port (20 words).
- YM2149 and Y8950: register shadows captured at the chips' write edge from
  the CPU, replayed after a load on a clock of their own:
  - 128 chip clocks between writes, since jtopl applies an operator write as
    its slots pass;
  - the Y8950's replay goes to the FM part only, so a replayed 0x07 cannot
    restart the ADPCM unit, and the unit does not step during the replay.

  FM envelope phases are approximate after a load, as on MS1BCD's YM2151.
- The palette-written flags (GN-1) are in the image, so a load keeps MAME's
  default colours on entries the game never wrote.

**Gate** (SS-13's three-save diff, `make ss` in `sim/rtl/gn_frames`):
save slot 0; save slot 1 60 frames after the resume; load slot 0; save
slot 2 60 frames after that resume. Slots 1 and 2 are one state reached two
ways.
- Attract, save at frame 300: **0 words differ; 59 of 59 pictures after
  the resumes identical.**
- Scripted play, save at frame 900: **0 words differ, sound board
  included; 59 of 59 pictures identical.** The harness replays
  `gn_play.lua`'s inputs from the loaded frame.

The play gate first failed, and a CPU write log after each resume (with the
beam position) found two causes:
- **The interrupt acknowledge synced to fx68k's E clock.** The first writes
  after the resumes matched to the dot; the second, after the IRQ1
  acknowledge, came 40 clocks later on the load path. A VPA (autovector)
  cycle waits for the 68000's internal E clock (CPU clock / 10). Its phase
  counts every CPU clock since reset, is not in the image, and differs
  between the two paths, so every interrupt entry after a load took a few
  cycles more or less. This game is that timing-sensitive (GN-7's
  divergences).
  - `gn_main` now answers interrupt acknowledges with DTACK and the vector
    number 24 + level: the same vectors as the autovectors, with no E sync.
  - Nothing else on this board uses VPA or E.
  - M2's attract against MAME is unchanged by it: 841 of 1,508 exact
    (840 before).
- **A harness bug.** The load completes a few hundred clocks after the
  frame boundary at which it resumes, so that frame's input had been set
  from the unshifted schedule. The input word the game stored then
  differed (Button 2). The input is now set again when the load completes.

Two further changes make the release deterministic; they are kept:
- the 68000 monitor's RESUME read is held without DTACK until the release;
- the sound clock stops exactly at the 6809's loop head.

**Board:** Alt+F1 wrote `Ginga Ninkyouden (set 1)_1.ss`, 45,736 bytes (8 +
0x5950 x 2). F1, 15 s later, brought the same scene back:
- after a save during the static roster, the post-load shots are
  pixel-identical to the post-save ones;
- during the moving demo, the stage timer after the load read 988, 960,
  945, 933 against 987, 968, 944, 932 after the save (screenshot timing is
  not frame-exact).

The first build had slot 2 on F5, as the siblings do: their F2 is a Service
key. This board has none, so `savestate_ui.sv` is back on F1-F4.

## GN-11 — M5 on the board: high scores, cheats, OSD and DIP flip, pause, autofire, set 2 (closed)

Each feature was driven by the saved settings file:
`/media/fat/config/ginganin.CFG` (the OSD status word) or
`config/dips/<name>.dip` (the switches). Each was judged by screenshots.

| feature | result |
|---|---|
| High scores | `hiscore.dat`'s 3 records, 214 bytes. The dump saves on OSD open. A patched `.nvm` (top score 760000, table No. 1 765400) is restored: HIGH-SCORE reads 760000 and the ranking lists 765400. |
| Cheats | Infinite Time holds the stage timer at 999 in the demo. The other five slots come from the same `ginganin.xml` table. |
| Flip screen (OSD) | An exact rot180: 0 of 57,344 pixels differ from the unflipped shot, turned. |
| Flip Screen DIP | The game's own flip: the picture turns. |
| Pause | Screenshots are identical while paused. The test paused from boot; a pause mid-game was not tried. |
| Set 2 (`ginganina`) | Boots into the attract. |
| Savestates | GN-10. |
| Autofire | Unlocked by the `.dip` (byte 2 bit 7), P1 at 10 Hz. In a game, Button 1 held, six savestates taken at irregular times. The game's stored input word (work RAM 0x200DC, read from the `.ss` files) has Button 1 down, up, down, down, up, up. Without autofire it is down all six times. (Bit 5 also varies: Left Alt, the save chord's key, is P1 Button 2.) |

**One test error on the way, not the core.** The first patched `.nvm` also
changed the last byte of the 3-byte top-score record. The vendored `hiscore`
(NMK16's modified copy) validates each record's first and last byte against
`hiscore.dat` before restoring, so it rightly discarded that dump. Patch only
bytes inside a record.
