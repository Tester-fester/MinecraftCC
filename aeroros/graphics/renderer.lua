--[[
  AeroOS · Renderer
  ComBox-inspired: takes an ImageHandler (pixel grid) and a Combinator (texel
  strategy), walks the grid in row-major order, asks the combinator for each
  texel's (char, fg, bg), and writes to the terminal via term.blit.

  Optimisations:
    - Builds fg/bg strings per row, then calls term.blit once per row.
      This is the single biggest perf win in CC:Tweaked rendering.
    - Skips texels whose (char, fg, bg) matches the previous output
      (dirty-cell tracking) so we don't redraw the whole screen every frame.
    - Supports a clip rect so we only redraw a window's dirty region.

  This is the workhorse of the compositor — it's what actually pushes pixels
  to the monitor.
]]

local color = require("aeroros.graphics.color")

local renderer = {}

local Renderer = {}
Renderer.__index = Renderer

-- Create a renderer bound to a term-like object.
-- term_obj can be the global term, a window.create() result, or a monitor.
function renderer.new(term_obj, w, h)
  local self = setmetatable({}, Renderer)
  self.term = term_obj
  self.w = w
  self.h = h
  self:reset_cache()
  return self
end

-- Reset the dirty cache so the next render paints everything.
function Renderer:reset_cache()
  -- Cache: for each cell, store {char, fg, bg} as a string so equality
  -- check is O(1).
  self.cache = {}
  for i = 1, self.w * self.h do
    self.cache[i] = ""
  end
end

-- Render an ImageHandler to the bound term, using the given combinator.
-- clip is optional {x1, y1, x2, y2} in screen coords (1-indexed, inclusive).
function Renderer:render(image, combinator, palette, clip)
  palette = palette or color.AERO
  clip = clip or { 1, 1, self.w, self.h }

  for y = clip[2], clip[4] do
    local line_chars = {}
    local line_fg = {}
    local line_bg = {}
    local dirty_start = nil
    local dirty_chars, dirty_fg, dirty_bg = {}, {}, {}

    for x = clip[1], clip[3] do
      local combo = combinator:findCombination(x, y, image, palette)
      local ch, fg, bg = combo[1], combo[2], combo[3]
      local key = ch .. "|" .. fg .. "|" .. bg

      local cache_idx = (y - 1) * self.w + x
      if self.cache[cache_idx] ~= key then
        self.cache[cache_idx] = key
        if not dirty_start then dirty_start = x end
        table.insert(dirty_chars, ch)
        table.insert(dirty_fg,   string.format("%x", fg))
        table.insert(dirty_bg,   string.format("%x", bg))
      else
        -- flush dirty run if we hit a clean cell
        if dirty_start then
          self.term.setCursorPos(dirty_start, y)
          self.term.blit(table.concat(dirty_chars), table.concat(dirty_fg), table.concat(dirty_bg))
          dirty_start = nil
          dirty_chars, dirty_fg, dirty_bg = {}, {}, {}
        end
      end
    end

    -- flush trailing run
    if dirty_start then
      self.term.setCursorPos(dirty_start, y)
      self.term.blit(table.concat(dirty_chars), table.concat(dirty_fg), table.concat(dirty_bg))
    end
  end
end

-- Convenience: paint a solid rect of one colour to the bound term.
function Renderer:fill_rect(x1, y1, x2, y2, ch, fg_idx, bg_idx)
  local ch_str = string.rep(ch, x2 - x1 + 1)
  local fg = string.rep(string.format("%x", fg_idx), x2 - x1 + 1)
  local bg = string.rep(string.format("%x", bg_idx), x2 - x1 + 1)
  for y = y1, y2 do
    self.term.setCursorPos(x1, y)
    self.term.blit(ch_str, fg, bg)
  end
end

-- Write a single line of text at (x, y) with given fg/bg indices.
function Renderer:text(x, y, str, fg_idx, bg_idx)
  self.term.setCursorPos(x, y)
  local len = #str
  local fg = string.rep(string.format("%x", fg_idx), len)
  local bg = string.rep(string.format("%x", bg_idx), len)
  self.term.blit(str, fg, bg)
end

return renderer
