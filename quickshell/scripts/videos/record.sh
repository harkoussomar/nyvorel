#!/usr/bin/env bash

CONFIG_FILE="$HOME/.config/nyvorel/config.json"
JSON_PATH=".screenRecord.savePath"

CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)

RECORDING_DIR=""

if [[ -n "$CUSTOM_PATH" ]]; then
    RECORDING_DIR="$CUSTOM_PATH"
else
    RECORDING_DIR="$HOME/Videos" # Use default path
fi

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}

getaudiooutput() {
    echo "default"
}

getactivemonitor() {
    hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

# parse --region <value> without modifying $@ so other flags like --fullscreen still work
ARGS=("$@")
MANUAL_REGION=""
SOUND_FLAG=0
FULLSCREEN_FLAG=0
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
        else
            notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--sound" ]]; then
        SOUND_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    fi
done


# GPU Screen Recorder region conversion
gsr_region_from_slurp() {
    local value="$1"

    if [[ "$value" =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]+([0-9]+)x([0-9]+)$ ]]; then
        printf '%sx%s%+d%+d\n' \
            "${BASH_REMATCH[3]}" \
            "${BASH_REMATCH[4]}" \
            "${BASH_REMATCH[1]}" \
            "${BASH_REMATCH[2]}"
        return 0
    fi

    if [[ "$value" =~ ^[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+$ ]]; then
        printf "%s\n" "$value"
        return 0
    fi

    echo "Unsupported region geometry: $value" >&2
    return 1
}

if pgrep -f '(^|/)gpu-screen-recorder( |$)' >/dev/null; then
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' &
    pkill -INT -f '(^|/)gpu-screen-recorder( |$)' &
else
    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        notify-send "Starting recording" 'recording_'"$(getdate)"'.mp4' -a 'Recorder' & disown
        if [[ $SOUND_FLAG -eq 1 ]]; then
            gpu-screen-recorder -f 60 -fm cfr -k h264 -q very_high -bm qp -cr limited -encoder gpu -w "$(getactivemonitor)" -a device:easyeffects_source -ac opus -ab 192 -o "./recording_$(getdate).mkv"
        else
            gpu-screen-recorder -f 60 -fm cfr -k h264 -q very_high -bm qp -cr limited -encoder gpu -w "$(getactivemonitor)" -o "./recording_$(getdate).mkv"
        fi
    else
        # If a manual region was provided via --region, use it; otherwise run slurp as before.
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                exit 1
            fi
        fi

        notify-send "Starting recording" 'recording_'"$(getdate)"'.mp4' -a 'Recorder' & disown
        if [[ $SOUND_FLAG -eq 1 ]]; then
            gpu-screen-recorder -f 60 -fm cfr -k h264 -q very_high -bm qp -cr limited -encoder gpu -w "$(gsr_region_from_slurp "$region")" -a device:easyeffects_source -ac opus -ab 192 -o "./recording_$(getdate).mkv"
        else
            gpu-screen-recorder -f 60 -fm cfr -k h264 -q very_high -bm qp -cr limited -encoder gpu -w "$(gsr_region_from_slurp "$region")" -o "./recording_$(getdate).mkv"
        fi
    fi
fi
