# Provenance — Arcade-GingaNin_MiSTer

Where every file came from. Pins are in `deps.lock`.

## RTL

| file | from | status |
|---|---|---|
| `sys/` | Template_MiSTer (via Arcade-JalecoMS1Z_MiSTer) | verbatim |
| `rtl/sdram.sv`, `sdram_arb.sv`, `sdram_req.sv`, `crt_chain.sv`, `cheats.sv`, `pll.v` | Arcade-JalecoMS1Z_MiSTer | verbatim |
| `rtl/video_retime.sv` | Arcade-NMKBP964_MiSTer | verbatim (the parameterised vertical window) |
| `rtl/savestate/savestate.sv`, `savestate_ui.sv`, `ss_m68k_park.sv` | Arcade-NMKBP964_MiSTer | verbatim (`savestate.sv` has NMKBP964's VARLAT mode) |
| `rtl/third_party/fx68k`, `hiscore`, `crt_adjust` | Arcade-JalecoMS1Z_MiSTer (its pins) | verbatim |
| `rtl/third_party/ym2149/ym2149_zx.sv` | MiSTer-devel/ZX-Spectrum_MISTer `rtl/ym2149.sv` | modified: the volume table is a `localparam` array instead of an initialised `wire` (Verilator); chosen over MSX_MiSTer's copy by Q5 (GN-5) |
| `rtl/third_party/mc6809/mc6809is.v` | Arcade-TimePilot84_MiSTer (upstream cavnex/mc6809) | modified: power-up values on the NMI/IRQ/FIRQ latches and samples (GN-4); `LICENSE.md` from upstream (BSD) |
| `rtl/third_party/jtopl/` | jotego/jtopl `hdl/` | verbatim, GPL-3.0 |

## Tools and simulation

| file | from | status |
|---|---|---|
| `tools/gn_romdata.py`, `gen_gn_mra.py`, `gn_model.py` | new (the generator follows NMKBP964's) | |
| `sim/oracle/gn_capture.lua`, `gn_play.lua`, `gn_sndtrace.lua` | new | |
| `tools/gn_sndcmp.py`, `sim/rtl/gn_snd/` | new | the sound-board trace gate (GN-4) |
| `rtl/gingan/gn_ptm6840.sv`, `gn_sound.sv`, `gn_y8950.sv` | new | |
| `rtl/gingan/gn_adpcmb.sv` | new: a port of MAME's ymfm `adpcm_b_channel` (Aaron Giles, BSD-3-Clause) | GN-5 |
| `sim/oracle/ymfm_y8950/` | new; compiles `~/mame/3rdparty/ymfm` in place | the Y8950 oracle |
