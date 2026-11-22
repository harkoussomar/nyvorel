#!/usr/bin/env bash

runtime="${XDG_RUNTIME_DIR:?Nyvorel recording requires XDG_RUNTIME_DIR}"
state="$runtime/nyvorel-recording.json"
socket="$runtime/nyvorel-recorder.sock"
run_lock="$runtime/nyvorel-recording.lock"
control_lock="$runtime/nyvorel-recording-control.lock"
umask 077

write_state() {
    local temp
    temp=$(mktemp "$state.XXXXXX") || return
    if jq -cn --arg phase "$1" --arg screen "$2" --argjson elapsed "$3" --argjson since "$4" \
        '{phase:$phase,screen:$screen,elapsed:$elapsed,since:$since}' > "$temp"; then
        mv -f -- "$temp" "$state"
    else
        rm -f -- "$temp"
        return 1
    fi
}

case "${1:-}" in
    --active)
        flock -n "$run_lock" true && exit 1
        exit 0
        ;;
    --pause|--resume|--stop)
        exec 8>"$control_lock"
        flock 8
        [[ -S "$socket" && -s "$state" ]] || exit 1
        read -r phase elapsed since < <(jq -r '[.phase,.elapsed,.since] | @tsv' "$state")
        screen=$(jq -r .screen "$state")
        now=$(date +%s%3N)
        case "$1:$phase" in
            --pause:recording)
                timeout 3 gsr-cli -ipc "$socket" set-paused true >/dev/null || exit 1
                write_state paused "$screen" "$((elapsed + now - since))" 0
                ;;
            --resume:paused)
                timeout 3 gsr-cli -ipc "$socket" set-paused false >/dev/null || exit 1
                write_state recording "$screen" "$elapsed" "$now"
                ;;
            --stop:recording|--stop:paused)
                [[ "$phase" != recording ]] || elapsed=$((elapsed + now - since))
                write_state stopping "$screen" "$elapsed" 0
                if ! timeout 15 gsr-cli -ipc "$socket" stop >/dev/null; then
                    write_state "$phase" "$screen" "$elapsed" "$now"
                    exit 1
                fi
                ;;
            *) exit 1 ;;
        esac
        exit
        ;;
esac

exec 9>"$run_lock"
if ! flock -n 9; then
    notify-send -a Recorder "A recording is already in progress"
    exit 1
fi

region=
monitor=
system_audio=false
microphone=false
fullscreen=false
while (($#)); do
    case "$1" in
        --region) region=${2:?Missing region}; shift ;;
        --monitor) monitor=${2:?Missing monitor}; shift ;;
        --fullscreen) fullscreen=true ;;
        --sound|--system-audio) system_audio=true ;;
        --microphone) microphone=true ;;
        *) exit 2 ;;
    esac
    shift
done

audio_sources=()
"$system_audio" && audio_sources+=(default_output)
"$microphone" && audio_sources+=(default_input)
audio=()
if (("${#audio_sources[@]}")); then
    audio=(-a "$(IFS='|'; printf '%s' "${audio_sources[*]}")" -ac opus -ab 192)
fi

if ! command -v gpu-screen-recorder >/dev/null || ! command -v gsr-cli >/dev/null; then
    notify-send -a Recorder "Recording unavailable" "Install GPU Screen Recorder to capture video."
    exit 1
fi

if [[ -z "$monitor" ]]; then
    monitor=$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')
fi
if "$fullscreen"; then
    [[ -n "$monitor" ]] || exit 1
    capture=(-w "$monitor")
else
    if [[ -z "$region" ]]; then
        region=$(slurp) || exit
    fi
    if [[ "$region" =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]+([0-9]+)x([0-9]+)$ ]]; then
        printf -v region '%sx%s%+d%+d' "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    fi
    if [[ ! "$region" =~ ^[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+$ ]]; then
        notify-send -a Recorder "Recording unavailable" "Invalid capture region."
        exit 1
    fi
    capture=(-w region -region "$region")
fi

config="${XDG_CONFIG_HOME:-$HOME/.config}/nyvorel/config.json"
directory=$(jq -r '.screenRecord.savePath // empty' "$config" 2>/dev/null)
directory=${directory:-$(xdg-user-dir VIDEOS)}
directory=${directory:-"$HOME/Videos"}
if ! mkdir -p -- "$directory"; then
    notify-send -a Recorder "Recording unavailable" "Could not open the recordings folder."
    exit 1
fi

output="$directory/recording_$(date '+%Y-%m-%d_%H.%M.%S').mkv"
cleanup() {
    exec 8>"$control_lock"
    flock 8
    rm -f -- "$state" "$socket"
}
trap cleanup EXIT
rm -f -- "$socket"
write_state starting "$monitor" 0 0 || exit 1
gpu-screen-recorder -f 60 -fm cfr -k h264 -q very_high -bm qp -cr limited -encoder gpu \
    "${capture[@]}" "${audio[@]}" -ipc "$socket" -o "$output" &
recorder=$!

for ((attempt=0; attempt<60; attempt++)); do
    [[ -S "$socket" ]] && break
    kill -0 "$recorder" 2>/dev/null || break
    sleep .1
done
if [[ ! -S "$socket" ]] || ! timeout 12 gsr-cli -ipc "$socket" set-paused false >/dev/null; then
    kill -INT "$recorder" 2>/dev/null || true
    wait "$recorder"
    notify-send -a Recorder "Recording failed" "GPU Screen Recorder could not start the capture."
    exit 1
fi
write_state recording "$monitor" 0 "$(date +%s%3N)"
if wait "$recorder"; then
    notify-send -a Recorder "Recording saved" "${output##*/}"
else
    notify-send -a Recorder "Recording failed" "GPU Screen Recorder could not complete the capture."
    exit 1
fi
