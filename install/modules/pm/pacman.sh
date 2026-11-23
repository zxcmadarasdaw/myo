#!/usr/bin/env bash

PM_BOOTSTRAP_TOOLS=(fzf jq curl git pciutils unzip fontconfig)
PM_EXTRA_PKGS=(qt6-multimedia-ffmpeg polkit python-yaml iproute2 nftables)
PM_AUDIO_BUILD_PKGS=(base-devel pkgconf pipewire)
PM_PACMAN_SYNCED=false
PM_QUEUE_WORKER="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../../native_packages.py"
source "$(dirname "$PM_QUEUE_WORKER")/modules/download_queue.sh"

pm_pacman_ready() {
    local updates status=0 db
    db="$(pacman-conf DBPath)" || return 1
    if [ -e "${db%/}/db.lck" ]; then
        echo "Pacman is locked at ${db%/}/db.lck. Wait for the current transaction and retry." >&2
        return 1
    fi
    if ! pacman -Sl >/dev/null; then
        echo 'Repository databases are unavailable. To refresh them with a consistent package set, review a full system upgrade.' >&2
        return 1
    fi
    updates="$(pacman -Qu)" || status=$?
    if (( status > 1 )); then return "$status"; fi
    if [ -n "$updates" ]; then
        echo 'The current repository databases have pending system upgrades. Review a full pacman upgrade, or use a Live image with a matching package snapshot.' >&2
        printf '%s\n' "$updates" >&2
        return 1
    fi
}

pm_pacman_install() {
    pm_pacman_ready || return 1
    pm_queue_run pacman -- "$@" || return 1
    PM_PACMAN_SYNCED=true
    if [ "${MANAGED_INSTALL:-false}" = true ]; then
        pacman -T "$@"
    else
        pacman -Q "$@"
    fi
}

pm_bootstrap_install() {
    pm_pacman_install "$@"
}

pm_missing_pkgs() {
    local result status=0 pkg
    local targets=()
    for pkg in "$@"; do
        if [[ "$pkg" == umbriel ]] && pm_is_installed umbriel-git && command -v umbriel >/dev/null; then
            continue
        fi
        if [[ "$pkg" == quickshell ]] && pm_is_installed quickshell-git && quickshell_is_current; then
            continue
        fi
        if [[ "$pkg" == qt6-multimedia-ffmpeg ]] && pm_is_installed qt6-multimedia-gstreamer; then
            continue
        fi
        targets+=("$pkg")
    done
    [ ${#targets[@]} -gt 0 ] || return 0
    result="$(pacman -T "${targets[@]}")" || status=$?
    case "$status" in
        0) return 0 ;;
        127) printf '%s\n' "$result" ;;
        *) echo "Failed to check installed packages with pacman -T (exit $status)." >&2; return "$status" ;;
    esac
}

pm_is_installed() {
    pacman -Q "$1" &>/dev/null
}

pm_install_batch() {
    pm_pacman_install "$@" || return 1
    PM_BATCH_LEFT=()
}

pm_install_pkg() {
    pm_pacman_install "$1"
}

pm_upgrade_quickshell() {
    if pm_is_installed quickshell-git; then
        echo "Update your installed quickshell-git through its original package source, then rerun the installer." >&2
        return 1
    fi
    pm_pacman_install quickshell
}

pm_upgrade_hyprland() {
    if pm_is_installed hyprland-git; then
        echo "Update your installed hyprland-git through its original package source." >&2
        return 1
    fi
    pm_pacman_install hyprland
}
