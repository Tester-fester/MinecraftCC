--[[
  AeroOS · Color & palette (v3 — fully fixed + richer palette)

  The 16-colour palette slots in CC:Tweaked map to CC color constants via:
      palette index N -> colors constant 2^N
      0 -> colors.white (1), 1 -> colors.orange (2), ..., 15 -> colors.black (32768)

  Static slots (0-3) are OS chrome that never moves.
  Dynamic slots (4-15) are owned by the focused window.

  The palette below is much richer than v2: we use every slot, and we add
  proper Aero "glass" tones so the desktop looks closer to real Windows 7.
]]

local color = {}

-- Palette indices (0-15).
color.SLOT = {
  BLACK          = 15,
  WHITE          = 0,
  GLASS_HI       = 2,   -- pale cyan glass edge
  TEXT_GRAY      = 7,   -- secondary text
  -- Dynamic (focused window controls these):
  DESKTOP_BG_TOP = 1,   -- deep aero blue (top of gradient)
  DESKTOP_BG_BOT = 14,  -- even deeper blue (bottom of gradient)
  TITLE_BAR      = 11,  -- bright aero blue (focused title bar)
  TITLE_BAR_DARK = 5,   -- darker title bar shade
  TITLE_INACTIVE = 13,  -- gray-blue for unfocused windows
  TASKBAR        = 5,   -- dark aero blue (taskbar)
  TASKBAR_HI     = 9,   -- cyan accent for focused taskbar slot
  WINDOW_BODY    = 3,   -- very light gray (window background)
  WINDOW_BODY_DK = 8,   -- slightly darker gray (borders)
  BUTTON_BASE    = 9,   -- cyan button base
  BUTTON_HOVER   = 11,  -- brighter on hover
  BUTTON_PRESS   = 5,   -- darker when pressed
  ACCENT_CYAN    = 9,   -- Aero cyan
  SUCCESS_GREEN  = 12,  -- green
  WARNING_AMBER  = 4,   -- yellow/amber
  ERROR_RED      = 14,  -- red
}

-- Static palette: installed once at boot, never moves.
-- These map to palette indices via color.SLOT.
color.STATIC = {
  [0]  = 0xFFFFFF, -- white
  [2]  = 0xC8E6FF, -- glass highlight (pale cyan)
  [7]  = 0x7A7A7A, -- text gray
  [3]  = 0xF0F4FA, -- window body light
  [8]  = 0xD4DCE8, -- window body darker
}

-- Aero desktop palette: all 16 slots filled with a richer set.
-- Slots not in STATIC are DYNAMIC; the desktop owns them by default.
color.AERO = {
  [0]  = 0xFFFFFF, -- white
  [1]  = 0x1F3A5F, -- desktop bg top (deep aero blue)
  [2]  = 0xC8E6FF, -- glass highlight
  [3]  = 0xF0F4FA, -- window body light
  [4]  = 0xF2C94C, -- warning amber
  [5]  = 0x1E3A5F, -- title bar dark / taskbar dark
  [6]  = 0x2C5784, -- mid aero blue (unused — reserved)
  [7]  = 0x7A7A7A, -- text gray
  [8]  = 0xD4DCE8, -- window body dark
  [9]  = 0x4A90E2, -- accent cyan / button base
  [10] = 0x3D7BBF, -- button hover
  [11] = 0x6FA8DC, -- bright title bar
  [12] = 0x6FCF97, -- success green
  [13] = 0xAACBED, -- unfocused gray-blue
  [14] = 0x0A1A2A, -- desktop bg bottom (deepest)
  [15] = 0x000000, -- black
}

-- CC color constants (powers of 2).
color.CC = {
  white      = 1,
  orange     = 2,
  magenta    = 4,
  lightBlue  = 8,
  yellow     = 16,
  lime       = 32,
  pink       = 64,
  gray       = 128,
  lightGray  = 256,
  cyan       = 512,
  purple     = 1024,
  blue       = 2048,
  brown      = 4096,
  green      = 8192,
  red        = 16384,
  black      = 32768,
}

-- All 16 valid CC color constants, in palette-index order.
-- palette index 0 -> white=1, 1 -> orange=2, 2 -> magenta=4, ...
color.CC_BY_INDEX = {
  [0]  = 1,      -- white
  [1]  = 2,      -- orange
  [2]  = 4,      -- magenta
  [3]  = 8,      -- lightBlue
  [4]  = 16,     -- yellow
  [5]  = 32,     -- lime
  [6]  = 64,     -- pink
  [7]  = 128,    -- gray
  [8]  = 256,    -- lightGray
  [9]  = 512,    -- cyan
  [10] = 1024,   -- purple
  [11] = 2048,   -- blue
  [12] = 4096,   -- brown
  [13] = 8192,   -- green
  [14] = 16384,  -- red
  [15] = 32768,  -- black
}

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Convert a palette index (0-15) to a CC colors.X constant (2^index).
-- CRITICAL: setPaletteColour() takes a CC color constant, NOT a palette index.
function color.cc_idx(idx)
  if idx < 0 or idx > 15 then return 1 end
  return color.CC_BY_INDEX[idx]
end

-- Convert RGB int to hex pair string (for term.blit).
function color.hex(idx)
  return string.format("%x", idx)
end

-- Build a hex string of length n using palette index `idx`.
function color.hex_n(idx, n)
  return string.rep(color.hex(idx), n)
end

-- Install the static + dynamic palette on a given term object.
function color.install(term_obj)
  term_obj = term_obj or term
  for idx, rgb in pairs(color.AERO) do
    term_obj.setPaletteColour(color.cc_idx(idx), rgb)
  end
end

-- Install a window's custom dynamic palette (slots 4..15).
function color.install_dynamic(term_obj, pal)
  term_obj = term_obj or term
  for idx = 4, 15 do
    local rgb = (pal and pal[idx]) or color.AERO[idx]
    if rgb then
      term_obj.setPaletteColour(color.cc_idx(idx), rgb)
    end
  end
end

-- Restore the desktop palette (e.g. when focus returns to the desktop shell).
function color.restore_default(term_obj)
  color.install_dynamic(term_obj, color.AERO)
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Mix two RGB ints by t (0..1).
function color.mix(a, b, t)
  local ar = bit32 and bit32.band(bit32.rshift(a, 16), 0xFF) or math.floor(a / 0x10000)
  local ag = bit32 and bit32.band(bit32.rshift(a, 8), 0xFF)  or math.floor(a / 0x100) % 256
  local ab = bit32 and bit32.band(a, 0xFF)                    or a % 256
  local br = bit32 and bit32.band(bit32.rshift(b, 16), 0xFF) or math.floor(b / 0x10000)
  local bg = bit32 and bit32.band(bit32.rshift(b, 8), 0xFF)  or math.floor(b / 0x100) % 256
  local bb = bit32 and bit32.band(b, 0xFF)                    or b % 256
  local r = math.floor(ar * (1-t) + br * t)
  local g = math.floor(ag * (1-t) + bg * t)
  local bl = math.floor(ab * (1-t) + bb * t)
  return r * 0x10000 + g * 0x100 + bl
end

-- Find the nearest palette index for an arbitrary RGB int.
function color.nearest(rgb, pal)
  pal = pal or color.AERO
  local function dist(c)
    local cr = math.floor(c / 0x10000)
    local cg = math.floor(c / 0x100) % 256
    local cb = c % 256
    local rr = math.floor(rgb / 0x10000)
    local rg = math.floor(rgb / 0x100) % 256
    local rb = rgb % 256
    return (cr-rr)^2 + (cg-rg)^2 + (cb-rb)^2
  end
  local best_idx, best_d = 0, math.huge
  for idx, c in pairs(pal) do
    local d = dist(c)
    if d < best_d then best_d, best_idx = d, idx end
  end
  return best_idx
end

-- SAFE COLOR WRAPPER.
-- If you're not sure whether a value is a CC color constant or a 24-bit RGB
-- int (e.g. from theme.COLORS.X), wrap it with this. Converts RGB ints to
-- the nearest CC color constant; passes valid CC colors through.
function color.cc(v)
  if v == nil then return 1 end
  if type(v) ~= "number" then return 1 end
  -- Valid CC color constants are 1, 2, 4, ..., 32768 (powers of 2).
  -- Combinations (sums of distinct powers of 2) are also valid, max 65535.
  if v >= 0 and v <= 65535 then
    return v
  end
  -- Treat as 24-bit RGB. Find nearest palette index, convert to CC color.
  local idx = color.nearest(v, color.AERO)
  return color.cc_idx(idx)
end

return color
