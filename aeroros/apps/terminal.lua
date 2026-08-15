--[[
  AeroOS · Terminal app

  A simple shell running inside an AeroOS window. Supports:
    - cd / ls / pwd / cat / edit / clear / help / echo / exit / ver
    - runs CC shell builtin if no match
    - command history with up/down arrows
    - CWD persists per terminal session
]]

local theme     = require("aeroros.wm.theme")  -- kept for future chrome overrides
local color     = require("aeroros.graphics.color")
local syscall   = require("aeroros.kernel.syscall")

local terminal = {}

local function register(desktop)
  desktop.register_app("Terminal", function()
    desktop.open_app("Terminal")
  end)
end

-- The actual app function. Takes a Window.
local function run(win)
  local cwd = shell.dir and shell.dir() or "/"
  local history = {}
  local hist_idx = 1
  local input_buf = ""

  -- For terminal output we use a CC `window` redirected onto the content rect.
  -- This is the cleanest way to get text into a region without reimplementing
  -- terminal semantics. (v1 tried to paint pixels into win.image — that's gone.)
  local content = win:content_rect()
  local term_win = win:get_content_term()
  local old_term = term.redirect(term_win)

  -- Repaint helpers using the redirected term.
  -- We wrap every color value with color.cc() so that even if an RGB int
  -- is passed by mistake, it gets clamped to the nearest CC color instead
  -- of throwing "color out of range".
  local function t_clear()
    term_win.setBackgroundColor(colors.lightBlue)
    term_win.setTextColor(colors.white)
    term_win.clear()
    term_win.setCursorPos(1, 1)
  end
  t_clear()

  local function t_write(s, fg, bg)
    term_win.setTextColor(color.cc(fg) or colors.white)
    term_win.setBackgroundColor(color.cc(bg) or colors.lightBlue)
    term_win.write(s)
  end

  local function t_newline()
    local cx, cy = term_win.getCursorPos()
    local w, h = term_win.getSize()
    if cy >= h then
      -- scroll
      term_win.scroll(1)
      term_win.setCursorPos(1, h)
    else
      term_win.setCursorPos(1, cy + 1)
    end
  end

  local function t_redraw_prompt()
    local cx, cy = term_win.getCursorPos()
    term_win.setCursorPos(1, cy)
    t_write(cwd .. "> ", colors.cyan, colors.lightBlue)
    t_write(input_buf, colors.white, colors.lightBlue)
  end

  -- Initial banner.
  t_write("AeroOS Terminal [Version 1.0]", colors.white, colors.lightBlue)
  t_newline()
  t_write("(c) AeroOS Project. All rights reserved.", colors.lightGray, colors.lightBlue)
  t_newline()
  t_newline()
  t_redraw_prompt()

  -- Command dispatch.
  local function run_command(cmdline)
    local args = {}
    for w in string.gmatch(cmdline, "%S+") do
      table.insert(args, w)
    end
    if #args == 0 then return end
    local cmd = args[1]
    if cmd == "exit" then
      old_term = term.redirect(old_term)
      require("aeroros.wm.manager"):close(win)
      return
    elseif cmd == "help" then
      t_write("Available: cd ls pwd cat edit clear echo ver exit help", colors.white, colors.lightBlue)
      t_newline()
    elseif cmd == "ver" then
      t_write("AeroOS 1.0  (Lua " .. _VERSION .. ")", colors.white, colors.lightBlue)
      t_newline()
    elseif cmd == "echo" then
      t_write(table.concat(args, " ", 2), colors.white, colors.lightBlue)
      t_newline()
    elseif cmd == "clear" then
      t_clear()
    elseif cmd == "pwd" then
      t_write(cwd, colors.white, colors.lightBlue)
      t_newline()
    elseif cmd == "ls" or cmd == "dir" then
      local path = args[2] or cwd
      local files = fs.list(path)
      for _, f in ipairs(files) do
        t_write(f .. "  ", colors.white, colors.lightBlue)
      end
      t_newline()
    elseif cmd == "cd" then
      local target = args[2]
      if not target then
        t_write(cwd, colors.white, colors.lightBlue)
        t_newline()
      elseif fs.isDir(target) then
        cwd = target
      elseif fs.isDir(fs.combine(cwd, target)) then
        cwd = fs.combine(cwd, target)
      else
        t_write("cd: no such directory: " .. target, colors.red, colors.lightBlue)
        t_newline()
      end
    elseif cmd == "cat" then
      local path = args[2]
      if not path or not fs.exists(path) then
        t_write("cat: no such file", colors.red, colors.lightBlue)
        t_newline()
      else
        local f = fs.open(path, "r")
        local line = f.readLine()
        while line do
          t_write(line, colors.white, colors.lightBlue)
          t_newline()
          line = f.readLine()
        end
        f.close()
      end
    else
      t_write("Unknown command: " .. cmd .. " (try 'help')", colors.red, colors.lightBlue)
      t_newline()
    end
  end

  -- Event loop for this app process.
  local process = require("aeroros.kernel.process")
  local event_mod = require("aeroros.kernel.event")
  event_mod.listen("char",   process.current())
  event_mod.listen("key",    process.current())

  while true do
    local rec = process.get(process.current())
    if rec and #rec.inbox > 0 then
      local ev = table.remove(rec.inbox, 1)
      local name = ev[1]
      if name == "char" then
        local ch = ev[2]
        input_buf = input_buf .. ch
        t_write(ch, colors.white, colors.lightBlue)
      elseif name == "key" then
        local key = ev[2]
        if key == keys.enter then
          t_newline()
          run_command(input_buf)
          if input_buf ~= "" then
            table.insert(history, input_buf)
          end
          input_buf = ""
          hist_idx = #history + 1
          t_redraw_prompt()
        elseif key == keys.backspace then
          if #input_buf > 0 then
            input_buf = input_buf:sub(1, -2)
            local cx, cy = term_win.getCursorPos()
            term_win.setCursorPos(cx - 1, cy)
            t_write(" ", colors.white, colors.lightBlue)
            term_win.setCursorPos(cx - 1, cy)
          end
        elseif key == keys.up then
          if hist_idx > 1 then
            hist_idx = hist_idx - 1
            input_buf = history[hist_idx] or ""
            -- Clear current line and rewrite.
            local cx, cy = term_win.getCursorPos()
            term_win.setCursorPos(cwd:len() + 3, cy)
            t_write(string.rep(" ", content.w), colors.white, colors.lightBlue)
            term_win.setCursorPos(cwd:len() + 3, cy)
            t_write(input_buf, colors.white, colors.lightBlue)
          end
        elseif key == keys.down then
          if hist_idx < #history then
            hist_idx = hist_idx + 1
            input_buf = history[hist_idx] or ""
            local cx, cy = term_win.getCursorPos()
            term_win.setCursorPos(cwd:len() + 3, cy)
            t_write(string.rep(" ", content.w), colors.white, colors.lightBlue)
            term_win.setCursorPos(cwd:len() + 3, cy)
            t_write(input_buf, colors.white, colors.lightBlue)
          end
        end
      elseif name == "terminate" then
        break
      end
    end
    -- Yield back to the scheduler.
    coroutine.yield()
    -- Re-render our window chrome via the desktop's paint loop.
    -- (The desktop calls win:paint() in its frame loop; we just need to
    -- keep our content image fresh, which we do by redirecting term output.)
  end

  -- Cleanup.
  term.redirect(old_term)
end

terminal.register = register
terminal.run = run
return terminal
