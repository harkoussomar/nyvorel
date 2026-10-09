#!/usr/bin/env bash
set -Eeuo pipefail

TARGET_HOME="${HOME:?HOME is not set}"
STATE_ARG=""
ASSUME_YES=0
DRY_RUN=0
FORCE_CHANGED=0
DEACTIVATE=1

usage() {
  cat <<'EOF'
Nyvorel uninstaller / recovery tool

Usage:
  ./uninstall.sh [options]

Options:
  --target-home PATH   Operate on another home directory.
  --state PATH         Use a specific Nyvorel installation-state directory.
  --yes                Confirm restore/removal without an interactive prompt.
  --dry-run            Show what would be restored/removed without changing files.
  --force-changed      Continue when installed files changed after installation;
                       changed files are archived before restore/removal.
  --deactivate         Stop/disable Nyvorel user services (default).
  --no-deactivate      Do not touch systemd user services.
  -h, --help           Show this help.

By default the tool reads:
  ~/.local/state/nyvorel/current-install

It restores every file that existed before installation and removes only files
that Nyvorel created. Runtime/user state under ~/.config/nyvorel is retained.
EOF
}

while (($#)); do
  case "$1" in
    --target-home)
      (($# >= 2)) || { echo "ERROR: --target-home requires a path" >&2; exit 2; }
      TARGET_HOME="$2"
      shift 2
      ;;
    --state)
      (($# >= 2)) || { echo "ERROR: --state requires a path" >&2; exit 2; }
      STATE_ARG="$2"
      shift 2
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --force-changed)
      FORCE_CHANGED=1
      shift
      ;;
    --deactivate)
      DEACTIVATE=1
      shift
      ;;
    --no-deactivate)
      DEACTIVATE=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: Python 3 is required." >&2
  exit 1
}

TARGET_HOME="$(python3 - "$TARGET_HOME" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
)"

[[ "$TARGET_HOME" != "/" ]] || {
  echo "ERROR: refusing to use / as target home" >&2
  exit 1
}

REAL_HOME="$(python3 - "$HOME" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
)"

if [[ -n "$STATE_ARG" ]]; then
  STATE="$(python3 - "$STATE_ARG" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
)"
else
  CURRENT_POINTER="$TARGET_HOME/.local/state/nyvorel/current-install"
  [[ -f "$CURRENT_POINTER" ]] || {
    echo "ERROR: no current Nyvorel installation pointer: $CURRENT_POINTER" >&2
    exit 1
  }
  STATE="$(tr -d '\r\n' <"$CURRENT_POINTER")"
fi

MANIFEST="$STATE/manifest.json"
[[ -f "$MANIFEST" ]] || {
  echo "ERROR: installation manifest not found: $MANIFEST" >&2
  exit 1
}

if (( DEACTIVATE )) && [[ "$TARGET_HOME" != "$REAL_HOME" ]]; then
  echo "ERROR: --deactivate is only allowed for the current user's real HOME." >&2
  echo "Use --no-deactivate for a sandbox/alternate home." >&2
  exit 1
fi

echo "============================================================"
echo "NYVOREL UNINSTALL / RECOVERY"
echo "============================================================"
echo "Target home   : $TARGET_HOME"
echo "Install state : $STATE"
echo "Dry run       : $([[ $DRY_RUN -eq 1 ]] && echo yes || echo no)"
echo "Force changed : $([[ $FORCE_CHANGED -eq 1 ]] && echo yes || echo no)"
echo "Deactivate    : $([[ $DEACTIVATE -eq 1 ]] && echo yes || echo no)"
echo

# Preflight and plan before service changes or filesystem mutation.
PLAN_JSON="$(
  python3 - \
    "$MANIFEST" \
    "$TARGET_HOME" \
    "$FORCE_CHANGED" <<'PYPLAN'
from __future__ import annotations

from pathlib import Path
import hashlib
import json
import os
import sys

manifest_path = Path(sys.argv[1])
home = Path(sys.argv[2]).resolve(strict=False)
force_changed = sys.argv[3] == "1"

def lexists(path: Path) -> bool:
    return os.path.lexists(path)

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

data = json.loads(manifest_path.read_text())

if data.get("schema") != 1:
    raise SystemExit("unsupported manifest schema")
if data.get("product") != "Nyvorel":
    raise SystemExit("manifest is not a Nyvorel installation")
if data.get("status") != "installed":
    raise SystemExit(f"manifest status is not installed: {data.get('status')!r}")
if Path(data.get("target_home", "")).resolve(strict=False) != home:
    raise SystemExit("manifest target_home does not match requested target home")

entries = data.get("entries")
if not isinstance(entries, list) or not entries:
    raise SystemExit("manifest contains no installation entries")

changed = []
missing = []
restore_count = 0
remove_count = 0

for entry in entries:
    rel = Path(entry["destination"])
    if rel.is_absolute() or ".." in rel.parts:
        raise SystemExit(f"unsafe manifest destination: {rel}")
    if entry.get("ownership") == "runtime" and rel.as_posix() != ".config/hypr/custom/appearance-runtime.conf":
        raise SystemExit(f"invalid runtime ownership destination: {rel}")

    dest = home / rel
    installed = entry.get("installed")
    if not isinstance(installed, dict):
        raise SystemExit(f"missing installed digest for {rel}")

    if entry.get("preexisting"):
        restore_count += 1
        backup_rel = entry.get("backup")
        if not backup_rel:
            raise SystemExit(f"preexisting entry has no backup: {rel}")
        backup = manifest_path.parent / Path(backup_rel)
        if not lexists(backup):
            raise SystemExit(f"required backup missing: {backup}")
    else:
        remove_count += 1

    if not lexists(dest):
        missing.append(rel.as_posix())
        changed.append(rel.as_posix())
        continue

    if entry.get("ownership") == "runtime":
        if not dest.is_file() or dest.is_symlink():
            changed.append(rel.as_posix())
        continue

    kind = installed.get("kind")
    expected = installed.get("value")

    if kind == "symlink":
        same = dest.is_symlink() and os.readlink(dest) == expected
    elif kind == "file":
        same = dest.is_file() and not dest.is_symlink() and sha256_file(dest) == expected
    else:
        raise SystemExit(f"unknown installed digest kind for {rel}: {kind!r}")

    if not same:
        changed.append(rel.as_posix())

plan = {
    "entries": len(entries),
    "restore": restore_count,
    "remove": remove_count,
    "changed": changed,
    "missing": missing,
    "force_changed": force_changed,
}
print(json.dumps(plan))
PYPLAN
)"

ENTRIES="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["entries"])' "$PLAN_JSON")"
RESTORES="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["restore"])' "$PLAN_JSON")"
REMOVALS="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["remove"])' "$PLAN_JSON")"
CHANGED_COUNT="$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])["changed"]))' "$PLAN_JSON")"

echo "Managed entries : $ENTRIES"
echo "Restore backups : $RESTORES"
echo "Remove created  : $REMOVALS"
echo "Changed/missing : $CHANGED_COUNT"

if (( CHANGED_COUNT > 0 )); then
  echo
  echo "Installed files changed or disappeared after installation:"
  python3 - "$PLAN_JSON" <<'PY'
import json,sys
for path in json.loads(sys.argv[1])["changed"][:40]:
    print("  " + path)
PY

  if (( ! FORCE_CHANGED )); then
    echo
    echo "ERROR: refusing to overwrite/remove changed installed files." >&2
    echo "Re-run with --force-changed to archive changed files first." >&2
    exit 3
  fi
fi

if (( DRY_RUN )); then
  echo
  echo "DRY RUN — no files or services changed."
  exit 0
fi

if (( ! ASSUME_YES )); then
  if [[ ! -t 0 ]]; then
    echo "ERROR: confirmation required; rerun with --yes." >&2
    exit 2
  fi
  printf '\nRestore/remove the managed Nyvorel installation now? [y/N] '
  read -r answer
  case "${answer,,}" in
    y|yes) ;;
    *) echo "Uninstall cancelled."; exit 0 ;;
  esac
fi

if (( DEACTIVATE )); then
  echo
  echo "Deactivating Nyvorel user services..."

  if command -v systemctl >/dev/null 2>&1; then
    path_units=(
      nyvorel-btop-style-sync.path
      nyvorel-dolphin-theme-sync.path
      nyvorel-fuzzel-style-sync.path
      nyvorel-kde-app-style-sync.path
      nyvorel-terminal-theme-sync.path
      nyvorel-zed-theme-sync.path
      nyvorel-zen-code-style-sync.path
    )

    systemctl --user stop nyvorel-quickshell.service >/dev/null 2>&1 || true
    systemctl --user disable --now \
      "${path_units[@]}" \
      nyvorel-operations-monitor.service >/dev/null 2>&1 || true
  else
    echo "WARNING: systemctl not available; continuing with file recovery." >&2
  fi
fi

python3 - \
  "$MANIFEST" \
  "$TARGET_HOME" \
  "$FORCE_CHANGED" <<'PYUNINSTALL'
from __future__ import annotations

from pathlib import Path
import hashlib
import json
import os
import shutil
import sys
import time

manifest_path = Path(sys.argv[1])
state = manifest_path.parent
home = Path(sys.argv[2]).resolve(strict=False)
force_changed = sys.argv[3] == "1"

def lexists(path: Path) -> bool:
    return os.path.lexists(path)

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def matches_installed(dest: Path, installed: dict) -> bool:
    if not lexists(dest):
        return False
    if installed["kind"] == "symlink":
        return dest.is_symlink() and os.readlink(dest) == installed["value"]
    if installed["kind"] == "file":
        return (
            dest.is_file()
            and not dest.is_symlink()
            and sha256_file(dest) == installed["value"]
        )
    return False

def remove_path(path: Path) -> None:
    if not lexists(path):
        return
    if path.is_dir() and not path.is_symlink():
        raise RuntimeError(f"refusing to remove directory destination: {path}")
    path.unlink()

data = json.loads(manifest_path.read_text())
entries = data["entries"]

conflict_root = state / "uninstall-conflicts" / time.strftime("%Y%m%d-%H%M%S")
archived = []

# Revalidate immediately before mutation.
conflicts = []
runtime_archives = []
for entry in entries:
    rel = Path(entry["destination"])
    if entry.get("ownership") == "runtime" and rel.as_posix() != ".config/hypr/custom/appearance-runtime.conf":
        raise SystemExit(f"invalid runtime ownership destination: {rel}")
    dest = home / rel
    if entry.get("ownership") == "runtime" and dest.is_file() and not dest.is_symlink():
        runtime_archives.append(rel)
        continue
    if not matches_installed(dest, entry["installed"]):
        conflicts.append(rel)

if conflicts and not force_changed:
    raise SystemExit("installed files changed after preflight; refusing recovery")

if conflicts or runtime_archives:
    conflict_root.mkdir(parents=True, exist_ok=True)
    for rel in conflicts + runtime_archives:
        dest = home / rel
        if not lexists(dest):
            continue
        archive = conflict_root / rel
        archive.parent.mkdir(parents=True, exist_ok=True)
        if dest.is_symlink():
            os.symlink(os.readlink(dest), archive)
        elif dest.is_file():
            shutil.copy2(dest, archive, follow_symlinks=False)
        else:
            raise SystemExit(f"changed destination became a directory: {dest}")
        archived.append(rel.as_posix())

# Restore in reverse order so nested destinations unwind predictably.
for entry in reversed(entries):
    rel = Path(entry["destination"])
    if rel.is_absolute() or ".." in rel.parts:
        raise SystemExit(f"unsafe manifest destination: {rel}")

    dest = home / rel
    remove_path(dest)

    if entry["preexisting"]:
        backup = state / Path(entry["backup"])
        if not lexists(backup):
            raise SystemExit(f"required backup disappeared: {backup}")
        dest.parent.mkdir(parents=True, exist_ok=True)

        if backup.is_symlink():
            os.symlink(os.readlink(backup), dest)
        elif backup.is_file():
            shutil.copy2(backup, dest, follow_symlinks=False)
        else:
            raise SystemExit(f"unsupported backup type: {backup}")

data["status"] = "uninstalled"
data["uninstalled_unix"] = int(time.time())
data["uninstall_conflicts_archived"] = archived
data["uninstall_conflict_root"] = str(conflict_root) if archived else None
manifest_path.write_text(json.dumps(data, indent=2) + "\n")

current = home / ".local/state/nyvorel/current-install"
if current.is_file():
    try:
        pointed = Path(current.read_text().strip()).resolve(strict=False)
        if pointed == state.resolve(strict=False):
            current.unlink()
    except Exception:
        pass

print(f"Restored pre-existing files : {sum(1 for e in entries if e['preexisting'])}")
print(f"Removed Nyvorel-created files: {sum(1 for e in entries if not e['preexisting'])}")
print(f"Archived changed files       : {len(archived)}")
if archived:
    print(f"Conflict archive             : {conflict_root}")
PYUNINSTALL

if (( DEACTIVATE )) && command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

echo
echo "Runtime/user state retained:"
echo "  $TARGET_HOME/.config/nyvorel"
echo "  $STATE"
echo
echo "============================================================"
echo "NYVOREL UNINSTALL / RECOVERY: PASS"
echo "============================================================"
