#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

export HOME="$work/home"
mkdir -p -- "$HOME" "$work/db"
PROJECT_ROOT="$work/checkout"
mkdir -p "$PROJECT_ROOT/bin" "$PROJECT_ROOT/src" "$PROJECT_ROOT/themess"
DISTRO_ID=cachyos
PM_NAME=pacman
source "$repo/install/modules/pm.sh"
source "$repo/install/modules/deps.sh"
source "$repo/install/modules/deploy.sh"
source "$repo/install/modules/service.sh"
t() { printf '%s' "$1"; }
source "$repo/install/modules/ui.sh"
source "$repo/install/modules/verify.sh"
source "$repo/install/modules/vpn.sh"
source "$repo/install/modules/audio.sh"
source "$repo/install/modules/manager.sh"
source "$repo/install/modules/pm/aur.sh"

MANAGED_INSTALL=true MANAGER_ACTION=install MANAGER_LIVE=false PACKAGED_INSTALL=false
INSTALL_STATE=fresh TARGET_VERSION=2.5.1 TARGET_COMMIT=fixture
manager_options hyprland,sway config,backup

pacman-conf() {
    case "$1" in DBPath) printf '%s\n' "$work/db";; CacheDir) printf '%s\n' "$work";; esac
}
pacman() {
    case "$1" in
        -Q) return 1 ;;
        -T) printf '%s\n' kitty; return 127 ;;
        -Qu) if [ -e "$work/updates" ]; then printf 'glibc 1 -> 2\n'; else return 1; fi ;;
        -Si)
            [ "${3:-}" != quickshell ] || return 1
            if [ "${3:-}" = extra/kitty ]; then printf 'Installed Size  : 10.00 MiB\n'; fi ;;
        -Sl) return 0 ;;
        -Sp) printf 'SP-SIZE:8388608\textra/kitty\nSP-SIZE:1048576\tcore/glibc\n' ;;
        *) return 2 ;;
    esac
}
sudo() {
    printf '%s\n' "$*" >> "$work/transactions"
}

manager_dependency_plan
[[ " ${DEPENDENCY_TARGETS[*]} " == *" hyprland "* ]]
[[ " ${DEPENDENCY_TARGETS[*]} " == *" sway "* ]]
[[ " ${MANAGER_MISSING[*]} " == *" kitty "* ]]
[ "$OPT_SYNC" = false ]
! [ -e "$HOME/.local" ]
! [ -e "$work/transactions" ]
manager_pacman_preflight > "$work/plan"
grep -q 'estimates 9 MiB' "$work/plan"
grep -q 'resolved 2 packages' "$work/plan"
! [ -e "$work/transactions" ]
printf 'PASS: preparation queries selected components and estimates cached-database downloads without sudo\n'

touch "$work/db/db.lck"
if manager_pacman_preflight > "$work/plan"; then exit 1; fi
grep -q 'Pacman is locked' "$work/plan"
[ -f "$work/db/db.lck" ]
rm -- "$work/db/db.lck"
touch "$work/updates"
if pm_pacman_install kitty; then exit 1; fi
! [ -e "$work/transactions" ]
rm -- "$work/updates"
printf 'PASS: pacman lock and pending upgrades prevent a transaction\n'

MANAGER_LIVE=true
OPT_SYNC=true
df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\nfixture 1048576 536576 512000 52%% /\n'; }
manager_probe > "$work/plan"
grep -q 'full upgrade can consume significant temporary space in Live' "$work/plan"
grep -q 'Insufficient Live storage' "$work/plan"
grep -q 'Available RAM:' "$work/plan"
grep -q 'Native cache:' "$work/plan"
! [ -e "$work/transactions" ]
OPT_SYNC=false
if manager_space > "$work/plan"; then exit 1; fi
grep -q 'Insufficient Live storage' "$work/plan"
printf 'PASS: a 500 MiB Live overlay blocks preparation before package installation\n'

MANAGER_ACTION=verify STATE_DIR="$HOME/.local/state/serpantinum"
verify_installation() { return 1; }
if manager_run > "$work/verify"; then exit 1; fi
grep -q $'@@integration\tFAILED' "$work/verify"
! grep -q '@@done' "$work/verify"
MANAGER_ACTION=install
printf 'PASS: verification failure cannot report a successful phase\n'

mkdir -p "$work/template" "$work/player-config"
printf 'new default\n' > "$work/template/settings"
printf 'local edit\n' > "$work/player-config/settings"
OPT_REPLACE_CONFIG=false
install_config_tree "$work/template" "$work/player-config"
grep -Fxq 'local edit' "$work/player-config/settings"
OPT_REPLACE_CONFIG=true
install_config_tree "$work/template" "$work/player-config"
grep -Fxq 'new default' "$work/player-config/settings"
grep -Fxq 'local edit' "$work/player-config_backup"/backup_*/settings
printf 'PASS: managed config changes require approval and keep a backup\n'

(
    OPT_ENGINES=true
    MANAGER_ACTION=missing
    FAILED_PKGS=()
    export PATH="$work/engine-bin:$PATH"
    mkdir "$work/engine-bin"
    for executable in ski serpantinum-gamma serpantinum-core; do
        printf '#!/bin/sh\nexit 0\n' > "$work/engine-bin/$executable"
    done
    printf '#!/bin/sh\nexit 1\n' > "$work/engine-bin/serpantinum-audio"
    chmod +x "$work/engine-bin/"*

    install_audio_daemon() { return 1; }
    if manager_engines > "$work/bad-engine"; then exit 1; fi
    grep -q $'@@component\tserpantinum-audio\tFailed' "$work/bad-engine"
    FAILED_PKGS=()
    install_audio_daemon() {
        printf '#!/bin/sh\necho "serpantinum-audio 0.4.0"\n' > "$work/engine-bin/serpantinum-audio"
        printf 'install\n' >> "$work/audio-repair"
    }
    manager_engines > "$work/repaired-engine"
    manager_engines >> "$work/repaired-engine"
    grep -q $'@@component\tserpantinum-audio\tInstalled' "$work/repaired-engine"
    [ "$(wc -l < "$work/audio-repair")" -eq 1 ]
)
printf 'PASS: Install Missing reports a broken DSP, retries it and keeps a working copy on a repeat run\n'

source "$repo/install/modules/pm/dnf.sh"
PM_YUM_REPOS_DIR="$work/repos"
mkdir -p "$PM_YUM_REPOS_DIR"
printf '[terra]\n' > "$PM_YUM_REPOS_DIR/terra.repo"
python3() {
    [ "$1" != -c ] || return 0
    [ "$2" = dnf ] || return 2
    printf '%s\n' "$*" > "$work/queue-call"
}
pm_dnf install -y --assumeyes hyprland
grep -q -- 'dnf --operation install --repo-option=--disablerepo=terra -- hyprland' "$work/queue-call"
printf 'PASS: the managed DNF path retains the Terra exclusion and native confirmation\n'

[ "$(pm_resolve_name umbriel)" = umbriel-nightly ]
[ "${PM_TERRA_MAP[umbriel]}" = 1 ]
[ "$(pm_aur_recipe umbriel)" = umbriel-git ]
[ "$(pm_aur_recipe xdg-desktop-portal-umbriel-git)" = xdg-desktop-portal-umbriel-git ]
mkdir -p "$work/share/wayland-sessions"
printf '[Desktop Entry]\nExec=umbriel\n' > "$work/share/wayland-sessions/umbriel.desktop"
XDG_DATA_DIRS="$work/share" verify_wayland_session Umbriel '[Uu]mbriel*'
printf 'PASS: Umbriel package sources, required AUR portal and Wayland session entry\n'
