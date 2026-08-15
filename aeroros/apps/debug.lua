--[[
  AeroOS · Debug app

  A full-screen panel for inspecting the running system:
    - Tab 1: Logs    — recent log entries, filter by level/category
    - Tab 2: Procs   — process table (PID, name, state, CPU, inbox depth)
    - Tab 3: Stats   — log counters, dump-to-file button
    - Tab 4: Settings— log level, file log toggle, overlay toggle

  Launch from Start menu → "Debug", or press F12 to toggle the inline
  overlay (a smaller translucent panel over the desktop).
]]

local theme = require("aeroros.wm.theme")
local debug = require("aeroros.kernel.debug")
local process_mod = require("aeroros.kernel.process")
local manager = require("aeroros.wm.manager")

local debug_app = {}

local function register(desktop)
  desktop.register_app("Debug", function()
    desktop.open_app("Debug")
  end)
end

local function run(win)
  local content = win:content_rect()
  local term_win = win:get_content_term()
  local old_term = term.redirect(term_win)

  local tab = 1  -- 1=Logs 2=Procs 3=Stats 4=Settings
  local scroll = 1
  local level_filter = 1  -- minimum level to show; 1=trace, 3=info default
  local category_filter = ""  -- empty = all

  local function paint()
    local w, h = term_win.getSize()
    term_win.setBackgroundColor(colors.black)
    term_win.clear()

    -- Tab bar.
    term_win.setCursorPos(1, 1)
    local tabs = { " Logs ", " Procs ", " Stats ", " Settings " }
    local x = 1
    for i, t in ipairs(tabs) do
      term_win.setBackgroundColor(i == tab and colors.blue or colors.gray)
      term_win.setTextColor(i == tab and colors.white or colors.lightGray)
      term_win.setCursorPos(x, 1)
      term_win.write(t)
      x = x + #t
    end
    -- Fill the rest of the tab row.
    term_win.setBackgroundColor(colors.black)
    term_win.setTextColor(colors.gray)
    term_win.setCursorPos(x, 1)
    term_win.write(" F12 overlay  Q quit  Tab cycle")

    if tab == 1 then
      -- Logs tab.
      term_win.setTextColor(colors.white)
      term_win.setBackgroundColor(colors.black)
      term_win.setCursorPos(1, 2)
      local filter_desc = ("Level>=%s  Cat=%s"):format(
        ({trace="T",debug="D",info="I",warn="W",error="E",fatal="F"})[
          ({[1]="trace",[2]="debug",[3]="info",[4]="warn",[5]="error",[6]="fatal"})[level_filter]
        ] or "?",
        category_filter == "" and "*" or category_filter)
      term_win.write(filter_desc .. string.rep(" ", w - #filter_desc))

      -- Recent log entries, oldest at top.
      local entries = debug.recent(200)
      local row = 3
      for i = scroll, #entries do
        if row > h then break end
        local e = entries[i]
        if e.level >= level_filter and
           (category_filter == "" or e.category:find(category_filter)) then
          local col
          if     e.level == 1 then col = colors.gray
          elseif e.level == 2 then col = colors.lightGray
          elseif e.level == 3 then col = colors.white
          elseif e.level == 4 then col = colors.yellow
          elseif e.level == 5 then col = colors.orange
          elseif e.level == 6 then col = colors.red
          end
          term_win.setTextColor(col)
          term_win.setCursorPos(1, row)
          local line = string.format("%s[%s] %s: %s",
            e.tag, e.category, e.name, e.message)
          line = line:sub(1, w)
          term_win.write(line .. string.rep(" ", w - #line))
          row = row + 1
        end
      end

      -- Footer.
      term_win.setTextColor(colors.gray)
      term_win.setCursorPos(1, h)
      term_win.write("Up/Dn:scroll  L:level  C:cat  D:dump  F:file")
    elseif tab == 2 then
      -- Procs tab.
      term_win.setTextColor(colors.cyan)
      term_win.setCursorPos(1, 2)
      term_win.write(("PID  %-20s %-8s %-6s %-6s"):format("Name", "State", "CPU", "Inbox"))
      term_win.setTextColor(colors.white)
      local procs = process_mod.list()
      for i, rec in ipairs(procs) do
        if i + 2 > h - 1 then break end
        term_win.setCursorPos(1, 2 + i)
        term_win.write(("%-4d %-20s %-8s %-6d %-6d"):format(
          rec.pid, rec.name:sub(1, 20), rec.state or "?",
          rec.cpu_time or 0, rec.inbox and #rec.inbox or 0))
      end
      -- Also show windows.
      term_win.setTextColor(colors.cyan)
      term_win.setCursorPos(1, h - 1 - #manager:list_windows())
      local wins = manager:list_windows()
      term_win.write("Windows:")
      for i, w in ipairs(wins) do
        term_win.setCursorPos(1, h - #wins + i - 1)
        term_win.setTextColor(colors.white)
        term_win.write(("win#%d pid=%d %-20s %s"):format(
          w.id, w.pid or -1, w.title:sub(1, 20),
          w.minimized and "min" or (w.focused and "FOCUS" or "run")))
      end
    elseif tab == 3 then
      -- Stats tab.
      local stats = debug.stats()
      term_win.setTextColor(colors.white)
      local y = 3
      local order = {"trace","debug","info","warn","error","fatal"}
      for _, k in ipairs(order) do
        term_win.setCursorPos(2, y); y = y + 1
        term_win.setTextColor(colors.cyan)
        term_win.write(string.format("%-7s", k:upper()))
        term_win.setTextColor(colors.white)
        term_win.write(" = " .. tostring(stats[k] or 0))
      end
      term_win.setCursorPos(2, y + 1)
      term_win.setTextColor(colors.gray)
      term_win.write("Press D to dump full log to file.")
      term_win.setCursorPos(2, y + 2)
      term_win.write("Press F to toggle file logging.")
    elseif tab == 4 then
      -- Settings tab.
      term_win.setTextColor(colors.white)
      local y = 3
      local items = {
        ("Log level:      %d  (1=trace..6=fatal)  [/+-]"):format(debug.get_level()),
        ("File logging:   %s  (F)"):format(log_to_file_state_str()),
        ("Overlay:        %s  (O)"):format(debug.overlay_visible and "ON" or "OFF"),
        ("Overlay lines:  %d  ([/])"):format(debug.overlay_lines),
      }
      for _, s in ipairs(items) do
        term_win.setCursorPos(2, y); y = y + 1
        term_win.write(s)
      end
      term_win.setCursorPos(2, y + 1)
      term_win.setTextColor(colors.gray)
      term_win.write("Tip: press F12 anywhere to toggle the inline overlay.")
    end
  end

  -- Helper: read the log_to_file state from the debug module.
  -- (debug.lua keeps this in a local; we approximate by attempting a no-op
  -- dump and checking the file's existence. Better: extend debug.lua with
  -- a getter. For now, return "?" if we can't tell.)
  function log_to_file_state_str()
    return fs.exists("/aeroos/etc/debug.log") and "ON" or "OFF"
  end

  paint()

  local proc = require("aeroros.kernel.process")
  local event_mod = require("aeroros.kernel.event")
  event_mod.listen("key", proc.current())

  while true do
    local rec = proc.get(proc.current())
    if rec and #rec.inbox > 0 then
      local ev = table.remove(rec.inbox, 1)
      local name = ev[1]
      if name == "key" then
        local key = ev[2]
        if key == keys.q then break
        elseif key == keys.tab then
          tab = (tab % 4) + 1
        elseif tab == 1 then
          if key == keys.up and scroll > 1 then scroll = scroll - 1
          elseif key == keys.down then scroll = scroll + 1
          elseif key == keys.l then
            level_filter = (level_filter % 6) + 1
          elseif key == keys.c then
            -- Cycle category filter.
            local cats = {"", "kernel", "wm", "gfx", "app", "net"}
            local idx = 1
            for i, c in ipairs(cats) do if c == category_filter then idx = i break end end
            category_filter = cats[(idx % #cats) + 1]
          elseif key == keys.d then
            local path = debug.dump_to_file()
            debug.info("app", "Dumped log to " .. (path or "?"))
          elseif key == keys.f then
            debug.enable_file_log()
            debug.info("app", "File logging enabled")
          end
        elseif tab == 3 then
          if key == keys.d then
            local path = debug.dump_to_file()
            debug.info("app", "Dumped log to " .. (path or "?"))
          elseif key == keys.f then
            if log_to_file_state_str() == "ON" then
              debug.disable_file_log()
            else
              debug.enable_file_log()
            end
          end
        elseif tab == 4 then
          if key == keys.leftCtrl then
            -- toggle overlay via O key instead (leftCtrl is the start menu)
          elseif key == keys.o then
            debug.toggle_overlay()
          elseif key == keys.leftBracket then
            debug.overlay_lines = math.max(3, debug.overlay_lines - 1)
          elseif key == keys.rightBracket then
            debug.overlay_lines = math.min(40, debug.overlay_lines + 1)
          elseif key == keys.slash then
            local lvl = debug.get_level()
            debug.set_level(math.max(1, lvl - 1))
          elseif key == keys.equals then
            local lvl = debug.get_level()
            debug.set_level(math.min(6, lvl + 1))
          end
        end
        paint()
      end
    end
    coroutine.yield()
    -- Auto-refresh logs view every tick.
    if tab == 1 or tab == 2 then paint() end
  end

  term.redirect(old_term)
end

debug_app.register = register
debug_app.run = run
return debug_app
