--[[
  AeroOS · Window (v2 — uses CC's native window API)

  This is the big architectural fix. The v1 Window tried to paint chrome as
  RGB pixels into an ImageHandler and let the compositor blit it. That fights
  with apps that use term.write/term.blit because those go through
  term.redirect and splat directly onto the screen, bypassing z-order.

  v2 takes the approach real CC:Tweaked OSes (OneOS, Opus) use:
    - Each window owns a CC `window` object (created via window.create).
    - The window's CC window covers the chrome + content area.
    - Chrome (title bar, borders, controls) is painted by the WM directly
      into that CC window via term.blit.
    - Apps get a *child* CC window for their content rect and redirect
      term output there. Their text shows up correctly because we're using
      the actual terminal machinery, not a parallel pixel pipeline.
    - The compositor handles z-order by reordering/restacking CC windows
      via window.setVisible and window.reposition.
    - The ImageHandler + Combinator + Renderer stack stays for the Image
      Viewer and Paint apps where we need actual pixel compositing.

  This split is right: text → CC windows (fast, native), pixels → ComBox
  (slow, but only used when actually needed).
]]

local theme = require("aeroros.wm.theme")

local Window = {}
Window.__index = Window

local next_id = 1

function Window.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Window)
  self.id = next_id; next_id = next_id + 1
  self.title = opts.title or "Window"
  self.x = opts.x or 4
  self.y = opts.y or 4
  self.w = opts.w or 30
  self.h = opts.h or 12
  self.min_w = theme.MIN_W
  self.min_h = theme.MIN_H
  self.focused = false
  self.minimized = false
  self.maximized = false
  self.saved_bounds = nil
  self.app = opts.app
  self.closable     = opts.closable     ~= false
  self.maximizable  = opts.maximizable  ~= false
  self.minimizable  = opts.minimizable  ~= false
  self.resizable    = opts.resizable    ~= false
  self.on_close = opts.on_close

  -- Create the CC window that backs this AeroOS window. We give it the
  -- full window rect (chrome + content). The WM draws chrome; the app
  -- draws content into a child CC window inside this rect.
  self.cc_window = window.create(term, self.x, self.y, self.w, self.h, false)
  -- App content CC window (created lazily — see get_content_term()).
  self.content_window = nil
  self.pid = nil

  return self
end

-- Reposition + resize the underlying CC window. Called whenever the window
-- moves or resizes (drag, maximize, restore).
function Window:set_rect(x, y, w, h)
  self.x = x
  self.y = y
  self.w = math.max(self.min_w, w)
  self.h = math.max(self.min_h, h)
  -- CC's window.reposition moves AND resizes. The args are:
  --   (new_x, new_y, new_width, new_height, parent_term)
  self.cc_window.reposition(self.x, self.y, self.w, self.h, term)
  -- If we had a content window, rebuild it at the new content rect.
  -- IMPORTANT: content_window is a CHILD of cc_window, so its coordinates
  -- must be RELATIVE to the parent, not screen coordinates.
  if self.content_window then
    local cw = math.max(1, self.w - 2 * theme.BORDER_W)
    local ch = math.max(1, self.h - theme.TITLE_BAR_H - theme.BORDER_W)
    -- Relative position inside cc_window: column BORDER_W+1, row TITLE_BAR_H+1.
    self.content_window.reposition(theme.BORDER_W + 1, theme.TITLE_BAR_H + 1,
                                  cw, ch, self.cc_window)
    -- Force a redraw so the content shows up at the new position.
    self.content_window.redraw()
  end
end

function Window:set_pos(x, y)
  self:set_rect(x, y, self.w, self.h)
end

function Window:set_size(w, h)
  self:set_rect(self.x, self.y, w, h)
end

-- The content rect (inside chrome), in screen coordinates.
function Window:content_rect()
  return {
    x = self.x + theme.BORDER_W,
    y = self.y + theme.TITLE_BAR_H,
    w = self.w - 2 * theme.BORDER_W,
    h = self.h - theme.TITLE_BAR_H - theme.BORDER_W,
  }
end

-- Get (or lazily create) the CC window the app should redirect term to.
-- The app uses this as its term; everything it writes lands inside the
-- window's content rect, properly clipped.
function Window:get_content_term()
  if not self.content_window then
    local c = self:content_rect()
    self.content_window = window.create(self.cc_window,
                                        theme.BORDER_W + 1,
                                        theme.TITLE_BAR_H + 1,
                                        math.max(1, c.w),
                                        math.max(1, c.h),
                                        true)
    -- Use the WINDOW_BODY palette slot (3) as the default content bg.
    self.content_window.setBackgroundColor(colors.lightBlue)
    self.content_window.setTextColor(colors.white)
    self.content_window.clear()
  end
  return self.content_window
end

function Window:show()
  self.cc_window.setVisible(true)
  if self.content_window then self.content_window.setVisible(true) end
end

function Window:hide()
  self.cc_window.setVisible(false)
end

function Window:maximize(work_x, work_y, work_w, work_h)
  if self.maximized then return end
  self.saved_bounds = { x = self.x, y = self.y, w = self.w, h = self.h }
  self:set_rect(work_x or 1, work_y or 1, work_w or 50, work_h or 18)
  self.maximized = true
end

function Window:restore()
  if not self.maximized then return end
  self.maximized = false
  if self.saved_bounds then
    self:set_rect(self.saved_bounds.x, self.saved_bounds.y,
                  self.saved_bounds.w, self.saved_bounds.h)
    self.saved_bounds = nil
  end
end

function Window:minimize()
  self.minimized = true
  self:hide()
end

function Window:unminimize()
  self.minimized = false
  self:show()
end

function Window:close()
  if self.on_close then self:on_close() end
  self:hide()
end

-- Paint the Aero chrome (title bar + borders + controls) into the CC window.
-- Called by the WM on every frame for visible windows.
function Window:paint_chrome()
  local cw = self.cc_window
  local w, h = self.w, self.h
  cw.setVisible(false)

  -- All colors below are PALETTE INDICES (0-15) used as hex chars in blit.
  -- These map to colors.X constants via 2^idx (see graphics/color.lua).
  -- Indices come from theme.SLOT so the chrome matches color.AERO palette.
  local idx_title    = string.format("%x", theme.SLOT.TITLE_BAR)       -- 11 (bright blue)
  local idx_title_dk = string.format("%x", theme.SLOT.TITLE_BAR_DARK)   -- 5 (dark blue)
  local idx_inactive = string.format("%x", theme.SLOT.TITLE_INACTIVE)  -- 13 (gray-blue)
  local idx_body     = string.format("%x", theme.SLOT.WINDOW_BODY)     -- 3 (light)
  local idx_body_dk  = string.format("%x", theme.SLOT.WINDOW_BODY_DK) -- 8 (darker)
  local idx_white    = string.format("%x", theme.SLOT.WHITE)             -- 0
  local idx_text_gry = string.format("%x", theme.SLOT.TEXT_GRAY)       -- 7
  local idx_black    = string.format("%x", theme.SLOT.BLACK)             -- 15 -> 'f'

  -- Title bar (row 1). Single row. For focused windows we use the bright
  -- blue; for unfocused, the gray-blue. Add a darker right edge for depth.
  local title_fg, title_bg
  if self.focused then
    title_fg = string.rep(idx_white, w)  -- white text on title bar
    if w >= 3 then
      title_bg = string.rep(idx_title, w - 2) .. idx_title_dk .. idx_title_dk
    else
      title_bg = string.rep(idx_title, w)
    end
  else
    title_fg = string.rep(idx_text_gry, w)
    title_bg = string.rep(idx_inactive, w)
  end
  cw.setCursorPos(1, 1)
  cw.blit(string.rep(" ", w), title_fg, title_bg)

  -- Window controls in top-right: close (w), maximize (w-1), minimize (w-2).
  if self.closable then
    cw.setCursorPos(w, 1)
    cw.blit("x", idx_white, idx_title_dk)
  end
  if self.maximizable then
    cw.setCursorPos(w - 1, 1)
    cw.blit("^", idx_white, idx_title_dk)
  end
  if self.minimizable then
    cw.setCursorPos(w - 2, 1)
    cw.blit("_", idx_white, idx_title_dk)
  end

  -- Title text (left-aligned).
  local max_title = math.max(1, w - 6)
  local title = self.title:sub(1, max_title)
  cw.setCursorPos(2, 1)
  cw.blit(title,
         string.rep(self.focused and idx_white or idx_text_gry, #title),
         string.rep(self.focused and idx_title   or idx_inactive, #title))

  -- Body fill (rows 2 to h-1): light window body.
  for row = 2, h - 1 do
    cw.setCursorPos(1, row)
    cw.blit(string.rep(" ", w), string.rep(idx_black, w), string.rep(idx_body, w))
  end

  -- Borders: left & right columns get the darker shade.
  for row = 2, h - 1 do
    cw.setCursorPos(1, row)
    cw.blit(" ", idx_black, idx_body_dk)
    cw.setCursorPos(w, row)
    cw.blit(" ", idx_black, idx_body_dk)
  end

  -- Bottom border.
  cw.setCursorPos(1, h)
  cw.blit(string.rep(" ", w), string.rep(idx_black, w), string.rep(idx_body_dk, w))

  -- Restore content window visibility (it might have been clobbered).
  if self.content_window then
    self.content_window.setVisible(true)
    self.content_window.redraw()
  end

  cw.setVisible(true)
  cw.redraw()
end

-- Hit-test a screen-space point.
-- Returns: "title" | "close" | "max" | "min" | "body" | "border_l" | "border_r" | "border_b" | "border_tl" | "border_tr" | "border_bl" | "border_br" | nil
function Window:hit_test(sx, sy)
  if self.minimized then return nil end
  if sx < self.x or sy < self.y then return nil end
  if sx > self.x + self.w - 1 or sy > self.y + self.h - 1 then return nil end

  local rx = sx - self.x + 1
  local ry = sy - self.y + 1

  -- Title bar row.
  if ry == 1 then
    if self.closable and rx == self.w then return "close" end
    if self.maximizable and rx == self.w - 1 then return "max" end
    if self.minimizable and rx == self.w - 2 then return "min" end
    return "title"
  end

  -- Bottom border.
  if ry == self.h then
    if rx == 1 then return "border_bl" end
    if rx == self.w then return "border_br" end
    return "border_b"
  end

  -- Side borders.
  if rx == 1 then
    if ry == 2 then return "border_tl" end  -- actually below title; treat as left edge
    return "border_l"
  end
  if rx == self.w then
    return "border_r"
  end

  return "body"
end

return Window
