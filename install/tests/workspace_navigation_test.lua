-- Run from the repository root with Lua 5.4+ or a Lua runtime such as Lupa.
local bindings, calls, existing = {}, {}, {}
local current, namedTarget
local firstScreen, secondScreen = { name = "DP-1" }, { name = "HDMI-A-1" }

local function dispatcher(kind)
  return function(options) return { kind = kind, options = options } end
end

hl = {
  gesture = function() end,
  bind = function(key, callback)
    assert(not bindings[key], "duplicate shortcut: " .. key)
    bindings[key] = callback
  end,
  dsp = setmetatable({ window = setmetatable({}, { __index = function(_, key) return dispatcher(key) end }) },
    { __index = function(_, key) return dispatcher(key) end }),
  get_active_workspace = function() return current end,
  get_workspaces = function() return existing end,
  get_workspace = function(selector)
    assert(selector == "m+1" or selector == "m-1")
    return namedTarget
  end,
  dispatch = function(action) table.insert(calls, action) end,
}

local function workspace(id, monitor, special)
  return { id = id, monitor = monitor or firstScreen, special = special or false }
end

local function check(key, expected)
  calls = {}
  bindings[key]()
  if expected == nil then
    assert(#calls == 0, key .. " crossed the workspace boundary")
  else
    assert(#calls == 1 and calls[1].kind == "focus" and calls[1].options.workspace == expected,
      key .. " did not focus the expected space")
    assert(calls[1].options.on_current_monitor == nil, "must not move or swap workspaces")
  end
end

dofile("compositors/hyprland/config/keybinds.lua")
assert(#calls == 0, "loading the configuration must not create any workspaces")

current = workspace(1)
existing = { current }
check("SUPER + Right", 2)
check("SUPER + Left", nil)
check("SUPER + ALT + Right", 2)
assert(bindings["SUPER + ALT + H"].options.direction == "left")
assert(bindings["SUPER + ALT + L"].options.direction == "right")

existing = { current, workspace(7), workspace(4), workspace(3, firstScreen, true), workspace(2, secondScreen) }
check("SUPER + Right", 4)
current = existing[3]
check("SUPER + Left", 1)

current = workspace(8)
existing = { current }
check("SUPER + Right", nil)
existing[2] = workspace(12)
check("SUPER + Right", 12)

serpantinumWorkspaceSlots = { count = 3, monitors = {} }
current, existing = workspace(3), {}
check("SUPER + Right", nil)

serpantinumWorkspaceSlots = { count = 8, monitors = { ["DP-1"] = { first = 9, count = 3 },
                                                     ["HDMI-A-1"] = { first = 10, count = 1 } } }
current = workspace(9)
existing = { current, workspace(15) }
check("SUPER + Right", 11)
current = workspace(11)
check("SUPER + Right", nil)
check("SUPER + Left", 9)

current, namedTarget = workspace(nil), workspace(1)
check("SUPER + Left", namedTarget)
namedTarget = current
check("SUPER + Right", nil)

print("Workspace navigation passed: focus only, per-monitor rules, live spaces and lazy numbered slots")
