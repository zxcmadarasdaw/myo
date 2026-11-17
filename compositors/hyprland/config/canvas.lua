-- All positions returned by the window API are logical desktop coordinates.
-- Keep the last compositor goal so a user move can be distinguished from a
-- camera move without polling or taking over Hyprland's pointer grabs.
local windows = {}
local cameras = {}

local function eligible(window)
  return window.mapped and not window.hidden and window.floating and not window.pinned
    and window.fullscreen == 0 and window.workspace and not window.workspace.special
end

local function move(window, x, y)
  return hl.dispatch(hl.dsp.window.move({window = window, x = x, y = y}))
end

local function tag(window, value)
  return hl.dispatch(hl.dsp.window.tag({window = window, tag = value}))
end

local function intersects(x, y, size, output)
  return x < output.x + output.w and x + size.x > output.x
    and y < output.y + output.h and y + size.y > output.y
end

local function project(record, camera, output, size, parking)
  local x = output.x + math.floor((record.x - camera.x) * camera.zoom + 0.5)
  local y = output.y + math.floor((record.y - camera.y) * camera.zoom + 0.5)
  if intersects(x, y, size, output) then return x, y, false end
  return parking.x, parking.y, true
end

function _G.serpantinumCanvasUpdate(views)
  local outputs = {}
  local parking = {x = 0, y = 0}
  for _, monitor in ipairs(hl.get_monitors()) do
    local mode = monitor.mode -- logical dimensions after scale/transform
    outputs[monitor.name] = {x = monitor.x, y = monitor.y, w = mode.width, h = mode.height}
    parking.x = math.max(parking.x, monitor.x + mode.width)
    parking.y = math.max(parking.y, monitor.y + mode.height)
  end
  -- A fully offscreen window must not land on a neighbouring output.
  -- Keep the destination bounded regardless of how far the camera travels.
  parking.x, parking.y = parking.x + 2048, parking.y + 2048

  for _, window in ipairs(hl.get_windows()) do
    local monitor = window.monitor
    local name = monitor and monitor.name
    local camera, output = views[name], outputs[name]
    if camera and output and eligible(window) then
      local at, size = window.at, window.size
      local id = window.address
      local record = windows[id]
      local previousTag = record and record.parkingTag
      local sameOutput = record and record.output == name
      local moved = sameOutput and (at.x ~= record.appliedX or at.y ~= record.appliedY)
        and (at.x - output.x ~= record.appliedX - record.outputX or at.y - output.y ~= record.appliedY - record.outputY)

      if not sameOutput or (moved and (not record.parked or intersects(at.x, at.y, size, output))) then
        local previous = cameras[name] or camera
        record = {
          x = (at.x - output.x) / previous.zoom + previous.x,
          y = (at.y - output.y) / previous.zoom + previous.y,
          output = name, appliedX = at.x, appliedY = at.y,
          outputX = output.x, outputY = output.y,
          visibleX = at.x - output.x, visibleY = at.y - output.y,
        }
        windows[id] = record
      end

      if camera.active then
        local x, y, parked = project(record, camera, output, size, parking)
        -- Manual window tags survive a config reload, even when the Lua VM
        -- and its tables are replaced. Record the destination before parking.
        local parkingTag = parked and ("serpantinum-canvas-park:%s:%s:%s:%s:%s"):format(
          x, y, record.visibleX, record.visibleY, name) or nil
        if parkingTag and parkingTag ~= previousTag then tag(window, "+" .. parkingTag) end
        if x ~= at.x or y ~= at.y then
          move(window, x, y)
        end
        local actual = window.at
        record.appliedX, record.appliedY = actual.x, actual.y
        record.outputX, record.outputY = output.x, output.y
        record.parked = parked and actual.x == x and actual.y == y
        record.parkingTag = record.parked and parkingTag or nil
        if previousTag and previousTag ~= record.parkingTag then tag(window, "-" .. previousTag) end
        if parkingTag and parkingTag ~= previousTag and not record.parked then
          tag(window, "-" .. parkingTag)
        end
        if intersects(actual.x, actual.y, size, output) then
          record.visibleX, record.visibleY = actual.x - output.x, actual.y - output.y
        end
      elseif sameOutput and cameras[name] and cameras[name].active then
        -- Disabling the canvas always leaves the real window reachable.
        local x, y, parked = project(record, camera, output, size, parking)
        if parked then x, y = output.x + record.visibleX, output.y + record.visibleY end
        if x ~= at.x or y ~= at.y then move(window, x, y) end
        if record.parkingTag then tag(window, "-" .. record.parkingTag) end
        windows[id] = nil
      else
        if previousTag then tag(window, "-" .. previousTag) end
        windows[id] = nil
      end
    end
  end
  cameras = views
  return "canvas-ok"
end

hl.on("window.close", function(window)
  if window.address then windows[window.address] = nil end
end)
-- Window tags retain the restore coordinates across Lua state replacement.
-- The post-reload event is available from Hyprland 0.55 onward.
hl.on("config.reloaded", function()
  for _, window in ipairs(hl.get_windows()) do
    for _, value in ipairs(window.tags) do
      local x, y, visibleX, visibleY, output = value:match(
        "^serpantinum%-canvas%-park:([^:]+):([^:]+):([^:]+):([^:]+):(.+)$")
      if output then
        local monitor, at = window.monitor, window.at
        visibleX, visibleY = tonumber(visibleX), tonumber(visibleY)
        if visibleX and visibleY and monitor and monitor.name == output and eligible(window)
            and at.x == tonumber(x) and at.y == tonumber(y) then
          move(window, monitor.x + visibleX, monitor.y + visibleY)
          windows[window.address] = nil
        end
        tag(window, "-" .. value)
      end
    end
  end
end)
