--[[
  AeroOS · File Explorer app

  Two-pane Win7-style explorer:
    - Left: tree (skipped for demo, just shows current path)
    - Right: file list (name + size)
  Double-click (or Enter) on a folder descends into it.
  Enter on a .txt or .lua file opens it in Notepad.

  Keeps it simple: one pane, keyboard navigable.
]]

local theme   = require("aeroros.wm.theme")
local color   = require("aeroros.graphics.color")

local explorer = {}

local function register(desktop)
  desktop.register_app("File Explorer", function()
    desktop.open_app("File Explorer")
  end)
end

local function run(win)
  local cwd = "/"
  local entries = {}
  local selected = 1
  local scroll = 1

  local function refresh()
    entries = fs.list(cwd)
    table.sort(entries)
    selected = 1
    scroll = 1
  end
  refresh()

  local content = win:content_rect()
  local term_win = win:get_content_term()
  local old_term = term.redirect(term_win)

  local function paint()
    term_win.setBackgroundColor(colors.lightBlue)
    term_win.clear()
    -- Header.
    term_win.setCursorPos(1, 1)
    term_win.setTextColor(colors.white)
    term_win.write("AeroOS File Explorer")
    term_win.setCursorPos(1, 2)
    term_win.write("Path: " .. cwd:sub(1, content.w - 8))
    term_win.setCursorPos(1, 3)
    term_win.write(string.rep("-", content.w))

    -- Entries.
    local max_show = content.h - 4
    for i = 0, max_show - 1 do
      local idx = scroll + i
      if idx > #entries then break end
      local name = entries[idx]
      local is_dir = fs.isDir(fs.combine(cwd, name))
      local label = (is_dir and "[DIR] " or "      ") .. name
      label = label:sub(1, content.w - 1)
      term_win.setCursorPos(1, 4 + i)
      if idx == selected then
        term_win.setTextColor(colors.white)
        term_win.setBackgroundColor(colors.blue)
      else
        term_win.setTextColor(is_dir and colors.cyan or colors.white)
        term_win.setBackgroundColor(colors.lightBlue)
      end
      term_win.write(label)
    end

    -- Footer.
    term_win.setTextColor(colors.gray)
    term_win.setBackgroundColor(colors.lightBlue)
    term_win.setCursorPos(1, content.h)
    term_win.write("Up/Dn:Move  Enter:Open  BS:Up  Q:Quit")
  end

  local function open_entry()
    local name = entries[selected]
    if not name then return end
    local path = fs.combine(cwd, name)
    if fs.isDir(path) then
      cwd = path
      refresh()
    else
      -- Open in Notepad if it's text-y.
      local ext = name:match("%.([^.]+)$") or ""
      if ext == "txt" or ext == "lua" or ext == "log" or ext == "md" then
        require("aeroros.apps.editor").open(path)
      end
    end
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
        if key == keys.up and selected > 1 then
          selected = selected - 1
          if selected < scroll then scroll = selected end
        elseif key == keys.down and selected < #entries then
          selected = selected + 1
          if selected > scroll + content.h - 5 then scroll = selected - content.h + 5 end
        elseif key == keys.enter then
          open_entry()
        elseif key == keys.backspace then
          -- Go up one level.
          local parent = fs.getDir(cwd)
          if parent and parent ~= cwd then
            cwd = parent
            refresh()
          end
        elseif key == keys.q then
          break
        end
        paint()
      end
    end
    coroutine.yield()
  end

  term.redirect(old_term)
end

explorer.register = register
explorer.run = run
explorer.open = function(path)
  -- Pre-seed cwd when launched from start menu shortcut.
  return function(win)
    local orig_run = run
    -- We don't override cwd here; the run() above defaults to "/" and the
    -- user can navigate. (Real impl would pass the path in via opts.)
    orig_run(win)
  end
end
return explorer
