--[[
  AeroOS · Desktop shell (v2)

  Major rewrite to use CC `window` API as the windowing primitive. The
  desktop now:
    - Owns the screen's term (the global `term` or a monitor).
    - Each open window is a CC `window` that the WM paints chrome into and
      the app paints content into.
    - The desktop draws the wallpaper directly into the underlying term,
      then the taskbar overlay on top.
    - Z-order is handled by CC's window stacking — the WM calls
      setVisible / redraw in stack order.

  New features in v2:
    - Boot animation (aeroros.shell.boot_anim).
    - Right-click context menu on the desktop (Refresh, Change Wallpaper,
      New File, Open Terminal Here, Display Settings).
    - Real Start menu with a working search box.
    - Taskbar shows running apps with focused-app highlight.
    - Session persistence (saves open windows to /aeroos/etc/session.cfg
      and restores them on next boot).
    - Wallpaper swatches (3 built-in wallpapers).
]]

local color         = require("aeroros.graphics.color")
local theme          = require("aeroros.wm.theme")
local manager        = require("aeroros.wm.manager")
local event          = require("aeroros.kernel.event")
local process        = require("aeroros.kernel.process")
local scheduler       = require("aeroros.kernel.scheduler")
local boot_anim      = require("aeroros.shell.boot_anim")
local persistence    = require("aeroros.shell.persistence")
local wallpaper_mod  = require("aeroros.shell.wallpaper")
local debug          = require("aeroros.kernel.debug")

local desktop = {}

desktop.compositor = nil   -- kept for the Image Viewer / Paint apps only
desktop.term = nil
desktop.w = 0
desktop.h = 0
desktop.work_h = 0
desktop.taskbar_y = 0
desktop.start_open = false
desktop.start_search = ""
desktop.apps = {}
desktop.running = true
desktop.context_menu = nil  -- { items = {...}, x = n, y = n }
desktop.current_wallpaper = "aero_blue"

-- Built-in app list (name + launcher). Apps register themselves at boot.
desktop.APP_LIST = {
  { name = "Terminal",       icon = ">",  key = "T" },
  { name = "File Explorer", icon = "[]", key = "E" },
  { name = "Notepad",        icon = "N",  key = "N" },
  { name = "Image Viewer",   icon = "I",  key = "V" },
  { name = "Calculator",     icon = "=",  key = "C" },
  { name = "Paint",          icon = "P",  key = "P" },
  { name = "Settings",      icon = "S",  key = "S" },
  { name = "Task Manager",   icon = "M",  key = "K" },
  { name = "Debug",          icon = "#",  key = "B" },
  { name = "About AeroOS",   icon = "?",  key = "A" },
}

function desktop.register_app(name, launcher)
  desktop.apps[name] = launcher
end

function desktop.open_app(name, ...)
  if desktop.apps[name] then desktop.apps[name](...) end
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Paint the desktop wallpaper directly into the term (NOT a CC window —
-- this is the bottom of the stack, painted first every frame).
local function paint_wallpaper()
  local t = desktop.term
  local w, h = desktop.w, desktop.h
  local pal = wallpaper_mod.get(desktop.current_wallpaper)
  pal.paint(t, w, h)
end

-- Paint the taskbar at the bottom row.
local function paint_taskbar()
  local t = desktop.term
  local w = desktop.w
  local y = desktop.h

  -- Taskbar background: dark blue. Palette slot 5 = TITLE_BAR_DARK = 0x1E3A5F.
  -- Hex char '5' is palette index 5. Length must be exactly w chars.
  local tb_bg = "5"   -- palette index 5
  local tb_fg = "0"   -- palette index 0 (white) for text default
  t.setCursorPos(1, y)
  t.blit(string.rep(" ", w), string.rep(tb_fg, w), string.rep(tb_bg, w))

  -- Start orb at the left (cells 1-3). Bright cyan orb on the dark taskbar.
  -- Palette: bg=5 (dark blue), orb fg=9 (accent cyan).
  -- The orb is drawn as:  O _ _  where O is bright cyan, _ are spaces.
  t.setCursorPos(1, y)
  t.blit("O  ", "900", "555")

  -- Window buttons.
  local bx = 5
  for _, win in ipairs(manager.windows) do
    if win.minimized then
      -- skip minimized windows in the taskbar layout
    else
      local lbl = win.title:sub(1, 14)
      local slot_w = #lbl + 3
      if bx + slot_w > w - 12 then break end
      -- Focused window gets the bright accent cyan slot (9), unfocused gets slot b (11 = bright blue)
      local bg_idx = win.focused and "9" or "b"
      local fg_idx = "0"  -- white text
      t.setCursorPos(bx, y)
      -- Text length must match fg length must match bg length.
      local text = " " .. lbl .. "  "
      -- Ensure #text == slot_w (it should: 1 + #lbl + 2)
      text = text:sub(1, slot_w)
      while #text < slot_w do text = text .. " " end
      t.blit(text, string.rep(fg_idx, slot_w), string.rep(bg_idx, slot_w))
      bx = bx + slot_w
    end
  end

  -- Clock at the right.
  local clock = os.date("%H:%M")
  local clock_text = " " .. clock .. " "
  local clock_len = #clock_text
  t.setCursorPos(w - clock_len + 1, y)
  t.blit(clock_text, string.rep("0", clock_len), string.rep("5", clock_len))
end

-- Paint the Start menu when open.
local function paint_start_menu()
  if not desktop.start_open then return end
  local t = desktop.term
  local w, h = desktop.w, desktop.h

  -- Filter the app list by search query.
  local apps = {}
  for _, app in ipairs(desktop.APP_LIST) do
    if desktop.start_search == "" or app.name:lower():find(desktop.start_search:lower()) then
      table.insert(apps, app)
    end
  end

  local mw = 26
  local mh = 2 + #apps + 2  -- search row + apps + spacer + footer
  local mx = 1
  local my = h - mh

  -- Background: light window body (palette slot 3 = 0xF0F4FA).
  for row = 0, mh - 1 do
    t.setCursorPos(mx, my + row)
    t.blit(string.rep(" ", mw), string.rep("f", mw), string.rep("3", mw))
  end

  -- Border: darker window body (slot 8 = 0xD4DCE8).
  for row = 0, mh - 1 do
    t.setCursorPos(mx, my + row)
    t.blit(" ", "f", "8")
    t.setCursorPos(mx + mw - 1, my + row)
    t.blit(" ", "f", "8")
  end
  for col = 0, mw - 1 do
    t.setCursorPos(mx + col, my)
    t.blit(" ", "f", "8")
    t.setCursorPos(mx + col, my + mh - 1)
    t.blit(" ", "f", "8")
  end

  -- Search row.
  t.setCursorPos(mx + 2, my + 1)
  local search_text = "Search: " .. desktop.start_search .. "_"
  local search_len = #search_text
  t.blit(search_text, string.rep("0", search_len), string.rep("3", search_len))

  -- Apps list.
  for i, app in ipairs(apps) do
    local row_y = my + i + 1
    if row_y >= my + mh - 1 then break end
    local label = "  " .. app.icon .. " " .. app.name
    label = label:sub(1, mw - 4)
    t.setCursorPos(mx + 2, row_y)
    t.blit(label, string.rep("0", #label), string.rep("3", #label))
  end

  -- Footer.
  t.setCursorPos(mx + 2, my + mh - 1)
  local footer = "Right-Ctrl to close"
  t.blit(footer, string.rep("7", #footer), string.rep("3", #footer))
end

-- Paint the right-click context menu when open.
local function paint_context_menu()
  if not desktop.context_menu then return end
  local t = desktop.term
  local cm = desktop.context_menu
  local mw = 24
  local mh = #cm.items + 2
  local mx = cm.x
  local my = cm.y

  -- Clamp to screen.
  if mx + mw > desktop.w then mx = desktop.w - mw end
  if my + mh > desktop.h then my = desktop.h - mh end

  -- Background: light window body (slot 3).
  for row = 0, mh - 1 do
    t.setCursorPos(mx, my + row)
    t.blit(string.rep(" ", mw), string.rep("f", mw), string.rep("3", mw))
  end
  -- Border: darker window body (slot 8).
  for row = 0, mh - 1 do
    t.setCursorPos(mx, my + row); t.blit(" ", "f", "8")
    t.setCursorPos(mx + mw - 1, my + row); t.blit(" ", "f", "8")
  end
  for col = 0, mw - 1 do
    t.setCursorPos(mx + col, my); t.blit(" ", "f", "8")
    t.setCursorPos(mx + col, my + mh - 1); t.blit(" ", "f", "8")
  end

  -- Items.
  for i, item in ipairs(cm.items) do
    local label = " " .. item.label
    label = label:sub(1, mw - 4)
    t.setCursorPos(mx + 2, my + i)
    if i == cm.hover then
      -- Hovered: white text on accent cyan (slot 9)
      t.blit(label, string.rep("0", #label), string.rep("9", #label))
    else
      -- Normal: dark text on light body
      t.blit(label, string.rep("0", #label), string.rep("3", #label))
    end
  end
end

-- Paint the debug overlay (translucent log panel on top of everything).
-- Triggered by F12. The overlay sits over the desktop, showing the most
-- recent log entries in colour-coded text.
local function paint_debug_overlay()
  if not debug.overlay_visible then return end
  local t = desktop.term
  local w, h = desktop.w, desktop.h
  local lines_to_show = math.min(debug.overlay_lines, h - 1)
  local entries = debug.recent(lines_to_show)
  -- Draw the panel as a band across the bottom of the screen (above taskbar).
  local panel_top = h - 1 - lines_to_show
  for i, e in ipairs(entries) do
    if i > lines_to_show then break end
    local row = panel_top + i
    -- Map level to palette index for the log text colour.
    local fg_idx
    if     e.level == 1 then fg_idx = "7"  -- gray (slot 7)
    elseif e.level == 2 then fg_idx = "8"  -- lightGray (slot 8 -> dark gray... actually slot 8 is darker gray)
    elseif e.level == 3 then fg_idx = "0"  -- white (slot 0)
    elseif e.level == 4 then fg_idx = "4"  -- warning amber (slot 4)
    elseif e.level == 5 then fg_idx = "e"  -- error red (slot 14 -> 'e')
    elseif e.level == 6 then fg_idx = "e"  -- fatal red
    else fg_idx = "0" end
    local line = string.format("%s[%s] %s: %s",
      e.tag, e.category, e.name, e.message)
    line = line:sub(1, w)
    -- Pad to full width so the bg fills.
    local padded = line .. string.rep(" ", w - #line)
    t.setCursorPos(1, row)
    t.blit(padded, string.rep(fg_idx, w), string.rep("f", w))  -- bg = black (slot 15 = 'f')
  end
  -- Header row: white text on aero blue (slot 11 = 'b').
  local stats = debug.stats()
  local header = string.format(" AeroOS DEBUG  L:%d I:%d W:%d E:%d F:%d  (F12 hide)",
    stats.debug or 0, stats.info or 0, stats.warn or 0,
    stats.error or 0, stats.fatal or 0)
  header = header:sub(1, w)
  header = header .. string.rep(" ", w - #header)
  t.setCursorPos(1, panel_top)
  t.blit(header, string.rep("0", w), string.rep("b", w))
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

function desktop.boot()
  -- Play boot animation first.
  boot_anim.play(term)

  -- Find a monitor; otherwise use the computer's term.
  local mon = peripheral.find("monitor")
  local term_obj = mon or term

  color.install(term_obj)
  term_obj.clear()

  local w, h = term_obj.getSize()
  desktop.w = w
  desktop.h = h
  desktop.work_h = h - 1
  desktop.taskbar_y = h
  desktop.term = term_obj
  manager.work_area = { x = 1, y = 1, w = w, h = h - 1 }

  -- Register apps.
  pcall(function()
    require("aeroros.apps.terminal").register(desktop)
    require("aeroros.apps.explorer").register(desktop)
    require("aeroros.apps.editor").register(desktop)
    require("aeroros.apps.viewer").register(desktop)
    require("aeroros.apps.about").register(desktop)
    require("aeroros.apps.calculator").register(desktop)
    require("aeroros.apps.paint").register(desktop)
    require("aeroros.apps.settings").register(desktop)
    require("aeroros.apps.taskmgr").register(desktop)
    require("aeroros.apps.debug").register(desktop)
  end)

  -- Wire the app dispatcher so desktop.open_app(name) launches the right app.
  require("aeroros.shell.dispatch").install()

  -- NOTE: event listeners are registered in desktop.run() below, AFTER the
  -- desktop process is spawned. If we register here (in boot()), the listeners
  -- would be attached to pid=0 (kernel context) and the desktop process's
  -- inbox would never receive events — which is exactly the bug that caused
  -- the desktop to freeze after the first paint.

  -- Restore previous session if any.
  persistence.restore(desktop)
  debug.info("shell", "Session restore complete")
end

-- One desktop frame: wallpaper -> windows (managed by CC window stacking)
-- -> taskbar -> start menu -> context menu.
function desktop.paint_frame()
  -- 1. Wallpaper (paints the whole term, including under windows).
  paint_wallpaper()

  -- 2. Windows: each window's CC window is already drawn by CC's window API
  --    in z-order. We just need to repaint chrome on the focused window
  --    (and any that have changed). For simplicity we repaint all chrome
  --    every frame — CC windows handle clipping.
  for _, w in ipairs(manager.windows) do
    if not w.minimized then
      w:paint_chrome()
    end
  end

  -- 3. Taskbar.
  paint_taskbar()

  -- 4. Start menu overlay.
  paint_start_menu()

  -- 5. Context menu overlay.
  paint_context_menu()

  -- 6. Debug overlay (drawn last so it sits on top of everything).
  paint_debug_overlay()
end

function desktop.run()
  -- Register event listeners NOW, because we're running inside the desktop
  -- process and process.current() returns our actual PID (not 0).
  local my_pid = process.current()
  debug.info("shell", "Desktop process started, pid=" .. tostring(my_pid))
  for _, ev in ipairs({"mouse_click","mouse_drag","mouse_up","key","char","terminate","paste"}) do
    event.listen(ev, my_pid)
  end

  while desktop.running do
    -- Drain events. Wrap each handler in pcall so a single bad event doesn't
    -- kill the desktop loop.
    local ok, err = pcall(function()
      local rec = process.get(my_pid)
      while rec and #rec.inbox > 0 do
        local ev = table.remove(rec.inbox, 1)
        local name = ev[1]
        desktop:_handle_event(name, ev)
      end
      -- Clean up any windows whose processes died.
      manager:cleanup_dead()
      desktop.paint_frame()
    end)
    if not ok then
      debug.error("shell", "desktop loop error: " .. tostring(err))
    end
    coroutine.yield()
  end
  -- Save session on exit.
  persistence.save(desktop)
end

function desktop:_handle_event(name, ev)
  if name == "mouse_click" then
    local button, sx, sy = ev[2], ev[3], ev[4]
    -- Right-click on desktop background -> context menu.
    if button == 2 then
      local win, hit = manager:_window_at(sx, sy)
      if not win then
        -- Right-click on desktop (or taskbar).
        if sy == desktop.h then
          -- Right-click on taskbar: small menu.
          desktop.context_menu = {
            x = sx, y = sy - 4, hover = 1,
            items = {
              { label = "Task Manager", action = "taskmgr" },
              { label = "Show Desktop", action = "minimize_all" },
            }
          }
        else
          desktop.context_menu = {
            x = sx, y = sy, hover = 1,
            items = {
              { label = "Refresh",          action = "refresh" },
              { label = "Open Terminal",   action = "terminal" },
              { label = "New File",        action = "new_file" },
              { label = "Change Wallpaper",action = "cycle_wallpaper" },
              { label = "Display Settings",action = "settings" },
            }
          }
        end
      end
      return
    end

    -- Left-click.
    -- Context menu takes priority if open.
    if desktop.context_menu then
      local cm = desktop.context_menu
      local mw = 24
      local mh = #cm.items + 2
      local mx, my = cm.x, cm.y
      if mx + mw > desktop.w then mx = desktop.w - mw end
      if my + mh > desktop.h then my = desktop.h - mh end
      if sx >= mx and sx < mx + mw and sy >= my and sy < my + mh then
        local idx = sy - my
        if idx >= 1 and idx <= #cm.items then
          desktop:_run_context_action(cm.items[idx].action)
        end
      end
      desktop.context_menu = nil
      return
    end

    -- Start menu takes priority if open.
    if desktop.start_open then
      local w, h = desktop.w, desktop.h
      local apps = {}
      for _, app in ipairs(desktop.APP_LIST) do
        if desktop.start_search == "" or app.name:lower():find(desktop.start_search:lower()) then
          table.insert(apps, app)
        end
      end
      local mw = 26
      local mh = 2 + #apps + 2
      local mx, my = 1, h - mh
      if sx >= mx and sx < mx + mw and sy >= my and sy < my + mh then
        -- Search row?
        if sy == my + 1 then
          -- Click in search box (no-op; we type via char events).
        else
          local row = sy - my - 1
          if row >= 1 and row <= #apps then
            desktop.open_app(apps[row].name)
            desktop.start_open = false
            desktop.start_search = ""
          end
        end
        return
      end
      -- Click outside start menu: close it.
      desktop.start_open = false
      desktop.start_search = ""
      return
    end

    -- Taskbar clicks.
    if sy == desktop.h then
      -- Start orb.
      if sx <= 3 then
        desktop.start_open = not desktop.start_open
        desktop.start_search = ""
        return
      end
      -- Window buttons.
      local bx = 5
      for _, win in ipairs(manager.windows) do
        local lbl = win.title:sub(1, 14)
        local slot_w = #lbl + 3
        if sx >= bx and sx < bx + slot_w then
          if win.minimized then win:unminimize(); manager:focus(win)
          elseif win.focused then win:minimize()
          else manager:focus(win) end
          return
        end
        bx = bx + slot_w
        if bx >= desktop.w - 12 then break end
      end
      return
    end

    -- Window hit-test.
    -- manager:on_mouse returns true if it consumed the event (close/max/min/
    -- drag start). For body clicks it returns false because the click should
    -- fall through to the app — but it has ALREADY focused the window via
    -- manager:focus(win) inside on_mouse. So we must NOT clear focus here.
    -- We only clear focus when the click truly landed on the desktop wallpaper.
    local win, hit = manager:_window_at(sx, sy)
    if win then
      -- Click landed on a window: focus is already set by manager:on_mouse.
      -- Forward the click to the app via the focus_pid (already done by
      -- event.dispatch since the app listens for mouse_click).
      manager:on_mouse("mouse_click", button, sx, sy)
    else
      -- Click on desktop wallpaper: clear focus.
      event.set_focus(nil)
    end
  elseif name == "mouse_drag" then
    manager:on_mouse("mouse_drag", ev[2], ev[3], ev[4])
  elseif name == "mouse_up" then
    manager:on_mouse("mouse_up", ev[2], ev[3], ev[4])
  elseif name == "key" then
    local key, held = ev[2], ev[3]
    -- F12 toggles the debug overlay regardless of focus.
    if key == keys.f12 then
      debug.toggle_overlay()
      debug.info("shell", "Debug overlay " .. (debug.overlay_visible and "ON" or "OFF"))
      return
    end
    if key == keys.rightCtrl then
      desktop.start_open = not desktop.start_open
      desktop.start_search = ""
    elseif desktop.start_open then
      if key == keys.enter then
        -- Launch first matching app.
        for _, app in ipairs(desktop.APP_LIST) do
          if desktop.start_search == "" or app.name:lower():find(desktop.start_search:lower()) then
            desktop.open_app(app.name)
            desktop.start_open = false
            desktop.start_search = ""
            return
          end
        end
      elseif key == keys.backspace then
        desktop.start_search = desktop.start_search:sub(1, -2)
      elseif key == keys.escape then
        desktop.start_open = false
        desktop.start_search = ""
      end
    else
      manager:on_key("key", key, held)
    end
  elseif name == "char" then
    if desktop.start_open then
      desktop.start_search = desktop.start_search .. ev[2]
    end
  elseif name == "paste" then
    if desktop.start_open then
      desktop.start_search = desktop.start_search .. ev[2]
    end
  elseif name == "terminate" then
    desktop.running = false
  end
end

function desktop:_run_context_action(action)
  if action == "refresh" then
    -- No-op repaint.
  elseif action == "terminal" then
    desktop.open_app("Terminal")
  elseif action == "new_file" then
    local n = 1
    while fs.exists("/new" .. n .. ".txt") do n = n + 1 end
    local f = fs.open("/new" .. n .. ".txt", "w"); f.write(""); f.close()
    desktop.open_app("File Explorer")
  elseif action == "cycle_wallpaper" then
    desktop.current_wallpaper = wallpaper_mod.next(desktop.current_wallpaper)
  elseif action == "settings" then
    desktop.open_app("Settings")
  elseif action == "taskmgr" then
    desktop.open_app("Task Manager")
  elseif action == "minimize_all" then
    for _, w in ipairs(manager.windows) do w:minimize() end
  end
  desktop.context_menu = nil
end

function desktop.shutdown()
  desktop.running = false
  scheduler.shutdown()
end

return desktop
