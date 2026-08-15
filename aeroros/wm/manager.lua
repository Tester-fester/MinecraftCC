--[[
  AeroOS · Window Manager (v2)

  Uses CC's native `window` API as the windowing primitive. This means:
    - Chrome is drawn by the WM via term.blit into each window's CC window.
    - Apps redirect term into their window's content_window. Text shows up
      correctly because CC windows handle the actual drawing.
    - Z-order is achieved by calling window.setVisible / redraw in stack
      order. Later windows paint over earlier ones. CC's window API handles
      the compositing for us — there's no manual pixel compositing needed
      for the text layer.
    - The ComBox-style ImageHandler/Renderer is kept ONLY for the Image
      Viewer and Paint apps, where we actually need pixel-level compositing.

  New in v2:
    - Window resize via edge/corner drag (border_l, border_r, border_b,
      border_bl, border_br).
    - Proper focus stack: when a window is focused, all others are
      re-stacked beneath it.
    - Right-click on desktop handled by desktop shell, not WM.
]]

local Window     = require("aeroros.wm.window")
local theme      = require("aeroros.wm.theme")
local event      = require("aeroros.kernel.event")
local process    = require("aeroros.kernel.process")
local scheduler  = require("aeroros.kernel.scheduler")
local debug      = require("aeroros.kernel.debug")

local manager = {}

manager.windows = {}    -- list, front-of-stack (focused) LAST
manager.drag = nil       -- active drag state
manager.work_area = { x = 1, y = 1, w = 50, h = 18 }  -- set by desktop

-- Spawn a window + its app process.
function manager.spawn(title, app_fn, opts)
  opts = opts or {}
  opts.title = title
  opts.app = app_fn
  local win = Window.new(opts)
  table.insert(manager.windows, win)
  manager:focus(win)
  local pid = scheduler.spawn(title, function() app_fn(win) end)
  win.pid = pid
  win:show()
  win:paint_chrome()
  debug.info("wm", string.format("spawned win#%d pid=%d title=%s at (%d,%d) %dx%d",
    win.id, pid, title, win.x, win.y, win.w, win.h))
  return win, pid
end

function manager:focus(win)
  for _, w in ipairs(manager.windows) do
    w.focused = (w == win)
  end
  -- Move to top of stack.
  for i, w in ipairs(manager.windows) do
    if w == win then
      table.remove(manager.windows, i)
      table.insert(manager.windows, w)
      break
    end
  end
  win:unminimize()
  if win.pid then event.set_focus(win.pid) end
  -- Restack: paint back-to-front so the focused ends up on top.
  manager:repaint_all()
end

function manager:focused()
  return manager.windows[#manager.windows]
end

function manager:close(win)
  debug.info("wm", string.format("closing win#%d pid=%d title=%s",
    win.id, win.pid or -1, win.title))
  win:close()
  for i, w in ipairs(manager.windows) do
    if w == win then
      table.remove(manager.windows, i)
      break
    end
  end
  if win.pid then process.kill(win.pid) end
  -- Force a full repaint of remaining windows (they may have been occluded).
  term.clear()
  if #manager.windows > 0 then
    manager:focus(manager.windows[#manager.windows])
  else
    event.set_focus(nil)
  end
end

function manager:repaint_all()
  for _, w in ipairs(manager.windows) do
    if not w.minimized then
      w:paint_chrome()
    end
  end
end

-- Hit-test top-down so the frontmost window gets the click first.
function manager:_window_at(sx, sy)
  for i = #manager.windows, 1, -1 do
    local w = manager.windows[i]
    if not w.minimized then
      local hit = w:hit_test(sx, sy)
      if hit then return w, hit end
    end
  end
  return nil, nil
end

-- Mouse event router.
function manager:on_mouse(name, button, sx, sy)
  -- Handle ongoing drag/resize first.
  if manager.drag and (name == "mouse_drag" or name == "mouse_up") then
    local d = manager.drag
    local win = d.win
    if name == "mouse_drag" then
      if d.mode == "move" then
        win:set_pos(sx - d.off_x, sy - d.off_y)
      elseif d.mode == "resize_r" then
        local new_w = math.max(win.min_w, sx - win.x + 1)
        win:set_size(new_w, win.h)
      elseif d.mode == "resize_b" then
        local new_h = math.max(win.min_h, sy - win.y + 1)
        win:set_size(win.w, new_h)
      elseif d.mode == "resize_br" then
        local new_w = math.max(win.min_w, sx - win.x + 1)
        local new_h = math.max(win.min_h, sy - win.y + 1)
        win:set_size(new_w, new_h)
      elseif d.mode == "resize_l" then
        local new_x = sx
        local new_w = win.x + win.w - sx
        if new_w >= win.min_w then
          win:set_rect(new_x, win.y, new_w, win.h)
        end
      end
      win:paint_chrome()
    elseif name == "mouse_up" then
      manager.drag = nil
    end
    return true
  end

  local win, hit = manager:_window_at(sx, sy)
  if not win then return false end

  if name ~= "mouse_click" then
    return false
  end

  manager:focus(win)

  if hit == "close" then
    manager:close(win); return true
  elseif hit == "max" then
    if win.maximized then
      win:restore()
    else
      local wa = manager.work_area
      win:maximize(wa.x, wa.y, wa.w, wa.h)
    end
    win:paint_chrome()
    return true
  elseif hit == "min" then
    win:minimize(); return true
  elseif hit == "title" then
    manager.drag = { win = win, mode = "move", off_x = sx - win.x, off_y = sy - win.y }
    return true
  elseif hit == "border_r" and win.resizable then
    manager.drag = { win = win, mode = "resize_r" }; return true
  elseif hit == "border_b" and win.resizable then
    manager.drag = { win = win, mode = "resize_b" }; return true
  elseif hit == "border_br" and win.resizable then
    manager.drag = { win = win, mode = "resize_br" }; return true
  elseif hit == "border_l" and win.resizable then
    manager.drag = { win = win, mode = "resize_l" }; return true
  elseif hit == "border_bl" and win.resizable then
    manager.drag = { win = win, mode = "resize_l" }; return true
  end
  return false
end

-- Keyboard router.
function manager:on_key(name, key, held)
  local win = manager:focused()
  if not win then return false end

  if name == "key" and key == keys.f4 and held == keys.leftAlt then
    manager:close(win); return true
  end
  if name == "key" and key == keys.rightCtrl then
    return false  -- desktop handles Start menu toggle
  end
  return false
end

-- Returns the list of running windows for the taskbar / task manager.
function manager:list_windows()
  return manager.windows
end

-- Remove windows whose process has died (crashed or exited). Called by the
-- desktop shell on every frame, or whenever a process_died event arrives.
function manager:cleanup_dead()
  local removed = false
  for i = #manager.windows, 1, -1 do
    local w = manager.windows[i]
    if w.pid then
      local rec = process.get(w.pid)
      if not rec or rec.state == 'dead' then
        debug.warn("wm", string.format(
          "cleanup: removing orphaned win#%d pid=%d title=%s",
          w.id, w.pid, w.title))
        table.remove(manager.windows, i)
        w:hide()
        removed = true
      end
    end
  end
  if removed and #manager.windows > 0 then
    -- Re-focus the topmost surviving window.
    manager:focus(manager.windows[#manager.windows])
  elseif removed then
    event.set_focus(nil)
  end
  return removed
end

return manager
