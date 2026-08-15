--[[
  AeroOS · Boot animation

  Aero-style boot splash: black screen, AeroOS logo, progress bar that fills
  over ~1.5 seconds. Replaced by the desktop once the shell is ready.
]]

local theme = require("aeroros.wm.theme")
local color = require("aeroros.graphics.color")

local boot_anim = {}

function boot_anim.play(term_obj)
  term_obj = term_obj or term
  local w, h = term_obj.getSize()
  color.install(term_obj)
  term_obj.setBackgroundColor(colors.black)
  term_obj.setTextColor(colors.lightBlue)
  term_obj.clear()

  -- Center the logo.
  local logo = "AeroOS"
  local logo_x = math.floor((w - #logo) / 2) + 1
  local logo_y = math.floor(h / 2) - 1

  -- Progress bar geometry.
  local bar_w = math.min(30, w - 10)
  local bar_x = math.floor((w - bar_w) / 2) + 1
  local bar_y = logo_y + 3

  -- Stages: phase 1 — paint logo.
  term_obj.setCursorPos(logo_x, logo_y)
  term_obj.blit(logo, string.rep("b", #logo), string.rep("f", #logo))  -- cyan on white? no, see below
  -- Actually use palette: cyan text on black bg.
  term_obj.setTextColor(colors.cyan)
  term_obj.setBackgroundColor(colors.black)
  term_obj.setCursorPos(logo_x, logo_y)
  term_obj.write(logo)

  term_obj.setTextColor(colors.gray)
  term_obj.setCursorPos(logo_x, logo_y + 1)
  term_obj.write("Starting up...")

  -- Progress bar background (dark slots).
  term_obj.setBackgroundColor(colors.gray)
  term_obj.setCursorPos(bar_x, bar_y)
  term_obj.write(string.rep(" ", bar_w))

  -- Fill the bar across ~1.5 seconds in 10 steps.
  for i = 1, 10 do
    sleep(0.12)
    term_obj.setBackgroundColor(colors.cyan)
    term_obj.setCursorPos(bar_x, bar_y)
    term_obj.write(string.rep(" ", math.floor(bar_w * i / 10)))
  end

  sleep(0.2)
  term_obj.setBackgroundColor(colors.black)
  term_obj.clear()
end

return boot_anim
