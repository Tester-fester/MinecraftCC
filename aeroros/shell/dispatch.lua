--[[
  AeroOS · App dispatcher (v2)

  Maps Start-menu app names to window launches. Default geometry per app.
  Called by desktop.open_app().
]]

local manager = require("aeroros.wm.manager")
local desktop_mod = require("aeroros.shell.desktop")

local M = {}

local DEFAULTS = {
  ["Terminal"]       = { w = 40, h = 16, x = 4,  y = 2 },
  ["File Explorer"] = { w = 36, h = 14, x = 8,  y = 3 },
  ["Notepad"]        = { w = 40, h = 16, x = 6,  y = 3 },
  ["Image Viewer"]   = { w = 32, h = 14, x = 10, y = 3 },
  ["Calculator"]     = { w = 22, h = 12, x = 12, y = 3 },
  ["Paint"]          = { w = 36, h = 16, x = 8,  y = 2 },
  ["Settings"]       = { w = 40, h = 16, x = 6,  y = 3 },
  ["Task Manager"]   = { w = 44, h = 16, x = 4,  y = 2 },
  ["Debug"]          = { w = 60, h = 20, x = 2,  y = 1 },
  ["About AeroOS"]   = { w = 44, h = 14, x = 6,  y = 4 },
}

local APP_MODULES = {
  ["Terminal"]       = "aeroros.apps.terminal",
  ["File Explorer"] = "aeroros.apps.explorer",
  ["Notepad"]        = "aeroros.apps.editor",
  ["Image Viewer"]   = "aeroros.apps.viewer",
  ["Calculator"]     = "aeroros.apps.calculator",
  ["Paint"]          = "aeroros.apps.paint",
  ["Settings"]       = "aeroros.apps.settings",
  ["Task Manager"]   = "aeroros.apps.taskmgr",
  ["Debug"]          = "aeroros.apps.debug",
  ["About AeroOS"]   = "aeroros.apps.about",
}

function M.launch(name)
  local opts = DEFAULTS[name] or { w = 30, h = 12, x = 4, y = 3 }
  local mod_name = APP_MODULES[name]
  if not mod_name then return end
  local ok, mod = pcall(require, mod_name)
  if not ok or not mod or not mod.run then return end
  manager.spawn(name, mod.run, opts)
end

function M.install()
  desktop_mod.open_app = function(name, ...) M.launch(name) end
end

return M
