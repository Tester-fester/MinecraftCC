--[[
  AeroOS · Installer

  Run this on a fresh CC:Tweaked computer (or turtle) to install AeroOS.
  It downloads the latest version from your repo and writes it to /aeroos/.

  Usage:
    wget <URL> /installer.lua
    /installer.lua

  By default it installs to /aeroos and adds /startup (this file's content
  is written to /startup.lua so CC boots into AeroOS next restart).
]]

local args = { ... }
local INSTALL_ROOT = args[1] or "/aeroos"
-- REPO_BASE: the raw GitHub URL where the AeroOS files live.
-- Default is the official Tester-fester/MinecraftCC repo.
-- Override by passing the URL as the second argument:
--   /installer.lua /aeroos https://raw.githubusercontent.com/YOURNAME/AeroOS/main
local DEFAULT_REPO = "https://raw.githubusercontent.com/Tester-fester/MinecraftCC/main"
local REPO_BASE = args[2] or DEFAULT_REPO

-- Sanity-check: warn if the URL still contains the old placeholder.
if REPO_BASE:find("yourname") then
  print("============================================================")
  print(" WARNING: installer URL still has the placeholder 'yourname'.")
  print("")
  print(" Pass your own repo URL as the 2nd argument:")
  print("   /installer.lua /aeroos https://raw.githubusercontent.com/YOURNAME/REPO/main")
  print("")
  print(" Or just press any key to try the default repo anyway:")
  print("   " .. DEFAULT_REPO)
  print("============================================================")
  os.pullEvent("char")
end

local FILES = {
  "startup.lua",
  "aeroros/boot.lua",
  -- kernel
  "aeroros/kernel/process.lua",
  "aeroros/kernel/scheduler.lua",
  "aeroros/kernel/event.lua",
  "aeroros/kernel/syscall.lua",
  "aeroros/kernel/debug.lua",
  -- graphics
  "aeroros/graphics/color.lua",
  "aeroros/graphics/combinator.lua",
  "aeroros/graphics/framebuffer.lua",
  "aeroros/graphics/renderer.lua",
  "aeroros/graphics/compositor.lua",
  -- window manager
  "aeroros/wm/theme.lua",
  "aeroros/wm/window.lua",
  "aeroros/wm/manager.lua",
  -- shell
  "aeroros/shell/desktop.lua",
  "aeroros/shell/dispatch.lua",
  "aeroros/shell/boot_anim.lua",
  "aeroros/shell/wallpaper.lua",
  "aeroros/shell/persistence.lua",
  -- widgets
  "aeroros/widgets/base.lua",
  "aeroros/widgets/button.lua",
  -- apps
  "aeroros/apps/terminal.lua",
  "aeroros/apps/explorer.lua",
  "aeroros/apps/editor.lua",
  "aeroros/apps/viewer.lua",
  "aeroros/apps/calculator.lua",
  "aeroros/apps/paint.lua",
  "aeroros/apps/settings.lua",
  "aeroros/apps/taskmgr.lua",
  "aeroros/apps/debug.lua",
  "aeroros/apps/about.lua",
}

local function ensure_dir(path)
  if not fs.exists(path) then
    fs.makeDir(path)
  elseif not fs.isDir(path) then
    error("Path exists and is not a directory: " .. path)
  end
end

local function download(rel)
  local url = REPO_BASE .. "/" .. rel
  local r = http.get(url)
  if not r then
    error("Failed to fetch: " .. url)
  end
  local body = r.readAll()
  r.close()
  return body
end

local function main()
  print("AeroOS installer")
  print("Install root: " .. INSTALL_ROOT)
  print()

  -- Make directory tree.
  local dirs = {
    INSTALL_ROOT,
    INSTALL_ROOT .. "/aeroros",
    INSTALL_ROOT .. "/aeroros/kernel",
    INSTALL_ROOT .. "/aeroros/graphics",
    INSTALL_ROOT .. "/aeroros/wm",
    INSTALL_ROOT .. "/aeroros/shell",
    INSTALL_ROOT .. "/aeroros/widgets",
    INSTALL_ROOT .. "/aeroros/apps",
  }
  for _, d in ipairs(dirs) do
    ensure_dir(d)
  end

  -- Download each file.
  for _, rel in ipairs(FILES) do
    local dst = fs.combine(INSTALL_ROOT, rel)
    -- Ensure parent dir exists.
    ensure_dir(fs.getDir(dst))
    io.write("  " .. rel .. " ... ")
    local body = download(rel)
    local f = fs.open(dst, "w")
    f.write(body)
    f.close()
    print("ok")
  end

  -- Write /startup.lua (or /aeroos/startup.lua and link).
  -- We write the canonical startup.lua content that loads AeroOS.
  local startup_body = [==[
-- AeroOS startup hook
local ok, err = pcall(function()
  local aeroos_root = "/aeroos"
  if fs.exists(aeroos_root) then
    package.path = package.path .. ";" .. aeroos_root .. "/?.lua"
                                  .. ";" .. aeroos_root .. "/?/init.lua"
  end
  require("aeroros.boot").boot()
end)
if not ok then
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.red)
  print("AeroOS boot failed:")
  print(err)
  term.setTextColor(colors.white)
  print("Falling back to default CraftOS shell.")
  if shell then shell.run("shell") end
end
]==]

  -- If install root is /aeroos, write startup.lua at root.
  local startup_dst = "/startup.lua"
  if fs.exists(startup_dst) then
    -- Rename old one so we don't blow it away.
    fs.move(startup_dst, "/startup.lua.bak")
  end
  local f = fs.open(startup_dst, "w")
  f.write(startup_body)
  f.close()

  print()
  print("AeroOS installed to " .. INSTALL_ROOT)
  print("Reboot the computer to start AeroOS.")
  print("(Restart with: ctrl+t then 'reboot')")
end

main()
