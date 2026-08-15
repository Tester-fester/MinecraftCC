--[[
  AeroOS · Paint app

  Demonstrates the ComBox-style pixel pipeline: draws into an ImageHandler
  (pixel grid) and renders it via the Renderer with a HalfBlock combinator
  for sub-cell resolution.

  Tools:
    1 = brush (draw pixels)
    2 = eraser
    3 = fill (bucket)
    4 = line
    Click+drag to draw. Number keys 1-4 switch tools.
    Colour keys: r=red, g=green, b=blue, c=cyan, m=magenta, y=yellow, w=white, k=black
]]

local ImageHandler       = require("aeroros.graphics.framebuffer")
local HalfBlockCombinator = require("aeroros.graphics.combinator").HalfBlockCombinator
local renderer_mod       = require("aeroros.graphics.renderer")
local color              = require("aeroros.graphics.color")
local theme              = require("aeroros.wm.theme")

local paint = {}

local function register(desktop)
  desktop.register_app("Paint", function()
    desktop.open_app("Paint")
  end)
end

local function run(win)
  local content = win:content_rect()
  local w, h = content.w, content.h
  -- The canvas is half-height (since each texel shows 2 vertical pixels).
  local canvas_w = w
  local canvas_h = h * 2
  local canvas = ImageHandler.new(canvas_w, canvas_h, 0xFFFFFF)

  -- Tool state.
  local tool = "brush"  -- "brush" | "eraser" | "fill" | "line"
  local current_color = 0x000000
  local drag_start = nil  -- for line tool

  -- Render canvas to the content term via the renderer.
  local term_win = win:get_content_term()
  local old_term = term.redirect(term_win)
  local r = renderer_mod.new(term_win, content.w, content.h)
  local combinator = HalfBlockCombinator.new()

  local function repaint()
    r:render(canvas, combinator, color.AERO)
    -- HUD overlay.
    term_win.setCursorPos(1, 1)
    local hud = ("Tool:%-7s Color:0x%06X"):format(tool, current_color)
    term_win.blit(hud, string.rep("0", #hud), string.rep("f", #hud))
  end

  -- Convert screen coords to canvas coords.
  local function screen_to_canvas(sx, sy)
    local lx = sx - content.x + 1
    local ly = sy - content.y + 1
    if lx < 1 or lx > canvas_w then return nil end
    -- Each screen row covers 2 canvas rows (top half + bottom half).
    local cy = (ly - 1) * 2 + 1
    return lx, cy, lx, cy + 1  -- returns both the top and bottom canvas y
  end

  -- Flood fill.
  local function flood_fill(x, y, target, replacement)
    if target == replacement then return end
    local stack = {{x, y}}
    while #stack > 0 do
      local p = table.remove(stack)
      local px, py = p[1], p[2]
      if px >= 1 and px <= canvas_w and py >= 1 and py <= canvas_h then
        local cur = canvas:get(px, py)
        if cur == target then
          canvas:set(px, py, replacement)
          table.insert(stack, {px + 1, py})
          table.insert(stack, {px - 1, py})
          table.insert(stack, {px, py + 1})
          table.insert(stack, {px, py - 1})
        end
      end
    end
  end

  local function draw_line(x0, y0, x1, y1, c)
    -- Bresenham.
    local dx = math.abs(x1 - x0)
    local dy = -math.abs(y1 - y0)
    local sx = x0 < x1 and 1 or -1
    local sy = y0 < y1 and 1 or -1
    local err = dx + dy
    while true do
      canvas:set(x0, y0, c)
      if x0 == x1 and y0 == y1 then break end
      local e2 = 2 * err
      if e2 >= dy then err = err + dy; x0 = x0 + sx end
      if e2 <= dx then err = err + dx; y0 = y0 + sy end
    end
  end

  local function handle_click(sx, sy, is_drag)
    local lx, ty, _, by = screen_to_canvas(sx, sy)
    if not lx then return end
    if tool == "brush" then
      canvas:set(lx, ty, current_color)
      canvas:set(lx, by, current_color)
    elseif tool == "eraser" then
      canvas:set(lx, ty, 0xFFFFFF)
      canvas:set(lx, by, 0xFFFFFF)
    elseif tool == "fill" and not is_drag then
      local target = canvas:get(lx, ty)
      if target then flood_fill(lx, ty, target, current_color) end
    elseif tool == "line" then
      if not is_drag then
        drag_start = { x = lx, y = ty }
      end
    end
  end

  local function handle_up(sx, sy)
    if tool == "line" and drag_start then
      local lx, ty = screen_to_canvas(sx, sy)
      if lx then
        draw_line(drag_start.x, drag_start.y, lx, ty, current_color)
      end
      drag_start = nil
    end
  end

  repaint()

  local process = require("aeroros.kernel.process")
  local event_mod = require("aeroros.kernel.event")
  event_mod.listen("mouse_click", process.current())
  event_mod.listen("mouse_drag",  process.current())
  event_mod.listen("mouse_up",    process.current())
  event_mod.listen("key",         process.current())
  event_mod.listen("char",       process.current())

  local COLOR_KEYS = {
    r = 0xE74C3C, g = 0x6FCF97, b = 0x4A90E2, c = 0x76C4F0,
    m = 0xB85CFF, y = 0xF2C94C, w = 0xFFFFFF, k = 0x000000,
  }

  while true do
    local rec = process.get(process.current())
    if rec and #rec.inbox > 0 then
      local ev = table.remove(rec.inbox, 1)
      local name = ev[1]
      if name == "mouse_click" then
        handle_click(ev[3], ev[4], false)
      elseif name == "mouse_drag" then
        handle_click(ev[3], ev[4], true)
      elseif name == "mouse_up" then
        handle_up(ev[3], ev[4])
      elseif name == "char" then
        local ch = ev[2]:lower()
        if COLOR_KEYS[ch] then current_color = COLOR_KEYS[ch] end
      elseif name == "key" then
        local key = ev[2]
        if key == keys.one   then tool = "brush"
        elseif key == keys.two   then tool = "eraser"
        elseif key == keys.three then tool = "fill"
        elseif key == keys.four  then tool = "line"
        elseif key == keys.s and (ev[3] == keys.leftCtrl or ev[3] == keys.rightCtrl) then
          -- Save PNG (would need MediaParser; we save as raw for now).
          local path = "/painting_" .. os.time() .. ".raw"
          local f = fs.open(path, "w")
          for y = 1, canvas_h do
            for x = 1, canvas_w do
              f.write(string.char(canvas:get(x, y) % 256))
            end
          end
          f.close()
        elseif key == keys.escape then break end
      end
      repaint()
    end
    coroutine.yield()
  end

  term.redirect(old_term)
end

paint.register = register
paint.run = run
return paint
