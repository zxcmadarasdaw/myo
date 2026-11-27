#!/usr/bin/env bash

terminal_pick() {
    local title="$1" cursor=0 key i
    shift
    local choices=("$@")
    while true; do
        printf '\033[H\033[2J%s╭── Serpantinum ──────────────────╮%s\n' "$C_CYAN" "$RESET"
        printf '  %s\n  %s · %s MiB · %s cores / %s threads\n  CPU: %s\n  GPU: %s\n  Driver: %s · acceleration: %s\n\n' \
            "$title" "$OS_NAME" "${RAM_MIB:-?}" "${CPU_CORES:-?}" "$CPU_THREADS" "$CPU_INFO" "$GPU_INFO" "${GPU_DRIVERS:-unknown}" "$ACCELERATION"
        for i in "${!choices[@]}"; do
            if (( i == cursor )); then
                printf '%s  ▸ %s%s\n' "$C_CYAN" "${choices[i]}" "$RESET"
            else
                printf '    %s\n' "${choices[i]}"
            fi
        done
        printf '\n  ↑ ↓ Navigate   Enter Select   Esc Back\n'
        key=$(read_key) || return 1
        case "$key" in
            UP|k) cursor=$(( (cursor + ${#choices[@]} - 1) % ${#choices[@]} )) ;;
            DOWN|j) cursor=$(( (cursor + 1) % ${#choices[@]} )) ;;
            ENTER|SPACE) TERMINAL_SELECTION=$cursor; return 0 ;;
            ESC|q) return 1 ;;
        esac
    done
}

terminal_dependencies() {
    local mode="$1" missing comp
    local targets=()
    collect_dependency_targets targets "${SELECTED_COMPOSITORS[@]}"
    printf 'Platform: %s %s (%s)\n' "$DISTRO_ID" "${DISTRO_VERSION:-rolling}" "$PM_NAME"
    printf 'Compositors: %s\n' "${SELECTED_COMPOSITORS[*]:-none selected}"
    printf 'Profile: %s\n' "${INSTALL_PROFILE:-keep existing setting}"
    printf 'SDDM: %s · full wallpaper pack: %s · telemetry: %s\n' "$OPT_SDDM" "$INSTALL_FULL_WALLPAPERS" "$ENABLE_TELEMETRY"
    local wayland=unavailable socket="${WAYLAND_DISPLAY:-}"
    if [[ -n "$socket" ]]; then
        if [[ "$socket" != /* ]]; then socket="${XDG_RUNTIME_DIR:-/}/$socket"; fi
        if [[ -S "$socket" ]]; then wayland=active; fi
    fi
    printf 'Session: %s · Wayland socket: %s\n' "${XDG_SESSION_TYPE:-unknown}" "$wayland"
    if command -v Hyprland >/dev/null; then Hyprland --version 2>/dev/null | head -n 1 || true; fi
    printf 'Bootstrap tools: %s\n' "${PM_BOOTSTRAP_TOOLS[*]}"
    printf 'Package targets: %s\n' "${targets[*]}"
    missing=$(pm_missing_pkgs "${targets[@]}") || return 1
    printf 'Missing packages:\n%s\n' "${missing:-  none}"
    if [[ "$PM_NAME" == emerge && -n "$missing" ]]; then
        printf 'Portage atoms:\n'
        while IFS= read -r comp; do pm_resolve_name "$comp" || return 1; done <<<"$missing"
    fi
    [[ "$mode" == online ]] || return 0
    case "$PM_NAME" in
        pacman) pm_pacman_ready && printf 'Local pacman repository databases are ready.\n' || true ;;
        dnf) dnf -C repolist || true ;;
        void) xbps-query -L || true ;;
        emerge) portageq get_repos /; printf 'Portage reviews dependency and USE constraints before installation.\n' ;;
    esac
    if command -v curl >/dev/null; then
        if curl -sSfI --connect-timeout 4 --max-time 8 https://github.com/ >/dev/null; then
            printf 'GitHub is reachable.\n'
        else
            printf 'Could not reach GitHub. Downloads may fail.\n'
        fi
    else
        printf 'Install curl to check connectivity.\n'
    fi
}

terminal_components() {
    local comp choice
    local candidates=(hyprland niri sway mango umbriel)
    local items=() next=()
    while true; do
        items=()
        for comp in "${candidates[@]}"; do
            if [[ " ${SELECTED_COMPOSITORS[*]} " == *" $comp "* ]]; then items+=("[x] $comp")
            else items+=("[ ] $comp"); fi
        done
        items+=("Back")
        terminal_pick 'Select compositors' "${items[@]}" || return 0
        (( TERMINAL_SELECTION < ${#candidates[@]} )) || return 0
        choice="${candidates[TERMINAL_SELECTION]}"
        next=()
        if [[ " ${SELECTED_COMPOSITORS[*]} " == *" $choice "* ]]; then
            for comp in "${SELECTED_COMPOSITORS[@]}"; do
                if [[ "$comp" != "$choice" ]]; then next+=("$comp"); fi
            done
        else
            next=("${SELECTED_COMPOSITORS[@]}" "$choice")
        fi
        SELECTED_COMPOSITORS=("${next[@]}")
    done
}

terminal_checkbox() {
    if [[ "$1" == true ]]; then printf '[x]'; else printf '[ ]'; fi
}

terminal_installer() {
    inspect_install_hardware
    local answer
    while terminal_pick 'Installation' 'Start installation / update' 'Check dependencies' 'Select components' \
        "Performance profile (${INSTALL_PROFILE:-keep current})" 'Advanced settings' 'Exit'; do
        case "$TERMINAL_SELECTION" in
            0)
                if (( ${#SELECTED_COMPOSITORS[@]} == 0 )); then
                    terminal_components
                    continue
                fi
                IS_REINSTALL=false
                if [[ "$INSTALL_STATE" == current ]]; then
                    terminal_pick "Existing installation" "Update" "Reinstall" || continue
                    if (( TERMINAL_SELECTION == 1 )); then IS_REINSTALL=true; fi
                fi
                if ! terminal_dependencies plan; then
                    printf "\nCannot build the installation plan. Press Enter to return."
                    read -r answer || return 1
                    continue
                fi
                printf '\nProceed with package and service changes? Existing configuration files that are replaced will be backed up. [y/N] '
                read -r answer || return 1
                [[ "$answer" == [yY] ]] && return 0 ;;
            1)
                terminal_dependencies online || printf 'Dependency check failed. Review the package manager output.\n'
                printf '\nPress Enter to return'
                read -r answer || return 1 ;;
            2) terminal_components ;;
            3)
                if terminal_pick "Performance profile · Recommended: $RECOMMENDED_PROFILE" \
                    'Full · standard visuals and playback' 'Light · static wallpaper and reduced motion' 'Keep current setting'; then
                    case "$TERMINAL_SELECTION" in
                        0) INSTALL_PROFILE=full ;;
                        1) INSTALL_PROFILE=light ;;
                        2) INSTALL_PROFILE= ;;
                    esac
                fi ;;
            4)
                if terminal_pick 'Advanced settings' "$(terminal_checkbox "$OPT_SDDM") Install and configure SDDM" \
                    "$(terminal_checkbox "$SDDM_WAYLAND") Use Wayland for SDDM" \
                    "$(terminal_checkbox "$INSTALL_FULL_WALLPAPERS") Full wallpaper collection" \
                    "$(terminal_checkbox "$ENABLE_TELEMETRY") Enable telemetry"; then
                    case "$TERMINAL_SELECTION" in
                        0) OPT_SDDM=$([[ "$OPT_SDDM" == true ]] && echo false || echo true) ;;
                        1) SDDM_WAYLAND=$([[ "$SDDM_WAYLAND" == true ]] && echo false || echo true) ;;
                        2) INSTALL_FULL_WALLPAPERS=$([[ "$INSTALL_FULL_WALLPAPERS" == true ]] && echo false || echo true) ;;
                        3) ENABLE_TELEMETRY=$([[ "$ENABLE_TELEMETRY" == true ]] && echo false || echo true) ;;
                    esac
                fi ;;
            5) break ;;
        esac
    done
    return 1
}
