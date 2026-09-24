-- Oracle capture for Arcade-GingaNin_MiSTer (MAME 0.289, ginganin / ginganina).
--
-- Every frame from MP_FROM to MP_FROM+MP_FRAMES-1, at frame_done, writes
--   <MP_OUT>/sNNNNN.bin  video state, big-endian 16-bit words in memory order:
--                          0x0000 text VRAM   0x800 bytes (030000)
--                          0x0800 sprite RAM  0x800 bytes (040000)
--                          0x1000 palette     0x800 bytes (050000)
--                          0x1800 vregs       0x010 bytes (060000), padded to 0x20
--                          0x1820 FG VRAM     0x4000 bytes (068000)
--                          0x5820 palette written mask, 1,024 bits, entry i = byte i/8 bit i%8
--                          0x58A0 end
--                        MAME shows its default palette for an entry never written
--                        (entry i: R = i&1, G = i&2, B = i&4, full intensity) while
--                        palette RAM reads 0 (GN-1); the mask says which entries those are.
--   <MP_OUT>/pNNNNN.raw  screen:pixels() (u32 0x00RRGGBB, 256 x 224)
-- and once, at the first frame, <MP_OUT>/mainrom.bin: 000000-01FFFF as the
-- 68000 reads it (big-endian words), to check the .mra's byte order (MS1-49).
-- frames.txt: F  latch_writes  latch_last  irq1_fetches
-- MP_DIP: see below.
--
-- Lessons applied: taps are kept referenced in _G (MS1-10); callbacks run
-- under pcall and print their errors (MS1Z-4); guarded against a re-run after
-- a machine reset (SS-7); screen:pixels() returns (data, w, h) (MS1-9).
if _G.gn_cap_loaded then return end
_G.gn_cap_loaded = true
if os.getenv("MP_PLAY") then dofile(os.getenv("MP_PLAY")) end

local OUT    = os.getenv("MP_OUT") or "."
local FROM   = tonumber(os.getenv("MP_FROM") or "0")
local FRAMES = tonumber(os.getenv("MP_FRAMES") or "600")
local cpu    = manager.machine.devices[":maincpu"]
local mem    = cpu.spaces["program"]
local scr    = manager.machine.screens[":screen"]
local function guard(fn) return function(...) local ok, e = pcall(fn, ...); if not ok then print("tap error: " .. tostring(e)) end end end

local function words(base, bytes)
  local t = {}
  for a = base, base + bytes - 1, 2 do t[#t+1] = string.pack(">I2", mem:read_u16(a)) end
  return table.concat(t)
end

local latch_w, latch_last, irq1 = 0, -1, 0
local written = {}
for i = 0, 1023 do written[i] = 0 end
_G.gn_cap_taps = {
  mem:install_write_tap(0x050000, 0x0507FF, "palw", guard(function(off, data, mask)
    written[(off - 0x050000) >> 1] = 1
  end)),
  mem:install_write_tap(0x06000E, 0x06000F, "latch", guard(function(off, data, mask)
    latch_w = latch_w + 1; latch_last = data
  end)),
  mem:install_read_tap(0x000064, 0x000067, "irq1vec", guard(function() irq1 = irq1 + 1 end)),
}

-- MP_DIP="Field Name=value[,...]": set DIPs (raw field values) before the
-- first frame. Run with a throwaway -cfg_directory: MAME saves a changed DIP
-- into cfg/ and reads it back on every later run (MS1-25).
if os.getenv("MP_DIP") then
  local dsw = manager.machine.ioport.ports[":DSW"]
  for kv in string.gmatch(os.getenv("MP_DIP"), "[^,]+") do
    local k, v = kv:match("^(.-)=(%d+)$")
    dsw.fields[k].user_value = tonumber(v)
    print("DIP " .. k .. " = " .. v)
  end
end

local ftxt = io.open(OUT .. "/frames.txt", "w")
local F = 0
_G.gn_cap_sub = emu.add_machine_frame_notifier(guard(function()
  if F == 0 then
    local f = io.open(OUT .. "/mainrom.bin", "wb"); f:write(words(0x000000, 0x20000)); f:close()
  end
  if F >= FROM and F < FROM + FRAMES then
    local f = io.open(string.format("%s/s%05d.bin", OUT, F), "wb")
    f:write(words(0x030000, 0x800))
    f:write(words(0x040000, 0x800))
    f:write(words(0x050000, 0x800))
    f:write(words(0x060000, 0x10)); f:write(string.rep("\0", 0x10))
    f:write(words(0x068000, 0x4000))
    local t = {}
    for b = 0, 127 do
      local v = 0
      for k = 0, 7 do v = v | (written[b * 8 + k] << k) end
      t[#t+1] = string.char(v)
    end
    f:write(table.concat(t))
    f:close()
    local px = scr:pixels()
    local p = io.open(string.format("%s/p%05d.raw", OUT, F), "wb"); p:write(px); p:close()
  end
  ftxt:write(string.format("%d %d %d %d\n", F, latch_w, latch_last, irq1)); ftxt:flush()
  F = F + 1
  if F >= FROM + FRAMES then manager.machine:exit() end
end))
