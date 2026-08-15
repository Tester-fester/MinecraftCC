--[[
  AeroOS · Session persistence

  Saves the list of open windows (title + bounds) to /aeroos/etc/session.cfg
  on shutdown and restores them on next boot. Apps are re-launched fresh
  (their internal state isn't snapshotted) but the window layout survives.

  File format: one window per line, tab-separated:
    Terminal\t4\t2\t40\t16
    Notepad\t6\t3\t40\t16
]]

local persistence = {}

local function session_file()
  if not fs.exists("/aeroos/etc") then fs.makeDir("/aeroos/etc") end
  return "/aeroos/etc/session.cfg"
end

function persistence.save(desktop)
  local manager = require("aeroros.wm.manager")
  local f = fs.open(session_file(), "w")
  if not f then return end
  for _, win in ipairs(manager.windows) do
    f.writeLine(win.title .. "\t" .. win.x .. "\t" .. win.y .. "\t" .. win.w .. "\t" .. win.h)
  end
  -- Save wallpaper choice too.
  f.writeLine("#wallpaper\t" .. (desktop.current_wallpaper or "aero_blue"))
  f.close()
end

function persistence.restore(desktop)
  local path = session_file()
  if not fs.exists(path) then return end
  local f = fs.open(path, "r")
  if not f then return end
  local line = f.readLine()
  while line do
    if not line:find("^#") then
      local parts = {}
      for p in line:gmatch("[^\t]+") do table.insert(parts, p) end
      if #parts >= 5 then
        local title, x, y, w, h = parts[1], tonumber(parts[2]), tonumber(parts[3]),
                                  tonumber(parts[4]), tonumber(parts[5])
        -- Only restore known apps.
        for _, app in ipairs(desktop.APP_LIST) do
          if app.name == title then
            desktop.open_app(title)
            break
          end
        end
      end
    else
      -- Parse wallpaper line.
      local wp = line:match("^#wallpaper\t(.+)$")
      if wp then desktop.current_wallpaper = wp end
    end
    line = f.readLine()
  end
  f.close()
end

return persistence
