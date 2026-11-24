#!/usr/bin/env bash
set -euo pipefail

if ! command -v fastfetch >/dev/null; then
    printf 'Abyss Terminal requires fastfetch.\n' >&2
    exit 127
fi

theme_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config="$theme_dir/abyss-fetch.jsonc"
poster="$theme_dir/media/abyss-fetch.png"
gif="$theme_dir/media/abyss-fetch.gif"
args=(--config "$config")

if [[ -t 1 && ${TERM:-} == xterm-kitty ]]; then
    if [[ ${1:-} == --animate ]] && command -v kitten >/dev/null; then
        if fastfetch "${args[@]}" --logo-type kitty-icat --logo "$gif"; then
            exit 0
        fi
    fi
    exec fastfetch "${args[@]}" --logo-type kitty-direct --logo "$poster"
fi

if [[ -t 1 && ${TERM_PROGRAM:-} =~ ^(iTerm.app|WezTerm|ghostty)$ ]]; then
    exec fastfetch "${args[@]}" --logo-type iterm --logo "$poster"
fi

# Text stays readable in emulators without a graphic protocol and when piped.
exec fastfetch "${args[@]}"
