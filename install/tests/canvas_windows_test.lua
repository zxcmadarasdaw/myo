-- Run from the repository root with Lua 5.4+.
local screen = {name = "DP-1", x = -1920, y = 120, mode = {width = 1920, height = 1080}}
local adjacent = {name = "HDMI-A-1", x = 0, y = 0, mode = {width = 2560, height = 1440}}
local desk1, desk2 = {id = 1, visible = true}, {id = 2, visible = false}
local desk3 = {id = 3, visible = true}
local function window(address, x, y, monitor, workspace)
  return {address = address, at = {x = x, y = y}, size = {x = 800, y = 600},
          monitor = monitor, workspace = workspace, mapped = true, fullscreen = 0, floating = true, tags = {}}
end
local firefox = window("0x1", -1500, 220, screen, desk1)
local inactive = window("0x2", -1700, 250, screen, desk2)
local pinned = window("0x3", -1750, 220, screen, desk1)
local tiled = window("0x4", -1800, 250, screen, desk1)
local fullscreen = window("0x5", -1920, 120, screen, desk1)
local special = window("0x6", -1800, 220, screen, {id = -1, special = true})
local external = window("0x7", 1100, 250, adjacent, desk3)
pinned.pinned, tiled.floating, fullscreen.fullscreen = true, false, 1

local count = 0
local events = {}
local version = "0.56.2"
hl = {
  version = function() return version end,
  get_monitors = function() return {screen, adjacent} end,
  get_windows = function() return {firefox, inactive, pinned, tiled, fullscreen, special, external} end,
  on = function(name, callback)
    assert(name == "window.close" or name == "config.reloaded"
      or (name == "config.unload" and version == "0.57.0"), "unknown event " .. name)
    events[name] = callback
  end,
  dsp = {window = {
    move = function(args) return args end,
    tag = function(args) return args end,
  }},
  dispatch = function(args)
    if args.tag then
      local tags, value = args.window.tags, args.tag:sub(2)
      if args.tag:sub(1, 1) == "+" then
        tags[#tags + 1] = value
      else
        for index, current in ipairs(tags) do
          if current == value then
            table.remove(tags, index)
            break
          end
        end
      end
      return
    end
    assert(args.workspace == nil and args.relative == nil)
    args.window.at = {x = args.x, y = args.y}
    count = count + 1
  end,
}
dofile("compositors/hyprland/config/canvas.lua")

local function update(x, y, zoom, active, adjacentX)
  assert(serpantinumCanvasUpdate({
    [screen.name] = {x = x, y = y, zoom = zoom, active = active ~= false},
    [adjacent.name] = {x = adjacentX or 0, y = 0, zoom = 1, active = true},
  }) == "canvas-ok")
end
local function pos(w, x, y)
  assert(w.at.x == x and w.at.y == y, w.address .. " at " .. w.at.x .. "," .. w.at.y)
end

update(0, 0, 1)
assert(count == 0)
update(200, -25, 1, true, 200)
pos(firefox, -1700, 245)
pos(inactive, -1900, 275)
pos(external, 900, 250)
pos(pinned, -1750, 220)
pos(tiled, -1800, 250)
pos(fullscreen, -1920, 120)
pos(special, -1800, 220)
local moved = count
update(200, -25, 1, true, 200)
assert(count == moved)

-- Pan far in either direction; the offscreen position is beyond all monitors.
update(-3000, 0, 1)
assert(firefox.at.x > 2560 and firefox.at.y > 1440)
local parked = count
update(9000, 0, 1)
assert(count == parked)
desk1.visible, desk2.visible = false, true
update(0, 0, 1)
desk1.visible, desk2.visible = true, false
pos(firefox, -1500, 220)
pos(inactive, -1700, 250)
assert(firefox.workspace == desk1 and inactive.workspace == desk2)

-- Native move and resize, then pan and zoom. The top-left anchor changes
-- scale, and the real surface keeps the size supplied by Hyprland.
firefox.at, firefox.size = {x = -1380, y = 520}, {x = 650, y = 450}
update(200, 100, 2)
pos(firefox, -1240, 720)
assert(firefox.size.x == 650 and firefox.size.y == 450)
update(0, 0, 1)
pos(firefox, -1380, 520)
update(4000, 0, 1)
update(0, 0, 1, false)
pos(firefox, -1380, 520)
assert(#firefox.tags == 0)

-- The Lua VM disappears when the compositor config is reloaded.
update(0, 0, 1)
update(4000, 0, 1)
assert(#firefox.tags == 1)
inactive.at = {x = -1600, y = 320}
events = {}
serpantinumCanvasUpdate = nil
dofile("compositors/hyprland/config/canvas.lua")
assert(not events["config.unload"])
events["config.reloaded"]()
pos(firefox, -1380, 520)
pos(inactive, -1600, 320)
assert(#firefox.tags == 0 and #inactive.tags == 0)
assert(firefox.workspace == desk1 and inactive.workspace == desk2)

version = "0.57.0"
events = {}
dofile("compositors/hyprland/config/canvas.lua")
assert(not events["config.reloaded"])
update(0, 0, 1)
update(4000, 0, 1)
events["config.unload"]()
pos(firefox, -1380, 520)
events["window.close"](firefox)
firefox.at = {x = -1100, y = 400}
update(4000, 0, 1)
pos(firefox, -1100, 400)
print("Canvas window projection, offscreen/return, user geometry and workspace isolation: OK")
