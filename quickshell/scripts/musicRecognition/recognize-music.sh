#!/usr/bin/env bash
set -uo pipefail
umask 077

interval=4
duration=16
source_type=monitor

while getopts 'i:t:s:' option; do
    case "$option" in
        i) interval=$OPTARG ;;
        t) duration=$OPTARG ;;
        s) source_type=$OPTARG ;;
        *) exit 3 ;;
    esac
done

[[ "$interval" =~ ^[1-9][0-9]?$ && "$duration" =~ ^([1-9][0-9]?|100)$ ]] || exit 3
for dependency in pactl parec ffmpeg songrec jq timeout; do
    command -v "$dependency" >/dev/null 2>&1 || exit 3
done

case "$source_type" in
    monitor) sink=$(pactl get-default-sink) && source_name="$sink.monitor" || exit 4 ;;
    input) source_name=$(pactl get-default-source) || exit 4 ;;
    *) exit 4 ;;
esac
[[ -n "$source_name" ]] || exit 4
pactl list short sources | awk -v name="$source_name" '$2 == name {found = 1} END {exit !found}' || exit 4

work=$(mktemp -d "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/nyvorel-songrec.XXXXXX") || exit 5
recorder=""
worker=""
cleanup() {
    if [[ -n "$worker" ]]; then
        kill "$worker" 2>/dev/null || true
        wait "$worker" 2>/dev/null || true
    fi
    if [[ -n "$recorder" ]]; then
        kill "$recorder" 2>/dev/null || true
        wait "$recorder" 2>/dev/null || true
    fi
    rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

wait_for() {
    "$@" &
    worker=$!
    local status=0
    wait "$worker" || status=$?
    worker=""
    return "$status"
}

rate=16000
raw="$work/audio.pcm"
sample="$work/sample.wav"
deadline=$((SECONDS + duration))
parec --raw --device="$source_name" --format=s16le --rate="$rate" --channels=1 >"$raw" &
recorder=$!

# Send a useful initial sample, then retry with fresh audio from the same stream.
initial=$((duration / 2))
((initial < 8)) || initial=8
((initial > 0)) || initial=1
wait_for sleep "$initial"
got_response=false

while ((SECONDS < deadline)); do
    kill -0 "$recorder" 2>/dev/null || exit 5
    [[ -s "$raw" ]] || exit 5
    tail -c "$((rate * 2 * 12))" -- "$raw" | ffmpeg -nostdin -v error \
        -f s16le -ar "$rate" -ac 1 -i pipe:0 -y "$sample" || exit 5

    remaining=$((deadline - SECONDS))
    ((remaining > 0)) || break
    if wait_for timeout --kill-after=1s "${remaining}s" songrec recognize --json "$sample" >"$work/result.json" &&
        jq -e 'type == "object"' "$work/result.json" >/dev/null 2>&1; then
        got_response=true
        if jq -ce 'select(.track.title | type == "string" and length > 0)' "$work/result.json"; then
            exit 0
        fi
    fi

    remaining=$((deadline - SECONDS))
    ((remaining > interval)) || break
    wait_for sleep "$interval"
done

if "$got_response"; then
    exit 2
fi
exit 6
