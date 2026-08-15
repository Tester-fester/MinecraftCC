--[[
  AeroOS · Settings app

  Tabs:
    - Personalize: switch wallpaper
    - About: show version info
  Arrow keys to navigate; Enter to apply.
]]

local theme = require("aeroros.wm.theme")
local wallpaper_mod = require("aeroros.shell.wallpaper")

local settings = {}

local function register(desktop)
  desktop.register_app("Settings", function()
    desktop.open_app("Settings")
  end)
end

local function run(win)
  local content = win:content_rect()
  local term_win = win:get_content_term()
  local old_term = term.redirect(term_win)

  local tab = 1  -- 1=Personalize, 2=About
  local sel = 1  -- selected row

  local function paint()
    local w, h = term_win.getSize()
    term_win.setBackgroundColor(colors.lightBlue)
    term_win.clear()

    -- Tab bar.
    term_win.setCursorPos(1, 1)
    term_win.setBackgroundColor(tab == 1 and colors.blue or colors.lightGray)
    term_win.setTextColor(tab == 1 and colors.white or colors.black)
    term_win.write(" Personalize ")
    term_win.setBackgroundColor(tab == 2 and colors.blue or colors.lightGray)
    term_win.setTextColor(tab == 2 and colors.white or colors.black)
    term_win.write(" About ")
    term_win.setBackgroundColor(colors.lightBlue)
    term_win.write(string.rep(" ", w - 21))

    if tab == 1 then
      -- List wallpapers.
      local wallpapers = wallpaper_mod.list()
      local desktop_mod = require("aeroros.shell.desktop")
      for i, name in ipairs(wallpapers) do
        local y = 3 + i
        if y > h - 2 then break end
        local wp = wallpaper_mod.get(name)
        local label = "  " .. wp.name
        if name == desktop_mod.current_wallpaper then
          label = "[x]" .. label:sub(3)
        else
          label = "[ ]" .. label:sub(3)
        end
        if i == sel then
          term_win.setBackgroundColor(colors.blue)
          term_win.setTextColor(colors.white)
        else
          term_win.setBackgroundColor(colors.lightBlue)
          term_win.setTextColor(colors.black)
        end
        term_win.setCursorPos(2, y)
        term_win.write(label .. string.rep(" ", w - #label - 2))
      end
      -- Footer.
      term_win.setCursorPos(1, h)
      term_win.setBackgroundColor(colors.gray)
      term_win.setTextColor(colors.white)
      term_win.write("Up/Dn:Select  Enter:Apply  Tab:Switch  Q:Quit")
    else
      -- About tab.
      term_win.setTextColor(colors.black)
      term_win.setBackgroundColor(colors.lightBlue)
      local lines = {
        "AeroOS 1.0",
        "",
        "Kernel:    Phoenix-inspired",
        "Graphics:  ComBox-inspired",
        "Host:      " .. (os.getComputerLabel() or "Computer #" .. os.getComputerID()),
        "Lua:       " .. _VERSION,
        "CC:        CraftOS",
        "",
        "Built with AeroOS shell,",
        "themed after Windows 7 Aero.",
      }
      for i, l in ipairs(lines) do
        term_win.setCursorPos(2, 3 + i)
        term_win.write(l)
      end
    end
  end

  paint()

  local process = require("aeroros.kernel.process")
  local event_mod = require("aeroros.kernel.event")
  event_mod.listen("key", process.current())

  local desktop_mod = require("aeroros.shell.desktop")
  local wallpapers = wallpaper_mod.list()

  while true do
    local rec = process.get(process.current())
    if rec and #rec.inbox > 0 then
      local ev = table.remove(rec.inbox, 1)
      local name = ev[1]
      if name == "key" then
        local key = ev[2]
        if key == keys.q then break
        elseif key == keys.tab then
          tab = tab == 1 and 2 or 1
        elseif tab == 1 then
          if key == keys.up and sel > 1 then sel = sel - 1
          elseif key == keys.down and sel < #wallpapers then sel = sel + 1
          elseif key == keys.enter then
            desktop_mod.current_wallpaper = wallpapers[sel]
          end
        end
        paint()
      end
    end
    coroutine.yield()
  end

  term.redirect(old_term)
end

settings.register = register
settings.run = run
return settings
