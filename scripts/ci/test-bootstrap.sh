#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

RUNTIME="${NYVOREL_CONTAINER_RUNTIME:-}"
IMAGE="${NYVOREL_BOOTSTRAP_IMAGE:-archlinux:base}"

if [[ -z "$RUNTIME" ]]; then
  if command -v podman >/dev/null 2>&1; then
    RUNTIME="podman"
  elif command -v docker >/dev/null 2>&1; then
    RUNTIME="docker"
  else
    die "podman or docker is required for the pristine-Arch bootstrap regression"
  fi
fi

command -v "$RUNTIME" >/dev/null 2>&1 \
  || die "requested container runtime is unavailable: $RUNTIME"

echo "== Nyvorel pristine Arch bootstrap planning =="
echo "runtime=$RUNTIME"
echo "image=$IMAGE"

"$RUNTIME" run --rm -i \
  -v "$ROOT:/src:ro" \
  "$IMAGE" \
  bash -s <<'CONTAINER'
set -Eeuo pipefail

pacman -Syu --noconfirm --needed \
  bash python coreutils >/dev/null

echo "== Install candidate into isolated Arch HOME =="
TARGET_HOME=/work/nyvoreltest
mkdir -p "$TARGET_HOME"
/src/install.sh \
  --target-home "$TARGET_HOME" \
  --yes \
  --no-activate >/work/install.log

CLI="$TARGET_HOME/.local/bin/nyvorel"
CONTRACT="$TARGET_HOME/.local/share/nyvorel/dependencies/arch.json"
[[ -x "$CLI" ]]
[[ -x "$TARGET_HOME/.local/bin/nyvorel-bootstrap" ]]
[[ -s "$CONTRACT" ]]

echo "== Build deterministic command/repository fixtures =="
mkdir -p /work/fake-bin
PACMAN_LOG=/work/pacman.log
: >"$PACMAN_LOG"

make_stub() {
  local name="$1"
  cat >"/work/fake-bin/$name" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "/work/fake-bin/$name"
}

python3 - "$CONTRACT" <<'PY' >/work/required-commands.txt
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
assert data["schema"] == 2

for entry in data["required"]:
    file_key = next((key for key in ("files_any_of", "files_all_of") if key in entry), None)
    if file_key:
        fixture = Path(sys.argv[1]).parent / (entry["id"] + ".fixture")
        fixture.write_text("test runtime asset\n")
        entry[file_key] = [str(fixture)]
        continue
    if isinstance(entry.get("commands_all_of"), list):
        for command in entry["commands_all_of"]:
            print(command)
    else:
        print(entry["commands_any_of"][0])
Path(sys.argv[1]).write_text(json.dumps(data))
PY

while IFS= read -r command; do
  [[ -n "$command" ]] && make_stub "$command"
done </work/required-commands.txt

# Force three missing required groups so the planner must build a package plan.
rm -f /work/fake-bin/hyprctl
rm -f /work/fake-bin/qs /work/fake-bin/quickshell
rm -f /work/fake-bin/git

cat >/work/fake-pacman <<'PACMAN'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >>"${NYVOREL_TEST_PACMAN_LOG:?}"

if [[ "${1:-}" == "-Si" && $# -eq 2 ]]; then
  if [[ "${NYVOREL_TEST_FAIL_QUICKSHELL:-0}" == "1" ]]; then
    case "$2" in
      quickshell|quickshell-git) exit 1 ;;
    esac
  fi
  exit 0
fi

echo "unexpected mutating/unsupported pacman call: $*" >&2
exit 91
PACMAN
chmod +x /work/fake-pacman

COMMON_ENV=(
  "HOME=$TARGET_HOME"
  "NYVOREL_BOOTSTRAP_SEARCH_PATH=/work/fake-bin"
  "NYVOREL_PACMAN_BIN=/work/fake-pacman"
  "NYVOREL_TEST_PACMAN_LOG=$PACMAN_LOG"
)

echo "== Required-only default plan =="
env "${COMMON_ENV[@]}" \
  "$CLI" bootstrap --json >/work/required-plan.json

python3 - /work/required-plan.json <<'PY'
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
assert data["schema"] == 1
assert data["product"] == "Nyvorel"
assert data["mode"] == "plan-only"
assert data["mutation_performed"] is False
assert data["status"] == "READY"
assert data["optional"]["selected_ids"] == []
assert data["required"]["satisfied"] < data["required"]["total"]

missing = {item["id"] for item in data["required"]["missing"]}
assert {"hyprland", "quickshell", "git"} <= missing, missing

packages = set(data["pacman_packages"])
assert "hyprland" in packages
assert "git" in packages
assert "quickshell" in packages
PY

echo "== Explicit optional selection =="
env "${COMMON_ENV[@]}" \
  "$CLI" bootstrap \
  --optional screenshots \
  --json >/work/optional-plan.json

python3 - /work/optional-plan.json <<'PY'
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
assert data["optional"]["selected_ids"] == ["screenshots"]
missing = {item["id"]: item for item in data["optional"]["missing"]}
assert "screenshots" in missing
assert missing["screenshots"]["command_mode"] == "all"
assert missing["screenshots"]["package_plan"]["package_mode"] == "all"

packages = set(data["pacman_packages"])
assert "grim" in packages
assert "slurp" in packages
PY

echo "== Fully satisfied required baseline =="
make_stub hyprctl
make_stub qs
make_stub git

env "${COMMON_ENV[@]}" \
  "$CLI" bootstrap --json >/work/satisfied.json

python3 - /work/satisfied.json <<'PY'
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
assert data["required"]["satisfied"] == data["required"]["total"]
assert data["required"]["missing"] == []
assert data["pacman_packages"] == []
assert data["manual_required"] == []
assert data["status"] == "READY"
PY

echo "== Unresolved required provider =="
rm -f /work/fake-bin/qs /work/fake-bin/quickshell

set +e
env \
  "${COMMON_ENV[@]}" \
  NYVOREL_TEST_FAIL_QUICKSHELL=1 \
  "$CLI" bootstrap --json >/work/manual.json
MANUAL_RC=$?
set -e

[[ "$MANUAL_RC" == "1" ]]

python3 - /work/manual.json <<'PY'
from pathlib import Path
import json
import sys

data = json.loads(Path(sys.argv[1]).read_text())
assert data["status"] == "MANUAL_REQUIRED"
manual = {item["id"] for item in data["manual_required"]}
assert "quickshell" in manual, manual
assert data["mutation_performed"] is False
PY

echo "== Pacman probe is read-only =="
[[ -s "$PACMAN_LOG" ]]
if grep -Ev '^-Si [A-Za-z0-9@._+-]+$' "$PACMAN_LOG"; then
  echo "bootstrap invoked a pacman operation other than -Si" >&2
  exit 1
fi

echo "PASS  pristine Arch required/optional/manual bootstrap planning without package mutation"
CONTAINER

echo "PASS  pristine Arch bootstrap planning regression"
