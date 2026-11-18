#!/usr/bin/env bash

manager_record() {
    local kind="$1" item
    shift
    printf '%s' "$kind"
    for item in "$@"; do
        item="${item//$'\n'/ }"
        printf '\t%s' "${item//$'\t'/ }"
    done
    printf '\n'
}

manager_options() {
    local comps="$1" options="$2" comp
    OPT_SDDM=false SDDM_WAYLAND=false REPLACE_DM=false
    OPT_SERVICES=false OPT_CONFIG=false OPT_REPLACE_CONFIG=false OPT_BACKUP=false OPT_GLOBAL_LAUNCHERS=false
    OPT_BUILD=false OPT_AUR=false OPT_SYNC=false OPT_VPN=false OPT_ENGINES=false
    OPT_FONTS=false OPT_WALLPAPERS=false INSTALL_FULL_WALLPAPERS=false ENABLE_TELEMETRY=false
    [[ ",$options," != *,sddm,* ]] || OPT_SDDM=true
    [[ ",$options," != *,wayland,* ]] || SDDM_WAYLAND=true
    [[ ",$options," != *,display-manager,* ]] || REPLACE_DM=true
    [[ ",$options," != *,services,* ]] || OPT_SERVICES=true
    [[ ",$options," != *,config,* ]] || OPT_CONFIG=true
    [[ ",$options," != *,replace,* ]] || OPT_REPLACE_CONFIG=true
    [[ ",$options," != *,backup,* ]] || OPT_BACKUP=true
    [[ ",$options," != *,global-launchers,* ]] || OPT_GLOBAL_LAUNCHERS=true
    [[ ",$options," != *,build,* ]] || OPT_BUILD=true
    [[ ",$options," != *,aur,* ]] || OPT_AUR=true
    [[ ",$options," != *,sync,* ]] || OPT_SYNC=true
    [[ ",$options," != *,vpn,* ]] || OPT_VPN=true
    [[ ",$options," != *,engines,* ]] || OPT_ENGINES=true
    [[ ",$options," != *,fonts,* ]] || OPT_FONTS=true
    [[ ",$options," != *,wallpapers,* ]] || OPT_WALLPAPERS=true
    [[ ",$options," != *,full-wallpapers,* ]] || INSTALL_FULL_WALLPAPERS=true
    [[ ",$options," != *,telemetry,* ]] || ENABLE_TELEMETRY=true
    if [ "$comps" != auto ]; then
        IFS=, read -r -a SELECTED_COMPOSITORS <<< "$comps"
    fi
    for comp in "${SELECTED_COMPOSITORS[@]}"; do
        case "$comp" in hyprland|niri|sway|mango) ;; *) return 1 ;; esac
    done
}

manager_disk() {
    local path="$1" required="$2" target="$1" available
    while [[ ! -e "$target" && "$target" != / ]]; do target="$(dirname -- "$target")"; done
    available="$(df -Pk -- "$target" | awk 'NR==2 {print $4}')"
    manager_record disk "$path" "$required" "${available:-unknown}"
    [[ "$available" =~ ^[0-9]+$ ]] && (( available >= required ))
}

manager_space() {
    local size path needed shortfall=0
    size="$(du -sk -- "$PROJECT_ROOT/bin" "$PROJECT_ROOT/src" "$PROJECT_ROOT/themess" |
        awk '{sum += $1} END {print sum+0}')"
    manager_disk "$HOME/.local/share" "$(( size + 16384 ))" || shortfall=1
    manager_disk "${XDG_CACHE_HOME:-$HOME/.cache}" 65536 || shortfall=1
    for path in /usr /var "${TMPDIR:-/tmp}"; do
        needed=131072
        if [ "$MANAGER_LIVE" = true ]; then needed=262144; fi
        if [ "$MANAGER_LIVE" = true ] && [ "$OPT_SYNC" = true ] && [ "$path" != "${TMPDIR:-/tmp}" ]; then
            needed=1048576
        fi
        manager_disk "$path" "$needed" || shortfall=1
    done
    if (( shortfall )); then
        manager_record error "Insufficient free space. Free space on the listed filesystems and review the plan again."
        return 1
    fi
}

manager_pacman_preflight() {
    local message pkg files bytes cache
    [ "$OPT_SYNC" != true ] && [ ${#MANAGER_MISSING[@]} -gt 0 ] || return 0
    if ! message="$(pm_pacman_ready 2>&1)"; then
        manager_record error "${message:-Failed to read pacman repository databases.}"
        return 1
    fi
    local official=()
    for pkg in "${MANAGER_MISSING[@]}"; do
        if pacman -Si -- "$pkg" >/dev/null 2>&1; then
            official+=("$pkg")
        elif [ "$OPT_AUR" = true ] && pm_aur_recipe "$pkg" >/dev/null; then
            manager_record change "Binary package unavailable in configured repositories. AUR fallback planned for $pkg."
        else
            manager_record error "$pkg is unavailable in configured pacman repositories. Check repository metadata and mirrors."
            return 1
        fi
    done
    [ ${#official[@]} -gt 0 ] || return 0
    if files="$(pacman -Sp --needed --print-format 'SP-SIZE:%s' "${official[@]}" </dev/null 2>/dev/null)"; then
        bytes="$(awk -F: '/^SP-SIZE:[0-9]+$/ { sum += $2 } END { printf "%.0f", sum }' <<< "$files")"
        if (( bytes > 0 )); then
            cache="${XDG_CACHE_HOME:-$HOME/.cache}/serpantinum-installer/packages/pacman"
            manager_record change "Pacman estimates $(( (bytes + 1048575) / 1048576 )) MiB of package downloads from current databases."
            if ! manager_disk "$cache" "$(( (bytes + 1023) / 1024 ))"; then
                manager_record error "The pacman cache at $cache has insufficient free space for the estimated downloads."
                return 1
            fi
        fi
    fi
}

manager_command_status() {
    local label="$1" command="$2" path
    if path="$(command -v "$command")"; then
        manager_record component "$label" Installed "$path"
    else
        manager_record component "$label" Missing "$command is unavailable on PATH"
    fi
}

manager_components() {
    local target="$HOME/.local/share/serpantinum" version job label path missing
    local qml="$target/src/quickshell" ready=false
    if [ "$PACKAGED_INSTALL" = true ]; then
        manager_record component Serpantinum Installed 'System package. Update and repair it with pacman.'
    elif [ -f "$qml/Shell.qml" ] && [ -x "$target/bin/serpantinumd" ]; then
        if installed_program_matches "$target"; then
            manager_record component Serpantinum Installed "Program files match the checkout."
        elif version_at_least "$TARGET_VERSION" "$OLD_VERSION" &&
            { [ "$TARGET_VERSION" != "$OLD_VERSION" ] ||
              { [ -n "$OLD_COMMIT" ] && [ "$TARGET_COMMIT" != unknown ] && [ "$TARGET_COMMIT" != "$OLD_COMMIT" ]; }; }; then
            manager_record component Serpantinum 'Update available' "Installed $OLD_VERSION ($OLD_COMMIT) · checkout $TARGET_VERSION ($TARGET_COMMIT)"
        else
            manager_record component Serpantinum Failed 'Installed shell differs from the checkout. Run Verify for details.'
        fi
    elif [ -d "$target/src" ] || [ "$INSTALL_STATE" = current ]; then
        manager_record component Serpantinum Failed 'The shell entry point or launcher is missing.'
    else
        manager_record component Serpantinum Missing 'The checkout is available for deployment.'
    fi
    if version="$(hyprland_version)"; then
        if version_at_least "$version" "$MIN_HYPRLAND_LUA_VERSION"; then
            manager_record component Hyprland Installed "$version · supports Lua configuration"
        else
            manager_record component Hyprland 'Update required' "$version · needs $MIN_HYPRLAND_LUA_VERSION or newer"
        fi
    else
        manager_record component Hyprland Missing 'Hyprland executable unavailable.'
    fi
    if quickshell_is_current; then
        manager_record component Quickshell Installed "$(quickshell_version)"
        ready=true
    elif command -v quickshell >/dev/null; then
        manager_record component Quickshell 'Update required' "$(quickshell_version) · needs $MIN_QUICKSHELL_VERSION or newer"
    else
        manager_record component Quickshell Missing 'The installer can run without the shell.'
    fi
    missing="$(pm_missing_pkgs qt6-multimedia qt6-imageformats qt6-wayland)" || return 1
    if [ -z "$missing" ]; then
        manager_record component 'Qt Multimedia' Installed 'Multimedia, image and Wayland packages are present.'
    else
        ready=false
        manager_record component 'Qt Multimedia' Missing "$missing"
    fi
    for job in 'Wallpaper Engine|wallpaper/WallpaperEngine.qml' 'Wallpaper Hub|../scripts/wallpaper/wallhub.py' \
        'Music Studio|widgets/MusicWidgetDrawer.qml' 'Desktop Terminal|widgets/faces/terminal/TerminalCore.qml'; do
        label="${job%%|*}" path="${job#*|}"
        if [ "$ready" = true ] && [ -f "$qml/$path" ] &&
            { [[ "$label" != Wallpaper* ]] || command -v ffmpeg >/dev/null; } &&
            { [ "$label" != 'Music Studio' ] || { command -v playerctl >/dev/null && command -v wpctl >/dev/null; }; }; then
            manager_record component "$label" Ready 'Installed implementation and local runtime prerequisites found.'
        elif [ -f "$PROJECT_ROOT/src/quickshell/$path" ]; then
            manager_record component "$label" Missing 'Available in checkout. Deployment or runtime dependencies required.'
        else
            manager_record component "$label" Failed 'Implementation missing from checkout.'
        fi
    done
    manager_command_status 'Terminal / Kitty' kitty
    manager_command_status 'Audio DSP' serpantinum-audio
    manager_command_status 'Ski file manager' ski
    manager_command_status 'Core daemon' serpantinum-core
    manager_command_status 'Gamma daemon' serpantinum-gamma
    if [ -x "$VPN_HELPER_DST" ] && [ -f "$VPN_UNIT_DST" ] &&
        timeout 5s python3 "$PROJECT_ROOT/src/scripts/system/serp_vpn.py" system-engine-check >/dev/null 2>&1; then
        manager_record component 'VPN Engine' Installed 'System engine and service files found. Verify TUN separately.'
    elif [ -e "$VPN_HELPER_DST" ] || [ -e "$VPN_UNIT_DST" ]; then
        manager_record component 'VPN Engine' Failed 'System engine or service setup is incomplete.'
    else
        manager_record component 'VPN Engine' Optional 'Enable VPN setup to install the offline engine and TUN integration.'
    fi
    if path="$(command -v ollama)"; then
        manager_record component 'AI Backend' Installed "$path · start the server and select a model in Serpantinum"
    else
        manager_record component 'AI Backend' Optional 'Ollama is configured separately in the shell. No model downloads are planned.'
    fi
}

manager_dependency_plan() {
    local pkg tool result
    local targets=()
    collect_dependency_targets targets
    local bootstrap=(jq curl git unzip fontconfig)
    for pkg in "${bootstrap[@]}"; do
        tool="$pkg"
        [ "$pkg" != fontconfig ] || tool=fc-cache
        if ! command -v "$tool" >/dev/null; then targets+=("$pkg"); fi
    done
    mapfile -t DEPENDENCY_TARGETS < <(printf '%s\n' "${targets[@]}" | awk '!seen[$0]++')
    result="$(pm_missing_pkgs "${DEPENDENCY_TARGETS[@]}")" || return 1
    MANAGER_MISSING=()
    if [ -n "$result" ]; then mapfile -t MANAGER_MISSING <<< "$result"; fi
    if command -v quickshell >/dev/null && ! quickshell_is_current; then
        MANAGER_MISSING+=(quickshell)
    fi
    if [[ " ${SELECTED_COMPOSITORS[*]} " == *" hyprland "* ]] &&
        hyprland_binary >/dev/null && ! version_at_least "$(hyprland_version)" "$MIN_HYPRLAND_LUA_VERSION"; then
        MANAGER_MISSING+=(hyprland)
    fi
}

manager_probe() {
    local pkg state missing=" ${MANAGER_MISSING[*]} "
    manager_record meta "$OS_NAME" "$DISTRO_ID" "$PM_NAME" "$TARGET_VERSION" "$TARGET_COMMIT" "$INSTALL_STATE"
    manager_record selected "${SELECTED_COMPOSITORS[*]}"
    manager_record display "$(active_display_manager)"
    if [ "$MANAGER_LIVE" = true ]; then
        manager_record warning 'Live/overlay session detected. Verify persistence and space before system changes.'
    fi
    if [ "$PACKAGED_INSTALL" = true ]; then
        manager_record error 'A native Serpantinum package is installed. Use pacman to manage this copy.'
    fi
    for pkg in "${DEPENDENCY_TARGETS[@]}"; do
        state=Installed
        if [[ "$missing" == *" $pkg "* ]]; then state=Missing; fi
        manager_record package "$pkg" "$state"
    done
    if [ "$MANAGER_ACTION" = inspect ]; then
        manager_components
        manager_space || true
    fi
    if [ "$MANAGER_ACTION" = verify ] || [ "$MANAGER_ACTION" = inspect ]; then return 0; fi
    if [ ${#SELECTED_COMPOSITORS[@]} -eq 0 ]; then manager_record error 'Select a compositor.'; fi
    if [ "$OPT_AUR" = true ] && [ "$OPT_BUILD" != true ]; then
        manager_record error 'AUR requires explicit permission to build packages.'
    fi
    if [ "$OPT_REPLACE_CONFIG" = true ] && [ "$OPT_CONFIG" != true ]; then
        manager_record error 'Configuration replacement requires configuration deployment.'
    fi
    manager_space || true
    if [ "$PM_NAME" = pacman ]; then
        if [ "$OPT_SYNC" = true ]; then
            manager_record change 'Refresh pacman databases and perform a full system upgrade after reviewing its transaction.'
            if [ "$MANAGER_LIVE" = true ]; then
                manager_record warning 'This full upgrade can consume significant temporary space in Live. Review the package manager’s actual download and installation sizes before approving its transaction.'
            fi
        else
            manager_record change 'Install using existing pacman databases. Refresh requires a separately selected full system upgrade.'
        fi
        if [ "$OPT_AUR" = true ]; then
            manager_record change 'Allow quickshell-git from AUR only if official binary repositories lack Quickshell. Review the exact recipe before building. Build tools may be required.'
        fi
        manager_pacman_preflight || true
    else
        manager_record change 'Install with DNF. Missing packages may require the configured COPR sources (Hyprland, Quickshell, cliphist, GPU Screen Recorder) or upstream releases (Matugen, Satty). Review any repository and key prompts.'
    fi
    manager_record change "Package targets missing or outdated: ${MANAGER_MISSING[*]:-none}. Native transaction reviews include dependencies, conflicts, changes and sizes."
    manager_record change 'Deploy the shell and themes under ~/.local/share/serpantinum, create user launch links and initial settings, and record the installed version.'
    if [ "$OPT_GLOBAL_LAUNCHERS" = true ]; then
        manager_record change 'Add missing compatibility links in /usr/local/bin using sudo.'
    elif [[ " ${SELECTED_COMPOSITORS[*]} " =~ [[:space:]](niri|sway|mango)[[:space:]] ]]; then
        manager_record warning 'For this desktop session, ensure ~/.local/bin is on its PATH or select compatibility launch links.'
    fi
    if [ "$OPT_CONFIG" = true ]; then
        manager_record change "Deploy configuration for ${SELECTED_COMPOSITORS[*]} and Kitty as applicable."
        if [ "$OPT_REPLACE_CONFIG" = true ]; then
            manager_record change 'Back up and replace matching compositor/Kitty files during installation or repair.'
        elif [ "$MANAGER_ACTION" = update ]; then
            manager_record change 'Update matching unmodified Hyprland files with backups. Keep locally edited files.'
        fi
    fi
    if [ "$OPT_BACKUP" = true ]; then manager_record change 'Make a private pre-installation settings snapshot.'; fi
    if [ "$OPT_SDDM" = true ]; then
        manager_record change "Install SDDM packages and theme. Switch the existing display manager: $REPLACE_DM."
        local display_manager
        display_manager="$(active_display_manager)"
        if [[ -n "$display_manager" && "$display_manager" != sddm && "$REPLACE_DM" != true ]]; then
            manager_record warning "The active display manager is $display_manager. SDDM configuration will be skipped unless switching is selected."
        fi
    fi
    if [ "$OPT_SERVICES" = true ]; then manager_record change 'Set up PAM, NetworkManager, power profiles and PipeWire services.'; fi
    if [ "$OPT_VPN" = true ]; then manager_record change 'Install the checked offline VPN bundle, TUN systemd unit and local polkit rules.'; fi
    if [ "$OPT_ENGINES" = true ]; then manager_record change 'Install Ski and the audio, gamma and core daemons from Serpantinum upstream releases. Update mode checks for newer releases.'; fi
    if [ "$OPT_BUILD" = true ]; then manager_record change 'Allow the audio daemon source build and its compiler dependencies if required.'; fi
    if [ "$OPT_FONTS" = true ]; then manager_record change 'Download missing Iosevka Nerd Fonts.'; fi
    if [ "$OPT_WALLPAPERS" = true ]; then manager_record change "Download wallpapers. Full pack: $INSTALL_FULL_WALLPAPERS."; fi
    if [ "$ENABLE_TELEMETRY" = true ]; then manager_record change 'Send anonymous installation telemetry.'; fi
}

manager_pacman_packages() {
    local pkg official=() aur=() db
    if [ "$OPT_SYNC" != true ] && [ ${#MANAGER_MISSING[@]} -eq 0 ]; then return 0; fi
    db="$(pacman-conf DBPath)" || return 1
    if [ -e "${db%/}/db.lck" ]; then
        echo "Pacman is locked at ${db%/}/db.lck. Wait and retry."
        return 1
    fi
    if [ "$OPT_SYNC" = true ]; then
        local sync_targets=()
        for pkg in "${MANAGER_MISSING[@]}"; do
            if [ "$OPT_AUR" = true ] && pm_aur_recipe "$pkg" >/dev/null; then continue; fi
            sync_targets+=("$pkg")
        done
        printf '@@activity\tDownloading\tPacman databases and system packages\n'
        pm_queue_run pacman --upgrade -- "${sync_targets[@]}" </dev/tty || return 1
        pm_pacman_ready || return 1
        manager_dependency_plan || return 1
        [ ${#MANAGER_MISSING[@]} -gt 0 ] || return 0
    fi
    pm_pacman_ready || return 1
    for pkg in "${MANAGER_MISSING[@]}"; do
        if pacman -Si -- "$pkg" >/dev/null 2>&1; then
            official+=("$pkg")
        elif [ "$OPT_AUR" = true ] && pm_aur_recipe "$pkg" >/dev/null; then
            aur+=("$pkg")
        else
            echo "$pkg is missing from configured pacman repositories. Check mirror metadata or provide a trusted package source."
            return 1
        fi
    done
    if [ ${#official[@]} -gt 0 ]; then
        printf '@@activity\tInstalling\t%s\n' "${official[*]}"
        pm_pacman_install "${official[@]}" </dev/tty || return 1
    fi
    for pkg in "${aur[@]}"; do pm_aur_install "$pkg" || return 1; done
}

manager_dnf_packages() {
    local pkg
    [ ${#MANAGER_MISSING[@]} -gt 0 ] || return 0
    printf '@@activity\tInstalling\t%s\n' "${MANAGER_MISSING[*]}"
    pm_install_batch "${MANAGER_MISSING[@]}" </dev/tty || return 1
    for pkg in "${PM_BATCH_LEFT[@]}"; do
        printf '@@activity\tInstalling\t%s\n' "$pkg"
        if [ "$pkg" = hyprland ] && hyprland_binary >/dev/null &&
            ! version_at_least "$(hyprland_version)" "$MIN_HYPRLAND_LUA_VERSION"; then
            pm_upgrade_hyprland </dev/tty || return 1
            continue
        fi
        if [ "$pkg" = quickshell ] && command -v quickshell >/dev/null && ! quickshell_is_current; then
            pm_upgrade_quickshell </dev/tty || return 1
            continue
        fi
        pm_install_pkg "$pkg" 1 </dev/tty || return 1
    done
}

manager_dependencies() {
    if [ "$PM_NAME" = pacman ]; then manager_pacman_packages || return 1; else manager_dnf_packages || return 1; fi
    hash -r
    manager_dependency_plan || return 1
    if [ ${#MANAGER_MISSING[@]} -gt 0 ]; then
        printf 'Required packages are still missing or outdated: %s\n' "${MANAGER_MISSING[*]}" >&2
        return 1
    fi
    quickshell_is_current || { echo "Quickshell $MIN_QUICKSHELL_VERSION or newer is required."; return 1; }
    if [[ " ${SELECTED_COMPOSITORS[*]} " == *" hyprland "* ]]; then
        version_at_least "$(hyprland_version)" "$MIN_HYPRLAND_LUA_VERSION" ||
            { echo "Hyprland $MIN_HYPRLAND_LUA_VERSION or newer is required."; return 1; }
        if [ "$OPT_CONFIG" = true ]; then check_hyprland_config "$PROJECT_ROOT/compositors/hyprland/hyprland.lua"; fi
    fi
}

manager_engines() {
    local job command fn
    if [ "$OPT_ENGINES" != true ]; then return 0; fi
    for job in 'ski:install_ski' 'serpantinum-audio:install_audio_daemon' \
        'serpantinum-gamma:install_gamma_daemon' 'serpantinum-core:install_core_daemon'; do
        command="${job%%:*}" fn="${job#*:}"
        if [ "$MANAGER_ACTION" != update ] && command -v "$command" >/dev/null; then continue; fi
        printf '@@activity\tDownloading\t%s\n' "$command"
        "$fn"
        hash -r
        if ! command -v "$command" >/dev/null; then FAILED_PKGS+=("$command"); fi
    done
    if [ ${#FAILED_PKGS[@]} -gt 0 ]; then
        printf 'Optional engine setup failed: %s\n' "${FAILED_PKGS[*]}"
        return 1
    fi
}

manager_deploy() {
    local wallpapers
    if [ "$MANAGER_ACTION" != missing ] ||
        [ ! -x "$HOME/.local/bin/serpantinumd" ] ||
        [ ! -f "$HOME/.local/share/serpantinum/src/quickshell/Shell.qml" ]; then
        deploy_package "$PROJECT_ROOT" "$OLD_COMMIT" "$TARGET_COMMIT" "$IS_REINSTALL" "$INSTALL_STATE" "${SELECTED_COMPOSITORS[@]}"
    elif [ "$OPT_CONFIG" = true ]; then
        echo 'Existing program kept. Use Repair to deploy compositor configuration.'
    fi
    wallpapers="$(get_wallpaper_dir)"
    mkdir -p -- "$wallpapers"
    if [ "$OPT_WALLPAPERS" = true ]; then
        printf '@@activity\tDownloading\tWallpaper collection\n'
        install_wallpapers "$INSTALL_FULL_WALLPAPERS"
    else
        install_bundled_wallpapers "$wallpapers"
    fi
    init_serpantinum_config "$PROJECT_ROOT" "$wallpapers"
    if [ "$OPT_CONFIG" = true ]; then
        configure_qt_icon_theme
        configure_ski_defaults "$SERP_NEW_SETTINGS"
    fi
    if [ "$OPT_FONTS" = true ]; then install_fonts; fi
    if [ "$OPT_GLOBAL_LAUNCHERS" = true ]; then
        local launcher
        for launcher in serpantinum serpantinumd; do
            install_launcher_link "$HOME/.local/share/serpantinum/bin/$launcher" "$HOME/.local/bin/$launcher" || return 1
        done
    fi
}

manager_services() {
    setup_sddm "$PROJECT_ROOT"
    if [ "$OPT_SERVICES" = true ]; then setup_services; fi
    if [ "$OPT_VPN" = true ]; then
        if [ "$MANAGER_ACTION" = missing ] && [ -f "$VPN_UNIT_DST" ] && [ -x "$VPN_HELPER_DST" ] &&
            timeout 5s python3 "$PROJECT_ROOT/src/scripts/system/serp_vpn.py" system-engine-check >/dev/null 2>&1; then
            echo 'Existing VPN engine and service kept.'
        else
            install_vpn_components || return 1
        fi
    fi
    if [ "$OPT_CONFIG" = true ] && [ "$OPT_SERVICES" = true ]; then hand_over_from_easyeffects; fi
}

manager_backup() (
    if [ "$OPT_BACKUP" = true ]; then
        source "$INSTALL_DIR/maintenance.sh"
        local snapshot
        snapshot="$(make_snapshot)" || return 1
        echo "Private settings snapshot: $snapshot"
    fi
)

manager_step() {
    local number="$1" status="$2" label="$3"
    shift 3
    if (( number < MANAGER_RESUME )); then return 0; fi
    manager_record '@@phase' "$number" 6 "$status" "$label"
    "$@"
    manager_record '@@done' "$number"
}

manager_run() {
    local lock="${STATE_DIR%/*}/.serpantinum-install.lock"
    if [ "$PACKAGED_INSTALL" = true ]; then
        echo 'Use pacman to manage the native Serpantinum package.'
        return 1
    fi
    if [ "$MANAGER_ACTION" = verify ]; then
        if [ -f "$lock" ]; then
            exec 9<"$lock"
            flock -sn 9 || { echo 'An installation is in progress. Verify after it finishes.'; return 1; }
        fi
        manager_record '@@phase' 1 1 Verifying 'Installed environment'
        verify_installation
        manager_record '@@done' 1
        return
    fi
    [ ${#SELECTED_COMPOSITORS[@]} -gt 0 ] || return 1
    if ! manager_space; then return 1; fi
    if [ "$PM_NAME" = pacman ] && (( MANAGER_RESUME <= 2 )); then
        manager_pacman_preflight || return 1
    fi

    umask 077
    mkdir -p -- "$STATE_DIR"
    exec 9>"$lock"
    flock -n 9 || { echo 'Another installer or maintenance operation is running.'; return 1; }
    MANAGER_TMP="$(mktemp -d)"
    trap 'rm -rf -- "$MANAGER_TMP"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM
    export SUDO_PROMPT=$'\n[Serpantinum sudo] Password for %u: '
    export GIT_TERMINAL_PROMPT=0 GIT_PAGER=cat DNF5_FORCE_INTERACTIVE=1
    export SERPANTINUM_MANAGED_VPN=true
    manager_step 1 Configuring 'Settings snapshot' manager_backup
    manager_step 2 Installing 'Distribution packages' manager_dependencies
    manager_step 3 Installing 'Optional desktop engines' manager_engines
    manager_step 4 Configuring 'Shell and configuration' manager_deploy
    manager_step 5 Configuring 'Services and VPN' manager_services
    manager_step 6 Verifying 'Installed environment' verify_installation

    if [ "$MANAGER_ACTION" != missing ] || [ "$INSTALL_STATE" != current ]; then
        local telemetry_id saved_sddm="$OPT_SDDM" saved_wayland="$SDDM_WAYLAND" saved_wallpapers="$INSTALL_FULL_WALLPAPERS"
        if [ "$OPT_SDDM" != true ]; then
            saved_sddm="$(get_saved_preference OPT_SDDM false)"
            saved_wayland="$(get_saved_preference SDDM_WAYLAND false)"
        fi
        if [ "$OPT_WALLPAPERS" != true ]; then
            saved_wallpapers="$(get_saved_preference INSTALL_FULL_WALLPAPERS false)"
        fi
        if [ "$INSTALL_STATE" = legacy ] && [ "$OPT_CONFIG" = true ]; then
            migrate_legacy
        fi
        if [[ "$INSTALL_STATE" != current || "$MANAGER_ACTION" = repair ]]; then
            rm -f -- "$STATE_DIR/first_launch.done" "$HOME/.local/state/quickshell/first_launch.done"
        fi
        telemetry_id="$(get_telemetry_id)"
        write_version_state "$TARGET_VERSION" "$TARGET_COMMIT" "$telemetry_id" "$ENABLE_TELEMETRY" \
            "${SELECTED_COMPOSITORS[*]}" "$saved_sddm" "$saved_wayland" "$saved_wallpapers"
        if [ "$ENABLE_TELEMETRY" = true ]; then
            bash "$MODULES_DIR/telemetry.sh" --mode done --version "$TARGET_VERSION" --old-version "$OLD_VERSION" \
                --install-state "$INSTALL_STATE" --compositor "${SELECTED_COMPOSITORS[*]}" --id "$telemetry_id" --enabled true
        fi
    fi
}

installer_manager() {
    MANAGED_INSTALL=true
    MANAGER_ACTION="$2"
    MANAGER_RESUME="${5:-1}"
    case "$MANAGER_ACTION" in inspect|install|verify|repair|update|missing) ;; *) return 2 ;; esac
    [[ "$MANAGER_RESUME" =~ ^[1-6]$ ]] || return 2
    source "$PROJECT_ROOT/src/scripts/xdg_paths.sh"
    export QS_STATE_DIR="$(serpantinum_state_dir)" QS_SETTINGS="$(serpantinum_settings_path)"
    source "$MODULES_DIR/version.sh"
    source "$MODULES_DIR/config.sh"
    INSTALL_STATE="$(detect_install_state)"
    TARGET_VERSION="$(get_target_version "$PROJECT_ROOT")"
    TARGET_COMMIT="$(get_target_commit "$PROJECT_ROOT")"
    OLD_VERSION="$(get_installed_version)"
    OLD_COMMIT="$(get_installed_commit)"
    init_compositor_detection
    manager_options "${3:-auto}" "${4:-}"
    MANAGER_LIVE=false PACKAGED_INSTALL=false
    if install_live_session; then MANAGER_LIVE=true; fi
    if [ "$PM_NAME" = pacman ]; then
        source "$MODULES_DIR/pm/aur.sh"
        if pm_is_installed serpantinum || pm_is_installed serpantinum-git; then PACKAGED_INSTALL=true; fi
    fi
    manager_dependency_plan
    IS_REINSTALL=false
    if [ "$MANAGER_ACTION" = repair ]; then IS_REINSTALL=true; fi
    if [ "$1" = --manager-probe ]; then manager_probe; else manager_run; fi
}
