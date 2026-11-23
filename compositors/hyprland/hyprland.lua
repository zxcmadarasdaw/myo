require("config/variables")
require("config/env")
require("config/autostart")
require("config/monitors")
require("config/settings")
require("config/keybinds")
require("config/canvas")

local configHome = os.getenv("XDG_CONFIG_HOME")
if not configHome or configHome == "" then configHome = os.getenv("HOME") .. "/.config" end
local animationPath = configHome .. "/hypr/serpantinum-animations.lua"
serpantinumAnimationRevision = "default"
local animationFile = io.open(animationPath, "r")
if animationFile then
  animationFile:close()
  dofile(animationPath)
end
