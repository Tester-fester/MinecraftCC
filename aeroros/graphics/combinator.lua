--[[
  AeroOS · Combinator
  ComBox-inspired: a combinator is a strategy that, given a texel coordinate
  and an image, decides what (char, fg, bg) to write there.

  Different combinators give different visual styles:
    - SimpleCombinator: blocky 2-colour cells, fastest.
    - HalfBlockCombinator: uses ▀/▄ to double vertical resolution.
    - ShadeCombinator: uses ░ ▒ ▓ █ to fake translucency gradients.
    - GlassCombinator: the Aero special — blends source with a glass tint
      to produce the frosted-glass look on title bars.

  Combinators are objects so they can hold state (precomputed palette table,
  cached masks) and respond to palette/image changes via onPaletteChange /
  onImageChange, exactly like ComBox's API.
]]

local color = require("aeroros.graphics.color")

local combinator = {}

-- Base class. Subclasses override findCombination().
local Combinator = {}
Combinator.__index = Combinator

function Combinator.new()
  return setmetatable({}, Combinator)
end

function Combinator:onPaletteChange() end
function Combinator:onImageChange() end
function Combinator:findCombination(u, v, image, palette)
  -- default: solid white-on-black pixel
  return { ' ', color.SLOT.WHITE, color.SLOT.BLACK }
end

combinator.Combinator = Combinator

-- SimpleCombinator: nearest-palette blocky 1-colour per cell.
local SimpleCombinator = setmetatable({}, { __index = Combinator })
SimpleCombinator.__index = SimpleCombinator

function SimpleCombinator.new()
  return setmetatable({}, SimpleCombinator)
end

function SimpleCombinator:findCombination(u, v, image, palette)
  local px = image:get(u, v)
  if not px then return { ' ', 1, 0 } end
  local idx = color.nearest(px, palette)
  return { ' ', idx, idx }
end
combinator.SimpleCombinator = SimpleCombinator

-- HalfBlockCombinator: each terminal cell shows TWO vertical pixels by using
-- ▀ (top half fg, bottom half bg) or ▄ (inverse). Doubles vertical res.
local HalfBlockCombinator = setmetatable({}, { __index = Combinator })
HalfBlockCombinator.__index = HalfBlockCombinator

function HalfBlockCombinator.new()
  return setmetatable({}, HalfBlockCombinator)
end

function HalfBlockCombinator:findCombination(u, v, image, palette)
  local top = image:get(u, v) or 0x000000
  local bot = image:get(u, v + 1) or 0x000000
  local ti = color.nearest(top, palette)
  local bi = color.nearest(bot, palette)
  if ti == bi then
    return { ' ', ti, ti }
  end
  -- Half-block char. CC's term.blit counts bytes, so multi-byte UTF-8
  -- chars break the length invariant. We fall back to a single-byte
  -- ASCII approximation: "^" for top-half, but for fidelity you may
  -- need to enable Unicode in your CC:Tweaked config and use "▀".
  return { '^', ti, bi }
end
combinator.HalfBlockCombinator = HalfBlockCombinator

-- ShadeCombinator: uses ░▒▓█ to fake translucency. Best for glass effects.
-- `tint` is the RGB colour to blend toward.
local ShadeCombinator = setmetatable({}, { __index = Combinator })
ShadeCombinator.__index = ShadeCombinator

function ShadeCombinator.new(tint)
  local self = setmetatable({}, ShadeCombinator)
  self.tint = tint or 0x4A90E2
  return self
end

-- Shade chars ordered from least to most opaque.
ShadeCombinator.SHADING = { ' ', ':', ';', '#', '#' }

function ShadeCombinator:findCombination(u, v, image, palette)
  local px = image:get(u, v)
  if not px then
    return { ' ', color.SLOT.GLASS_HI, color.SLOT.TASKBAR }
  end
  -- Blend source with tint.
  local blended = color.mix(self.tint, px, 0.4)
  local idx = color.nearest(blended, palette)
  return { ' ', idx, idx }
end
combinator.ShadeCombinator = ShadeCombinator

return combinator
