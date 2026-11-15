local mainMod = _G.mainMod or "SUPER"
local terminal = _G.terminal or "kitty"

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind(mainMod .. " + SHIFT + Left", hl.dsp.window.resize({ x = -50, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + Right", hl.dsp.window.resize({ x = 50, y = 0, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + Up", hl.dsp.window.resize({ x = 0, y = -50, relative = true }), { repeating = true })
hl.bind(mainMod .. " + SHIFT + Down", hl.dsp.window.resize({ x = 0, y = 50, relative = true }), { repeating = true })

hl.bind(mainMod .. " + CTRL + Left", hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + CTRL + Right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mainMod .. " + CTRL + Up", hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + CTRL + Down", hl.dsp.window.move({ direction = "d" }))

hl.bind(mainMod .. " + Up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + Down", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + ALT + H", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + ALT + L", hl.dsp.focus({ direction = "right" }))

local function stepWorkspace(direction)
  local current = hl.get_active_workspace()
  if not current or not current.monitor then return end
  if not current.id or current.id < 1 then
    local target = hl.get_workspace(direction > 0 and "m+1" or "m-1")
    if target and target ~= current then hl.dispatch(hl.dsp.focus({ workspace = target })) end
    return
  end

  local monitor = current.monitor.name
  local slots = _G.serpantinumWorkspaceSlots or { count = 8, monitors = {} }
  local block = slots.monitors[monitor]
  local first = block and block.first or 1
  local last = first + (block and block.count or slots.count) - 1
  local inside = current.id >= first and current.id <= last
  local nearest, beyond, occupied = nil, nil, {}
  for _, workspace in ipairs(hl.get_workspaces()) do
    local id = workspace.id
    if id and id > 0 and not workspace.special then
      occupied[id] = true
      if workspace.monitor and workspace.monitor.name == monitor and (id - current.id) * direction > 0 then
        if id >= first and id <= last then
          if not nearest or (id - nearest) * direction < 0 then nearest = id end
        elseif not beyond or (id - beyond) * direction < 0 then
          beyond = id
        end
      end
    end
  end

  -- Existing spaces take priority. Only materialize a numbered slot of the bar
  -- on demand, staying within the configured range and skipping other outputs.
  if not nearest and inside then
    for id = current.id + direction, direction > 0 and last or first, direction do
      local reserved = false
      for output, range in pairs(slots.monitors) do
        if output ~= monitor and id >= range.first and id < range.first + range.count then
          reserved = true
          break
        end
      end
      if not occupied[id] and not reserved then
        nearest = id
        break
      end
    end
  end
  local target = nearest or ((not block or not inside) and beyond)
  if target then hl.dispatch(hl.dsp.focus({ workspace = target })) end
end

local function previousWorkspace() stepWorkspace(-1) end
local function nextWorkspace() stepWorkspace(1) end
hl.bind(mainMod .. " + Left", previousWorkspace)
hl.bind(mainMod .. " + Right", nextWorkspace)
hl.bind(mainMod .. " + ALT + Left", previousWorkspace)
hl.bind(mainMod .. " + ALT + Right", nextWorkspace)

hl.bind(mainMod .. " + Q", hl.dsp.window.close())
-- Window states. Tiled / Floating / Fullscreen are separate:
--   Super+Z          Floating <-> previous maximized or tiled mode (70 % on first float)
--                    An extra shortcut such as Ctrl+Z can be enabled in Serpantinum settings.
--   Super+Shift+F    real fullscreen on/off (games, video)
--   Super+Alt+F      maximized: fills the work area, bar and gaps stay
--   Super+Alt+Z      pin a small window in a corner on every workspace (again: back to tiling)
--   Super+Shift+Z    minimize (Serpantinum keeps it in a hidden workspace; dock restores it)
--   Super+Ctrl+Z     restore the last minimized window
--   Super+LMB drag   move, Super+RMB drag   resize (top of this file)
-- The window commands run a script directly, not through the Quickshell IPC.
hl.bind(mainMod .. " + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("serpantinum window float --notify"), { description = "Serpantinum window: float" })
hl.bind(mainMod .. " + ALT + Z", hl.dsp.exec_cmd("serpantinum window pin --notify"), { description = "Serpantinum window: pin" })
hl.bind(mainMod .. " + SHIFT + Z", hl.dsp.exec_cmd("serpantinum window minimize --notify"), { description = "Serpantinum window: minimize" })
hl.bind(mainMod .. " + CTRL + Z", hl.dsp.exec_cmd("serpantinum window restore --notify"), { description = "Serpantinum window: restore" })

hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("serpantinum brightness lower"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("serpantinum brightness raise"), { locked = true })

hl.bind("Print", hl.dsp.exec_cmd("serpantinum screenshot"), { locked = true })
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("serpantinum screenshot --edit"), { locked = true })
hl.bind("SUPER + Print", hl.dsp.exec_cmd("serpantinum screenshot --full"), { locked = true })
hl.bind("SUPER + SHIFT + Print", hl.dsp.exec_cmd("serpantinum screenshot --full --edit"), { locked = true })

hl.bind("XF86PowerOff", hl.dsp.exec_cmd("serpantinum lock"), { locked = true })
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("serpantinum lock"), { repeating = true, locked = true })

hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("serpantinum volume mic-toggle"), { locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("serpantinum volume mute-toggle"), { locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("serpantinum volume lower"), { repeating = true, locked = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("serpantinum volume raise"), { repeating = true, locked = true })

hl.bind(mainMod .. " + F", hl.dsp.exec_cmd("firefox"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("ski"))
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))

hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("serpantinum reload"))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("serpantinum msg toggle clipboard"))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("serpantinum msg toggle processes"))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("serpantinum msg toggle launcher"))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("serpantinum msg toggle music"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("serpantinum msg toggle system"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("serpantinum msg toggle wallpaper"))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd("serpantinum msg toggle calendar"))
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("serpantinum msg toggle network"))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("serpantinum msg toggle volume"))
hl.bind(mainMod .. " + H", hl.dsp.exec_cmd("serpantinum msg toggle settings"))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("serpantinum msg bar autohide"))

for i = 1, 10 do
  local ws = tostring(i)
  local key = tostring(i % 10)
  hl.bind(mainMod .. " + " .. key, hl.dsp.exec_cmd("serpantinum msg workspace " .. ws))
  hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.exec_cmd("serpantinum msg workspace " .. ws .. " move"))
end

-- Recovery binds that work even when the shell is not running:
-- Super+Return opens a terminal (above), Super+Ctrl+R restarts the shell,
-- Super+Ctrl+Shift+Escape leaves the session.
hl.bind(mainMod .. " + CTRL + R", hl.dsp.exec_cmd("serpantinum restart"))
if hl.dsp.exit then
  hl.bind(mainMod .. " + CTRL + SHIFT + Escape", hl.dsp.exit())
end
