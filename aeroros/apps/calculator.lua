--[[
  AeroOS · Calculator app

  Simple four-function calculator. Keypad layout:
    7 8 9 +
    4 5 6 -
    1 2 3 *
    0 . = /

  Click to type, or use the keyboard. C = clear, Backspace = delete last.
]]

local theme = require("aeroros.wm.theme")

local calculator = {}

local function register(desktop)
  desktop.register_app("Calculator", function()
    desktop.open_app("Calculator")
  end)
end

local function run(win)
  local content = win:content_rect()
  local term_win = win:get_content_term()
  local old_term = term.redirect(term_win)

  local display = "0"
  local prev = nil
  local op = nil
  local just_equalled = false

  local KEYS = {
    { "7", "8", "9", "/" },
    { "4", "5", "6", "*" },
    { "1", "2", "3", "-" },
    { "0", ".", "=", "+" },
  }

  local function compute(a, b, op)
    a, b = tonumber(a), tonumber(b)
    if not a or not b then return "Err" end
    if op == "+" then return tostring(a + b)
    elseif op == "-" then return tostring(a - b)
    elseif op == "*" then return tostring(a * b)
    elseif op == "/" then
      if b == 0 then return "Err" end
      return tostring(a / b)
    end
    return "Err"
  end

  local function press(k)
    if k == "C" then
      display, prev, op = "0", nil, nil
    elseif k == "Back" then
      display = display:sub(1, -2)
      if display == "" then display = "0" end
    elseif k == "=" then
      if op and prev then
        display = compute(prev, display, op)
        prev, op = nil, nil
        just_equalled = true
      end
    elseif k == "+" or k == "-" or k == "*" or k == "/" then
      if op and prev and not just_equalled then
        -- Chain: compute first, then take new op.
        display = compute(prev, display, op)
      end
      prev = display
      op = k
      just_equalled = true
    elseif k == "." then
      if just_equalled then display = "0"; just_equalled = false end
      if not display:find("%.") then display = display .. "." end
    else  -- digit
      if just_equalled or display == "0" then
        display = k
        just_equalled = false
      else
        display = display .. k
      end
    end
  end

  local function paint()
    local w, h = term_win.getSize()
    term_win.setBackgroundColor(colors.lightBlue)
    term_win.clear()

    -- Display.
    term_win.setCursorPos(1, 1)
    term_win.setTextColor(colors.black)
    term_win.setBackgroundColor(colors.white)
    term_win.write(string.rep(" ", w))
    term_win.setCursorPos(w - #display - 1, 1)
    term_win.write(display)

    -- Keypad.
    local key_w = math.floor(w / 4)
    local key_h = math.floor((h - 2) / 4)
    for r, row in ipairs(KEYS) do
      for c, k in ipairs(row) do
        local x = (c - 1) * key_w + 1
        local y = 2 + (r - 1) * key_h
        local bg = (k == "=") and colors.blue or colors.lightGray
        local fg = (k == "=") and colors.white or colors.black
        term_win.setBackgroundColor(bg)
        term_win.setTextColor(fg)
        for yy = 0, key_h - 1 do
          term_win.setCursorPos(x, y + yy)
          if yy == math.floor(key_h / 2) then
            term_win.write(string.rep(" ", math.floor((key_w - 1) / 2)) .. k ..
                           string.rep(" ", key_w - #k - math.floor((key_w - 1) / 2)))
          else
            term_win.write(string.rep(" ", key_w))
          end
        end
      end
    end
    -- Clear button at top-right of keypad.
    term_win.setBackgroundColor(colors.red)
    term_win.setTextColor(colors.white)
    term_win.setCursorPos(w, 1)
    term_win.write("C")
  end

  -- Determine which key was clicked.
  local function key_at(sx, sy)
    local w, h = term_win.getSize()
    local key_w = math.floor(w / 4)
    local key_h = math.floor((h - 2) / 4)
    if sy == 1 then
      if sx == w then return "C" end
      return nil
    end
    if sy >= 2 then
      local r = math.floor((sy - 1) / key_h) + 1
      local c = math.floor((sx - 1) / key_w) + 1
      if r >= 1 and r <= 4 and c >= 1 and c <= 4 then
        return KEYS[r][c]
      end
    end
  end

  paint()

  local process = require("aeroros.kernel.process")
  local event_mod = require("aeroros.kernel.event")
  event_mod.listen("char", process.current())
  event_mod.listen("key",  process.current())
  event_mod.listen("mouse_click", process.current())

  while true do
    local rec = process.get(process.current())
    if rec and #rec.inbox > 0 then
      local ev = table.remove(rec.inbox, 1)
      local name = ev[1]
      if name == "mouse_click" then
        local _, _, lx, ly = unpack(ev)
        -- ev from CC has screen coords; we need window-local coords.
        -- The CC mouse_click event passes (button, sx, sy) in screen space.
        -- Convert to window-local:
        local sx, sy = ev[3], ev[4]
        local lx = sx - content.x + 1
        local ly = sy - content.y + 1
        local k = key_at(lx, ly)
        if k then press(k); paint() end
      elseif name == "char" then
        local ch = ev[2]
        if ch:match("[0-9%.]") then press(ch); paint()
        elseif ch == "+" or ch == "-" or ch == "*" or ch == "/" then press(ch); paint()
        elseif ch == "=" or ch == "\n" or ch == "\r" then press("="); paint()
        elseif ch == "c" or ch == "C" then press("C"); paint()
        end
      elseif name == "key" then
        local key = ev[2]
        if key == keys.enter then press("="); paint()
        elseif key == keys.backspace then press("Back"); paint()
        elseif key == keys.escape then break
        end
      end
    end
    coroutine.yield()
  end

  term.redirect(old_term)
end

calculator.register = register
calculator.run = run
return calculator
