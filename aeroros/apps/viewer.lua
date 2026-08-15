--[[
  AeroOS · Image Viewer

  Uses the ComBox-style renderer to display an image. For the demo we
  synthesise a procedural "Aero wallpaper" image (a blue-to-cyan gradient with
  a glassy orb) rather than parsing PNGs. Real ComBox ships a MediaParser that
  does PNG/QOI; we keep this self-contained.

  The point of this app is to demonstrate the renderer's combinator pipeline:
  ImageHandler (pixels) -> Combinator (texel decision) -> term.blit.
]]

local ImageHandler       = require("aeroros.graphics.framebuffer")
local HalfBlockCombinator = require("aeroros.graphics.combinator").HalfBlockCombinator
local renderer_mod       = require("aeroros.graphics.renderer")
local color              = require("aeroros.graphics.color")
local theme              = require("aeroros.wm.theme")

local viewer = {}

local function register(desktop)
  desktop.register_app("Image Viewer", function()
    desktop.open_app("Image Viewer")
  end)
end

local function run(win)
  local content = win:content_rect()
  local w, h = content.w, content.h
  -- Build a procedural Aero image.
  local img = ImageHandler.new(w, h, 0x1A2A40)
  -- Diagonal gradient: top-left cyan to bottom-right dark blue.
  for y = 1, h do
    for x = 1, w do
      local t = (x + y) / (w + h)
      local c = color.mix(0x6FA8DC, 0x0A1A2A, t)
      img:set(x, y, c)
    end
  end
  -- A glassy orb in the middle.
  local cx, cy, r = math.floor(w/2), math.floor(h/2), math.min(w, h) / 3
  for y = 1, h do
    for x = 1, w do
      local dx, dy = x - cx, y - cy
      local d = math.sqrt(dx*dx + dy*dy)
      if d <= r then
        -- inside orb: light cyan, brighter toward the centre.
        local t = 1 - (d / r)
        local c = color.mix(0x4A90E2, 0xFFFFFF, t * 0.7)
        img:set(x, y, c)
      elseif d <= r + 1 then
        -- edge: anti-alias ring with the glass tint.
        img:set(x, y, 0xC8E6FF)
      end
    end
  end

  -- Render the image directly via a renderer bound to the content rect.
  local content = win:content_rect()
  local term_win = win:get_content_term()
  local old_term = term.redirect(term_win)
  local r = renderer_mod.new(term_win, content.w, content.h)

  local combinator = HalfBlockCombinator.new()
  r:render(img, combinator, color.AERO)

  -- Wait for any key to close.
  local process = require("aeroros.kernel.process")
  local event_mod = require("aeroros.kernel.event")
  event_mod.listen("key", process.current())
  while true do
    local rec = process.get(process.current())
    if rec and #rec.inbox > 0 then
      local ev = table.remove(rec.inbox, 1)
      if ev[1] == "key" then break end
    end
    coroutine.yield()
  end

  term.redirect(old_term)
end

viewer.register = register
viewer.run = run
return viewer
