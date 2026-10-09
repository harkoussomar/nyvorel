#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
venv="${NYVOREL_VIRTUAL_ENV:-$HOME/.local/state/quickshell/.venv}"
[[ "$venv" != '~/'* ]] || venv="$HOME/${venv:2}"

# Content-region hints are optional. Manual screenshot/OCR selection must
# still work on minimal Arch, where OpenCV is intentionally not installed.
python=""
for candidate in "$venv/bin/python" "$(command -v python3)"; do
    [[ -x "$candidate" ]] || continue
    if "$candidate" -c 'import cv2, numpy' >/dev/null 2>&1; then
        python="$candidate"
        break
    fi
done
if [[ -z "$python" ]]; then
    printf '[]\n'
    exit 0
fi

if output="$("$python" "$script_dir/find_regions.py" "$@")" \
    && "$python" -c 'import json,sys; assert isinstance(json.loads(sys.stdin.read()), list)' <<< "$output" 2>/dev/null; then
    printf '%s\n' "$output"
else
    printf '[]\n'
fi
