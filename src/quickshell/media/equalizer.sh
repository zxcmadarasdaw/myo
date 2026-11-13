#!/usr/bin/env bash
# Keep the historic entry point; all state/control commands use one adapter.
case "$1" in
    test|stop_test) ;;
    *) exec python3 "$(dirname "${BASH_SOURCE[0]}")/equalizer.py" "$@" ;;
esac
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/caching.sh"
qs_ensure_cache "music"
SINK_NAME="serpantinum_sink"
TEST_FILE="$QS_RUN_MUSIC/channel_test.wav"
TEST_PID_FILE="$QS_RUN_MUSIC/channel_test.pid"
stop_test() {
    if [ -f "$TEST_PID_FILE" ]; then
        pid=$(cat "$TEST_PID_FILE" 2>/dev/null || true)
        if [[ "$pid" =~ ^[0-9]+$ ]]; then
            kill "$pid" >/dev/null 2>&1 || true
        fi
        rm -f "$TEST_PID_FILE"
    fi
}

play_test() {
    stop_test

    if [ ! -s "$TEST_FILE" ]; then
        python3 - "$TEST_FILE" <<'PY'
import math, struct, sys, wave

path = sys.argv[1]
rate = 48000
segments = [(0.75, 660, 0), (0.18, 0, 0), (0.75, 0, 880),
            (0.18, 0, 0), (1.0, 770, 770)]
with wave.open(path, 'wb') as out:
    out.setnchannels(2)
    out.setsampwidth(2)
    out.setframerate(rate)
    for duration, left_hz, right_hz in segments:
        for index in range(int(duration * rate)):
            fade = min(1.0, index / (rate * 0.015),
                       (duration * rate - index) / (rate * 0.015))
            def sample(freq):
                return int(9000 * fade * math.sin(2 * math.pi * freq * index / rate)) if freq else 0
            out.writeframesraw(struct.pack('<hh', sample(left_hz), sample(right_hz)))
PY
    fi

    target=()
    if command -v pw-dump >/dev/null 2>&1 &&
       pw-dump 2>/dev/null | jq -e --arg n "$SINK_NAME" 'any(.[]; .info.props["node.name"] == $n)' >/dev/null 2>&1; then
        target=(--target="$SINK_NAME")
    fi

    (
        player_pid=""
        cleanup_test() {
            [ -n "$player_pid" ] && kill "$player_pid" >/dev/null 2>&1 || true
            if [ "$(cat "$TEST_PID_FILE" 2>/dev/null)" = "$BASHPID" ]; then
                rm -f "$TEST_PID_FILE"
            fi
        }
        trap cleanup_test EXIT TERM INT
        pw-play "${target[@]}" \
            -P '{"application.id":"serpantinum-audio-test","application.name":"Serpantinum audio test","media.role":"music"}' \
            "$TEST_FILE" >/dev/null 2>&1 &
        player_pid=$!
        wait "$player_pid"
    ) &
    echo "$!" > "$TEST_PID_FILE"
}

case "$1" in
    test) play_test ;;
    stop_test) stop_test ;;
esac
