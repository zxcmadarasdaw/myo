# Mochi Night and ERROR//OVERDRIVE

Two Themess packages on one video wallpaper: the anime girl with blue-grey hair among retro
error windows (source: `animmmmm/`, left untouched). No glass, mica or blur in either theme.

Both packages name their media as `@shared/error-girl/...`, so the library keeps a single
copy in `themess/.shared/error-girl/`:

| File | Used by | Format |
| --- | --- | --- |
| `error-girl.webm` | wallpaper of both themes | VP9 + Opus, 1280x720, 5.2 s loop, with sound |
| `fastfetch-girl.webm` | Fastfetch Media of ERROR//OVERDRIVE | VP9, 480x640 crop of the face, no sound |

The clips are WebM on purpose: Fedora's stock `ffmpeg-free` (and Qt Multimedia on top of it)
cannot decode H.264 High profile, so an MP4 makes Themess reject the package with a decode
error and the wallpaper would not play.

## Mochi Night

Graphite matte surfaces, soft pink and lavender, thin solid top bar. Atelier widgets only:

| Widget | Style | Place (2560x1440) |
| --- | --- | --- |
| Clock + date | Elegant | top left |
| Weather (animated scene) | Minimal | top left, under the clock |
| Music player | Matte | bottom left |
| Visualizer (only while music plays) | Minimal | bottom left, above the player |
| CPU, RAM | Compact | top right |
| Network | Compact | top right |

## ERROR//OVERDRIVE

Near-black with hot pink and ice blue, modular top bar with pills, workspaces, media and sysmon.

| Widget | Style | Place |
| --- | --- | --- |
| Clock | Editorial | top left |
| Month calendar | Retro | left |
| Weather (animated scene) | Technical | left |
| Terminal: Fastfetch, then your shell | Retro | bottom left |
| Music player with visualizer | Premium | top right |
| Spectrum | Retro | right |
| CPU, GPU | Technical | right |
| RAM, Disk | Retro | right |
| Network with totals | Technical | bottom right |

The terminal runs in `fetchShell` mode: Fastfetch runs once (`--logo none`, modules OS, Kernel,
Uptime, Packages, CPU, GPU, Memory, Disk, Display, Shell, WM, Terminal), then your shell starts
on the same PTY, so you can type commands. The Fedora logo is replaced by the looping clip of
the girl, drawn by Qt Multimedia inside the same terminal card; it pauses while the terminal
is hidden.

Widgets keep to the left (x < 750) and right (x > 1860) parts of the screen, so the face stays clear.

## Applying

1. `Super + H` -> **Themess** -> **Refresh**.
2. Select **Mochi Night** or **ERROR//OVERDRIVE**: the preview lists every change.
3. **Apply** (or close the confirmation to cancel). Wallpaper, widgets, bar, colours, terminal
   and Fastfetch Media are set together. The current widgets are saved first:
   **Restore Previous** brings them back, **Restore Original** returns to the state before Themess.

## Changing the girl in the terminal

Settings -> Display -> Widgets -> **Fastfetch Media**: pick any PNG, JPG, WebP, GIF, MP4 or
WebM, and set size, zoom, position, speed, loop, opacity, autoplay and pause-when-hidden.
Applying the theme again restores the bundled clip.

## Workspaces

The bar's workspace pills switch real Hyprland workspaces. `Super + Left/Right` already move
focus between windows, so previous/next workspace is `Super + Alt + Left/Right`.
