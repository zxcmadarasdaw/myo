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
        -Si) [ "${3:-}" != quickshell ] ;;
        -Sl) return 0 ;;
        -Sp) printf 'SP-SIZE:8388608\nSP-SIZE:1048576\n' ;;
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
df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\nfixture 16384 12000 4384 73%% /\n'; }
manager_probe > "$work/plan"
grep -q 'full upgrade can consume significant temporary space in Live' "$work/plan"
grep -q 'Insufficient free space' "$work/plan"
! [ -e "$work/transactions" ]
printf 'PASS: low-space Live preparation blocks a full upgrade\n'

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

source "$repo/install/modules/pm/dnf.sh"
PM_YUM_REPOS_DIR="$work/repos"
mkdir -p "$PM_YUM_REPOS_DIR"
printf '[terra]\n' > "$PM_YUM_REPOS_DIR/terra.repo"
pm_dnf install -y --assumeyes hyprland
grep -Fxq 'dnf --disablerepo=terra --setopt=assumeyes=False install hyprland' "$work/transactions"
printf 'PASS: the managed DNF path retains the Terra exclusion and native confirmation\n'
