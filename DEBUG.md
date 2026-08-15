# Debugging AeroOS

AeroOS ships with a proper debug subsystem. Here's how to use it.

## Quick start

### Enable debug mode at boot

Create `/aeroos/etc/boot_args.cfg` with:

```text
debug
level=trace
```

Reboot. Now AeroOS will:
- Log at the `trace` level (most verbose)
- Write every log entry to `/aeroos/etc/debug.log`
- Print `error` and `fatal` messages directly to the screen bottom

### Toggle the on-screen overlay

Anywhere in AeroOS, press **F12**. A translucent panel slides up from the
bottom showing the most recent log entries, colour-coded by level:

- gray = trace
- light gray = debug
- white = info
- yellow = warn
- orange = error
- red = fatal

Press F12 again to hide it.

### Launch the full Debug app

Open the Start menu → **Debug** (or press Right-Ctrl, type "debug", Enter).
The app has four tabs:

- **Logs** — recent log entries with level + category filters
- **Procs** — full process table (PID, name, state, CPU, inbox depth) and
  the window list
- **Stats** — per-level log counters + dump-to-file button
- **Settings** — log level, file logging toggle, overlay toggle

Keyboard shortcuts in the Debug app:
- `Tab` — cycle tabs
- `Up/Down` — scroll logs
- `L` — cycle level filter (on Logs tab)
- `C` — cycle category filter (on Logs tab)
- `D` — dump full log to a timestamped file
- `F` — toggle file logging
- `O` — toggle the F12 overlay (Settings tab)
- `[` / `]` — fewer / more overlay lines (Settings tab)
- `/` / `=` — lower / raise log level (Settings tab)
- `Q` — quit

## Boot args reference

`/aeroos/etc/boot_args.cfg` is read at every boot. One option per line:

| Line | Effect |
|---|---|
| `debug` | Enables debug mode (file logging + lower default level) |
| `level=trace` | Sets min log level. Values: trace, debug, info, warn, error, fatal |
| `cat=net` | Disables a category (so `net` logs are dropped). Repeat for multiple. |

Example for production (only warnings and worse, no network noise):

```text
level=warn
cat=net
cat=app
```

Example for max verbosity when chasing a bug:

```text
debug
level=trace
```

## The debug.lua API (for app developers)

```lua
local debug = require("aeroros.kernel.debug")

-- Log at each level. First arg is a category string; second is the message.
debug.trace("net", "received packet from " .. sender)
debug.debug("app", "calculating " .. n .. " factorial")
debug.info ("shell", "user opened Start menu")
debug.warn ("wm", "window " .. title .. " hit_test returned nil")
debug.error("gfx", "compositor: framebuffer too small: " .. w .. "x" .. h)
debug.fatal("kernel", "scheduler panic: " .. err)

-- Runtime controls
debug.set_level("debug")          -- raise/lower the min level at runtime
debug.enable_file_log()            -- start writing to debug.log
debug.disable_file_log()
debug.enable_category("net")      -- re-enable a filtered category
debug.disable_category("net")

-- Introspection
local entries = debug.recent(50)   -- last 50 log entries
local stats   = debug.stats()      -- { trace=N, debug=N, info=N, ... }

-- Post-mortem dump
local path = debug.dump_to_file()  -- writes everything to a timestamped file
```

## Log entry format

Each entry has:

| Field | Type | Description |
|---|---|---|
| `time` | number | `os.clock()` seconds since boot |
| `level` | number | 1=trace, 2=debug, 3=info, 4=warn, 5=error, 6=fatal |
| `tag` | string | single-char level tag (T/D/I/W/E/F) |
| `category` | string | subsystem: kernel, shell, wm, gfx, app, net, ... |
| `pid` | number | PID of the process that wrote the log |
| `name` | string | name of that process |
| `message` | string | the log message |

In the file log, each line looks like:

```text
[12.345] I [shell] pid=1 (Desktop) user opened Start menu
[12.567] W [wm] pid=0 (kernel) window Terminal hit_test returned nil
[12.891] E [kernel] pid=4 (Terminal) process crashed: attempt to index nil
```

## Where to look when something breaks

### Boot fails entirely
The `/startup.lua` wrapper catches errors and prints them to the screen
before falling back to the default CraftOS shell. The error message tells
you which file/line threw.

### A specific app crashes
1. Press F12 to see the overlay.
2. Look for the `E [kernel]` line that says "process pid=N name=X crashed: ...".
3. Open the Debug app → Logs tab, set level filter to `debug`.
4. Reproduce the bug.
5. Press `D` to dump the full log to a file.
6. Read `/aeroos/etc/debug_dump_*.log` from outside Minecraft.

### The whole OS hangs
The most common cause is a process that doesn't yield. The scheduler's
0.05s heartbeat should re-arm itself; if the overlay stops updating, you
probably have an infinite loop in a process. Press `Ctrl+T` (terminate) to
force-quit the desktop shell, which usually surfaces the culprit in the
log.

### Z-order or focus is wrong
Filter the Logs tab to `wm` category. You'll see every spawn / focus /
close event with the window ID and PID, so you can trace exactly what the
WM did.

## Performance note

The ring buffer is 500 entries, written in O(1). Logging at the `trace`
level adds noticeable overhead because every line goes through the
formatter + ring + (optional) file write. For normal use, `info` is the
right default.
