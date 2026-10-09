#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/venv/bin"
real_python="$(command -v python3)"
export HOME="$tmp/home"
mkdir -p "$HOME"

cat > "$tmp/venv/bin/python" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == -c && "${2:-}" == 'import cv2, numpy' ]]; then
    [[ "${NYVOREL_TEST_HAS_CV2:-0}" == 1 ]]
    exit
fi
if [[ "${1:-}" == -c ]]; then
    exec "${NYVOREL_TEST_REAL_PYTHON:?}" "$@"
fi
printf '%s\n' "${NYVOREL_TEST_DETECTOR_OUTPUT:-[]}"
[[ "${NYVOREL_TEST_DETECTOR_FAIL:-0}" != 1 ]]
EOF
cp "$tmp/venv/bin/python" "$tmp/bin/python3"
chmod +x "$tmp/venv/bin/python" "$tmp/bin/python3"
export PATH="$tmp/bin:$PATH"
export NYVOREL_VIRTUAL_ENV="$tmp/venv"
export NYVOREL_TEST_REAL_PYTHON="$real_python"
wrapper="$root/quickshell/scripts/images/find-regions-venv.sh"

[[ "$(NYVOREL_TEST_HAS_CV2=0 "$wrapper" --image missing)" == '[]' ]]
[[ "$(NYVOREL_TEST_HAS_CV2=0 NYVOREL_VIRTUAL_ENV='~/.local/state/quickshell/.venv' "$wrapper" --image missing)" == '[]' ]]
expected='[{"at":[1,2],"size":[3,4]}]'
[[ "$(NYVOREL_TEST_HAS_CV2=1 NYVOREL_TEST_DETECTOR_OUTPUT="$expected" "$wrapper" --image fixture)" == "$expected" ]]
[[ "$(NYVOREL_TEST_HAS_CV2=1 NYVOREL_TEST_DETECTOR_OUTPUT=not-json "$wrapper" --image fixture)" == '[]' ]]
[[ "$(NYVOREL_TEST_HAS_CV2=1 NYVOREL_TEST_DETECTOR_FAIL=1 "$wrapper" --image fixture)" == '[]' ]]
echo 'PASS optional content detection returns valid region JSON or an empty list'
