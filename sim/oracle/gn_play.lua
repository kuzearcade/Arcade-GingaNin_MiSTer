-- Scripted play for oracle captures (MAME 0.289). Coin at frame F0, start at
-- F0+60, then Button 1 pulsed every 8 frames, Button 2 every 97, and a move
-- pattern that changes every 60 frames. With MP_CHEATS=1 (the default) it
-- keeps P1's lives at 3 (0x20058, the driver's notes) every frame, so an
-- unattended run reaches later stages. The RTL harnesses reproduce it
-- exactly (same frame numbering: F counts frame_done calls, 1 = first).
-- Environment: MP_PLAY_FROM (default 600), MP_CHEATS.
-- Guarded against MAME re-running the autoboot script after a reset (SS-7).
if _G.gn_play_loaded then return end
_G.gn_play_loaded = true
local F0 = tonumber(os.getenv("MP_PLAY_FROM") or "600")
local cheats = (os.getenv("MP_CHEATS") or "1") == "1"
local inp = manager.machine.ioport.ports[":P1_P2"]
local mem = manager.machine.devices[":maincpu"].spaces["program"]
local moves = { {}, {"P1 Right"}, {"P1 Right"}, {"P1 Left"}, {"P1 Right","P1 Up"}, {"P1 Down"}, {"P1 Right"} }
local held = {}
local function set(n, v) local f = inp.fields[n]; if f then f:set_value(v) end end
local F = 0
_G.gn_play_sub = emu.add_machine_frame_notifier(function()
  F = F + 1
  for n,_ in pairs(held) do set(n, 0) end
  held = {}
  local function press(n) set(n, 1); held[n] = true end
  if F >= F0 and F < F0 + 6 then press("Coin 1") end
  if F >= F0 + 60 and F < F0 + 66 then press("1 Player Start") end
  if F >= F0 + 120 then
    if (F % 8) < 4 then press("P1 Button 1") end
    if (F % 97) < 6 then press("P1 Button 2") end
    for _,n in ipairs(moves[(F // 60) % #moves + 1]) do press(n) end
    if cheats then mem:write_u16(0x020058, 3) end
  end
end)
