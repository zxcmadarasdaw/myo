#!/usr/bin/env bash

# The graphical and terminal installers share the native transaction runner.
pm_queue_run() {
    local backend="$1" package
    shift
    if ! command -v python3 >/dev/null; then
        package=python3
        [ "$backend" != pacman ] || package=python
        bootstrap_tool "$package" 'Python 3 is required to report package progress.' || return 1
    fi
    python3 "$PM_QUEUE_WORKER" "$backend" "$@"
}
