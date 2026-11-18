#!/usr/bin/env bash
# Regression tests for installation and startup fixes.
#
#   bash install/tests/install_runtime_test.sh
#
# Runs in a disposable HOME. Package managers, quickshell and Hyprland are
# replaced by stubs, so this proves the installer/launcher logic, not that the
# real packages work. The supervisor test needs Linux (setsid, flock, /proc)
# and is skipped elsewhere.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0
SKIP=0

ok() { PASS=$((PASS + 1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL: $1"; }
skip() { SKIP=$((SKIP + 1)); echo "SKIP: $1"; }

new_home() {
    local dir
    dir="$(mktemp -d)"
    mkdir -p "$dir/stub-bin"
    echo "$dir"
}

# ---------------------------------------------------------------------------
# 1. First launch picks a GIF and falls back to a bundled wallpaper when the
#    wallpaper folder is empty (failed download).
# ---------------------------------------------------------------------------
test_first_launch() {
    local home app out
    home="$(new_home)"
    app="$home/.local/share/serpantinum"
    mkdir -p "$app/themess/Pack/wallpapers" "$home/Pictures/Wallpapers" "$home/.config/serpantinum"
    cp -r "$ROOT/src" "$app/src"
    printf 'GIF89a' > "$app/themess/Pack/wallpapers/still #1.gif"
    printf '{"wallpaperDir": "%s"}' "$home/Pictures/Wallpapers" > "$home/.config/serpantinum/settings.json"

    out="$(HOME="$home" SERPANTINUM_DIR="$app/src" bash "$app/src/scripts/first_launch.sh" --check 2>/dev/null)"
    if [[ "$out" == "FIRST|$app/themess/Pack/wallpapers/still #1.gif|"* ]]; then
        ok "first launch uses bundled wallpaper when folder is empty"
    else
        bad "first launch fallback (got: $out)"
    fi

    rm -f "$home/.local/state/serpantinum/first_launch.done"
    printf 'GIF89a' > "$home/Pictures/Wallpapers/anim.gif"
    out="$(HOME="$home" SERPANTINUM_DIR="$app/src" bash "$app/src/scripts/first_launch.sh" --check 2>/dev/null)"
    if [[ "$out" == "FIRST|$home/Pictures/Wallpapers/anim.gif|"* ]]; then
        ok "first launch accepts GIF wallpapers"
    else
        bad "first launch GIF selection (got: $out)"
    fi
    rm -rf "$home"
}

# ---------------------------------------------------------------------------
# 2. deploy: program files are mirrored even without a commit change, the
#    Themess packages are installed, and an empty wallpaper folder is filled.
# ---------------------------------------------------------------------------
test_deploy_sync() {
    local home repo
    home="$(new_home)"
    repo="$home/repo"
    mkdir -p "$repo/bin" "$repo/src/scripts" "$repo/themess/Pack/wallpapers" "$repo/src/__pycache__"
    echo 'echo v1' > "$repo/bin/serpantinumd"
    echo 'echo new' > "$repo/src/scripts/tool.sh"
    echo 'x' > "$repo/src/__pycache__/junk.pyc"
    printf 'GIF89a' > "$repo/themess/Pack/wallpapers/w.gif"
    mkdir -p "$home/.local/share/serpantinum/src/scripts"
    echo 'echo stale' > "$home/.local/share/serpantinum/src/scripts/stale.sh"

    (
        export HOME="$home"
        t() { echo "$1"; }
        # shellcheck source=/dev/null
        source "$ROOT/install/modules/deploy.sh"
        TARGET_BASE="$HOME/.local/share/serpantinum"
        sync_program_dir "$repo/bin" "$TARGET_BASE/bin"
        sync_program_dir "$repo/src" "$TARGET_BASE/src"
        sync_program_dir "$repo/themess" "$TARGET_BASE/themess"
        mkdir -p "$HOME/Pictures/Wallpapers"
        install_bundled_wallpapers "$HOME/Pictures/Wallpapers" >/dev/null
    )
    local base="$home/.local/share/serpantinum"
    [ -f "$base/src/scripts/tool.sh" ] && ok "deploy copies uncommitted source files" || bad "deploy source copy"
    [ ! -e "$base/src/scripts/stale.sh" ] && ok "deploy removes stale files" || bad "deploy stale removal"
    [ ! -e "$base/src/__pycache__" ] && ok "deploy skips __pycache__" || bad "deploy __pycache__"
    [ -f "$base/themess/Pack/wallpapers/w.gif" ] && ok "deploy installs bundled Themess packages" || bad "deploy themess"
    [ -f "$home/Pictures/Wallpapers/w.gif" ] && ok "empty wallpaper folder gets bundled wallpapers" || bad "bundled wallpapers"
    rm -rf "$home"
}

test_window_config_update() {
    local home repo config revision
    home="$(new_home)"
    repo="$home/repo"
    config="$home/.config/hypr/config"
    mkdir -p "$repo/compositors/hyprland/config" "$config"
    printf '%s\n' '-- shipped settings' > "$repo/compositors/hyprland/config/settings.lua"
    printf '%s\n' '-- shipped keys' > "$repo/compositors/hyprland/config/keybinds.lua"
    printf '%s\n' '-- shipped entry point' > "$repo/compositors/hyprland/hyprland.lua"
    cp "$repo/compositors/hyprland/config/settings.lua" "$config/settings.lua"
    cp "$repo/compositors/hyprland/hyprland.lua" "$config/../hyprland.lua"
    printf '%s\n' '-- customized keys' > "$config/keybinds.lua"
    git -C "$repo" init -q
    git -C "$repo" add compositors
    git -C "$repo" -c user.name=Test -c user.email=test@example.invalid commit -qm baseline
    revision="$(git -C "$repo" rev-parse HEAD)"
    cp "$ROOT/compositors/hyprland/config/"{settings,keybinds,canvas}.lua "$repo/compositors/hyprland/config/"
    cp "$ROOT/compositors/hyprland/hyprland.lua" "$repo/compositors/hyprland/"

    (
        export HOME="$home"
        source "$ROOT/install/modules/deploy.sh"
        setup_pam_service() { :; }
        deploy_package "$repo" "$revision" "$revision" false current hyprland
    ) >/dev/null

    if cmp -s "$ROOT/compositors/hyprland/config/settings.lua" "$config/settings.lua" \
        && grep -q -- '-- shipped settings' "$home/.config/hypr_backup/"update_*/config/settings.lua; then
        ok "local update deploys the stock Hyprland window modes with a backup"
    else
        bad "local update of the shipped Hyprland window modes"
    fi
    grep -qx -- '-- customized keys' "$config/keybinds.lua" \
        && ok "local update preserves customized Hyprland shortcuts" || bad "custom Hyprland shortcuts were changed"
    if cmp -s "$ROOT/compositors/hyprland/config/canvas.lua" "$config/canvas.lua" \
        && grep -qx 'require("config/canvas")' "$config/../hyprland.lua"; then
        ok "local update installs and enables the Hyprland canvas module"
    else
        bad "Hyprland canvas module was not deployed"
    fi
    local base="$home/.local/share/serpantinum"
    mkdir -p "$base/vpn-bundle" "$base/vpn/bin"
    touch "$base/vpn-bundle/manifest.json" "$base/vpn/bin/sing-box"
    (
        export HOME="$home"
        source "$ROOT/install/modules/deploy.sh"
        setup_pam_service() { :; }
        deploy_package "$repo" unknown unknown false current hyprland
    ) >/dev/null
    if [ -f "$base/vpn-bundle/manifest.json" ] && [ -f "$base/vpn/bin/sing-box" ]; then
        ok "full program deployment preserves the cached VPN bundle and user engine"
    else
        bad "program deployment removed VPN files"
    fi
    rm -rf "$home"
}

# ---------------------------------------------------------------------------
# 3. verify_installation refuses to report success when required packages or
#    a Lua-capable Hyprland are missing.
# ---------------------------------------------------------------------------
test_verify() {
    local home result
    home="$(new_home)"
    mkdir -p "$home/.local/share/serpantinum/src/quickshell" "$home/.local/share/serpantinum/bin" "$home/.local/bin" "$home/.config/hypr" "$home/Pictures/Wallpapers"
    touch "$home/.local/share/serpantinum/src/quickshell/Shell.qml" "$home/.config/hypr/hyprland.lua" "$home/Pictures/Wallpapers/a.png"
    printf '#!/bin/sh\n' > "$home/.local/share/serpantinum/bin/serpantinumd"
    chmod +x "$home/.local/share/serpantinum/bin/serpantinumd"
    cp "$home/.local/share/serpantinum/bin/serpantinumd" "$home/.local/bin/serpantinumd"
    printf '#!/bin/sh\necho "quickshell 0.3.1"\n' > "$home/stub-bin/quickshell"
    cat > "$home/stub-bin/Hyprland" <<'EOF'
#!/bin/sh
case "$1" in
    --version) echo "Hyprland ${STUB_HYPR_VERSION} built from branch" ;;
    --verify-config)
        [ "$2" = --config ] && [ "$3" = "$HOME/.config/hypr/hyprland.lua" ] || exit 2
        if grep -q 'config.unload' "$3"; then
            echo 'hl.on: unknown event "config.unload"'
            exit 1
        fi
        ;;
    *) exit 2 ;;
esac
EOF
    chmod +x "$home/stub-bin/"*

    run_verify() {
        (
            export HOME="$home" PATH="$home/stub-bin:$home/.local/bin:/usr/bin:/bin" STUB_HYPR_VERSION="$1"
            t() { echo "$1"; }
            # shellcheck source=/dev/null
            source "$ROOT/install/modules/deps.sh" 2>/dev/null
            # shellcheck source=/dev/null
            source "$ROOT/install/modules/deploy.sh"
            # shellcheck source=/dev/null
            source "$ROOT/install/modules/verify.sh"
            pm_missing_pkgs() { [ -n "$STUB_MISSING" ] && printf '%s\n' $STUB_MISSING; return 0; }
            SELECTED_COMPOSITORS=(hyprland)
            verify_installation >/dev/null 2>&1
            echo "$INSTALL_INCOMPLETE"
        )
    }

    result="$(STUB_MISSING="" run_verify 0.57.1)"
    [ "$result" = "false" ] && ok "complete environment verifies" || bad "complete environment (got $result)"
    result="$(STUB_MISSING="qt6-imageformats" run_verify 0.57.1)"
    [ "$result" = "true" ] && ok "missing required package marks install incomplete" || bad "missing package detection (got $result)"
    result="$(STUB_MISSING="" run_verify 0.54.0)"
    [ "$result" = "true" ] && ok "Hyprland without Lua config support is rejected" || bad "old Hyprland detection (got $result)"
    printf 'hl.on("config.unload", function() end)\n' > "$home/.config/hypr/hyprland.lua"
    result="$(STUB_MISSING="" run_verify 0.56.2)"
    [ "$result" = "true" ] && ok "unknown Lua event marks install incomplete" || bad "Hyprland config error detection (got $result)"
    : > "$home/.config/hypr/hyprland.lua"

    # The real shell tree passes the Quickshell QML check; a sibling type that
    # Quickshell cannot see (the WallpaperGif crash, exit 255) fails verify.
    local py
    py="$(command -v python3 || command -v python || true)"
    if [ -n "$py" ] && "$py" -c 'import sys; sys.exit(sys.version_info < (3, 6))' 2>/dev/null; then
        printf '#!/bin/sh\nexec "%s" "$@"\n' "$py" > "$home/stub-bin/python3"
        chmod +x "$home/stub-bin/python3"
        rm -rf "$home/.local/share/serpantinum/src/quickshell"
        cp -r "$ROOT/src/quickshell" "$home/.local/share/serpantinum/src/quickshell"
        result="$(STUB_MISSING="" run_verify 0.57.1)"
        [ "$result" = "false" ] && ok "installed shell passes the Quickshell QML type check" || bad "QML check on the real shell (got $result)"
        printf 'import QtQuick\nItem {\n    WallpaperGif {}\n}\n' > "$home/.local/share/serpantinum/src/quickshell/wallpaper/Probe.qml"
        result="$(STUB_MISSING="" run_verify 0.57.1)"
        [ "$result" = "true" ] && ok "unresolved QML type (WallpaperGif is not a type) marks install incomplete" || bad "QML type check in verify (got $result)"
    else
        skip "QML type check in verify (python3 not found)"
    fi
    rm -rf "$home"
}

# ---------------------------------------------------------------------------
# 4. serpantinumd logs quickshell output, retries and stops after 3 quick
#    failures instead of leaving an empty session silently.
# ---------------------------------------------------------------------------
test_supervisor() {
    if [ "$(uname -s)" != "Linux" ] || ! command -v setsid >/dev/null 2>&1 || ! command -v flock >/dev/null 2>&1; then
        skip "daemon supervision (needs Linux setsid/flock)"
        return
    fi
    local home app log
    home="$(new_home)"
    app="$home/app"
    mkdir -p "$app"
    cp -r "$ROOT/bin" "$ROOT/src" "$app/"
    printf '#!/bin/sh\n[ "$1" = "--version" ] && { echo "quickshell 0.3.1"; exit 0; }\necho "qml: module Quickshell.Fake is not installed" >&2\nexit 1\n' > "$home/stub-bin/quickshell"
    chmod +x "$home/stub-bin/quickshell"
    (
        export HOME="$home" XDG_STATE_HOME="$home/state" XDG_RUNTIME_DIR="$home/run" PATH="$home/stub-bin:/usr/bin:/bin"
        mkdir -p "$XDG_RUNTIME_DIR"
        # Keep the test away from a real session's pid/lock files.
        sed -i "s|/tmp/serpantinumd|$home/serpantinumd|g" "$app/bin/serpantinumd"
        timeout 30 bash "$app/bin/serpantinumd" start >/dev/null 2>&1
    )
    log="$home/state/serpantinum/logs/shell.log"
    if [ -f "$log" ] && [ "$(grep -c 'exited with code 1' "$log")" -eq 3 ] && grep -q 'EMERGENCY' "$log" && grep -q 'Quickshell.Fake' "$log"; then
        ok "serpantinumd logs output, retries 3 times, then reports an emergency"
    else
        bad "daemon supervision (log: $(tail -n 5 "$log" 2>/dev/null))"
    fi
    rm -rf "$home"
}

# ---------------------------------------------------------------------------
# 5. Fedora + Hyprland never touches Terra. Terra is needed only for MangoWC
#    (mangowm); a configured but unreachable Terra repo (left by an earlier
#    MangoWC install) must not break the Hyprland install, and a Terra failure
#    for MangoWC must still be reported as a failed package.
# ---------------------------------------------------------------------------
test_fedora_terra() {
    local home log result
    home="$(new_home)"
    log="$home/dnf.log"
    mkdir -p "$home/repos" "$home/.local/bin"
    # sudo/dnf/rpm/curl stubs. dnf fails like dnf5 does when an enabled repo
    # cannot be loaded: any repo-loading command without --disablerepo=terra
    # fails while a terra*.repo file exists and STUB_TERRA_BROKEN=1.
    printf '#!/bin/sh\nexec "$@"\n' > "$home/stub-bin/sudo"
    cat > "$home/stub-bin/dnf" <<'EOF'
#!/bin/sh
echo "dnf $*" >> "$STUB_DNF_LOG"
cmd=""; terra_off=0
for a in "$@"; do
    case "$a" in
        --disablerepo=terra) terra_off=1 ;;
        -*) ;;
        *) [ -z "$cmd" ] && cmd="$a" ;;
    esac
done
case "$cmd" in
    install|upgrade|makecache|repoquery|remove)
        if [ "$STUB_TERRA_BROKEN" = 1 ] && [ "$terra_off" = 0 ] && ls "$PM_YUM_REPOS_DIR"/terra*.repo >/dev/null 2>&1; then
            echo "Failed to download metadata for repository 'terra'" >&2; exit 1
        fi ;;
esac
case "$cmd" in
    repoquery) for a in "$@"; do last="$a"; done
        case " $STUB_UNAVAILABLE " in *" $last "*) ;; *) echo "$last-1.0-1.fc45.x86_64" ;; esac ;;
    install) case "$*" in *terra-release*) [ "$STUB_TERRA_UNREACHABLE" = 1 ] && exit 1 ;; esac ;;
esac
exit 0
EOF
    cat > "$home/stub-bin/rpm" <<'EOF'
#!/bin/sh
for a in "$@"; do last="$a"; done
case " $STUB_RPM_MISSING terra-release " in *" $last "*) exit 1 ;; esac
exit 0
EOF
    printf '#!/bin/sh\nexit 1\n' > "$home/stub-bin/curl"
    printf '#!/bin/sh\necho "matugen 4.2.0"\n' > "$home/.local/bin/matugen"
    printf '#!/bin/sh\nexit 0\n' > "$home/stub-bin/satty"
    chmod +x "$home/stub-bin/"* "$home/.local/bin/matugen"

    run_deps() {
        (
            export HOME="$home" PATH="$home/stub-bin:$home/.local/bin:/usr/bin:/bin"
            export STUB_DNF_LOG="$log" PM_YUM_REPOS_DIR="$home/repos"
            export STUB_RPM_MISSING="hyprland quickshell kitty mangowm" STUB_UNAVAILABLE="mangowm"
            : > "$log"
            t() { echo "$1"; }
            sleep() { :; }
            # shellcheck source=/dev/null
            source "$ROOT/install/modules/pm/dnf.sh"
            python3() {
                [ "$1" != -c ] || return 0
                [[ "$1" == */download_queue.py ]] || return 2
                shift 2
                local operation=install opts=() targets=()
                while (( $# )); do
                    case "$1" in
                        --operation) operation="$2"; shift 2 ;;
                        --repo-option=*) opts+=("${1#--repo-option=}"); shift ;;
                        --) shift; targets=("$@"); break ;;
                        *) return 2 ;;
                    esac
                done
                sudo dnf "${opts[@]}" "$operation" -y "${targets[@]}"
            }
            # shellcheck source=/dev/null
            source "$ROOT/install/modules/deps.sh"
            OPT_SDDM=false
            install_dependencies fresh false "$@" >/dev/null 2>&1
            echo "${FAILED_PKGS[*]}"
        )
    }

    # a) Hyprland only, no Terra configured: Terra is never enabled.
    rm -f "$home/repos/"*
    result="$(STUB_TERRA_BROKEN=1 run_deps hyprland)"
    if [ -z "$result" ] && grep -q 'dnf install -y hyprland' "$log" && ! grep -qi 'terra' "$log"; then
        ok "Fedora + Hyprland installs without enabling Terra"
    else
        bad "Fedora + Hyprland without Terra (failed: '$result'; log: $(grep -i terra "$log" | head -n 3))"
    fi

    # b) Hyprland only, broken Terra repo left on the system: every dnf call
    #    excludes it, so the install succeeds and terra-release is not touched.
    printf '[terra]\nname=Terra\n[terra-source]\nenabled=0\n' > "$home/repos/terra.repo"
    result="$(STUB_TERRA_BROKEN=1 run_deps hyprland)"
    if [ -z "$result" ] && ! grep -q 'terra-release' "$log" \
        && ! grep -E 'dnf .*(install|upgrade|makecache|repoquery|remove)' "$log" | grep -qv -- '--disablerepo=terra '; then
        ok "Fedora + Hyprland ignores an unreachable leftover Terra repo"
    else
        bad "Fedora + Hyprland with leftover Terra repo (failed: '$result'; log: $(head -n 5 "$log"))"
    fi

    # c) Hyprland + MangoWC with Terra unreachable: only mangowm fails, and it
    #    is reported (not masked); Hyprland and the shell still install.
    rm -f "$home/repos/"*
    result="$(STUB_TERRA_UNREACHABLE=1 run_deps hyprland mango)"
    if [ "$result" = "mangowm" ] && grep -q 'terra-release' "$log" && grep -q 'dnf install -y hyprland' "$log"; then
        ok "Terra failure fails only mangowm and is reported"
    else
        bad "Terra failure handling for MangoWC (failed: '$result')"
    fi
    rm -rf "$home"
}

test_platform_selection() (
    local home
    home="$(new_home)"
    source "$ROOT/install/install.sh"
    pacman() { return 0; }
    dnf() { return 0; }
    printf 'ID=fedora\nVERSION_ID="45"\n' > "$home/release"
    detect_install_platform "$home/release" x86_64 && [ "$PM_NAME" = dnf ] && [ "$DISTRO_VERSION" = 45 ] || return 1
    printf 'ID=cachyos\nID_LIKE=arch\n' > "$home/release"
    detect_install_platform "$home/release" x86_64 && [ "$PM_NAME" = pacman ] || return 1
    printf 'ID=arch\n' > "$home/release"
    detect_install_platform "$home/release" x86_64 && [ "$PM_NAME" = pacman ] || return 1
    if detect_install_platform "$home/release" aarch64 2>/dev/null; then return 1; fi
    unset -f pacman
    if PATH="$home/stub-bin" detect_install_platform "$home/release" x86_64 2>/dev/null; then return 1; fi
    printf 'ID=debian\n' > "$home/release"
    if detect_install_platform "$home/release" x86_64 2>/dev/null; then return 1; fi
    df() { printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\ntest 100 92 8 92%% /\n'; }
    check_install_space "$home" 8 && ! check_install_space "$home" 9 2>/dev/null || return 1
    rm -rf "$home"
)

test_pacman_provider() (
    local home
    home="$(new_home)"
    export HOME="$home"
    PM_NAME=pacman
    source "$ROOT/install/modules/pm.sh"
    source "$ROOT/install/modules/deps.sh"
    OPT_SDDM=false
    REQUIRED_PKGS=(quickshell kitty)
    PM_EXTRA_PKGS=()
    quickshell_is_current() { return 0; }
    install_fonts() { :; }
    configure_qt_icon_theme() { :; }
    t() { printf '%s' "$1"; }
    sudo() { "$@"; }
    pacman() {
        local operation="$1"
        shift
        case "$operation" in
            -T)
                [ "$*" = 'kitty hyprland' ] || return 2
                if [ ! -f "$home/installed" ]; then printf 'kitty\nhyprland\n'; return 127; fi
                ;;
            -Q|-Sl) return 0 ;;
            -Qu) return 1 ;;
            -Syu|-S)
                printf '%s %s\n' "$operation" "$*" >> "$home/transactions"
                [ ! -f "$home/fail" ] || return 1
                touch "$home/installed"
                ;;
            *) return 3 ;;
        esac
    }
    pacman-conf() { [ "$1" = DBPath ] && echo "$home/db"; }
    mkdir -p "$home/db"
    python3() {
        [[ "$1" == */download_queue.py && "$2" == pacman && "$3" == -- ]] || return 2
        shift 3
        sudo pacman -S --needed "$@"
    }
    touch "$home/fail"
    if install_dependencies fresh false hyprland >/dev/null 2>&1; then return 1; fi
    [ ! -f "$home/installed" ] && [ "$PM_PACMAN_SYNCED" = false ] || return 1
    rm "$home/fail"
    install_dependencies fresh false hyprland >/dev/null || return 1
    install_dependencies current false hyprland >/dev/null || return 1
    [ "$(cat "$home/transactions")" = "$(printf '%s\n' '-S --needed kitty hyprland' '-S --needed kitty hyprland')" ] || return 1
    pm_bootstrap_install jq >/dev/null && grep -Fxq -- '-S --needed jq' "$home/transactions" || return 1
    rm -rf "$home"
)

test_config_backup() (
    local home
    home="$(new_home)"
    export HOME="$home" XDG_CONFIG_HOME="$home/xdg"
    source "$ROOT/install/modules/deploy.sh"
    source "$ROOT/install/modules/config.sh"
    local incoming="$home/incoming" target="$XDG_CONFIG_HOME/hypr"
    mkdir -p "$incoming" "$target" "$CONFIG_DIR"
    printf 'new\n' > "$incoming/hyprland.lua"
    printf 'old\n' > "$target/hyprland.lua"
    printf 'personal\n' > "$target/personal.lua"
    printf '{"wallpaperDir":"/my pictures","userSetting":true}\n' > "$CONFIG_FILE"
    confirm_config_replacement() { return 1; }
    install_config_tree "$incoming" "$target" >/dev/null || return 1
    [ "$(cat "$target/hyprland.lua")" = old ] || return 1
    confirm_config_replacement() { return 0; }
    cp() {
        [ "$1" != -a ] || return 1
        command cp "$@"
    }
    if install_config_tree "$incoming" "$target" >/dev/null 2>&1; then return 1; fi
    [ "$(cat "$target/hyprland.lua")" = old ] || return 1
    unset -f cp
    install_config_tree "$incoming" "$target" >/dev/null || return 1
    grep -qFx old "$target"_backup/backup_*/hyprland.lua || return 1
    [ "$(cat "$target/hyprland.lua")" = new ] && [ "$(cat "$target/personal.lua")" = personal ] || return 1
    install_config_tree "$incoming" "$target" >/dev/null || return 1
    [ "$(find "$target"_backup -type f -name hyprland.lua | wc -l)" -eq 1 ] || return 1
    init_serpantinum_config "$ROOT" "$home/Pictures" || return 1
    [ "$SERP_NEW_SETTINGS" = false ] && grep -qF '"/my pictures"' "$CONFIG_FILE" || return 1
    rm -rf "$home"
)

test_sddm_keeps_display_manager() (
    source "$ROOT/install/modules/deploy.sh"
    OPT_SDDM=true
    SDDM_WAYLAND=false
    REPLACE_DM=false
    detect_init_system() { echo systemd; }
    resolve_sddm_backend() { echo x11; }
    systemctl() { echo plasmalogin.service; }
    sudo() { echo 'unexpected privileged action' >&2; exit 42; }
    setup_sddm "$ROOT"
)

test_arch_vpn_provider() (
    local home result
    home="$(new_home)"
    export HOME="$home" XDG_STATE_HOME="$home/state"
    PM_NAME=pacman
    DISTRO_ID=cachyos
    DISTRO_VERSION=""
    PROJECT_ROOT="$ROOT"
    source "$ROOT/install/modules/vpn.sh"
    pm_missing_pkgs() {
        [ "$*" = "polkit python-yaml iproute2 nftables" ] || return 1
        printf 'python-yaml\niproute2\n'
    }
    pm_install_batch() {
        [ "$*" = "python-yaml iproute2" ] || return 1
        printf 'dependencies\n' >> "$home/log"
    }
    vpn_prepare_linux() { printf 'local bundle\n' >> "$home/log"; }
    timeout() {
        [[ "$*" == *'verify-install --prepare-status=0' ]] || return 1
        printf 'verification\n' >> "$home/log"
    }
    result="$(install_vpn_components)" || return 1
    [ "$(cat "$home/log")" = "$(printf 'dependencies\nlocal bundle\nverification')" ] || return 1
    [[ "$result" == *'VPN components: READY' ]] || return 1
    timeout() { return 1; }
    if install_vpn_components >/dev/null 2>&1; then return 1; fi
    rm -rf "$home"
)

test_xdg_paths() (
    local home
    home="$(new_home)"
    export HOME="$home" XDG_CONFIG_HOME="$home/xdg/config" XDG_STATE_HOME="$home/xdg/state"
    source "$ROOT/src/scripts/xdg_paths.sh"
    [ "$(serpantinum_settings_path)" = "$XDG_CONFIG_HOME/serpantinum/settings.json" ] || return 1
    [ "$(serpantinum_state_dir)" = "$XDG_STATE_HOME/serpantinum" ] || return 1
    mkdir -p "$HOME/.config/serpantinum" "$HOME/.local/state/serpantinum"
    touch "$HOME/.config/serpantinum/settings.json" "$HOME/.local/state/serpantinum/version"
    [ "$(serpantinum_settings_path)" = "$HOME/.config/serpantinum/settings.json" ] || return 1
    [ "$(serpantinum_state_dir)" = "$HOME/.local/state/serpantinum" ] || return 1
    rm -rf "$home"
)

test_maintenance_round_trip() (
    local home snapshot output
    home="$(new_home)"
    export HOME="$home" XDG_CONFIG_HOME="$home/xdg/config" XDG_STATE_HOME="$home/xdg/state"
    export XDG_DATA_HOME="$home/xdg/data"
    # Git Bash lacks the Linux flock executable. The snapshot test uses a private HOME.
    if ! command -v flock >/dev/null; then
        printf '#!/usr/bin/env bash\nexit 0\n' > "$home/stub-bin/flock"
        chmod +x "$home/stub-bin/flock"
        export PATH="$home/stub-bin:$PATH"
    fi
    local settings="$XDG_CONFIG_HOME/serpantinum/settings.json" dir="$HOME/.local/share/serpantinum"
    mkdir -p "${settings%/*}" "$XDG_STATE_HOME/serpantinum" "$dir/src" "$dir/bin" "$dir/themess"
    printf 'original\n' > "$settings"
    printf 'library\n' > "$XDG_STATE_HOME/serpantinum/favorites"
    printf 'bundled or user theme\n' > "$dir/themess/keep"
    printf 'source files\n' > "$dir/src/keep"
    printf 'launcher files\n' > "$dir/bin/keep"
    snapshot="$(bash "$ROOT/install/maintenance.sh" backup)" || return 1
    [ -f "$snapshot/.format" ] || return 1
    printf 'edited\n' > "$settings"
    if bash "$ROOT/install/maintenance.sh" restore "$home" >/dev/null 2>&1; then return 1; fi
    [ "$(cat "$settings")" = edited ] || return 1
    output="$(bash "$ROOT/install/maintenance.sh" restore "$snapshot")" || return 1
    [ "$(cat "$settings")" = original ] || return 1
    [ "$(cat "${output#Backup before restore: }/settings/settings.json")" = edited ] || return 1
    output="$(bash "$ROOT/install/maintenance.sh" uninstall)" || return 1
    [ ! -e "$dir/src" ] && [ ! -e "$dir/bin" ] || return 1
    [ -f "$dir/themess/keep" ] && [ -f "$settings" ] && [ -f "$XDG_STATE_HOME/serpantinum/favorites" ] || return 1
    local archives=("$XDG_DATA_HOME"/serpantinum-backups/program_*)
    [ -f "${archives[0]}/src/keep" ] && [ -f "${archives[0]}/bin/keep" ] || return 1
    rm -rf "$home"
)

test_first_launch
test_deploy_sync
test_window_config_update
test_verify
test_supervisor
test_fedora_terra
test_platform_selection && ok "os-release selects the correct provider before bootstrap and checks space" || bad "platform selection or space check"
test_pacman_provider && ok "pacman failure can be retried, preserves quickshell-git and skips installed packages" || bad "pacman transaction and retry"
test_config_backup && ok "backup failure preserves configs and a successful retry retains user files" || bad "config backup and retry"
test_sddm_keeps_display_manager >/dev/null && ok "SDDM leaves the existing display manager in place" || bad "display manager preservation"
test_arch_vpn_provider && ok "Arch VPN setup uses native dependencies and requires successful verification" || bad "Arch VPN provider and verification"
test_xdg_paths && ok "XDG paths are used for new installs and preserve legacy data" || bad "XDG path selection"
test_maintenance_round_trip && ok "maintenance backs up, restores and archives a shell install without deleting user data" || bad "backup, restore and uninstall"

echo
echo "passed=$PASS failed=$FAIL skipped=$SKIP"
[ "$FAIL" -eq 0 ]
