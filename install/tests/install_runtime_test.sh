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
    printf '#!/bin/sh\necho "Hyprland ${STUB_HYPR_VERSION} built from branch"\n' > "$home/stub-bin/Hyprland"
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

test_first_launch
test_deploy_sync
test_verify
test_supervisor

echo
echo "passed=$PASS failed=$FAIL skipped=$SKIP"
[ "$FAIL" -eq 0 ]
