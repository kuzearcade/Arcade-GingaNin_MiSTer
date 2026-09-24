# Arcade-GingaNin_MiSTer — Project Plan (approved 2026-09-24; implementation under way)

A MiSTer core for **Ginga Ninkyouden** (Jaleco, 1987). It covers both MAME
sets, `ginganin` and `ginganina`, in one bitstream. The reference is MAME's
`jaleco/ginganin.cpp` (driver by **Luca Elia**; local copy
`~/mame/src/mame/jaleco/ginganin.cpp`, 610 lines, MAME commit `774a180d`).

The method is the siblings':
- `Arcade-NMK16_MiSTer`, `Arcade-SandScrp_MiSTer`, `Arcade-JalecoMS1BCD_MiSTer`
  and `Arcade-JalecoMS1Z_MiSTer`;
- plus what `Arcade-NMKBP964_MiSTer` (Macross Plus) added since.

That method, in short:
- MAME is the oracle.
- Every claim is a measurement.
- Each block is gated against MAME before it is integrated.
- Every finding is written down as it is made.

**Approved 2026-09-24 with the recommended option for every decision:**
D1 A (BRAM + SDRAM split), D2 A (Y8950 from jtopl + jt12's ADPCM-B),
D3 A (MAME's 60.000 Hz frame, 400×250 at 6 MHz), D4 A (the YM2149 chosen by
measurement, ZX copy by default), D5 A (both sets in one bitstream).
Findings are in `docs/known-issues.md` (GN-n).

---

## 0. Facts that shape the plan

Each fact below was measured or read for this plan, not assumed.

1. **The ROMs are complete and verify.** `mame -verifyroms ginganin
   ginganina` (0.289) against `~/Arcade-GingaNin_MiSTer/mame_roms`:
   2 of 2 OK.
   - `ginganin.zip`: 15 files, 966,656 bytes (944 KB).
   - `ginganina.zip`: 3 files. The clone replaces the two main-CPU ROMs
     (`1.bin`/`2.bin`) and the text-tile ROM (`10.bin`).
2. **Small board, two CPUs, three sound devices.**
   - Main CPU: a 68000 at 6 MHz.
   - Sound CPU: an MC6809 on the 3.579545 MHz crystal, so the E clock is
     894.9 kHz.
   - An MC6840 PTM (its timer 1 drives the 6809's IRQ).
   - A YM2149 at 1.79 MHz.
   - A **Y8950** (MSX-AUDIO: OPL FM plus a DELTA-T ADPCM unit) at
     3.58 MHz, with 128 KB of ADPCM ROM.
3. **A Y8950 is not in `MSX_MiSTer`.** The request named it as a source.
   I cloned `MiSTer-devel/MSX_MiSTer` (`bb130169`) and searched every file
   and its whole history: its FM chip is the YM2413 (OPLL: IKAOPLL,
   VM2413), with no Y8950 or MSX-AUDIO anywhere. `MiSTer-devel/MSX1_MiSTer`
   (`d947f4a`) has none either. Jotego's `jtopl` (`7ac0c81`) lists the
   Y8950 as "`jt8950.v` — Not yet", and the file does not exist.
   **No open Y8950 was found. It has to be built**, from two existing
   halves (§2.5):
   - the YM3526 in `jtopl`;
   - the DELTA-T ADPCM-B unit in Jotego's `jt12` (`dc9be7c`).

   MAME's Y8950 (`3rdparty/ymfm`) is built exactly this way: an OPL FM
   engine plus `adpcm_b_engine`.
4. **The YM2149 exists** as `rtl/ym2149.sv` in `MiSTer-devel/ZX-Spectrum_MISTer`
   (`d41751d0`, MikeJ/Sorgelig, BSD-style licence). `MSX_MiSTer`'s copy
   **differs in behaviour**, not just the module name:
   - period 0 of a tone generator;
   - the I/O-port read mask;
   - the envelope reset value.

   Which one matches MAME is Q5, settled by the isolation harness.
5. **The 6809 exists.** `mc6809is.v` is Greg Miller's cycle-accurate core in
   Sorgelig's synchronous version, as used in
   `MiSTer-devel/Arcade-TimePilot84_MiSTer` (`9b32de7`). Upstream is
   `cavnex/mc6809` (`17e94a6`), under the standard BSD licence
   (`documentation/LICENSE.md`).
6. **No MC6840 was found anywhere.** GitHub has no repository for "mc6840",
   "6840 ptm" or "6840 verilog/vhdl". It is written new, with MAME's
   `machine/6840ptm.cpp` as the oracle (§2.5).
7. **Sprites are light on this board, as far as measured.** A MAME run
   counted sprites overlapping each visible line (3,000 frames of attract,
   3,000 of scripted play):

   | | max sprites on one line | mean | max on screen |
   |---|---|---|---|
   | attract | 18 | 2.4 | 93 |
   | play | 17 | 1.1 | 75 |

   18 sprites × 16 px on a line is about 540 clocks of serial SDRAM fetch
   at 48 MHz, against a line of about 3,200 clocks (§2.2). So MP-14's
   failure (a too-slow sprite fetch) is far away. The hardware limit is
   256 sprites on one line, though, and later stages were not reached: Q3
   measures deeper play.
8. **The 6809 program never uses FIRQ.** Its vectors (gn_05 at `0xFFF0`):
   - RESET `5000`;
   - NMI `4700` (the sound-latch handler);
   - IRQ `4640` (the PTM);
   - FIRQ `3000`, which is unmapped.

   FIRQ is masked from reset and never used, so it cannot be the savestate
   park path. NMI with vector substitution can (§2.9).
9. **The 68000 uses one handler for everything.** SSP `0x023FFE`, PC
   `0x000400`, and all seven autovectors point to `0xD17A`. MAME raises
   level 1 at vblank (`irq1_line_hold`), so one acknowledge must retire one
   interrupt (MS1-23).
10. **Feature data exists.**
    - `hiscore.dat` has an entry covering both sets: three records at
      `0x20291` (0x50 bytes), `0x202E1` (0x83), `0x2011D` (3), all in main
      RAM at odd byte addresses.
    - Pugsy's cheat 0.279 has `ginganin.xml` and `ginganina.xml`, each with
      seven entries (one a blank separator): Infinite Time, Energy, Beam,
      Sword, P1 Lives, P2 Lives.
11. **The CPUs run at their own clocks: there is no D3 here.**
    - fx68k and mc6809is are cycle-accurate at their native clocks, and
      6 MHz divides 48 MHz exactly.
    - Macross Plus needed MP-13's calibration only because TG68K is not
      cycle-exact.
    - What remains is making the frame period match MAME's (§2.2, D3),
      since both CPUs' work per frame follows from it.
12. **MAME's screen is a nominal one**: 256×256 at 60 Hz, visible 256×224
    (lines 16-239), with zero vblank time. No pixel clock and no blanking
    are specified. The raster is a decision (D3), as SS-1 and MS1Z were.

---

## 1. The hardware, from the driver

### 1.1 CPUs and clocks (`ginganin.cpp:493-527`)

| part | clock | notes |
|---|---|---|
| 68000 (main) | 6 MHz XTAL | `irq1_line_hold` at vblank |
| MC6809 (sound) | 3.579545 MHz XTAL, E = /4 = 894.886 kHz | `MBL68B09?` in the comment |
| MC6840 PTM | 894.886 kHz (the E clock) | external clocks 0; output 1 → 6809 IRQ |
| YM2149 | 1.789773 MHz | routed at 0.10 |
| Y8950 | 3.579545 MHz | routed at 1.0; its IRQ is not wired in MAME |

### 1.2 Main memory map (`:374-387`), 16-bit

| address | size | contents |
|---|---|---|
| `000000-01FFFF` | 128 KB | program ROM. Writes are ignored: the POST writes `0x10000-0x13FFF` (`:376`) |
| `020000-023FFF` | 16 KB | work RAM |
| `030000-0307FF` | 2 KB | text VRAM, 32×32 words |
| `040000-0407FF` | 2 KB | sprite RAM, 256 × 4 words |
| `050000-0507FF` | 2 KB | palette, 1,024 × RGBx_444 |
| `060000-06000F` | 8 words | vregs (below) |
| `068000-06BFFF` | 16 KB | FG VRAM, 256×32 words (column order) |
| `070000` | word | P1_P2 inputs |
| `070002` | word | DSW (16 bits) |

The vregs (`:265-301`):

| offset | meaning |
|---|---|
| 0 | FG scroll Y |
| 1 | FG scroll X |
| 2 | BG scroll Y |
| 3 | BG scroll X |
| 4 | layer enables: bit 0 BG (else fill with pen 0), 1 FG, 2 text, 3 sprites |
| 5 | unused |
| 6 | flip = **NOT** bit 0 |
| 7 | sound latch write, plus a pulse on the 6809's NMI |

Unmapped reads: Q7.

### 1.3 Sound map (`:390-398`), 8-bit 6809

| address | contents |
|---|---|
| `0000-07FF` | RAM |
| `0800-0807` | MC6840 |
| `1800` | sound-latch read |
| `2000-2001` | Y8950 (**write only** in MAME's map; status reads go to open bus) |
| `2800-2801` | YM2149 address/data (write) |
| `4000-FFFF` | ROM (region offset `0x4000`: 48 KB used of gn_05's 64 KB) |

### 1.4 Video (`:145-371`)

**Layers**, back to front:

| layer | tiles | map | source | colours | transparent |
|---|---|---|---|---|---|
| BG | 16×16×4 bpp, 1,024 | 512×32 tiles (8192×512 px), `SCAN_COLS` | **ROM** `bgrom` (gn_11, 32 KB, big-endian word per tile) | 768-1023 | none |
| FG | 16×16×4, 1,024 | 256×32 (4096×512), `SCAN_COLS` | FG VRAM | 512-767 | pen 15 |
| sprites | 16×16×4, **0xA00** | 256 entries | sprite RAM | 256-511 | pen 15 |
| text | 8×8×4, 512 | 32×32, `SCAN_ROWS`, no scroll | text VRAM | 0-255 | pen 15 |

**Tile word** (all layers): `code[11:0]`, colour `[15:12]`.

**Tile formats:**
- 16×16 is `gfx_8x8x4_col_2x2_group_packed_msb`: 128 bytes a tile. Row r's
  left 8 pixels are bytes `4r..4r+3`, its right 8 pixels bytes
  `64+4r..64+4r+3`, high nibble first.
- 8×8 text is `packed_msb`: 32 bytes, row r at `4r`.

**Sprites** (`:305-353`):
- word 0: Y, 9-bit signed;
- word 1: X, 9-bit signed;
- word 2: flip Y `[15]`, flip X `[14]`, code `[13:0]`;
- word 3: colour `[15:12]`;
- drawn in index order, so the **highest index is in front** (MS1Z-7's
  rule).

**Tile codes wrap by a true modulo.** The sprite ROM holds 0xA00 tiles and
the code field is 14 bits. MAME's `gfx_element` wraps codes modulo the
element count, which is **not a power of two** here (NMK-25). BG and FG
hold 1,024 tiles, so their bits 10-11 wrap too.

**Flip:** a whole-screen `TILEMAP_FLIPX|FLIPY` of the 256×256 frame, and
sprites at `240 - x`, `240 - y`. That is **rot180 of the finished frame**
(MS1-13).

**Palette:** 1,024 × `RGBx_444`, i.e. `RRRR GGGG BBBB xxxx`.

**Known MAME TODOs** (`:46-55`, "might be BTANBs"):
- palette and tilemaps not initialised at start-up;
- sprites lingering at the top in later levels;
- a spurious replay of all samples.

Each becomes a question (Q8), not an assumption.

### 1.5 Inputs and DIPs (`:401-469`)

- **P1_P2** is one 16-bit word: two sticks, two buttons each, two coins,
  two starts, active low.
- **DSW** is one 16-bit word: Coin A, Coin B, Infinite Lives, "Free Play &
  Invulnerability", Lives, Demo Sounds, Cabinet, two unknowns (one "does
  something"), Flip Screen, Freeze.
- The `.mra` DIPs are generated from `mame -listxml` (MS1-47's rule), not
  transcribed.

### 1.6 ROMs (`:537-604`)

| region | files | bytes |
|---|---|---|
| maincpu | gn_02 (even) / gn_01 (odd), `LOAD16_BYTE` | 128 KB |
| audiocpu | gn_05 | 64 KB |
| bgtiles | gn_15, gn_14 | 128 KB |
| fgtiles | gn_12, gn_13 | 128 KB |
| txttiles | gn_10 (clone: 10.bin) | 16 KB |
| sprites | gn_06 (**split**: first half at 0, second at `0x40000`), gn_07, gn_08, gn_09 | 320 KB |
| bgrom | gn_11 | 32 KB |
| ymsnd (ADPCM) | gn_04, gn_03 | 128 KB |

The clone differs in the main CPU (1.bin/2.bin) and text tiles (10.bin).

---

## 2. Architecture and reuse

### 2.1 Block diagram

```
 ioctl ──► gn_rom_hw ──► BRAM: main prog, sound prog, text tiles, BG map
                  └────► SDRAM (sdram.sv, 4 ports): BG tiles | FG tiles | sprites | ADPCM
 gn_main  (fx68k, work RAM, VRAM/palette/vregs, inputs, IRQ1, latch+NMI)
 gn_video (timing, BG/FG/text line engines, sprite line renderer, mixer, palette)
 gn_sound (mc6809is, RAM, gn_ptm6840, YM2149, gn_y8950 = jtopl + ADPCM-B, mixer)
 MiSTer top: video_retime/crt_chain/screen_rotate, hiscore, cheats, autofire,
             savestate engine + UI, OSD, keyboard
```

### 2.2 Clocks and raster

- **`clk_sys` is 48 MHz**, as on every sibling.
- **68000:** phi1/phi2 enables, 48/8 = 6 MHz exactly.
- **6809 E/Q:** a 4-phase enable from a rational accumulator for 3.579545 MHz
  (MS1-28: the accumulator must be wide enough).
- **Y8950:** a `cen` at 3.579545 MHz. **YM2149:** half of it.
- **PTM:** clocked on E.
- **Raster** (D3, recommended A): a 6 MHz dot clock (`ce_pix` = 48/8),
  **400 dots × 250 lines = 100,000 dots a frame = exactly 60.000 Hz**,
  lines 16-239 visible (224), IRQ1 at the start of line 240, 15.0 kHz.
  The frame period then equals MAME's exactly, so both CPUs get MAME's
  cycles per frame (100,000 for the 68000; 14,915 E cycles for the 6809).
  M2's frame-exact gate depends on that.
- The output side is the siblings' `video_retime` / `crt_chain`: 15 kHz
  analog, the scandoubler, and CRT Adjust.

### 2.3 Memory (D1, recommended A)

| region | size | where | why |
|---|---|---|---|
| main program | 128 KB | **BRAM** (8K × 16 per lane) | zero-wait 68000 fetches; removes the cache bug class (MS1-50, SS-12) |
| sound program | 48 KB | **BRAM** | MS1Z's reason: removes NMK16's busy-poll timing bug class |
| text tiles | 16 KB | BRAM | 8-pixel rows every 8 dots |
| BG map (gn_11) | 32 KB | BRAM | read per 16-pixel column |
| BG tiles | 128 KB | SDRAM port 0 | line engine, prefetch across the line |
| FG tiles | 128 KB | SDRAM port 1 | same |
| sprites | 320 KB | SDRAM port 2 | 2 × 32-bit reads per 16-px row; ≤ 18 rows a line measured |
| ADPCM | 128 KB | SDRAM port 3 | byte reads at ≤ 50 kHz; also the download's write port |

- BRAM is about 224 KB of ROM plus about 45 KB of RAM (Appendix F), which
  fits the 553 M10K with the framework.
- The whole romset is 944 KB and SDRAM holds 576 KB of it. No DDR3 image is
  needed (unlike Macross Plus).
- DDR3 carries only `screen_rotate` and the savestate slots.
- The download follows SS-12/SS-15:
  - `ioctl_wait` backpressure;
  - held write requests;
  - every stream in reset until the load ends and the switches have arrived
    (MS1-53).

### 2.4 Main board — `gn_main.sv`

- fx68k with the **MS1Z/MS1BCD bus glue** (DTACK, byte lanes, the global
  address mask as part of decode: MS1-21).
- Work RAM, and the VRAM/palette ports shared with video, as true-dual-port
  lanes (MS1Z-6, SS-14).
- **vregs:**
  - scrolls and layer enables go to video;
  - vregs[6] bit 0 inverted is the flip;
  - a write to vregs[7] latches the 8-bit sound command and pulses the
    6809's NMI.

  MAME calls `pulse_input_line(NMI)`, an edge. Q2 checks the 6809's view.
- **IRQ1** is raised at the start of line 240 and held until one level-1
  IACK cycle (MS1-23).
- **Inputs:** the two 16-bit ports. The DSW comes from the `.mra` switches.
  The game reads the Flip Screen DIP (bit 14); the OSD Flip is a separate
  rot180.
- **Unmapped reads** return the value MAME's open bus gives (Q7).

### 2.5 Sound board — `gn_sound.sv`

- **6809** (`mc6809is`, `ILLEGAL_INSTRUCTIONS="GHOST"`): RAM 2 KB; ROM
  `4000-FFFF` from BRAM; the latch at `1800`.
- **The NMI** comes from the latch write, as an edge.
- **The IRQ** is the PTM's output 1, as a level.
- **`gn_ptm6840.sv` (new):** three 16-bit timers, CR1-CR3, the status
  register, MSB/LSB buffer latches, and continuous/single-shot and 8-bit
  dual modes, clocked on E. Output 1 goes to the 6809's IRQ, gated by CR1
  bit 6 and the status IRQ flag.
  - Written against MAME's `6840ptm.cpp`, **only the modes the program
    uses** (Q1 lists them from a register trace), each one tested in a
    unit harness against MAME's device driven by the same trace.
- **YM2149:** the vendored `ym2149.sv` (Q5 picks the variant). `cen` at
  1.79 MHz, 8-bit channels summed.
- **`gn_y8950.sv` (new wrapper around vendored parts):**
  - **FM:** `jtopl.v` (YM3526) unmodified. Register writes are routed as
    `y8950::write_data` routes them:
    - `0x07`, `0x09-0x12`, `0x15-0x17` go to ADPCM;
    - `0x08` is split (bits 7:6 to FM, bits 3:0 to ADPCM);
    - `0x04` also clears ADPCM EOS;
    - `0x18`/`0x19` are I/O, which this board ignores.
  - **ADPCM:** `jt10_adpcmb.v` (the decoder, unmodified), plus a new
    **Y8950 DELTA-T controller** derived from `jt10_adpcm_drvB.v`:
    - start/stop registers in **32-byte units** (`address_shift` 5 for
      ROM, per `ymfm_adpcm.cpp:655`);
    - Delta-N stepping at **one step per FM sample** (clock/72 =
      49.7 kHz), where the YM2610 uses its 55 kHz timebase;
    - repeat, reset and start;
    - EOS and BRDY status;
    - the level register (0x12);
    - external ROM reads through SDRAM port 3, with a one-byte prefetch.
  - **Output**, as `y8950::generate`: FM plus ADPCM (the ADPCM shifted by
    3), then the **YM3014 10.3 floating-point round trip**
    (`output->roundtrip_fp()`).
  - The chip is gated **against MAME's ymfm Y8950** by a standalone C++
    harness that compiles `3rdparty/ymfm` directly. SandScrp's SS-10 used
    this method for the YM2203. The same register trace goes into both,
    and the outputs are compared sample by sample (FM exact is the target;
    ADPCM decoder exact).
- **Mixer:** the YM2149 at 0.10 against the Y8950 at 1.0, **level measured
  in dB against MAME's WAV** (MS1Z-13), and each source is judged isolated
  (SS-10). Mono out to both channels.
- **Pause** gates the 6809's E/Q only on a cycle boundary (NMK-24), and
  gates the PTM and both chips' enables.

### 2.6 Video — `gn_video.sv`

Per-line engines, targeting the line **2 ahead of the beam** (Macross Plus's
engines drew the beam's own line first; fixed by `vcount + 2`):

- **BG:** the column index from scroll X; map words from the BG-map BRAM;
  tile rows from SDRAM port 0 with a prefetch, **tested in M1 with stalls
  injected** (MP-9, MS1-57).
- **FG:** the same, with the FG VRAM as the map.
- **Text:** direct from its VRAM and the tile BRAM.
- **Sprites:** a scan of 256 entries a line (Y range test), then a
  row-fetch job per hit (two 32-bit SDRAM reads), written into a 256-px
  line buffer.
  - Drawn in reverse index order with first-writer-wins, so the highest
    index is in front.
  - The true modulo on the code (0xA00).
  - Flip applied on output as rot180.
  - An **overrun counter** (MS1-60, MS1Z-12).
- **Mixer:** text over sprites over FG over BG, each with pen 15
  transparent. A BG layer turned off fills with pen 0 (palette entry 0).
  The palette read goes through its own port.

**Which state MAME draws** is measured in M0, never assumed:
- MAME's `screen_update` draws the sprite list at update time with no
  buffering; NMK-1 and MS1Z-12 found a frame of lag against their
  hardware;
- MS1Z-5 and MP-1 settle which state each picture shows.

**MP-4 applies:** MAME renders the whole frame at once, and a line renderer
cannot. Mid-frame writes tear differently, which is recorded, not "fixed".

### 2.7 Repository layout (as the siblings)

```
GingaNin.sv                 MiSTer top (from MS1Z.sv)
Arcade-GingaNin.qpf/.qsf/.sdc, files_gingan.qip, deps.lock, LICENSE (GPL-3.0)
rtl/gingan/                 gn_core, gn_main, gn_sound, gn_video (+ engines), gn_rom_hw, gn_ptm6840, gn_y8950
rtl/savestate/              savestate.sv (with VARLAT), savestate_ui, ss_m68k_park, ss_m6809_park (new)
rtl/third_party/            fx68k, mc6809is (BSD), ym2149 (BSD-style), jtopl + jt12 ADPCM-B (GPL-3), hiscore, crt_adjust
rtl/                        sdram.sv, sdram_arb.sv, sdram_req.sv, video_retime.sv, crt_chain.sv, cheats.sv
sim/oracle/                 MAME Lua: capture, play, isolation
sim/rtl/                    video_state (M1), gn_frames (M2, + ss_top savestate gate), gn_hw (M3), unit harnesses
tools/                      gn_romdata.py (the one ROM table), gen_gn_mra.py, gen_hiscore_mra.py,
                            gen_cheats_mra.py, gen_autofire_mra.py, gn_model.py, board/build.sh
docs/                       PLAN.md, known-issues.md (GN-n), hw-bringup.md, provenance.md
releases/                   the .mra files and Arcade-GingaNin_<date>.rbf
```

### 2.8 Reuse map

| from | files | how |
|---|---|---|
| Template_MiSTer via MS1Z | `sys/` | verbatim |
| MS1Z | top structure, `sdram*.sv`, `video_retime.sv`, `crt_chain.sv`, `cheats.sv`, hiscore, fx68k, CRT Adjust | verbatim / adapted |
| MS1BCD / MS1Z | the 68000 bus glue, the IACK rule, the DIP/switches path, `gen_*_mra.py`, the ROM-table pattern | adapted |
| NMKBP964 | `savestate.sv` with **VARLAT**; `ss_top` and the `MP_SS` gate harness; `make lint`; the MAME inject/busy tools as templates | copied |
| jaleco `ms1_tilemap.sv` | the 16×16 tile row engine | adapted to `col_2x2_group` packing and SCAN_COLS maps |
| ZX-Spectrum_MISTer `d41751d0` | `rtl/ym2149.sv` | vendored (or MSX's, per Q5) |
| TimePilot84 `9b32de7` / cavnex `17e94a6` | `mc6809is.v` | vendored, BSD licence text kept |
| jtopl `7ac0c81` | `hdl/jtopl*.v` | vendored unmodified |
| jt12 `dc9be7c` | `jt10_adpcmb*.v` unmodified; `jt10_adpcm_drvB.v` as the base of the Y8950 controller | vendored / derived (GPL-3) |
| MAME | `ginganin.cpp`, `6840ptm.cpp`, `ymfm` | reference only; never compiled into RTL |

### 2.9 Savestates

- **The engine:** `savestate.sv` in its **VARLAT** handshake mode, 4 slots
  at `0x3E000000`, park at the vblank edge, Alt+F1/F5/F3/F4 to save
  (NMK-34).
- **68000:** `ss_m68k_park` (SSP/USP; the rest on its stack).
- **6809: `ss_m6809_park` (new).** NMI with the **vector at `0xFFFC`
  substituted** by a monitor overlay while parking, as the 68000 park does.
  - The 6809's NMI already stacks every register (E=1).
  - The monitor saves S and DP-independent state, writes DONE, spins on
    RESUME, restores S and RTIs.
  - The game's own NMI (the latch) cannot collide: the main CPU is parked
    first, so no command can arrive.
  - M5 proves it in a unit harness before wiring, as MS1Z's `ss_z80` proof
    did.
- **PTM:** all timers, latches, control and status in the image.
- **YM2149:** its 16 registers from a write-edge shadow, replayed. The
  envelope phase is approximate, as MS1BCD's YM2151.
- **Y8950:** the register shadow (FM and ADPCM), replayed, **captured from
  the live bus at the write edge** (MS1-62). ADPCM position, accumulator
  and step go through a small state port. Replay never freezes the chip's
  `cen` (MS1-61).
- **The image** (Appendix C) is about 40 KB, in a 0x80000 slot.
- **The gate is SS-13's three-save diff** (NMKBP964's `MP_SS` harness):
  per region, plus identical pictures after resume.

### 2.10 Feature parity with the siblings

| feature | plan |
|---|---|
| DIPs in the OSD | `DIP;` from the `.mra` (generated from `-listxml`) |
| Service / Test | the game has no Service input; nothing to bind (no NMK-34 clash) |
| Pause | gates both CPUs on cycle boundaries and the sound enables; mutes |
| Savestates | 4 slots, §2.9 |
| High scores | `hiscore.dat` (both sets, three records at odd byte addresses of 16-bit RAM) |
| Cheats | the 6 cheats per set (Pugsy 0.279), named in each `.mra` |
| Autofire | on Button 1, unlocked by the `.mra`'s switches bit, via `gen_autofire_mra.py` |
| Orientation | ROT0; Horz / Vert 90 / Vert 270 for rotated cabinets (NMK-35: text, not a number) |
| Flip screen | OSD rot180 of the finished frame; the Flip Screen and Cabinet DIPs are the game's |
| CRT Adjust, scandoubler / HQ2x / aspect | as the siblings |
| Keyboard | MAME keys (5/6 coin, 1/2 start, Ctrl/Alt buttons) |
| Buttons | 2 (MAME's Button 1 / Button 2; their in-game names are read from play in M0), `.mra` `<buttons>` matching `J1` |

### 2.11 Tools, `.mra`, releases

- `gn_romdata.py` is the one ROM table (from `-listxml`). `gen_gn_mra.py`
  builds the two `.mra`: parent in `_Arcade/`, clone under
  `_alternatives/_Ginga Ninkyouden/`.
- **Every generated `.mra` must parse as XML** (NMKBP964: a `--` inside a
  comment broke strict parsers). The generator checks it.
- `gen_hiscore_mra.py`, `gen_cheats_mra.py` and `gen_autofire_mra.py` come
  from the siblings, and `carry_over()` checksums before and after.
- kuzecores is one `CORES` entry, then the verification the siblings ran
  (size, MD5, `.mra` identity, XML parse, `<rbf>` resolution).

### 2.12 No baked ROM data, and licences

- No ROM, ROM-derived table, capture or trace is ever committed. Oracle
  captures live in `sim/oracle/traces/` (git-ignored).
- The history is scanned before the first push.
- The project licence is **GPL-3.0**, required by `jtopl` and `jt12`.
  mc6809is keeps its BSD notice, `ym2149.sv` its MikeJ/Sorgelig notice, and
  fx68k its own.

---

## 3. Milestones, tasks and gates

### M0 — Foundation (no RTL judged yet)

- The repository, `.gitignore` (build products, traces, `obj_*`),
  `deps.lock` with the pins in §2.8, `provenance.md`.
- The ROM table and `.mra` generator; verify both sets.
- **MAME oracle:**
  - `gn_capture.lua` dumps text/FG VRAM, sprites, palette and vregs at
    `frame_done`, and the picture from `screen:pixels()`;
  - `gn_play.lua` plays a script;
  - taps are kept referenced and wrapped in `pcall` (MS1-10, MS1Z-4);
  - guarded against re-runs (SS-7);
  - run with the SDL dummy drivers (MS1-14).
- **`tools/gn_model.py`:** a Python renderer of a captured state that must
  be **exact against MAME's pictures** before any RTL. That fixes which
  state pairs with which picture (MP-1 / MS1Z-5). Sweep attract and play.
- **Measurements:**
  - Q1: the PTM modes used;
  - Q2: NMI timing;
  - Q3: sprites per line in deep play;
  - Q4: the Y8950 register traffic (FM, ADPCM, whether status is ever
    read);
  - Q6: 68000 opcodes and the POST's ROM writes.
- The unit harnesses first:
  - `gn_ptm6840` against MAME's PTM on the Q1 trace;
  - `gn_y8950` against ymfm on the Q4 trace;
  - `ym2149` against MAME's `ay8910.cpp` on its trace;
  - `mc6809is` running the sound program alone against MAME's 6809 bus
    trace.

**Gate:** the model is exact on every sampled frame. Each chip matches its
MAME counterpart per §2.5's targets, or the difference is a named, measured
GN entry.

### M1 — Video against MAME state

`sim/rtl/video_state`: load a captured state, render, compare to MAME's
picture, with **ready stalls injected** (MP-9) and **board-like SDRAM
service** for the sprite and tile streams (MP-14: serial pair reads at the
measured latency, not an idealised queue).

**Gate:** 100 % of sampled attract and play frames pixel-exact, and flip
checked **against MAME's own flipped output** (Cabinet = Cocktail and the
Flip DIP), never against rot180 of our own frame (NMK-21).

### M2 — Whole board from reset (ROMs as arrays)

`sim/rtl/gn_frames`: both CPUs, all devices, the scripted play, WAV out.

**Gate:**
- frame-exact against MAME at a constant offset over attract and play;
- audio within 0.5 dB of MAME, with band correlation reported;
- `make lint` clean (no undriven, implicit or used-before-declared signal:
  NMKBP964's `rom_req` / `S_FILL2`).

### M3 — Hardware path

`sim/rtl/gn_hw`: `gn_rom_hw`, `sdram.sv` against the SDRAM model, the real
download.

**Gate:**
- the copy checked word for word;
- a **response checker on every stream** (MP-11: it found BG2's wrap);
- zero overruns;
- measured latencies recorded (MP-13's lesson: harness latency is not board
  latency).

### M4 — Quartus and the board

- `quartus_map` first: every array infers as M10K, checked in the report
  (MS1-37, MS1Z-6, SS-14).
- A full compile with timing met. The build script requires "Full
  Compilation was successful" and a fresh `.rbf`.
- **On the board:**
  - deploy by md5;
  - diagnose a black screen with SS-15's method;
  - compare the attract to MAME frames by screenshot;
  - capture HDMI video and audio with the capture box (`/dev/video0`, ALSA
    `hw:1,0`);
  - inject keys with `tools/mister_keys.py`.

### M5 — Feature parity

- Savestates (§2.9): the SS-13 gate in simulation, then a round trip on the
  board, pixel-exact.
- High scores (the patch-the-`.nvm` proof), cheats (visible effects),
  autofire (captured shot rate), pause, DIPs, orientation, flip, CRT
  Adjust, and audio against MAME's WAV.
- The clone set.

### M6 — Release

- `releases/` gets the `.rbf` and `.mra`.
- The history is scanned; push to `kuzearcade/Arcade-GingaNin_MiSTer`.
- Add to kuzecores and verify the published `db.json.zip` **by commit**:
  the raw CDN serves a cached copy for minutes.

---

## 4. Lessons carried in, mapped onto this board

### 4.A ROMs, `.mra`, loading
- `LOAD16_BYTE`: gn_02 is the even (high) byte. Checked against MAME's
  memory in M0 (MS1-49's byte-swap trap).
- `ROM_CONTINUE` splits gn_06 across `0x00000` and `0x40000`. The ROM
  table models it; the M3 copy check proves it.
- MiSTer never sends an empty `<switches>` (MS1-47), and the core must not
  run before they arrive (MS1-53).
- `config/dips/<mra name>.dip` overrides the whole switches value,
  including the autofire unlock byte (NMKBP964 board test).
- `.nvm` is named by the description, `.CFG` by setname (NMK-24).
- The disabled hiscore module must neither extract nor upload (NMK-33).
- The `.mra` must be well-formed XML (NMKBP964). Rotation is text, not a
  number (NMK-35).

### 4.B SDRAM, caches, buses
- Held addresses and held requests; every port through the arbiter; the
  download's backpressure (MS1-50, SS-12 #2-#5).
- A held `valid` passes a per-clock check it should fail (MS1-27).
- **Dump the value, not just the address** (NMK-21b).
- Model the board's memory service in the reference harnesses, pipelining
  and latency both (MP-14, MP-13).
- Offsets as wide as the image (MP-11: 25 bits wrapped BG2).

### 4.C Quartus
- Byte-lane arrays, the true-dual-port template with one always block per
  port, no logic between the read and its register (NMK-10, SS-14, MS1-37,
  MS1Z-6, MP-10).
- Restores inside the owning always block (MS1-34, MS1-38).
- Short per-pixel paths (NMK-25). No combinational divider (MP-10: −32 ns).
- A fitter seed can clear a −0.07 ns framework-clock miss at 86 %
  utilisation (NMKBP964); record the seed.

### 4.D Video
- `hcount`/`vcount` aligned to the pipeline (MS1-59). Engines target a
  line ahead (NMKBP964).
- Line engines count overruns (MS1-60, MS1Z-12).
- Flip checked against MAME's flip (NMK-21).
- Sprite order from MAME's code (MS1-16, MS1Z-7). True modulo on codes
  (NMK-25: 0xA00 here).
- Width and concatenation traps in blends: none here, since the board has
  no alpha, but NMKBP964's `avg()` bug is the reminder.

### 4.E Audio
- Each source isolated (SS-10).
- `-wavwrite` with `-sound none` is silent; use the SDL dummy drivers
  (MS1-14).
- dB before and after the gain (MS1Z-13).
- Savestate audio rules: shadow at the write edge; never freeze what replay
  needs; release when `ss_replay` drops (MS1-61, MS1-62).
- jt-family chips sample `write` on `cen` (MS1-29): the Y8950 wrapper
  holds a write until the chip has taken it.

### 4.F Simulation harnesses
- Makefiles depend on everything `-y` finds (MS1-58). Check that the binary
  rebuilt.
- **`make lint` gate** (NMKBP964): `-Wno-fatal` hid an undriven output and
  a use before declaration.
- Park on the vblank edge; force every divider phase (MS1-61).
- One-clock request pulses must survive the clock edge that samples them
  (the `MP_SS` harness bug).
- `stdbuf -oL`; `pgrep`/`kill` by PID, never `pkill` (it matches the
  invoking shell).

### 4.G Board and process
- Deploy by md5; keep the board tools in `tools/board/` with no password.
- The measurement kit on this machine:
  - `/dev/MiSTer_cmd` screenshots (before `screen_rotate`);
  - the EVGA capture box for the real HDMI output and audio;
  - `mister_keys.py` over uinput (chords for savestates, a hold of at
    least 0.6 s);
  - `config/<set>.CFG` as a 16-byte status word;
  - OSD navigation by capture.
- A slot survives a core reload; test it (NMKBP964).
- `.gitignore` from commit 1. Never rewrite pushed history.

### 4.H Working method
- Every claim is a measurement: report non-blank counts, and a negative
  control for every new checker (MP-9's 62,293 px).
- "Matches MAME" and "matches the board" are different claims.
- When a metric depends on phase, find the invariant one (MP-13: `work`
  against `busy`).

---

## 5. Risk register

| risk | likelihood | impact | plan |
|---|---|---|---|
| The Y8950 ADPCM controller mis-times Delta-N or its addresses | medium | wrong samples | ymfm harness, sample-exact, before integration |
| jtopl's YM3526 differs from ymfm's OPL in details (EG, rhythm) | medium | small tonal differences | measure per channel; accept documented residue, or patch |
| The 6809 park through NMI conflicts with the latch NMI | low | a failed or garbled save | main parked first; a unit proof before wiring |
| The PTM modes are more varied than expected | low | wrong sound tempo | Q1 trace first; implement exactly those |
| Late levels need more sprites per line | low | overruns | Q3 in deep play; the overrun counter; a sprite-row cache if needed |
| The raster choice differs from the real board | high (unknowable) | only output timing | documented; the frame period equals MAME's (D3) |
| MAME BTANBs (lingering sprites, palette at boot) are real behaviours | medium | "differences" that are correct | compare against MAME, record, do not "fix" |
| M10K pressure | low | — | Appendix F; the `quartus_map` probe in M0 |

## 6. Open questions — each settled by a measurement

- **Q1** Which PTM registers and modes the sound program uses (a MAME
  register trace over attract and play).
- **Q2** The NMI-to-latch-read timing, and whether a second command can
  land before the first is read.
- **Q3** Sprites per line in deep play, stages 2 and up. Use the infinite
  cheats to get there.
- **Q4** Y8950 traffic: ADPCM start/stop/Delta-N ranges, the repeat
  flag, whether status or I/O is ever used, and whether the "spurious
  replay" TODO shows in a trace.
- **Q5** YM2149: the ZX or the MSX variant, whichever matches MAME's
  `ay8910.cpp` output on the game's own traffic.
- **Q6** The 68000 POST's ROM writes (`0x10000-0x13FFF`); the executed
  opcodes (no surprises expected on a 68000).
- **Q7** Unmapped reads: MAME's value on this map.
- **Q8** The TODOs: palette at boot, lingering sprites. What MAME shows is
  the target; record it.
- **Q9** Which frame's sprite list and scroll MAME shows against the
  picture (MP-1 / MS1Z-5 method).
- **Q10** The clone: does `ginganina` differ in anything but code and text
  tiles (hiscore addresses, cheats)?

## 7. Decisions for you before M0

- **D1 — Memory layout.**
  - **A (recommended):** programs, text tiles and the BG map in BRAM;
    BG/FG/sprite tiles and ADPCM in SDRAM on the four ports (§2.3).
  - B: everything in SDRAM behind caches, as MS1Z.
  - C: everything in BRAM. It does not fit: 944 KB against about 690 KB of
    M10K.
- **D2 — The Y8950.**
  - **A (recommended):** compose `jtopl` (YM3526) and `jt12`'s ADPCM-B
    decoder, with a new Y8950 DELTA-T controller and the ymfm-gated output
    stage (§2.5). GPL-3.0.
  - B: write the whole chip from ymfm. More work, the same licence
    question avoided only if written clean-room, and a less proven FM.
- **D3 — Raster.**
  - **A (recommended):** MAME's frame, 6 MHz dots, 400×250, exactly
    60.000 Hz, 224 visible lines.
  - B: a guessed period-accurate Jaleco raster (e.g. 384×264). The frame
    rate would differ from MAME and break M2's frame-exact gate.
- **D4 — The YM2149 source.**
  - **A (recommended):** decided by Q5's measurement, defaulting to the
    ZX-Spectrum copy you named.
  - B: Jotego's `jt49` instead. GPL-3, widely used in arcade cores.
- **D5 — Sets.** **A (recommended):** one bitstream for both sets (they
  share everything but program and text ROMs).

## 8. Day one

1. Create the repository and structure; `deps.lock`; vendor the four
   third-party blocks at their pins, each with its licence.
2. Write the ROM table and `.mra` generator; build both `.mra`; verify.
3. The capture and play Lua; the first captures.
4. `gn_model.py` until it is exact on the first 100 frames.
5. Trace the sound board in MAME (Q1, Q4) to start the chip harnesses.

---

## Appendix A — OSD string (draft)

```
"GingaNin;SS3E000000:80000;",
"-;",
"HBO[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
"HBO[3:1],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
"H0O[9:8],Orientation,Horz,Vert 90,Vert 270;",
"O[17],Flip screen,Off,On;",
"P3,CRT Adjust;", ...                      (the siblings' CRT Adjust page)
"h1O[12:10],P1 Autofire,Off,10Hz,12Hz,15Hz,20Hz,30Hz;",
"h1O[15:13],P2 Autofire,Off,10Hz,12Hz,15Hz,20Hz,30Hz;",
"-;", "DIP;", "-;",
"O[29],Pause,Off,On;",
"P1,Scores;", "P1O[39],High Scores,Off,On;", "P1-;", "dAP1R[30],Save Scores;", "dAP1R[31],Reset Scores;",
"P2,Cheats;", "P2-;", "h3P2O[32],Cheat 1,Off,On;" ... "h9P2O[38],Cheat 7,Off,On;",
"P4,Savestates;", "P4O[41:40],Slot,1,2,3,4;", "P4-;",
"P4R[42],Save state (Alt+F1 F5 F3 F4);", "P4R[43],Load state (F1 F5 F3 F4);",
"-;", "R[0],Reset;",
"J1,Button 1,Button 2,Start,Coin;",
```

## Appendix B — Memory maps in the core

| main address | block | port shared with |
|---|---|---|
| `000000-01FFFF` | BRAM program, 2 × 64K × 8 | — |
| `020000-023FFF` | work RAM, 2 × 8K × 8 | hiscore/cheat back door |
| `030000-0307FF` | text VRAM | text engine |
| `040000-0407FF` | sprite RAM | sprite scan |
| `050000-0507FF` | palette | mixer |
| `068000-06BFFF` | FG VRAM | FG engine |

| SDRAM byte base | region | port |
|---|---|---|
| `0x000000` | BG tiles, 128 KB | 0 |
| `0x020000` | FG tiles, 128 KB | 1 |
| `0x040000` | sprites, 320 KB (gn_06 split as in MAME) | 2 |
| `0x090000` | ADPCM, 128 KB | 3 |
| `0x0B0000` | end (704 KB) | |

## Appendix C — Savestate image (draft, 16-bit words)

| words | contents |
|---|---|
| `0000-1FFF` | work RAM (16 KB) |
| `2000-23FF` | text VRAM |
| `2400-27FF` | sprite RAM |
| `2800-2BFF` | palette |
| `2C00-4BFF` | FG VRAM (16 KB) |
| `4C00-4C0F` | vregs |
| `5000-53FF` | sound RAM (2 KB, one byte a word) |
| `5400-54FF` | Y8950 register shadow (256) |
| `5500-551F` | Y8950 ADPCM state (address, accumulator, step, flags) |
| `5520-552F` | YM2149 registers |
| `5530-554F` | PTM (counters, latches, control, status) |
| `5550-557F` | scalars: latch, NMI pending, IRQ1, flip, layer enables, divider phases |
| `5580-558F` | 68000 park frame; 6809 park frame |

About 0x5590 words (≈ 44 KB), so a 0x80000 slot as the siblings.

## Appendix D — `.mra` ROM layout (index 0, one image)

| offset | contents |
|---|---|
| `0x000000` | main program, interleaved as MAME's memory (gn_02 even, gn_01 odd) |
| `0x020000` | sound program (gn_05, all 64 KB; the core uses `0x4000-0xFFFF`) |
| `0x030000` | text tiles (gn_10 / 10.bin) |
| `0x034000` | BG map (gn_11) |
| `0x03C000` | BG tiles (gn_15, gn_14) |
| `0x05C000` | FG tiles (gn_12, gn_13) |
| `0x07C000` | sprites (gn_06 first half, gn_07, gn_08, gn_09, gn_06 second half: MAME's order) |
| `0x0CC000` | ADPCM (gn_04, gn_03) |
| `0x0EC000` | end (944 KB) |

The loader splits it: the first 0x3C000 bytes to BRAM, the rest to SDRAM
at Appendix B's bases.

## Appendix E — Vendored sources and pins

| block | repository | commit | licence |
|---|---|---|---|
| YM2149 | MiSTer-devel/ZX-Spectrum_MISTer `rtl/ym2149.sv` | `d41751d0` | MikeJ/Sorgelig BSD-style |
| YM2149 (alt.) | MiSTer-devel/MSX_MiSTer `rtl/SOUND/psg/ym2149.sv` | `bb130169` | same |
| MC6809 | Arcade-TimePilot84_MiSTer `rtl/cpu/MC6809/mc6809is.v` (upstream cavnex/mc6809) | `9b32de7` (`17e94a6`) | BSD (Greg Miller) |
| YM3526 | jotego/jtopl `hdl/jtopl*.v` | `7ac0c81` | GPL-3.0 |
| ADPCM-B | jotego/jt12 `hdl/adpcm/jt10_adpcmb*.v`, `jt10_adpcm_drvB.v` | `dc9be7c` | GPL-3.0 |
| MC6840 | none found; written new | — | GPL-3.0 (this project) |
| Y8950 | none found (not in MSX_MiSTer or MSX1_MiSTer; jtopl's `jt8950` "not yet") | — | composed here |

## Appendix F — M10K budget (estimate; the `quartus_map` probe decides)

| block | M10K |
|---|---|
| main program 128 KB | 128 |
| sound program 48 KB | 48 |
| text tiles 16 KB, BG map 32 KB | 48 |
| work RAM 16 KB, FG VRAM 16 KB (TDP) | 32 |
| text VRAM, sprite RAM, palette, sound RAM (2 KB each) | 8 |
| sprite line buffers (2 × 256 × 8 bit), tile row caches | ~8 |
| jtopl, ADPCM, YM2149 internal tables | ~10 |
| framework (`sys/`: scaler, OSD, audio) | ~60 |
| **total** | **~342 of 553** |
