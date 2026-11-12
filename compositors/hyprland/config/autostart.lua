hl.on("hyprland.start", function()
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
  -- ~/.local/bin is not always in PATH of a session started by a display
  -- manager; fall back to the path the installer links the daemon to.
  hl.exec_cmd('if command -v serpantinumd >/dev/null 2>&1; then exec serpantinumd start; else exec "$HOME/.local/bin/serpantinumd" start; fi')
end)
