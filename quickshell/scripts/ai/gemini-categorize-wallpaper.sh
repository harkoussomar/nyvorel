#!/usr/bin/env bash
set -euo pipefail

wallpaper=""
if [[ "${1:-}" == "--save-cookie-style" ]]; then
    wallpaper="${2:?Wallpaper path is required}"
    shift 2
fi

source_image="${1:?Wallpaper image is required}"
model="${2:-${GEMINI_WALLPAPER_MODEL:-gemini-2.5-flash}}"
prompt="${3:-${GEMINI_WALLPAPER_PROMPT:-Categorize the wallpaper. Its file name is $(basename -- "$source_image")}}"
config="${XDG_CONFIG_HOME:-$HOME/.config}/nyvorel/config.json"
still_enabled() {
    jq -e --arg wallpaper "$wallpaper" '
        .background.wallpaperPath == $wallpaper and .background.widgets.clock.cookie.aiStyling == true
    ' "$config" >/dev/null
}

if [[ -n "$wallpaper" ]]; then
    still_enabled || exit 0
fi
[[ -f "$source_image" && "$model" =~ ^[A-Za-z0-9_.-]+$ ]]
key="$(timeout 8 secret-tool lookup application nyvorel | jq -er '.apiKeys.gemini // empty')"
[[ "$key" =~ ^[A-Za-z0-9_-]+$ ]]

scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT
magick "${source_image}[0]" -thumbnail '200x200>' -quality 55 "$scratch/wallpaper.jpg"
base64 -w0 "$scratch/wallpaper.jpg" > "$scratch/image.base64"
jq -n --rawfile image "$scratch/image.base64" --arg prompt "$prompt" '{
    contents: [{parts: [
        {inline_data: {mime_type: "image/jpeg", data: $image}},
        {text: $prompt}
    ]}],
    generationConfig: {
        responseMimeType: "text/x.enum",
        responseSchema: {
            type: "string",
            enum: ["abstract", "anime", "city", "minimalist", "landscape", "plants", "person", "space"]
        },
        temperature: 0
    }
}' > "$scratch/request.json"

category="$(
    printf 'header = "x-goog-api-key: %s"\n' "$key" |
        curl --config - --fail --silent --show-error --max-time 20 \
        -H 'Content-Type: application/json' -X POST --data-binary "@$scratch/request.json" \
        "https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent" |
        jq -er '.candidates[0].content.parts[0].text'
)"
[[ "$category" =~ ^(abstract|anime|city|minimalist|landscape|plants|person|space)$ ]]

if [[ -z "$wallpaper" ]]; then
    printf '%s\n' "$category"
elif still_enabled; then
    directory="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/wallpaper"
    mkdir -p -- "$directory"
    pending="$(mktemp "$directory/.category.XXXXXX")"
    trap 'rm -rf -- "$scratch"; rm -f -- "$pending"' EXIT
    jq -n --arg wallpaper "$wallpaper" --arg category "$category" \
        '{wallpaper: $wallpaper, category: $category}' > "$pending"
    mv -fT -- "$pending" "$directory/category.txt"
fi
