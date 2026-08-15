--[[
  AeroOS · Task Manager app

  Lists running AeroOS processes (PID, name, CPU ticks, state) and running
  windows. Press K to kill the selected window.
]]

local theme = require("aeroros.wm.theme")
local process_mod = require("aeroros.kernel.process")
local manager = require("aeroros.wm.manager")

local taskmgr = {}

local function register(desktop)
  desktop.register_app("Task Manager", function()
    desktop.open_app("Task Manager")
  end)
end

local function run(win)
  local content = win:content_rect()
  local term_win = win:get_content_term()
  local old_term = term.redirect(term_win)

  local sel = 1

  local function paint()
    local w, h = term_win.getSize()
    term_win.setBackgroundColor(colors.lightBlue)
    term_win.clear()

    -- Header.
    term_win.setCursorPos(1, 1)
    term_win.setTextColor(colors.white)
    term_win.setBackgroundColor(colors.blue)
    term_win.write(" AeroOS Task Manager" .. string.rep(" ", w - 20))

    -- Columns header.
    term_win.setCursorPos(1, 2)
    term_win.setTextColor(colors.black)
    term_win.setBackgroundColor(colors.lightGray)
    term_win.write(("PID  %-20s %-10s %s"):format("Name", "CPU", "State") .. string.rep(" ", w))

    -- List windows (which correspond to running apps).
    local wins = manager:list_windows()
    for i, w in ipairs(wins) do
      local row = 2 + i
      if row > h - 1 then break end
      local rec = process_mod.get(w.pid)
      local cpu = rec and tostring(rec.cpu_time) or "-"
      local state = w.minimized and "min" or (w.focused and "focus" or "run")
      local line = ("%-4d %-20s %-10s %s"):format(w.pid, w.title:sub(1, 20), cpu, state)
      if i == sel then
        term_win.setTextColor(colors.white)
        term_win.setBackgroundColor(colors.blue)
      else
        term_win.setTextColor(colors.black)
        term_win.setBackgroundColor(colors.lightBlue)
      end
      term_win.setCursorPos(1, row)
      term_win.write(line .. string.rep(" ", w - #line))
    end

    -- Footer.
    term_win.setCursorPos(1, h)
    term_win.setTextColor(colors.white)
    term_win.setBackgroundColor(colors.gray)
    term_win.write("Up/Dn:Select  K:Kill  R:Refresh  Q:Quit")
  end

  paint()

  local process = require("aeroros.kernel.process")
  local event_mod = require("aeroros.kernel.event")
  event_mod.listen("key", process.current())

  while true do
    local rec = process.get(process.current())
    if rec and #rec.inbox > 0 then
      local ev = table.remove(rec.inbox, 1)
      local name = ev[1]
      if name == "key" then
        local key = ev[2]
        local wins = manager:list_windows()
        if key == keys.q then break
        elseif key == keys.r then paint()
        elseif key == keys.up and sel > 1 then sel = sel - 1; paint()
        elseif key == keys.down and sel < #wins then sel = sel + 1; paint()
        elseif key == keys.k then
          if wins[sel] then
            manager:close(wins[sel])
            if sel > 1 then sel = sel - 1 end
            paint()
          end
        end
      end
    end
    coroutine.yield()
    -- Auto-refresh every ~0.5s.
    paint()
  end

  term.redirect(old_term)
end

taskmgr.register = register
taskmgr.run = run
return taskmgr
