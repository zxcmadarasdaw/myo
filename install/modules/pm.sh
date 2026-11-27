#!/usr/bin/env bash

PM_MODULES_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")/pm"

case "$PM_NAME" in
    pacman|dnf|void|emerge) ;;
    *) echo "Package provider was not selected by the installer." >&2; return 1 ;;
esac

PM_EXTRA_PKGS=()
PM_SDDM_EXTRA_PKGS=()
PM_SDDM_WAYLAND_DEFAULT=false
PM_SDDM_CURSOR_FIX=false
PM_AUDIO_BUILD_PKGS=()

source "$PM_MODULES_DIR/$PM_NAME.sh"
