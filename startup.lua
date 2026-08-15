--[[
  AeroOS · startup.lua

  This is the file CC:Tweaked runs on computer boot. It must live in the root
  of the computer's filesystem (or be referenced by /startup). We install
  aeroos to /aeroos/ and require() the boot module.

  If AeroOS is missing or broken, this falls back to the default CraftOS
  shell so you can debug.
]]

local ok, err = pcall(function()
  -- Add /aeroos to package.path so require("aeroros.*") works.
  local aeroos_root = "/aeroos"
  if fs.exists(aeroos_root) then
    package.path = package.path .. ";" .. aeroos_root .. "/?.lua"
                                  .. ";" .. aeroos_root .. "/?/init.lua"
  end

  local boot = require("aeroros.boot")
  boot.boot()
end)

if not ok then
  -- Fall back to default shell on error.
  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.red)
  print("AeroOS boot failed:")
  print(err)
  term.setTextColor(colors.white)
  print()
  print("Falling back to default CraftOS shell.")
  print()
  -- Run the default shell.
  if shell then
    shell.run("shell")
  end
end
