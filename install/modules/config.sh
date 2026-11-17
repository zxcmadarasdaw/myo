CONFIG_FILE="${QS_SETTINGS:-$HOME/.config/serpantinum/settings.json}"
CONFIG_DIR="$(dirname "$CONFIG_FILE")"

init_serpantinum_config() {
    local project_root="$1"
    local wallpaper_dir="$2"
    local template_json="$project_root/config/serpantinum/settings.json"
    local script_path="$project_root/src/scripts/location.sh"
    local initial_json sys_lang="en"

    SERP_NEW_SETTINGS=false
    if [ -e "$CONFIG_FILE" ] || [ -L "$CONFIG_FILE" ]; then return 0; fi
    mkdir -p "$CONFIG_DIR" || return 1
    command -v detect_system_language &>/dev/null && sys_lang="$(detect_system_language)"

    initial_json="$(jq -e --arg wp "$wallpaper_dir" --arg lang "$sys_lang" '
        . * {wallpaperDir: $wp, general: {language: $lang}}
    ' "$template_json")" || return 1
    (set -o noclobber; printf '%s\n' "$initial_json" > "$CONFIG_FILE") || return 1
    SERP_NEW_SETTINGS=true

    if [ -f "$script_path" ]; then
        bash "$script_path" --refresh >/dev/null 2>&1 || true
    fi
}
