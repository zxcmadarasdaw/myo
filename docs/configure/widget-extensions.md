---
sidebar_position: 5
title: Network, File Dock, Terminal and Process Explorer
sidebar_label: Widget extensions
slug: /configure/widget-extensions
---

# Network, File Dock, Terminal and Process Explorer

Four additions to the existing widget system. Nothing changes until you add one of them: the original network indicator, all existing widgets and their settings stay exactly as they were.

## Network Monitor Pro

**Desktop widget.** In the widget editor pick **Network** and one of the variants: *Original*, *Minimal Speed*, *Glass Network*, *Live Graph*, *Cyber Network*, *Compact Panel*.

Settings: interface (*Auto* follows the default route), refresh interval, totals (Glass), latency and ping host (Glass, Graph, Cyber).

**Bar.** The bar's Wi-Fi module has a new style **Speed**: the same button with live download/upload speed. The default style (*Button*) is unchanged.

One shared sampler reads `/proc/net/dev` (and `/proc/net/route` for the default interface) only while a network widget or the Speed style is visible. Latency is off by default; when enabled, `ping -c 1` runs against the chosen host (default `1.1.1.1`) only while such a widget is visible.

## File Dock

Add **File Dock** in the widget editor. Variants: *Floating Glass*, *Minimal Icons*, *Folder Stack*, *Expandable Dock*, *Grid*, *Cyber Files*. Each dock has its own items.

- Widget settings → **File** / **Folder** → pick → **Pin**; or drop files from the file manager onto the dock.
- Double click opens the item with its default application, folders in the default file manager (`xdg-open`).
- Press and hold an item, then drag, to reorder; or use the arrows in **Items** in the settings.
- Removing an item removes only the shortcut. Files are never deleted, moved or renamed; drops are accepted as links.

## Desktop Terminal

Add **Terminal** in the widget editor. Variants: *Transparent*, *Glass Terminal*, *Cyber Terminal*, *Minimal*, *Console Card*.

A real terminal: bash or zsh runs on a pseudo-terminal through `scripts/system/serp_pty.py`, with colours (16/256/true colour), scrollback (wheel, Shift+PageUp/PageDown), selection, copy **Ctrl+Shift+C**, paste **Ctrl+Shift+V** / Shift+Insert / middle click, full-screen programs (vim, htop, less), resize with the widget, several terminals at once.

**Keyboard.** Click the terminal to type into it. It gives the keyboard back as soon as another window is focused and never takes it on its own.

**Modes:** *Interactive*, *Fastfetch*, *CMatrix*, *CAVA*, *Command monitor* (runs *Command* every N seconds). A missing program is reported together with the `dnf install` command; cmatrix and cava are optional and not installed by the installer.

**Commands are never run without your approval.** A start or monitor command runs only after you typed it in the widget settings on this computer or pressed *Run once* / *Always allow* in the widget. Approvals live in `$XDG_STATE_HOME/serpantinum/terminal/trusted.json`. Layouts, presets and Themess packages cannot pre-approve a command.

Other settings: shell, monospace font, size, colours (Theme, Classic, Matrix, Cyber, Amber), background opacity, radius, appear animation, **Paused** (stops the process).

Terminals are not available on the lock screen; previews in the widget picker show a static sample and start nothing.

### Fastfetch Media

1. Add a **Terminal** widget and set **Mode → Fastfetch** in its widget settings.
2. Open **Super + H → Display → Widgets → Terminal · Fastfetch Media**. Choose a local file, turn on **Use custom media instead of distro logo**, and open **Preview** to see the layout with live Fastfetch data.
3. Choose one of the six themes, then adjust the layout, media dimensions, alignment, zoom, opacity, corner radius and playback. Wider layouts switch to vertical when the widget is narrow. Minimal displays OS, CPU, GPU and memory. The other layouts also include kernel, uptime, disks, shell, WM and terminal.

The editor accepts PNG, JPEG, GIF, WebP and local video containers including MP4 and WebM. Actual codec and animated WebP support come from Qt. The optional animated-image frame limit caps how often the image is drawn on the GPU. GIF and WebP decoding still follows source timing and playback speed. GPU safe mode, performance mode and the recording-light profile suppress video and pause animated images.

Video sound is opt-in. One visible terminal owns the media audio output at a time. Enable **Allow mixing with wallpaper audio** to hear both together. Hidden widgets release their audio output, and the pause setting also suspends playback while hidden. A failed or missing file restores standard Fastfetch. The standalone `fastfetch` command and its config still work from interactive terminals.

Themess packages can include a `fastfetch.json`, for example `{"appearance":{"theme":"glass_noir","layout":"floating","width":48,"opacity":0.9}}`. The package carries appearance settings. The local media path, enable switch, playback and audio preferences stay in the user's settings.

On Fedora, test a local MP4 and a GIF in the preview and on the desktop. Resize the widget, hide it, switch workspaces, lock and unlock, and restart Quickshell. Play a video with audio while wallpaper audio is active and check both positions of the mixing control. In Interactive mode, type a command, select output with the mouse, and paste text to confirm focus still works.

## Process Explorer

Press **Super+Shift+P** (Hyprland, Sway, MangoWC) or run `serpantinum msg toggle processes`. Close with **Esc**, the same hotkey, the close button or a click outside.

- Header: CPU, RAM, GPU (amdgpu, recent Intel, or `nvidia-smi`; otherwise "not reported"), process count, busiest process.
- Search by name, command or PID (just type); sort by CPU, memory, name, PID; ↑/↓, Ctrl+R to refresh.
- Details: user, threads, state, start time, executable, command line, **Open file location**.
- **End process…** asks first, then sends SIGTERM (*End*) or SIGKILL (*Force*) with `kill`. Offered only for your own processes and never for the shell itself; Linux permissions are not bypassed.

The panel and its sampler exist only while it is open: no CPU cost and no keyboard grab when closed.

Settings (Super+H) → General, *Process Explorer* rows: hotkey (Hyprland; applied to the running session with `hyprctl`, your Hyprland files are not edited), material (*Standard*, *Liquid Glass*, *Mica*, *Neon Glass*), refresh interval.

## Restrained and Lush looks

Every widget type has two more variants in the widget editor. They only change the look; the data, settings and actions are the same as the type's other variants, and the existing variants are unchanged.

- **Restrained** — 1 px hairlines, no shadows or gradients, light type, radius of at most 3 px, muted theme colours, a short fade (OutCubic) when it appears and no movement.
- **Lush** — layered gradient glass (with the wallpaper blur when the GPU profile allows it), a soft halo, thin corner ornaments, glowing display type, accent colours of the theme; it fades in and settles with OutCubic/OutQuint, never overshooting.

All colours come from the current theme (`ThemeBackend`), so both looks follow dark and light themes; on light themes the glow is darker and weaker so it stays visible.

| Widget | Restrained key | Lush key |
|---|---|---|
| Visualizer | `minimal` | `lush` |
| Clock | `clockMinimal` (`minimal` is the existing Minimal clock) | `lush` |
| Music | `musicMinimal` (`minimal` exists) | `lush` |
| Weather, Picture, User, CPU, RAM, Temperature, Disk, Battery, GitHub, Notes, Timer, Text | `minimal` | `lush` |
| Network | `networkMinimal` (`minimal` is *Minimal Speed*) | `lush` |
| File Dock | `filedockMinimal` (`minimal` is *Minimal Icons*) | `lush` |
| Terminal | `terminalMinimal` (`minimal` exists) | `lush` |

Notes on behaviour:
- **Timer** shows the mode that is active in the quick-actions timer (timer, stopwatch, pomodoro); the mode names on top switch it.
- **Notes** lists the quick-actions notes (pinned first); a click opens the notes panel. Editing stays in the panel.
- **User**: sleep, reboot and power off must be held until the button fills; a short click does nothing.
- **File Dock** and **Terminal** keep the same safety rules as above (shortcuts only, `xdg-open` with the path as one argument; commands only after approval; previews start nothing).
- Network: latency/ping host work in both looks, totals in *Lush*. File Dock: labels and background opacity work in both looks.

The shared pieces live in `src/quickshell/widgets/faces/common/` (`MinimalCard`, `LushCard`, `LushOrnament`, `LushGlowText`, `FaceRing`, `FaceButton`, `HoldAction`, the appear animations, `FaceTone` for theme-derived colours).

## Updating without losing settings

Update as usual: `git pull` in your Serpantinum checkout, then run the installer again (`serpantinum updates` tells you when a new version exists). Settings, layouts and widget properties live in your config/state directories and are kept. Updates do not overwrite compositor configuration, so on Hyprland the shell checks at startup whether a key already opens the Process Explorer and binds the configured one for the running session if not. On Sway and MangoWC with an older keybinds file, add the line yourself:

```
# sway
bindsym $mod+Shift+P exec serpantinum msg toggle processes
# mango
bind=SUPER+SHIFT,P,spawn,serpantinum msg toggle processes
```

## Manual test checklist (Fedora + Hyprland)

Automated tests (`install/tests/`) cover the logic offscreen; these need a real Wayland session.

**Regression**
- [ ] Shell starts without QML errors (no "is not a type").
- [ ] Bar Wi-Fi module unchanged with the default *Button* style.
- [ ] Clock, Weather (animations), CPU/RAM/Temp/Disk/Battery, Notes, Timer, Picture, Visualizer widgets render and can be edited.
- [ ] Music widget and the slide-out music panel work.
- [ ] Wallpapers: static, GIF, video, transitions, two monitors.
- [ ] Super+H settings open; Themess gallery previews and applies a package.
- [ ] Lock screen: existing lock layouts unchanged; Terminal is not offered.

**Network**
- [ ] All 6 variants show plausible speeds during a download (compare with `nload`).
- [ ] Wired + Wi-Fi: *Auto* follows the default route; SSID on Wi-Fi.
- [ ] `pgrep ping` is empty while latency is off.
- [ ] Bar *Speed* style works; switching back to *Button* restores the old look.

**File Dock**
- [ ] Pin a file and a folder; drag a file from Nautilus/Dolphin — the original stays in place.
- [ ] Double click opens files and folders; paths with spaces and non-ASCII names work.
- [ ] Reorder, remove, restart the shell: items persist; the removed file still exists on disk.
- [ ] Two docks keep separate items; all variants look right in light and dark themes.

**Terminal**
- [ ] bash and zsh: colours, `vim`, `htop`, `less`, `fastfetch`, Ctrl+C, Tab, history.
- [ ] Resize the widget: `stty size` follows; `vim` redraws.
- [ ] Copy/paste both ways with other apps; bracketed paste in bash.
- [ ] Clicking another window takes the keyboard away from the terminal.
- [ ] Fastfetch, CMatrix, CAVA with and without the program installed; monitor with `uptime` every 2 s.
- [ ] A command written into `layout.json` by hand shows the approval prompt.
- [ ] *Paused* and removing the widget stop the process (`pgrep -f serp_pty`).
- [ ] Two terminals on two monitors.

**Restrained / Lush**
- [ ] Every widget type offers both looks in the editor; switching back restores the previous variant's look.
- [ ] Each look on a dark and a light theme, at the smallest and a large size: no clipped text, glow visible on light themes.
- [ ] Lush with blur on and off (GPU profile); no stutter while several Lush widgets are on screen.
- [ ] User: hold sleep/reboot/poweroff — a short click does nothing.

**Process Explorer**
- [ ] Super+Shift+P opens on the focused monitor; Esc / hotkey / outside click closes; keyboard free afterwards.
- [ ] Numbers roughly match `htop`; GPU shown or "not reported".
- [ ] `sleep 1000 &`: confirmation, *End* works; root processes cannot be ended.
- [ ] Open file location opens the executable's folder.
- [ ] Change the hotkey in Settings: works at once and after a shell restart; the old key no longer opens it.
- [ ] All four materials with blur on/off, light and dark.
