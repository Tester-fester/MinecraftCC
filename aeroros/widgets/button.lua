--[[
  AeroOS · Aero button widget

  Glossy blue button with hover glow and press states. Mimics the Windows 7
  Aero button: light blue base, brighter hover, darker pressed.

  Buttons are widgets that paint themselves into a parent ImageHandler.
]]

local Widget = require("aeroros.widgets.base")
local theme  = require("aeroros.wm.theme")

local Button = setmetatable({}, { __index = Widget })
Button.__index = Button

function Button.new(opts)
  local self = setmetatable(Widget.new(opts), Button)
  self.label = opts.label or "Button"
  self.state = "normal"   -- "normal" | "hover" | "pressed"
  return self
end

function Button:set_label(s) self.label = s end

function Button:render(parent_image)
  if not self.visible then return end
  local col
  if self.state == "pressed" then
    col = theme.COLORS.button_press
  elseif self.state == "hover" then
    col = theme.COLORS.button_hover
  else
    col = theme.COLORS.button_base
  end
  parent_image:rect(self.x, self.y, self.w, self.h, col)
  -- Slight gloss: paint top row with a lighter shade.
  parent_image:hline(self.x, self.x + self.w - 1, self.y, theme.COLORS.accent_cyan)
end

function Button:handle_event(ev)
  if not self.visible or not self.enabled then return false end
  local name = ev[1]
  if name == "mouse_click" then
    local _, _, sx, sy = unpack(ev)
    -- Convert screen coords to parent-local if needed. For the demo apps
    -- we accept that buttons are usually used inside a window's content
    -- and the parent already routes events to us with parent-local coords.
    -- We just trust the hit-test passed by the parent.
    self.state = "pressed"
    return true
  elseif name == "mouse_up" then
    if self.state == "pressed" then
      self.state = "hover"
      if self.on_click then self:on_click() end
      return true
    end
  elseif name == "mouse_drag" then
    -- could detect leave/enter; skipped for demo
  end
  return false
end

function Button:set_state(s) self.state = s end

return Button
