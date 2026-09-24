-- Sound-board bus trace for Arcade-GingaNin_MiSTer (MAME 0.289): every 6809
-- write to the MC6840 (0800-0807), the Y8950 (2000-2001) and the YM2149
-- (2800-2801), every read of the PTM and of the sound latch (1800), and every
-- main-CPU latch write, one line each:
--     t_ns  dev  R|W  offset  data
-- dev: ptm, opl, psg, latch (sound-side read), cmd (main-side write).
-- The unit harnesses replay these traces into both MAME's devices (through
-- the same log) and the RTL (docs/PLAN.md M0, Q1/Q4/Q5).
-- MP_OUT=file MP_FRAMES=n; MP_PLAY=<gn_play.lua> to play.
if _G.gn_snd_loaded then return end
_G.gn_snd_loaded = true
if os.getenv("MP_PLAY") then dofile(os.getenv("MP_PLAY")) end
local out = io.open(os.getenv("MP_OUT") or "sndtrace.txt", "w")
local N = tonumber(os.getenv("MP_FRAMES") or "3600")
local smem = manager.machine.devices[":audiocpu"].spaces["program"]
local mem = manager.machine.devices[":maincpu"].spaces["program"]
local function guard(fn) return function(...) local ok, e = pcall(fn, ...); if not ok then print("tap error: " .. tostring(e)) end end end
local function t() return manager.machine.time:as_double() * 1e9 end
local function log(dev, rw, off, data) out:write(string.format("%.0f %s %s %X %X\n", t(), dev, rw, off, data)) end
_G.gn_snd_taps = {
  smem:install_write_tap(0x0800, 0x0807, "ptmw", guard(function(o, d) log("ptm", "W", o - 0x800, d) end)),
  smem:install_read_tap(0x0800, 0x0807, "ptmr", guard(function(o, d) log("ptm", "R", o - 0x800, d) end)),
  smem:install_write_tap(0x2000, 0x2001, "oplw", guard(function(o, d) log("opl", "W", o - 0x2000, d) end)),
  smem:install_read_tap(0x2000, 0x2001, "oplr", guard(function(o, d) log("opl", "R", o - 0x2000, d) end)),
  smem:install_write_tap(0x2800, 0x2801, "psgw", guard(function(o, d) log("psg", "W", o - 0x2800, d) end)),
  smem:install_read_tap(0x1800, 0x1800, "latr", guard(function(o, d) log("latch", "R", 0, d) end)),
  mem:install_write_tap(0x06000E, 0x06000F, "cmd", guard(function(o, d) log("cmd", "W", 0, d) end)),
}
local F = 0
_G.gn_snd_sub = emu.add_machine_frame_notifier(function()
  F = F + 1
  out:write(string.format("%.0f frame %d\n", t(), F))
  if F >= N then out:flush(); manager.machine:exit() end
end)
