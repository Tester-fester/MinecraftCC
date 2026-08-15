--[[
  AeroOS · Debug logger

  A proper kernel debug subsystem with:
    - 6 log levels (TRACE, DEBUG, INFO, WARN, ERROR, FATAL)
    - Category filtering (kernel, wm, gfx, net, app, ...)
    - Ring buffer (last N entries, default 500)
    - Optional on-screen overlay (toggle with F12)
    - Optional file dump to /aeroos/etc/debug.log
    - Per-process attribution (logs know which PID wrote them)

  Usage:
    local debug = require("aeroros.kernel.debug")
    debug.info("kernel", "boot complete")
    debug.warn("wm", "window " .. win.title .. " hit_test returned nil")
    debug.error("gfx", "compositor: framebuffer too small: " .. w .. "x" .. h)
    debug.fatal("kernel", "scheduler panic: " .. err)

  The overlay is rendered by the desktop shell in paint_frame(), reading
  from this module's ring buffer.
]]

local process = require("aeroros.kernel.process")

local debug = {}

-- Log levels. Higher number = more important.
debug.LEVELS = {
  trace = 1,
  debug = 2,
  info  = 3,
  warn  = 4,
  error = 5,
  fatal = 6,
}

-- Current minimum level. Anything below this is dropped.
-- Defaults to INFO; can be lowered via set_level() or the --debug boot flag.
local min_level = debug.LEVELS.info

-- Per-category enable. If a category is listed here as false, its logs are
-- dropped even if the level passes. Unlisted categories default to enabled.
local disabled_categories = {}

-- Ring buffer of the last N log entries.
-- Each entry: { time, level, category, pid, name, message }
local RING_SIZE = 500
local ring = {}
local ring_head = 1  -- next slot to write

-- Overlay state.
debug.overlay_visible = false
debug.overlay_lines = 18  -- how many recent lines to show

-- File log path. If set, every entry is also appended to this file.
local LOG_FILE = "/aeroos/etc/debug.log"
local log_to_file = false  -- off by default; enable via enable_file_log()

-- Counter for stats.
local stats = { trace=0, debug=0, info=0, warn=0, error=0, fatal=0 }

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Convert a level name to its numeric value.
local function level_num(lvl)
  if type(lvl) == "number" then return lvl end
  return debug.LEVELS[lvl] or debug.LEVELS.info
end

-- Convert a numeric level to a single-char tag for display.
local function level_tag(n)
  if n == 1 then return "T"
  elseif n == 2 then return "D"
  elseif n == 3 then return "I"
  elseif n == 4 then return "W"
  elseif n == 5 then return "E"
  elseif n == 6 then return "F"
  end
  return "?"
end

-- Set the minimum log level. Accepts a name ("trace".."fatal") or number.
function debug.set_level(lvl)
  min_level = level_num(lvl)
end

function debug.get_level()
  return min_level
end

-- Disable a category. Logs from it will be dropped regardless of level.
function debug.disable_category(cat)
  disabled_categories[cat] = false
end

function debug.enable_category(cat)
  disabled_categories[cat] = nil
end

function debug.enable_file_log()
  if not fs.exists("/aeroos/etc") then fs.makeDir("/aeroos/etc") end
  log_to_file = true
end

function debug.disable_file_log()
  log_to_file = false
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- The core log function.
local function log(lvl, category, message)
  local n = level_num(lvl)
  if n < min_level then return end
  if disabled_categories[category] == false then return end

  -- Get caller's PID + name.
  local pid = process.current()
  local name = "?"
  if pid and pid > 0 then
    local rec = process.get(pid)
    if rec then name = rec.name end
  end

  local entry = {
    time = os.clock(),
    level = n,
    tag = level_tag(n),
    category = category or "?",
    pid = pid or 0,
    name = name,
    message = tostring(message),
  }

  -- Write to ring buffer (overwrite oldest when full).
  ring[ring_head] = entry
  ring_head = (ring_head % RING_SIZE) + 1

  -- Stats.
  local lvl_name = lvl
  if type(lvl_name) == "number" then
    for k, v in pairs(debug.LEVELS) do
      if v == lvl_name then lvl_name = k break end
    end
  end
  stats[lvl_name] = (stats[lvl_name] or 0) + 1

  -- Optional file log.
  if log_to_file then
    local f = fs.open(LOG_FILE, "a")
    if f then
      f.writeLine(string.format("[%.3f] %s [%s] pid=%d (%s) %s",
        entry.time, entry.tag, entry.category, entry.pid, entry.name, entry.message))
      f.close()
    end
  end

  -- If this is an ERROR or worse, also print to the parent term so it shows
  -- up on the screen even if the desktop shell is broken.
  if n >= 5 then
    -- Write to the underlying term (not a redirected one) by saving and
    -- restoring. We use term.native() if available so the message isn't
    -- clipped to a window's content rect.
    local native = term.native and term.native() or term
    local old_x, old_y = native.getCursorPos()
    local w, h = native.getSize()
    native.setBackgroundColor(colors.black)
    native.setTextColor(n == 6 and colors.red or colors.orange)
    native.setCursorPos(1, h)
    native.write(string.format("%s [%s] %s", entry.tag, entry.category, entry.message:sub(1, w - 6)))
    native.setCursorPos(old_x, old_y)
  end
end

-- Convenience methods.
function debug.trace(cat, msg) log("trace", cat, msg) end
function debug.debug(cat, msg) log("debug", cat, msg) end
function debug.info (cat, msg) log("info",  cat, msg) end
function debug.warn (cat, msg) log("warn",  cat, msg) end
function debug.error(cat, msg) log("error", cat, msg) end
function debug.fatal(cat, msg) log("fatal", cat, msg) end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Return the last N entries, oldest first.
function debug.recent(n)
  n = n or RING_SIZE
  local out = {}
  -- Start from ring_head (oldest entry if buffer is full) and walk forward.
  local start = ring_head
  -- If the buffer isn't full yet, start from 1.
  if #ring < RING_SIZE then start = 1 end
  for i = 0, RING_SIZE - 1 do
    local idx = ((start + i - 1) % RING_SIZE) + 1
    if ring[idx] then
      table.insert(out, ring[idx])
      if #out >= n then break end
    end
  end
  return out
end

-- Return the count of entries at each level.
function debug.stats()
  return stats
end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Overlay control. The desktop shell reads overlay_visible + recent() to
-- paint the log panel on top of everything else.
function debug.toggle_overlay()
  debug.overlay_visible = not debug.overlay_visible
end

function debug.show_overlay() debug.overlay_visible = true end
function debug.hide_overlay() debug.overlay_visible = false end

-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- --

-- Dump the entire ring buffer + stats to a file. Useful for post-mortem
-- debugging after a crash.
function debug.dump_to_file(path)
  path = path or ("/aeroos/etc/debug_dump_" .. os.time() .. ".log")
  if not fs.exists("/aeroos/etc") then fs.makeDir("/aeroos/etc") end
  local f = fs.open(path, "w")
  if not f then return nil, "cannot open " .. path end
  f.writeLine("AeroOS debug dump  (time=" .. os.time() .. ")")
  f.writeLine("================================")
  f.writeLine("Stats:")
  for k, v in pairs(stats) do
    f.writeLine("  " .. k .. ": " .. tostring(v))
  end
  f.writeLine("")
  f.writeLine("Log entries (oldest first):")
  for _, entry in ipairs(debug.recent()) do
    f.writeLine(string.format("[%.3f] %s [%s] pid=%d (%s) %s",
      entry.time, entry.tag, entry.category, entry.pid, entry.name, entry.message))
  end
  f.close()
  return path
end

return debug
