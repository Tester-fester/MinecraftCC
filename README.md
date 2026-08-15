# AeroOS

**A Windows 7 Aero-themed operating system for CC:Tweaked.**

AeroOS is a fork of the Phoenix OS design (pre-emptive scheduler, process
table, syscall layer, VFS) with a ComBox-inspired renderer (ImageHandler +
Combinator + Renderer + Compositor). It runs entirely inside Minecraft on
a ComputerCraft computer, turtle, or monitor-attached computer.

The "screen" is a CC:Tweaked terminal — a 16-colour text-mode grid where
each cell holds one character + one text colour + one background colour.
AeroOS uses the native `window` API for text and a half-block / shade
combinator for image regions where sub-cell resolution is needed.

---

## Quick start

### Install (online, GitHub)

On your CC:Tweaked computer's shell:

```text
wget https://raw.githubusercontent.com/Tester-fester/MinecraftCC/main/installer.lua /installer.lua
/installer.lua
reboot
```

The installer pulls every file from the official repo into `/aeroos/`,
writes `/startup.lua`, and tells you to reboot. The computer then boots
straight into AeroOS.

To install from a fork:

```text
/installer.lua /aeroos https://raw.githubusercontent.com/YOURNAME/AeroOS/main
```

### Install (offline, from this zip)

1. Unzip `AeroOS.zip`.
2. Copy the `AeroOS/` folder into the computer's filesystem so it lands at
   `/aeroos`. (For single-player: copy into `<save>/computercraft/computer/<id>/`.
   For servers: use a floppy disk or ender-modem file transfer.)
3. Copy `startup.lua` to `/startup.lua`.
4. Reboot the computer in-game (`Ctrl+R` while looking at it, or break & replace).

### Run after install

Just reboot. AeroOS boots automatically.

---

## What's in this package (v2)

```
AeroOS/
├── startup.lua            ← CC:Tweaked boot entry
├── installer.lua          ← wget-based installer (run on the computer)
├── LICENSE                ← MIT
├── .gitignore
├── CONTRIBUTING.md
├── README.md
└── aeroros/
    ├── boot.lua           ← Boot sequence (palette, animation, desktop, scheduler)
    ├── kernel/
    │   ├── process.lua    ← PID table, process records, event inbox
    │   ├── scheduler.lua  ← Pre-emptive time-sliced coroutine scheduler
    │   ├── event.lua      ← Event router (focus-based for input)
    │   └── syscall.lua    ← Sandbox wrapper for fs/peripheral/http/rednet
    ├── graphics/
    │   ├── color.lua      ← 16-colour palette manager (static + dynamic slots)
    │   ├── combinator.lua ← Simple / HalfBlock / Shade combinators
    │   ├── framebuffer.lua ← ImageHandler (pixel grid with gradients, rects, composite)
    │   ├── renderer.lua    ← Renders ImageHandler → term.blit with dirty-cell cache
    │   └── compositor.lua  ← (legacy) pixel compositor for image-only apps
    ├── wm/
    │   ├── theme.lua      ← Aero colour palette + glyph constants
    │   ├── window.lua     ← Window class backed by a CC `window`
    │   └── manager.lua    ← Z-order, focus, mouse/keyboard routing, resize
    ├── shell/
    │   ├── desktop.lua    ← Desktop, taskbar, Start menu, context menu, event loop
    │   ├── dispatch.lua   ← Maps Start-menu app names to launches
    │   ├── boot_anim.lua  ← Aero boot splash with progress bar
    │   ├── wallpaper.lua  ← 3 built-in wallpapers (Aero Blue, Emerald, Midnight)
    │   └── persistence.lua ← Save / restore open windows across reboots
    ├── widgets/
    │   ├── base.lua       ← Widget base class
    │   └── button.lua     ← Aero button (normal/hover/pressed states)
    └── apps/
        ├── terminal.lua   ← Command prompt (cd/ls/cat/echo/ver/help/exit + history)
        ├── explorer.lua   ← File explorer (keyboard-navigable)
        ├── editor.lua     ← Notepad-style editor (Ctrl+S save, Ctrl+Q quit)
        ├── viewer.lua     ← Image viewer (demonstrates the pixel renderer)
        ├── calculator.lua ← Four-function calculator (click or keyboard)
        ├── paint.lua      ← Pixel paint (brush/eraser/fill/line, half-block res)
        ├── settings.lua   ← Wallpaper picker + about tab
        ├── taskmgr.lua    ← Task Manager (list windows, kill)
        └── about.lua      ← About dialog
```

---

## New in v3 — Debug subsystem

A full kernel-level debug logger is now wired in:

- **6 log levels** (trace / debug / info / warn / error / fatal) with a
  ring buffer of the last 500 entries.
- **F12 overlay** — press F12 anywhere to slide up a translucent log panel.
  Colour-coded by level; shows the most recent entries live.
- **Debug app** — Start menu → Debug. Four tabs: Logs (with filters),
  Procs (process table + window list), Stats (counters + dump button),
  Settings (level, file log, overlay).
- **File logging** — `debug.enable_file_log()` writes every entry to
  `/aeroos/etc/debug.log`. Enable at boot with `debug` in
  `/aeroos/etc/boot_args.cfg`.
- **Boot args** — `/aeroos/etc/boot_args.cfg` lets you set the log level
  and disable categories without editing code.
- **Post-mortem dump** — `debug.dump_to_file()` writes the entire ring
  buffer + stats to a timestamped file for offline inspection.
- **Error visibility** — `error` and `fatal` messages print directly to
  the screen bottom (via `term.native()`), so they're visible even if the
  desktop shell is broken.
- **Instrumentation** — scheduler logs every spawn / crash / exit; WM
  logs every spawn / focus / close / cleanup; desktop logs boot phases.

See `DEBUG.md` for the full API and usage guide.

---

## Controls cheat sheet

| Action | How |
|---|---|
| Open Start menu | Right-Ctrl, or click Start orb (bottom-left) |
| Search apps | Open Start menu, then type |
| Launch app | Click it in Start menu, or Enter on first match |
| Move window | Click & drag title bar |
| Resize window | Click & drag right / bottom / bottom-right edge |
| Maximize / restore | Click `^` in title bar |
| Minimize | Click `_` in title bar |
| Close window | Click `x`, or Alt+F4 |
| Right-click desktop | Context menu (refresh, new file, wallpaper, etc.) |
| Save file (Notepad) | Ctrl+S |
| Quit app (Notepad) | Ctrl+Q |
| Terminal history | Up / Down arrows |
| **Debug overlay** | **F12** (toggle on/off) |
| **Debug app** | Start menu → Debug |
| Boot shutdown | Ctrl+T (terminate) |

---

## How it actually works

### Two rendering layers

| Layer | Used for | Mechanism |
|---|---|---|
| **Text** | Chrome, app text, taskbar, menus | CC `window` API + `term.blit` |
| **Pixel** | Image Viewer, Paint | `ImageHandler` + `Combinator` + `Renderer` → `term.blit` |

This is the right split: CC's text APIs are fast and correct, so we use
them everywhere they work. The ComBox pixel pipeline only kicks in when an
app actually needs to render arbitrary pixels (an image, a paint canvas).

### Palette arbitration

CC:Tweaked terminals have a single global palette of 16 colours. AeroOS
reserves slots 0-3 for static OS colours (black, white, glass highlight,
text gray) so the desktop chrome always renders right. Slots 4-15 are
dynamic — they belong to whichever window is focused. When focus changes,
the newly focused window re-blasts its palette.

### Pre-emptive multitasking

Each app runs as a coroutine. The scheduler hooks `os.pullEventRaw` and
time-slices via a 0.05s timer. Apps that block on `coroutine.yield` (or any
event-pulling API) surrender their slice; the scheduler picks the next
runnable process.

### Session persistence

On shutdown, the desktop writes the list of open windows (title + bounds)
and the current wallpaper to `/aeroos/etc/session.cfg`. On next boot, it
reads that file and re-launches the same apps at the same positions. App
internal state (unsaved text, calculator memory, etc.) is NOT preserved —
just the window layout.

---

## Credits

- **Phoenix** (`phoenix.madefor.cc`) — the OS design we fork from. The
  scheduler, process, syscall, and VFS patterns come from Phoenix's docs.
- **ComBox** (`github.com/hexelll/ComBox`) — the renderer design we adopt.
  ImageHandler + Combinator + Renderer is ComBox's architecture, simplified.
- **CC: Tweaked** (`tweaked.cc`) — the Minecraft mod that provides the
  programmable computer, monitor, turtle, and event loop.

AeroOS is a thin, opinionated layer on top of these three projects.

---

## Known limits / next steps

- **Real PNG support** — ComBox's `MediaParser` can be vendored to enable
  loading actual image files in the viewer and paint apps.
- **Window snap** — Win7-style Aero Snap (drag to top to maximize, drag to
  side to half-screen) is the obvious next polish.
- **Turtle daemon** — turtles should be first-class. A fleet manager that
  runs as a kernel service and exposes a turtle API to userland.
- **Networking** — wire up rednet to give the terminal a `net` command and
  the explorer network paths.
- **Sound** — Phoenix's `speaker` driver is there; an Aero startup sound
  would be a nice touch.
- **Theming** — the theme system is there but only one theme is wired up.
  Adding "Classic Dark" and "Glass White" palettes is straightforward.

Pull requests welcome — see CONTRIBUTING.md.
