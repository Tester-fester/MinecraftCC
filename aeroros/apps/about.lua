--[[
  AeroOS · About dialog
  Shows version info and credits. Closes on any key.
]]

local theme = require("aeroros.wm.theme")

local about = {}

local function register(desktop)
  desktop.register_app("About AeroOS", function()
    desktop.open_app("About AeroOS")
  end)
end

local function run(win)
  local content = win:content_rect()
  local term_win = win:get_content_term()
  local old_term = term.redirect(term_win)

  local function line(y, txt, fg, bg)
    term_win.setCursorPos(1, y)
    term_win.setTextColor(fg or colors.white)
    term_win.setBackgroundColor(bg or colors.blue)
    term_win.write(txt)
  end

  term_win.setBackgroundColor(colors.blue)
  term_win.clear()
  term_win.setCursorPos(1, 1)
  line(1, "AeroOS 1.0  ", colors.white, colors.blue)
  line(2, "A Windows-7-Aero themed OS for CC:Tweaked", colors.lightBlue, colors.blue)
  line(4, "Kernel:", colors.cyan, colors.blue)
  line(5, "  Fork of Phoenix design (scheduler, VFS, IPC)", colors.white, colors.blue)
  line(7, "Graphics:", colors.cyan, colors.blue)
  line(8, "  ComBox-inspired renderer + combinators", colors.white, colors.blue)
  line(9, "  HalfBlock + Shade combinators for glass look", colors.white, colors.blue)
  line(11, "Press any key to close", colors.gray, colors.blue)

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

about.register = register
about.run = run
return about
