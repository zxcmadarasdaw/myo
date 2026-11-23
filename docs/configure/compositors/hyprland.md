---
sidebar_position: 1
title: Hyprland
sidebar_label: Hyprland
slug: /configure/compositors/hyprland
---

# Hyprland

Configuration is stored in `~/.config/hypr`. The main file is `hyprland.lua`, which loads modules from the `config/` directory:

- `variables.lua` - modifier keys and default applications
- `env.lua` - environment variables
- `autostart.lua` - startup processes
- `monitors.lua` - display and resolution setup
- `settings.lua` - window decorations, blur, animations, and input
- `keybinds.lua` - keybindings for compositor actions and shell controls
- `canvas.lua` - projects real floating windows onto the Infinite Canvas

## Window animations

Open **Settings → Animations** with **Super+H**, or run
`serpantinum settings animations`. Opening and closing have separate
styles, durations and easing. Moving and resizing share Hyprland's
`windowsMove` setting. **Move and resize** also has separate switches for
animation during manual resizing and dragging with the mouse.

To set a rule for Firefox, a terminal or a file manager, open the app and
select it under **Application rules → Open windows**. This fills in the
class reported by Hyprland, which can vary by package. Rules apply one
style to both opening and closing, or disable all animations for that
window. Switching presets preserves the rules. **Restore defaults**
clears the profile and its rules.

**Apply** saves the profile to
`${XDG_CONFIG_HOME:-~/.config}/hypr/serpantinum-animations.lua` and reloads
Hyprland. The supplied `hyprland.lua` loads the file again at startup.
If you maintain your own `hyprland.lua`, copy the animation loader from the
[shipped configuration](../../../compositors/hyprland/hyprland.lua) after
your window and animation settings, then run `hyprctl reload`.

## Floating windows on the Infinite Canvas

With Hyprland 0.57.1 and the Lua configuration, use **Super+Z** to float an
app and move or resize it using Hyprland's regular controls. When you pan,
the window moves with the widgets and returns to the same world position
when the camera returns. A manual move is picked up before the next pan.
The compositor keeps each window on its own workspace.

Zoom changes the position of the top-left anchor. Hyprland and the client
continue to determine the surface size and handle input. The shell batches
camera updates at intervals of at least 45 ms. Fully offscreen windows are
placed beyond every output until their anchor and surface intersect their
own output again. Hyprland can draw a partially overlapping surface on an
adjacent monitor while it crosses the edge. Display and movement also use
Hyprland's configured animations. Keep `misc.float_force_onscreen` at its
default `0` for offscreen movement.

On config reload, parked windows return to their last visible positions.
If keeping a customized `hyprland.lua`, add `require("config/canvas")` after
the existing modules. Run `hyprctl reload` and check `hyprctl configerrors`.

## Autostart

The shell daemon and clipboard history are launched from `config/autostart.lua`:

```lua
hl.on("hyprland.start", function()
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
  hl.exec_cmd("serpantinumd start")
end)
```

`serpantinumd start` also starts the [audio engine](/audio).

## Keybindings

Shell overlays and controls are bound in `config/keybinds.lua` using `serpantinum msg toggle <module>`:

- `launcher` - application launcher
- `system` - system control panel
- `clipboard` - clipboard history
- `music` - media player
- `wallpaper` - wallpaper selector
- `calendar` - calendar popout
- `network` - wi-fi and network connections
- `volume` - audio output and input slider
- `settings` - cheat sheet for keybindings

`Super+Right` and `Super+Left` switch to the next and previous workspace on the focused monitor. Hyprland prefers the nearest existing numbered workspace within the range shown by the bar. If none exists in that direction, the shortcut can open an empty slot within that range. The default range is 1–8. Set the number of slots and optional per-monitor numbering in the bar's workspace settings.

The bar follows the active workspace reported by Hyprland for its own monitor. Its workspace buttons still switch directly to the selected number. `Super+Alt+Left/Right` also switches workspaces, and `Super+Alt+H/L` moves window focus horizontally. Regular floating windows stay on their own workspace when switching.

The numbered shortcuts use the shell's workspace commands:

```lua
for i = 1, 10 do
  hl.bind("SUPER + " .. (i % 10), hl.dsp.exec_cmd("serpantinum msg workspace " .. i))
  hl.bind("SUPER + SHIFT + " .. (i % 10), hl.dsp.exec_cmd("serpantinum msg workspace " .. i .. " move"))
end
```

Quick utility actions:
- Lock screen: `serpantinum lock`
- Reload shell: `serpantinum reload`
- Bar autohide: `serpantinum msg bar autohide`
- Screenshots: `serpantinum screenshot` (add `--edit`, `--full`, or `--full --edit`)
- Brightness: `serpantinum brightness lower` and `serpantinum brightness raise`
- Volume: `serpantinum volume lower`, `serpantinum volume raise`, and `serpantinum volume mute-toggle`
