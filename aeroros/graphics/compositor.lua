--[[
  AeroOS · Compositor

  Owns the screen (or a monitor). Maintains a list of "surfaces" (one per
  window). On every frame:
    1. Walks surfaces in z-order (back to front).
    2. Builds a single ImageHandler the size of the screen.
    3. Composites each surface's image onto it (with alpha for glass).
    4. Hands the composited image to the Renderer for scan-out.

  The compositor also handles the desktop wallpaper layer (drawn first) and
  the taskbar (drawn last, always on top).

  This is the heart of the Aero look: every window's pixels get composited
  into one final framebuffer, then blitted in one pass.
]]

local ImageHandler = require("aeroros.graphics.framebuffer")
local renderer     = require("aeroros.graphics.renderer")
local color        = require("aeroros.graphics.color")
local ShadeCombinator = require("aeroros.graphics.combinator").ShadeCombinator
local HalfBlockCombinator = require("aeroros.graphics.combinator").HalfBlockCombinator

local compositor = {}

local Compositor = {}
Compositor.__index = Compositor

-- Create a compositor bound to a term (and its size).
function compositor.new(term_obj)
  local w, h = term_obj.getSize()
  local self = setmetatable({}, Compositor)
  self.term = term_obj
  self.w = w
  self.h = h
  self.renderer = renderer.new(term_obj, w, h)
  -- Composite image — full screen. Rebuilt every frame.
  self.framebuffer = ImageHandler.new(w, h, 0x1A2A40)
  -- Surfaces in z-order. Back-of-stack first.
  self.surfaces = {}    -- each: { window, image, alpha_map, x, y, z }
  -- Default combinator for the desktop + chrome.
  self.default_combinator = ShadeCombinator.new(0x4A90E2)
  -- Half-block for sharper text regions.
  self.text_combinator = HalfBlockCombinator.new()
  return self
end

-- Register a window's surface.
function Compositor:add_surface(window, image, alpha_map, x, y, z)
  z = z or #self.surfaces + 1
  table.insert(self.surfaces, {
    window = window,
    image = image,
    alpha_map = alpha_map,
    x = x, y = y, z = z,
  })
  -- keep sorted back-to-front
  table.sort(self.surfaces, function(a, b) return a.z < b.z end)
end

function Compositor:remove_surface(window)
  for i = #self.surfaces, 1, -1 do
    if self.surfaces[i].window == window then
      table.remove(self.surfaces, i)
    end
  end
end

function Compositor:update_surface(window, image, alpha_map, x, y, z)
  for i = 1, #self.surfaces do
    if self.surfaces[i].window == window then
      self.surfaces[i].image = image or self.surfaces[i].image
      self.surfaces[i].alpha_map = alpha_map or self.surfaces[i].alpha_map
      self.surfaces[i].x = x or self.surfaces[i].x
      self.surfaces[i].y = y or self.surfaces[i].y
      if z then self.surfaces[i].z = z end
      break
    end
  end
  if z then
    table.sort(self.surfaces, function(a, b) return a.z < b.z end)
  end
end

-- Render the full frame. Wallpaper -> surfaces (back to front) -> taskbar.
-- wallpaper_fn(image) lets the shell draw the desktop background.
-- taskbar_fn(image) lets the shell draw the taskbar at the bottom.
function Compositor:paint(wallpaper_fn, taskbar_fn)
  -- 1. Paint wallpaper / desktop background.
  if wallpaper_fn then
    wallpaper_fn(self.framebuffer)
  else
    self.framebuffer:gradient(1, 1, self.w, self.h, 0x1A2A40, 0x0A1A2A, true)
  end

  -- 2. Composite each surface in z-order.
  for _, surf in ipairs(self.surfaces) do
    if surf.image then
      self.framebuffer:composite(surf.image, surf.x, surf.y, surf.alpha_map)
    end
  end

  -- 3. Paint taskbar (always on top).
  if taskbar_fn then
    taskbar_fn(self.framebuffer)
  end

  -- 4. Scan-out.
  self.renderer:render(self.framebuffer, self.default_combinator, color.AERO)
end

return compositor
