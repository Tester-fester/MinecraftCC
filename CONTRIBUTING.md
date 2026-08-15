# Contributing to AeroOS

Thanks for your interest! AeroOS is a small project but contributions are welcome.

## Project layout

```
aeroros/
  kernel/      # scheduler, process, event, syscall
  graphics/    # color, palette, combinator, framebuffer, renderer, compositor
  wm/          # window, manager, theme
  shell/       # desktop, dispatch, boot_anim, wallpaper, persistence
  widgets/     # button, base
  apps/        # one file per app: terminal, editor, explorer, ...
```

## Architecture (read this first)

AeroOS uses **two rendering layers**:

1. **Text layer** — CC:Tweaked's native `window` API. Each AeroOS window owns a
   CC `window`; the WM draws chrome into it via `term.blit`, and apps redirect
   `term` to a child CC `window` for their content. This is fast and handles
   text correctly.

2. **Pixel layer** — ComBox-style `ImageHandler` + `Combinator` + `Renderer`.
   Used only by apps that actually need pixel compositing (Image Viewer,
   Paint). This is slow per-cell but gives sub-cell resolution via half-blocks.

**Do not** try to paint text through the pixel layer — `term.write` /
`term.blit` go through `term.redirect` and bypass any RGB framebuffer.

## Adding a new app

1. Create `aeroros/apps/yourapp.lua`.
2. Export `register(desktop)` (calls `desktop.register_app("Name", ...)`)
   and `run(win)` (the app coroutine; receives the Window).
3. Use `win:content_rect()` to get the content area, then
   `window.create(term, c.x, c.y, c.w, c.h, false)` for your term.
4. `term.redirect(term_win)` to draw into it.
5. Listen for events: `event.listen("key", process.current())` etc.
6. Drain your inbox in a `while true` loop, then `coroutine.yield()`.
7. Add the app to `desktop.APP_LIST` in `aeroros/shell/desktop.lua` and to
   `APP_MODULES` + `DEFAULTS` in `aeroros/shell/dispatch.lua`.
8. Add the file to `FILES` in `installer.lua`.

## Code style

- 2-space indent.
- `local` everything; no globals.
- Module pattern: `local M = {} ... M.foo = ... return M`.
- Comments explaining "why", not "what".

## Testing

Boot AeroOS in a CC:Tweaked creative world. Test:
- Start menu launches every app.
- Window move / resize / minimize / maximize / close.
- Right-click desktop context menu works.
- Session restores on reboot.
- No "AeroOS boot failed" fallback.

If you find a bug, please include:
- The error message (from the boot fallback screen).
- Which app / action triggered it.
- The Lua file + line if you can.
