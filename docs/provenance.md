# Provenance — Arcade-GingaNin_MiSTer

Where every file came from. Pins are in `deps.lock`.

## RTL

| file | from | status |
|---|---|---|
| `sys/` | Template_MiSTer (via Arcade-JalecoMS1Z_MiSTer) | verbatim |
| `rtl/sdram.sv`, `sdram_arb.sv`, `sdram_req.sv`, `crt_chain.sv`, `cheats.sv`, `pll.v` | Arcade-JalecoMS1Z_MiSTer | verbatim |
| `rtl/video_retime.sv` | Arcade-NMKBP964_MiSTer | verbatim (the parameterised vertical window) |
| `rtl/savestate/savestate.sv` | Arcade-NMKBP964_MiSTer | verbatim (NMKBP964's VARLAT mode; used here with a fixed latency) |
| `rtl/savestate/ss_m68k_park.sv` | Arcade-NMKBP964_MiSTer | modified: `stall` holds the monitor's RESUME read until the release, so the 68000 leaves on a fixed clock (GN-10) |
| `rtl/savestate/savestate_ui.sv` | Arcade-NMKBP964_MiSTer | modified: slot 2 on F2, not F5 (this board has no Service key; GN-10) |
| `rtl/savestate/ss_m6809_park.sv` | new, after `ss_m68k_park` / MS1Z's `ss_z80_park` | GN-10 |
| `rtl/third_party/fx68k`, `hiscore`, `crt_adjust` | Arcade-JalecoMS1Z_MiSTer (its pins) | verbatim |
| `rtl/third_party/ym2149/ym2149_zx.sv` | MiSTer-devel/ZX-Spectrum_MISTer `rtl/ym2149.sv` | modified: the volume table is a `localparam` array instead of an initialised `wire` (Verilator); chosen over MSX_MiSTer's copy by Q5 (GN-5) |
| `rtl/third_party/mc6809/mc6809is.v` | Arcade-TimePilot84_MiSTer (upstream cavnex/mc6809) | modified: power-up values on the NMI/IRQ/FIRQ latches and samples (GN-4); `LICENSE.md` from upstream (BSD) |
| `rtl/third_party/jtopl/` | jotego/jtopl `hdl/` | verbatim, GPL-3.0 |
| `GingaNin.sv` | Arcade-JalecoMS1Z_MiSTer `MS1Z.sv` | derived: this board's inputs, raster, SDRAM ports; no savestates yet |
| `GingaNin.qpf`, `.qsf`, `.sdc`, `files_gn.qip`, `build.sh` | Arcade-JalecoMS1Z_MiSTer's project files and build script | derived |

## Tools and simulation

| file | from | status |
|---|---|---|
| `tools/gn_romdata.py`, `gen_gn_mra.py`, `gn_model.py` | new (the generator follows NMKBP964's) | |
| `sim/oracle/gn_capture.lua`, `gn_play.lua`, `gn_sndtrace.lua` | new | |
| `tools/gn_sndcmp.py`, `sim/rtl/gn_snd/` | new | the sound-board trace gate (GN-4) |
| `rtl/gingan/gn_ptm6840.sv`, `gn_sound.sv`, `gn_y8950.sv` | new | |
| `rtl/gingan/gn_adpcmb.sv` | new: a port of MAME's ymfm `adpcm_b_channel` (Aaron Giles, BSD-3-Clause) | GN-5 |
| `rtl/gingan/gn_main.sv`, `gn_core.sv`, `gn_rom_hw.sv` (with `gn_romport`) | new; `gn_rom_hw`'s download follows MS1Z's `ms1z_rom_hw` | |
| `sim/rtl/gn_frames/` (with `ss_top.sv`), `sim/rtl/gn_hw/`, `tools/gn_torn.py` | new; `gn_hw` follows NMKBP964's `macplus_hw` | M2, M3 (GN-7, GN-8) |
| `sim/models/sdram_model.sv` | Arcade-NMKBP964_MiSTer | verbatim |
| `tools/gen_hiscore_mra.py`, `tools/gen_cheats_mra.py` | Arcade-JalecoMS1Z_MiSTer | modified: this game's cheat slots; the sibling-specific overrides removed |
| `sim/oracle/ymfm_y8950/` | new; compiles `~/mame/3rdparty/ymfm` in place | the Y8950 oracle |
