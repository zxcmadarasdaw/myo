#!/usr/bin/env bash

get_compositor_config_dir_name() {
    local comp="$1"
    case "$comp" in
        hyprland) echo "hypr" ;;
        niri) echo "niri" ;;
        sway) echo "sway" ;;
        *) echo "$comp" ;;
    esac
}

migrate_legacy() {
    pkill -f "settings_watcher.sh" 2>/dev/null || true
    pkill -f "hypr/scripts/quickshell" 2>/dev/null || true

    if [ -f "$HOME/.local/state/imperative-dots-version" ]; then
        local backup
        backup="$(create_config_backup_dir "${XDG_CONFIG_HOME:-$HOME/.config}/hypr_backup" legacy)" || return 1
        mv "$HOME/.local/state/imperative-dots-version" "$backup/"
    fi
}
