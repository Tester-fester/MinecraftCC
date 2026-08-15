--[[
  AeroOS · Boot sequence (v3 — with debug support)

  Entry point. CC:Tweaked's bios.lua runs /startup.lua, which requires this
  module and calls boot().

  Boot order:
    1. Parse boot args from /aeroos/etc/boot_args.cfg (if present).
    2. If --debug is set, enable file logging + lower the log level.
    3. desktop_mod.boot() — palette, animation, register apps, dispatcher,
       restore session.
    4. Spawn the desktop as a kernel process.
    5. Hand control to the scheduler. Blocks until shutdown.

  Boot args file format (one per line):
    debug
    level=trace
    cat=net
]]

local desktop_mod = require("aeroros.shell.desktop")
local scheduler   = require("aeroros.kernel.scheduler")
local debug       = require("aeroros.kernel.debug")

-- Parse boot args from /aeroos/etc/boot_args.cfg.
local function parse_args()
  local args = { debug = false, level = nil, cats = {} }
  local path = "/aeroos/etc/boot_args.cfg"
  if not fs.exists(path) then return args end
  local f = fs.open(path, "r")
  if not f then return args end
  local line = f.readLine()
  while line do
    line = line:match("^%s*(.-)%s*$")  -- trim
    if line == "debug" then args.debug = true
    elseif line:find("^level=") then args.level = line:sub(7)
    elseif line:find("^cat=") then
      table.insert(args.cats, line:sub(5))
    end
    line = f.readLine()
  end
  f.close()
  return args
end

local function boot()
  local args = parse_args()

  if args.debug then
    debug.set_level(args.level or "debug")
    debug.enable_file_log()
    debug.info("kernel", "Boot started (debug mode ON, level=" ..
               tostring(args.level or "debug") .. ")")
  else
    debug.info("kernel", "Boot started")
  end

  -- Disable any categories the user wanted to filter out.
  for _, cat in ipairs(args.cats) do
    debug.disable_category(cat)
  end

  debug.debug("kernel", "Calling desktop_mod.boot()...")
  local ok, err = pcall(desktop_mod.boot)
  if not ok then
    debug.fatal("kernel", "desktop_mod.boot() crashed: " .. tostring(err))
    error(err)
  end
  debug.info("kernel", "Desktop booted, spawning desktop process")

  scheduler.spawn("Desktop", desktop_mod.run)
  debug.info("kernel", "Handing control to scheduler")
  scheduler.run()

  debug.info("kernel", "Scheduler exited, shutting down")
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.cyan)
  term.write("AeroOS halted.  Press any key to return to CraftOS.")
  os.pullEvent("char")
end

return { boot = boot }
