hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")

-- Keybinds call `serpantinum ...`, which the installer links into ~/.local/bin.
-- Sessions started from a display manager may not have it in PATH.
if os and os.getenv then
  local home = os.getenv("HOME")
  local path = os.getenv("PATH") or "/usr/local/bin:/usr/bin:/bin"
  if home and not string.find(":" .. path .. ":", ":" .. home .. "/.local/bin:", 1, true) then
    hl.env("PATH", home .. "/.local/bin:" .. path)
  end
end
