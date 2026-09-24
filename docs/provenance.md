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
| `rtl/third_party/ym2149/ym2149_zx.sv` | MiSTer-devel/ZX-Spectrum_MISTer `rtl/ym2149.sv` | verbatim (module `YM2149`) |
| `rtl/third_party/ym2149/ym2149_msx.sv` | MiSTer-devel/MSX_MiSTer `rtl/SOUND/psg/ym2149.sv` | verbatim (module `ym2149`); Q5 picks one |
| `rtl/third_party/mc6809/mc6809is.v` | Arcade-TimePilot84_MiSTer (upstream cavnex/mc6809) | verbatim; `LICENSE.md` from upstream (BSD) |
| `rtl/third_party/jtopl/` | jotego/jtopl `hdl/` | verbatim, GPL-3.0 |
| `rtl/third_party/jt12_adpcm/` | jotego/jt12 `hdl/adpcm/jt10_adpcmb*.v`, `jt10_adpcm_drvB.v`, `jt10_adpcm_div.v` | verbatim, GPL-3.0 |

## Tools and simulation

| file | from | status |
|---|---|---|
| `tools/gn_romdata.py`, `gen_gn_mra.py`, `gn_model.py` | new (the generator follows NMKBP964's) | |
| `sim/oracle/gn_capture.lua`, `gn_play.lua` | new | |
