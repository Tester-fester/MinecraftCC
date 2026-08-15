--[[
  AeroOS · Notepad (text editor)

  Minimal single-file editor. Keyboard shortcuts:
    Ctrl+S : save
    Ctrl+Q : quit
    Arrow keys / Home / End / Backspace / Enter : normal editing
]]

local theme = require("aeroros.wm.theme")

local editor = {}

local function register(desktop)
  desktop.register_app("Notepad", function()
    desktop.open_app("Notepad")
  end)
end

-- Open a path in a new Notepad window.
local function open(path)
  local desktop = require("aeroros.shell.desktop")
  local manager = require("aeroros.wm.manager")
  manager.spawn("Notepad - " .. (path or "untitled"), function(win)
    editor.run(win, path)
  end, { w = 40, h = 16, x = 6, y = 3 })
end

local function run(win, path)
  local lines = {}
  local dirty = false
  if path and fs.exists(path) then
    local f = fs.open(path, "r")
    local line = f.readLine()
    while line do
      table.insert(lines, line)
      line = f.readLine()
    end
    f.close()
  end
  if #lines == 0 then lines = { "" } end

  local cursor_row = 1
  local cursor_col = 1
  local scroll_row = 1

  local content = win:content_rect()
  local term_win = win:get_content_term()
  local old_term = term.redirect(term_win)

  local function paint()
    term_win.setBackgroundColor(colors.white)
    term_win.setTextColor(colors.black)
    term_win.clear()

    -- Top status bar.
    term_win.setCursorPos(1, 1)
    term_win.setTextColor(colors.white)
    term_win.setBackgroundColor(colors.blue)
    local title = " Notepad "
    if path then title = title .. "- " .. path:sub(1, content.w - 12) .. " " end
    if dirty then title = title .. "*" end
    term_win.write(title .. string.rep(" ", content.w - #title))

    -- Text area.
    term_win.setBackgroundColor(colors.white)
    term_win.setTextColor(colors.black)
    for i = 0, content.h - 3 do
      local row = scroll_row + i
      if row > #lines then break end
      term_win.setCursorPos(1, 2 + i)
      local txt = lines[row]:sub(1, content.w)
      term_win.write(txt)
    end

    -- Cursor.
    term_win.setCursorPos(cursor_col, 2 + (cursor_row - scroll_row))
    term_win.setCursorBlink(true)

    -- Bottom status bar.
    term_win.setCursorPos(1, content.h)
    term_win.setTextColor(colors.white)
    term_win.setBackgroundColor(colors.gray)
    term_win.write(("Ln %d, Col %d  Ctrl+S Save  Ctrl+Q Quit"):format(cursor_row, cursor_col):sub(1, content.w))
  end

  local function save()
    if not path then return end
    local f = fs.open(path, "w")
    for _, l in ipairs(lines) do f.writeLine(l) end
    f.close()
    dirty = false
  end

  local function clamp_cursor()
    if cursor_row < 1 then cursor_row = 1 end
    if cursor_row > #lines then cursor_row = #lines end
    if cursor_col < 1 then cursor_col = 1 end
    if cursor_col > #lines[cursor_row] + 1 then cursor_col = #lines[cursor_row] + 1 end
    if cursor_row < scroll_row then scroll_row = cursor_row end
    if cursor_row >= scroll_row + content.h - 2 then scroll_row = cursor_row - content.h + 3 end
  end

  paint()

  local process = require("aeroros.kernel.process")
  local event_mod = require("aeroros.kernel.event")
  event_mod.listen("char", process.current())
  event_mod.listen("key",  process.current())

  while true do
    local rec = process.get(process.current())
    if rec and #rec.inbox > 0 then
      local ev = table.remove(rec.inbox, 1)
      local name = ev[1]
      if name == "char" then
        local ch = ev[2]
        local line = lines[cursor_row]
        lines[cursor_row] = line:sub(1, cursor_col - 1) .. ch .. line:sub(cursor_col)
        cursor_col = cursor_col + 1
        dirty = true
      elseif name == "key" then
        local key = ev[2]
        local held = ev[3]
        if key == keys.left then
          cursor_col = cursor_col - 1
        elseif key == keys.right then
          cursor_col = cursor_col + 1
        elseif key == keys.up then
          cursor_row = cursor_row - 1
          cursor_col = 1
        elseif key == keys.down then
          cursor_row = cursor_row + 1
          cursor_col = 1
        elseif key == keys.home then
          cursor_col = 1
        elseif key == keys["end"] then
          cursor_col = #lines[cursor_row] + 1
        elseif key == keys.backspace then
          if cursor_col > 1 then
            local line = lines[cursor_row]
            lines[cursor_row] = line:sub(1, cursor_col - 2) .. line:sub(cursor_col)
            cursor_col = cursor_col - 1
            dirty = true
          elseif cursor_row > 1 then
            local prev = lines[cursor_row - 1]
            cursor_col = #prev + 1
            lines[cursor_row - 1] = prev .. lines[cursor_row]
            table.remove(lines, cursor_row)
            cursor_row = cursor_row - 1
            dirty = true
          end
        elseif key == keys.enter then
          local line = lines[cursor_row]
          local before = line:sub(1, cursor_col - 1)
          local after = line:sub(cursor_col)
          lines[cursor_row] = before
          table.insert(lines, cursor_row + 1, after)
          cursor_row = cursor_row + 1
          cursor_col = 1
          dirty = true
        elseif key == keys.s and (held == keys.leftCtrl or held == keys.rightCtrl) then
          save()
        elseif key == keys.q and (held == keys.leftCtrl or held == keys.rightCtrl) then
          break
        end
        clamp_cursor()
      elseif name == "terminate" then
        break
      end
      paint()
    end
    coroutine.yield()
  end

  term.redirect(old_term)
end

editor.register = register
editor.run = run
editor.open = open
return editor
