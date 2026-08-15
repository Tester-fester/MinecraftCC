--[[
  AeroOS · Theme constants

  Every visual value that gives AeroOS its "Windows 7 Aero" look lives here.
  Tweak these to reskin the whole desktop.

  Aero tells (from the Win7 design language):
    - Glassy blue title bars with subtle gradient
    - Soft white-on-blue text with drop-shadow feel
    - Rounded window corners (we use box-drawing chars)
    - Glossy buttons with hover/press states
    - Dark teal taskbar with subtle vertical gradient
    - Start orb: round, gradient blue, white flag
    - Desktop: deep blue gradient (Win7 default was the Windows logo, but
      we use a clean blue gradient for a more "Aero" feel)
]]

local theme = {}

theme.NAME = "AeroOS"

-- Window chrome geometry.
theme.TITLE_BAR_H    = 1     -- single row title bar (CC: terminal cells are tall)
theme.BORDER_W       = 1     -- single-cell border on each side
theme.MIN_W          = 12
theme.MIN_H          = 4
theme.CORNER_CHAR    = " "   -- corners just get painted with the title bar color

-- Aero palette (this mirrors graphics.color.AERO but named for theme reasons).
theme.COLORS = {
  desktop_bg_top    = 0x1F3A5F,   -- deep aero blue
  desktop_bg_bottom = 0x0A1A2A,
  title_bar_top     = 0x6FA8DC,   -- light aero blue (top of gradient)
  title_bar_bot     = 0x2C5784,   -- darker (bottom of gradient)
  title_text        = 0xFFFFFF,
  title_inactive    = 0xAACBED,
  window_body       = 0xF0F4FA,
  window_body_dark  = 0xD4DCE8,
  window_border     = 0x6FA8DC,
  taskbar_top       = 0x2C5784,
  taskbar_bot       = 0x0F1E30,
  taskbar_text      = 0xFFFFFF,
  start_orb_outer   = 0x1E3A5F,
  start_orb_inner   = 0x6FA8DC,
  start_orb_flag    = 0xFFFFFF,
  button_base       = 0xAACBED,
  button_hover      = 0x6FA8DC,
  button_press      = 0x3D7BBF,
  button_text       = 0x0F1E30,
  text              = 0x0F1E30,
  text_disabled     = 0x7A7A7A,
  glass_tint        = 0x4A90E2,
  accent_cyan       = 0x76C4F0,
  success           = 0x6FCF97,
  error             = 0xE74C3C,
  warning           = 0xF2A93B,
}

-- Map theme colours to palette indices (0..15).
-- These MUST match color.AERO so chrome blits land on the right palette slot.
theme.SLOT = {
  -- Static
  WHITE          = 0,
  DESKTOP_BG_TOP = 1,
  GLASS_HI       = 2,
  WINDOW_BODY    = 3,
  WARNING_AMBER  = 4,
  TITLE_BAR_DARK = 5,   -- also TASKBAR
  MID_BLUE       = 6,
  TEXT_GRAY      = 7,
  WINDOW_BODY_DK = 8,
  ACCENT_CYAN    = 9,   -- also BUTTON_BASE
  BUTTON_HOVER   = 10,
  TITLE_BAR      = 11,  -- bright aero blue
  SUCCESS_GREEN  = 12,
  TITLE_INACTIVE = 13,
  DESKTOP_BG_BOT = 14,
  ERROR_RED      = 15,
  BLACK          = 15,
  -- Aliases used by older code:
  TASKBAR        = 5,
  TASKBAR_HI     = 9,
  BUTTON_PRESS   = 5,
  -- Aliases kept for back-compat with theme.COLORS names.
  -- (Render code should use theme.SLOT.X, not raw palette indices.)
}

-- Glyphs used to fake rounded corners and glossy edges in text mode.
-- All glyphs MUST be single-byte ASCII so term.blit's byte-count invariant
-- (text length == fg length == bg length) holds.
theme.GLYPHS = {
  -- rounded corners (use + for corners; full rounded box-drawing chars are
  -- multi-byte UTF-8 and would break term.blit)
  corner_tl = "+",
  corner_tr = "+",
  corner_bl = "+",
  corner_br = "+",
  -- horizontal / vertical lines
  hline      = "-",
  vline      = "|",
  -- glass / shade chars (frosted-glass translucency)
  -- These are single-byte ASCII substitutes for the multi-byte block chars.
  glass_25   = ".",
  glass_50   = ":",
  glass_75   = ";",
  glass_100  = "#",
  -- half blocks: CC's text mode normally has tall cells (each cell is
  -- ~2:1 height/width). The actual block chars ▀▄█ are multi-byte and
  -- would break blit. We use ASCII approximations instead.
  top_half   = "^",
  bot_half   = "_",
  full_block = "#",
  -- start orb (ASCII only)
  orb_full   = "O",
  orb_dot    = ".",
  orb_ring   = "o",
  -- window controls
  ctrl_close     = "x",
  ctrl_maximize  = "^",
  ctrl_minimize  = "_",
  -- checkboxes / radio
  check_on   = "X",
  check_off  = "[ ]",
  radio_on  = "(O)",
  radio_off = "( )",
}

return theme
