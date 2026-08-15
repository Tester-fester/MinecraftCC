--[[
  AeroOS · Wallpapers (v3 — proper pixel art using palette slots)

  Each wallpaper is a function paint(t, w, h) that uses term.blit with
  palette indices (0-15 as hex chars). No more raw RGB ints leaking into
  blit calls. Wallpapers use the same palette slots as the chrome so the
  look is consistent.

  Three built-in wallpapers:
    - aero_blue   : deep blue gradient with a glassy diagonal highlight
    - emerald     : green-tinted night sky
    - midnight    : dark navy with scattered stars + crescent moon
]]

local wallpaper = {}

local function idx_hex(slot)
  return string.format("%x", slot)
end

local wallpapers = {
  aero_blue = {
    name = "Aero Blue",
    paint = function(t, w, h)
      -- Vertical gradient: deep blue at top -> deepest navy at bottom.
      -- We use slots 1 (DESKTOP_BG_TOP) and 14 (DESKTOP_BG_BOT), with a
      -- mid slot 5 for the transition band.
      local top_idx = "1"    -- 0x1F3A5F
      local mid_idx = "5"    -- 0x1E3A5F
      local bot_idx = "e"    -- 0x0A1A2A (index 14 -> 'e')
      local glass_idx = "2"  -- 0xC8E6FF (pale cyan glass highlight)
      for row = 1, h - 1 do
        local ratio = (row - 1) / math.max(1, h - 2)
        local slot
        if ratio < 0.4 then slot = top_idx
        elseif ratio < 0.7 then slot = mid_idx
        else slot = bot_idx end
        t.setCursorPos(1, row)
        t.blit(string.rep(" ", w), string.rep("0", w), string.rep(slot, w))
      end
      -- Glassy diagonal highlight in the top-left, very subtle.
      for i = 1, math.min(w, h - 1) do
        t.setCursorPos(i, i)
        t.blit(" ", "0", glass_idx)
      end
    end,
  },
  emerald = {
    name = "Emerald",
    paint = function(t, w, h)
      -- Green-tinted gradient: slot 12 (success green) top, slot 5 (dark blue) bottom.
      local top_idx = "c"  -- 12 -> 'c' (0x6FCF97)
      local mid_idx = "5"   -- 5 (dark blue)
      local bot_idx = "e"   -- 14 (deepest)
      for row = 1, h - 1 do
        local ratio = (row - 1) / math.max(1, h - 2)
        local slot
        if ratio < 0.3 then slot = top_idx
        elseif ratio < 0.6 then slot = mid_idx
        else slot = bot_idx end
        t.setCursorPos(1, row)
        t.blit(string.rep(" ", w), string.rep("0", w), string.rep(slot, w))
      end
    end,
  },
  midnight = {
    name = "Midnight",
    paint = function(t, w, h)
      -- Solid very-dark navy with scattered stars and a crescent moon.
      -- We use slot 14 (DESKTOP_BG_BOT) for the background, slot 0 (white)
      -- for stars, slot 2 (glass pale cyan) for the moon highlight.
      local bg_idx = "e"     -- 14 (deepest)
      local star_chars = { ".", "*", "+", "." }
      local star_slots = { "0", "2", "0", "7" }  -- white / glass / white / gray
      -- Fill background.
      for row = 1, h - 1 do
        t.setCursorPos(1, row)
        t.blit(string.rep(" ", w), string.rep("0", w), string.rep(bg_idx, w))
      end
      -- Scatter stars deterministically (no math.random so the layout is
      -- the same every boot — looks more like a real wallpaper).
      local seed = 12345
      local function rand()
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed / 2147483648
      end
      for _ = 1, math.floor((w * (h - 1)) / 18) do
        local x = math.floor(rand() * w) + 1
        local y = math.floor(rand() * (h - 1)) + 1
        local idx = math.floor(rand() * 4) + 1
        local ch = star_chars[idx]
        local fg = star_slots[idx]
        t.setCursorPos(x, y)
        t.blit(ch, fg, bg_idx)
      end
      -- Crescent moon: a 3x3 cluster in the top-right.
      -- Slot 2 (pale cyan) for the moon body, slot 0 (white) for the highlight.
      if w >= 12 and h >= 6 then
        local mx, my = w - 6, 2
        -- Moon body (3 chars wide, 1 row tall).
        t.setCursorPos(mx, my)
        t.blit("()(", "222", "eee")
        t.setCursorPos(mx, my + 1)
        t.blit(" O ", "020", "eee")
        t.setCursorPos(mx, my + 2)
        t.blit("   ", "000", "eee")
      end
    end,
  },
}

local order = { "aero_blue", "emerald", "midnight" }

function wallpaper.get(name)
  return wallpapers[name] or wallpapers.aero_blue
end

function wallpaper.next(name)
  for i, n in ipairs(order) do
    if n == name then
      return order[(i % #order) + 1]
    end
  end
  return order[1]
end

function wallpaper.list()
  return order
end

return wallpaper
