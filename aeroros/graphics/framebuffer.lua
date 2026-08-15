--[[
  AeroOS · ImageHandler
  ComBox-inspired: a 2D grid of RGB pixels. Stored as a flat array of 24-bit
  ints, one per pixel, row-major.

  Supports:
    - get(x, y)            -> rgb int or nil
    - set(x, y, rgb)
    - fill(rgb)
    - rect(x, y, w, h, rgb)
    - hline(x1, x2, y, rgb)
    - vline(x, y1, y2, rgb)
    - gradient(x1, y1, x2, y2, rgb1, rgb2, vertical?) -- Aero gradients
    - size()               -> w, h

  Used by the renderer to represent anything from a window background to a
  loaded PNG. The compositor treats the framebuffer as one big ImageHandler
  per surface.
]]

local ImageHandler = {}
ImageHandler.__index = ImageHandler

function ImageHandler.new(w, h, fill_rgb)
  local self = setmetatable({}, ImageHandler)
  self.w = w
  self.h = h
  self.pixels = {}
  local f = fill_rgb or 0x000000
  for i = 1, w * h do
    self.pixels[i] = f
  end
  return self
end

function ImageHandler:size()
  return self.w, self.h
end

function ImageHandler:get(x, y)
  if x < 1 or y < 1 or x > self.w or y > self.h then return nil end
  return self.pixels[(y - 1) * self.w + x]
end

function ImageHandler:set(x, y, rgb)
  if x < 1 or y < 1 or x > self.w or y > self.h then return end
  self.pixels[(y - 1) * self.w + x] = rgb
end

function ImageHandler:fill(rgb)
  for i = 1, self.w * self.h do
    self.pixels[i] = rgb
  end
end

function ImageHandler:rect(x, y, w, h, rgb)
  for yy = y, y + h - 1 do
    for xx = x, x + w - 1 do
      self:set(xx, yy, rgb)
    end
  end
end

function ImageHandler:hline(x1, x2, y, rgb)
  for x = x1, x2 do self:set(x, y, rgb) end
end

function ImageHandler:vline(x, y1, y2, rgb)
  for y = y1, y2 do self:set(x, y, rgb) end
end

-- Linear gradient. vertical=true means top->bottom, false means left->right.
function ImageHandler:gradient(x1, y1, x2, y2, rgb1, rgb2, vertical)
  local len = vertical and (y2 - y1 + 1) or (x2 - x1 + 1)
  for i = 0, len - 1 do
    local t = i / (len - 1)
    local c = math.floor(rgb1 * (1 - t) + rgb2 * t)
    if vertical then
      for x = x1, x2 do self:set(x, y1 + i, c) end
    else
      for y = y1, y2 do self:set(x1 + i, y, c) end
    end
  end
end

-- Composite another ImageHandler onto this one at (x, y). Optional alpha map
-- (same dimensions as src) for translucency. Without alpha, just overwrites.
function ImageHandler:composite(src, x, y, alpha_map)
  for sy = 1, src.h do
    for sx = 1, src.w do
      local px = src:get(sx, sy)
      if px then
        if alpha_map then
          local a = alpha_map[(sy - 1) * src.w + sx] or 1
          if a >= 0.99 then
            self:set(x + sx - 1, y + sy - 1, px)
          elseif a > 0.01 then
            local cur = self:get(x + sx - 1, y + sy - 1) or 0
            self:set(x + sx - 1, y + sy - 1, math.floor(cur * (1 - a) + px * a))
          end
        else
          self:set(x + sx - 1, y + sy - 1, px)
        end
      end
    end
  end
end

return ImageHandler
