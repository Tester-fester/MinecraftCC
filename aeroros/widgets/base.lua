--[[
  AeroOS · Widget base class
  Minimal OO base for buttons / labels / fields / lists / panels.

  Each widget has:
    - x, y, w, h (relative to parent panel)
    - render(image) — paint self into a parent ImageHandler at (x, y)
    - handle_event(ev) — return true if consumed

  Subclasses override render() and handle_event().
]]

local Widget = {}
Widget.__index = Widget

function Widget.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Widget)
  self.x = opts.x or 1
  self.y = opts.y or 1
  self.w = opts.w or 4
  self.h = opts.h or 1
  self.visible = opts.visible ~= false
  self.enabled = opts.enabled ~= false
  self.parent = nil
  self.on_click = opts.on_click
  self.on_change = opts.on_change
  self.tag = opts.tag  -- arbitrary user data
  return self
end

function Widget:set_pos(x, y) self.x, self.y = x, y end
function Widget:set_size(w, h) self.w, self.h = w, h end
function Widget:show() self.visible = true end
function Widget:hide() self.visible = false end

-- Default no-op render.
function Widget:render(parent_image) end

-- Default no-op event handler.
function Widget:handle_event(ev) return false end

-- Hit-test: returns true if (sx, sy) in widget-local coords falls inside.
function Widget:hit(x, y)
  return x >= self.x and x < self.x + self.w
     and y >= self.y and y < self.y + self.h
end

return Widget
