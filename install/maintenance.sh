#!/usr/bin/env bash

set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$root/src/scripts/xdg_paths.sh"

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
backup_home="${XDG_DATA_HOME:-$HOME/.local/share}/serpantinum-backups"
app_dir="$HOME/.local/share/serpantinum"

declare -A snapshot_paths=(
    [settings]="$config_home/serpantinum"
    [state]="$state_home/serpantinum"
    [hypr]="$config_home/hypr"
    [niri]="$config_home/niri"
    [sway]="$config_home/sway"
    [mango]="$config_home/mango"
    [kitty]="$config_home/kitty"
)

if [ "$config_home" != "$HOME/.config" ]; then
    snapshot_paths[legacy-settings]="$HOME/.config/serpantinum"
    snapshot_paths[legacy-hypr]="$HOME/.config/hypr"
fi
if [ "$state_home" != "$HOME/.local/state" ]; then
    snapshot_paths[legacy-state]="$HOME/.local/state/serpantinum"
fi

exists() { [ -e "$1" ] || [ -L "$1" ]; }

lock_installation() {
    local state
    state="$(serpantinum_state_dir)"
    mkdir -p -- "${state%/*}"
    exec 9>"${state%/*}/.serpantinum-install.lock"
    if ! flock -n 9; then
        echo "An installation or maintenance operation is already running." >&2
        return 1
    fi
}

make_snapshot() {
    local snapshot key path
    mkdir -p -- "$backup_home"
    snapshot="$(mktemp -d -- "$backup_home/snapshot_XXXXXX")"
    for key in "${!snapshot_paths[@]}"; do
        path="${snapshot_paths[$key]}"
        exists "$path" || continue
        if [[ "$(realpath -m -- "$snapshot")/" == "$(realpath -m -- "$path")/"* ]]; then
            echo "Backup directory is inside $path. Set XDG_DATA_HOME to a separate location." >&2
            return 1
        fi
        cp -a -- "$path" "$snapshot/$key" || return 1
    done
    printf 'serpantinum-snapshot-v1\n' > "$snapshot/.format"
    printf '%s\n' "$snapshot"
}

restore_snapshot() {
    local snapshot="$1" before key target work
    if [ ! -f "$snapshot/.format" ] || [ "$(cat "$snapshot/.format")" != serpantinum-snapshot-v1 ]; then
        echo "Choose a completed snapshot created by this script." >&2
        return 1
    fi
    snapshot="$(realpath -- "$snapshot")"
    for target in "${snapshot_paths[@]}"; do
        if [[ "$snapshot/" == "$(realpath -m -- "$target")/"* ]]; then
            echo "Move the snapshot outside $target before restore." >&2
            return 1
        fi
    done
    before="$(make_snapshot)"
    printf 'Backup before restore: %s\n' "$before"
    for key in "${!snapshot_paths[@]}"; do
        exists "$snapshot/$key" || continue
        target="${snapshot_paths[$key]}"
        mkdir -p -- "${target%/*}"
        work="$(mktemp -d -- "${target%/*}/.serpantinum-restore.XXXXXX")"
        cp -a -- "$snapshot/$key" "$work/replacement"
        if exists "$target"; then
            mv -T -- "$target" "$work/previous"
        fi
        if ! mv -T -- "$work/replacement" "$target"; then
            if exists "$work/previous"; then mv -T -- "$work/previous" "$target"; fi
            echo "Restore stopped at $target. Full pre-restore backup: $before" >&2
            return 1
        fi
        rm -rf -- "$work"
    done
}

archive_installation() {
    local archive entry link
    if [ ! -d "$app_dir/src" ] && [ ! -d "$app_dir/bin" ]; then
        echo "No shell installation found in $app_dir."
        return 0
    fi
    mkdir -p -- "$backup_home"
    archive="$(mktemp -d -- "$backup_home/program_XXXXXX")"
    printf 'Program archive: %s\n' "$archive"
    for entry in bin src; do
        if exists "$app_dir/$entry"; then mv -T -- "$app_dir/$entry" "$archive/$entry"; fi
    done
    for entry in serpantinum serpantinumd; do
        link="$HOME/.local/bin/$entry"
        if [[ -L "$link" && "$(readlink -- "$link")" = "$app_dir/bin/$entry" ]]; then
            rm -- "$link"
        fi
    done
    echo "User settings and data are in their original locations."
}

if [ "$EUID" -eq 0 ]; then
    echo "Run maintenance as your desktop user." >&2
    exit 1
fi
umask 077
case "${1:-}" in
    check)
        source "$root/install/install.sh"
        detect_install_platform /etc/os-release "$(uname -m)"
        source "$root/install/modules/pm.sh"
        source "$root/install/modules/deps.sh"
        printf 'Distribution: %s %s\nPackage manager: %s\n' "$DISTRO_ID" "$DISTRO_VERSION" "$PM_NAME"
        missing="$(pm_missing_pkgs "${REQUIRED_PKGS[@]}" "${PM_EXTRA_PKGS[@]}")"
        printf 'Missing dependencies:\n%s\n' "${missing:-none}"
        QS_SETTINGS="$(serpantinum_settings_path)" QS_STATE_DIR="$(serpantinum_state_dir)" \
            python3 "$root/src/scripts/system/serp_diag.py" summary
        ;;
    backup)
        lock_installation
        make_snapshot
        ;;
    restore)
        [ "$#" = 2 ] || { echo "Usage: $0 restore SNAPSHOT_DIRECTORY" >&2; exit 2; }
        lock_installation
        restore_snapshot "$2"
        ;;
    uninstall)
        lock_installation
        archive_installation
        ;;
    *)
        echo "Usage: $0 {check|backup|restore SNAPSHOT_DIRECTORY|uninstall}" >&2
        exit 2
        ;;
esac
