#!/usr/bin/env bash
# Isolated contract tests. No native package manager, sudo, or desktop is used.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
expect() { [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"; }

source "$root/install/install.sh"
pacman() {
    case "$1" in
        -Q) return 1 ;;
        -T) if [[ " $* " == *' hyprland '* ]]; then echo hyprland; return 127; fi ;;
        *) return 2 ;;
    esac
}
dnf() { return 2; }
xbps-install() { return 2; }
emerge() { fail 'Unexpected Portage transaction'; }
sudo() { fail 'Unexpected privileged command'; }
portageq() {
    [[ "$1 $2" == 'has_version /' ]] || return 2
    case "$3" in
        app-misc/jq|'dev-qt/qtmultimedia:6[qml,pipewire]') return 0 ;;
        '>=gui-apps/quickshell-0.3.0'|gui-wm/hyprland) return 1 ;;
        *) return 2 ;;
    esac
}

platform() {
    printf '%s\n' "$1" >"$work/os-release"
    detect_install_platform "$work/os-release" x86_64
    expect "$PM_NAME" "$2"
}
platform 'ID=arch' pacman
platform 'ID=cachyos' pacman
platform 'ID=endeavouros' pacman
platform $'ID=arch-derivative\nID_LIKE=arch' pacman
source "$root/install/modules/pm.sh"
expect "$(pm_missing_pkgs jq hyprland)" hyprland
platform $'ID=fedora\nVERSION_ID=45' dnf
platform $'ID=nobara\nID_LIKE=fedora' dnf
platform 'ID=void' void
platform 'ID=gentoo' emerge
expect "$PM_COMMAND" emerge
if detect_install_platform "$work/os-release" aarch64 2>/dev/null; then fail 'Gentoo architecture validation'; fi
source "$root/install/modules/pm/emerge.sh"
expect "$(pm_resolve_name pipewire-alsa)" 'media-video/pipewire[pipewire-alsa]'
expect "$(pm_resolve_name qt6-multimedia)" 'dev-qt/qtmultimedia:6[qml,pipewire]'
expect "$(pm_missing_pkgs jq quickshell hyprland qt6-multimedia)" $'quickshell\nhyprland'
if pm_missing_pkgs nonexistent 2>/dev/null; then fail 'Unknown logical package accepted'; fi
source "$root/install/modules/deps.sh"
source "$root/install/modules/terminal.sh"
OPT_SDDM=true
SDDM_WAYLAND=false
INSTALL_FULL_WALLPAPERS=true
ENABLE_TELEMETRY=false
SELECTED_COMPOSITORS=(hyprland)
targets=()
collect_dependency_targets targets "${SELECTED_COMPOSITORS[@]}"
for name in "${targets[@]}" "${PM_BOOTSTRAP_TOOLS[@]}" "${PM_AUDIO_BUILD_PKGS[@]}"; do
    pm_resolve_name "$name" >/dev/null || fail "Missing Portage atom for $name"
done

# The read-only plan includes the exact selected compositor and SDDM targets.
pm_missing_pkgs() { printf '%s\n' hyprland; }
report="$(terminal_dependencies plan)"
[[ "$report" == *'Compositors: hyprland'* && "$report" == *'gui-wm/hyprland'* &&
   "$report" == *'sddm qt6-declarative qt6-svg'* ]] || fail 'Incomplete dry-run plan'
printf 'Distribution, package and plan tests passed.\n'

if ! command -v jq >/dev/null; then
    printf 'SKIP profile tests: jq is required.\n'
    exit 0
fi
source "$root/install/modules/profile.sh"
printf '%s\n' '{"general":{"language":"ru"},"theme":"existing"}' >"$work/settings.json"
apply_install_profile light "$work/settings.json"
expect "$(jq -c . "$work/settings.json")" '{"general":{"language":"ru","performance":true},"theme":"existing"}'
apply_install_profile light "$work/settings.json"
backups=("$work"/settings.json.backup.*)
expect "${#backups[@]}" 1
expect "$(jq -r .theme "${backups[0]}")" existing
apply_install_profile full "$work/settings.json"
expect "$(jq -r .general.performance "$work/settings.json")" false
printf 'Profile tests passed.\n'
