#!/usr/bin/env bash

# Keep using data created by older versions when only the legacy copy exists.
serpantinum_state_dir() {
    local current="${XDG_STATE_HOME:-$HOME/.local/state}/serpantinum"
    local legacy="$HOME/.local/state/serpantinum"
    if [ ! -e "$current/version" ] && [ -f "$legacy/version" ]; then
        current="$legacy"
    fi
    printf '%s\n' "$current"
}

serpantinum_settings_path() {
    local current="${XDG_CONFIG_HOME:-$HOME/.config}/serpantinum/settings.json"
    local legacy="$HOME/.config/serpantinum/settings.json"
    if [[ ! -e "$current" && ! -L "$current" ]] && [[ -e "$legacy" || -L "$legacy" ]]; then
        current="$legacy"
    fi
    printf '%s\n' "$current"
}
