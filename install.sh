#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$(tr -d '[:space:]' <"$ROOT/VERSION")"

TARGET_HOME="${HOME:?HOME is not set}"
ASSUME_YES=0
DRY_RUN=0
ACTIVATE=0

usage() {
  cat <<'EOF'
Nyvorel installer

Usage:
  ./install.sh [options]

Options:
  --target-home PATH  Install into another home directory (testing/staging).
  --yes               Allow replacement of existing managed files.
  --dry-run           Show the installation plan without changing files.
  --activate           Activate Nyvorel user services after installation.
  --no-activate        Do not activate services (default).
  -h, --help           Show this help.

The installer creates timestamped backups and a manifest under:
  ~/.local/state/nyvorel/installations/

Source files containing @HOME@ are rendered with the target home path during
installation. The public source tree itself is never rewritten.
EOF
}

while (($#)); do
  case "$1" in
    --target-home)
      (($# >= 2)) || { echo "ERROR: --target-home requires a path" >&2; exit 2; }
      TARGET_HOME="$2"
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
    --activate)
      ACTIVATE=1
      shift
      ;;
    --no-activate)
      ACTIVATE=0
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

[[ "$VERSION" == "0.1.0" ]] || {
  echo "ERROR: unsupported/invalid VERSION: $VERSION" >&2
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

if (( ACTIVATE )); then
  REAL_HOME="$(python3 - "$HOME" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
)"
  [[ "$TARGET_HOME" == "$REAL_HOME" ]] || {
    echo "ERROR: --activate is only allowed for the current user's real HOME." >&2
    exit 1
  }
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
STATE="$TARGET_HOME/.local/state/nyvorel/installations/$STAMP"
MODE="install"
(( DRY_RUN )) && MODE="dry-run"

echo "============================================================"
echo "NYVOREL INSTALLER"
echo "============================================================"
echo "Version      : $VERSION"
echo "Source       : $ROOT"
echo "Target home  : $TARGET_HOME"
echo "Mode         : $MODE"
echo "Activate     : $([[ $ACTIVATE -eq 1 ]] && echo yes || echo no)"
echo

python3 - \
  "$ROOT" \
  "$TARGET_HOME" \
  "$STATE" \
  "$VERSION" \
  "$ASSUME_YES" \
  "$DRY_RUN" <<'PYINSTALL'
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import time

root = Path(sys.argv[1]).resolve()
home = Path(sys.argv[2]).resolve(strict=False)
state = Path(sys.argv[3])
version = sys.argv[4]
assume_yes = sys.argv[5] == "1"
dry_run = sys.argv[6] == "1"

@dataclass(frozen=True)
class Item:
    src: Path
    rel: Path

def lexists(path: Path) -> bool:
    return os.path.lexists(path)

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def installed_digest(path: Path) -> dict:
    if path.is_symlink():
        return {"kind": "symlink", "value": os.readlink(path)}
    return {"kind": "file", "value": sha256_file(path)}

def add_tree(items: list[Item], src_root: Path, dest_root: Path) -> None:
    if not src_root.is_dir():
        raise SystemExit(f"required source directory missing: {src_root}")
    for src in sorted(src_root.rglob("*")):
        if src.is_dir():
            continue
        if not (src.is_file() or src.is_symlink()):
            continue
        rel_inside = src.relative_to(src_root)
        items.append(Item(src=src, rel=dest_root / rel_inside))

items: list[Item] = []

add_tree(items, root / "quickshell", Path(".config/quickshell/nyvorel"))
add_tree(items, root / "hypr", Path(".config/hypr"))
add_tree(items, root / "bin", Path(".local/bin"))

for name in ("fish", "kitty"):
    src = root / "integrations" / name
    if src.is_dir():
        add_tree(items, src, Path(f".config/{name}"))

systemd_root = root / "systemd"
if not systemd_root.is_dir():
    raise SystemExit("required source directory missing: systemd")

for src in sorted(systemd_root.rglob("*")):
    if src.is_dir():
        continue
    if not (src.is_file() or src.is_symlink()):
        continue
    rel_inside = src.relative_to(systemd_root)
    name = rel_inside.name
    if name.endswith(".in"):
        name = name[:-3]
    dest_inside = rel_inside.with_name(name)
    items.append(Item(src=src, rel=Path(".config/systemd/user") / dest_inside))

logo = root / "assets" / "nyvorel.svg"
if not logo.is_file():
    raise SystemExit("required Nyvorel logo missing")
items.append(
    Item(
        src=logo,
        rel=Path(".local/share/icons/hicolor/scalable/apps/nyvorel.svg"),
    )
)

# Plan safety.
seen: dict[str, Path] = {}
for item in items:
    rel = item.rel
    if rel.is_absolute() or ".." in rel.parts:
        raise SystemExit(f"unsafe destination path: {rel}")
    key = rel.as_posix()
    if key in seen:
        raise SystemExit(
            f"duplicate destination: {rel} from {seen[key]} and {item.src}"
        )
    seen[key] = item.src

token_files = 0
token_occurrences = 0
for item in items:
    if item.src.is_symlink():
        target = os.readlink(item.src)
        if os.path.isabs(target):
            raise SystemExit(f"absolute source symlink refused: {item.src} -> {target}")
        continue
    data = item.src.read_bytes()
    n = data.count(b"@HOME@")
    if n:
        token_files += 1
        token_occurrences += n

existing = []
conflicts = []
for item in items:
    dest = home / item.rel
    if lexists(dest):
        if dest.is_dir() and not dest.is_symlink():
            conflicts.append(str(item.rel))
        else:
            existing.append(str(item.rel))

if conflicts:
    print("ERROR: file destinations collide with existing directories:", file=sys.stderr)
    for rel in conflicts[:30]:
        print(f"  {rel}", file=sys.stderr)
    raise SystemExit(1)

print(f"Managed files          : {len(items)}")
print(f"Existing replacements  : {len(existing)}")
print(f"@HOME@ template files  : {token_files}")
print(f"@HOME@ occurrences     : {token_occurrences}")

if token_occurrences != 29:
    raise SystemExit(
        f"expected 29 @HOME@ occurrences in v0.1.0 source, found {token_occurrences}"
    )

if dry_run:
    print()
    print("DRY RUN — no files changed.")
    print("Install roots:")
    print(f"  {home / '.config/quickshell/nyvorel'}")
    print(f"  {home / '.config/hypr'}")
    print(f"  {home / '.local/bin'}")
    print(f"  {home / '.config/systemd/user'}")
    print(f"  {home / '.config/fish'}")
    print(f"  {home / '.config/kitty'}")
    print(f"  {home / '.local/share/icons/hicolor/scalable/apps/nyvorel.svg'}")
    raise SystemExit(0)

if existing and not assume_yes:
    if not sys.stdin.isatty():
        raise SystemExit(
            "existing managed files would be replaced; rerun with --yes after reviewing --dry-run"
        )
    print()
    answer = input(
        f"{len(existing)} managed destination file(s) already exist. "
        "Back them up and continue? [y/N] "
    ).strip().lower()
    if answer not in {"y", "yes"}:
        raise SystemExit("installation cancelled")

backup_root = state / "backup"
manifest_path = state / "manifest.json"
records: list[dict] = []

state.mkdir(parents=True, exist_ok=False)
backup_root.mkdir(parents=True, exist_ok=True)

def write_manifest(status: str) -> None:
    commit = ""
    try:
        commit = subprocess.check_output(
            ["git", "-C", str(root), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        pass

    payload = {
        "schema": 1,
        "product": "Nyvorel",
        "version": version,
        "status": status,
        "source_root": str(root),
        "source_commit": commit,
        "target_home": str(home),
        "created_unix": int(time.time()),
        "entries": records,
    }
    manifest_path.write_text(json.dumps(payload, indent=2) + "\n")

def restore_record(record: dict) -> None:
    dest = home / Path(record["destination"])
    if lexists(dest):
        if dest.is_dir() and not dest.is_symlink():
            shutil.rmtree(dest)
        else:
            dest.unlink()

    if record["preexisting"]:
        backup = state / Path(record["backup"])
        dest.parent.mkdir(parents=True, exist_ok=True)
        if backup.is_symlink():
            os.symlink(os.readlink(backup), dest)
        else:
            shutil.copy2(backup, dest, follow_symlinks=False)

def rollback() -> None:
    for record in reversed(records):
        try:
            restore_record(record)
        except Exception as exc:
            print(
                f"ROLLBACK WARNING: {record['destination']}: {exc}",
                file=sys.stderr,
            )
    try:
        write_manifest("rolled-back")
    except Exception:
        pass

try:
    for item in items:
        dest = home / item.rel
        preexisting = lexists(dest)
        backup_rel = Path("backup") / item.rel

        if preexisting:
            backup = state / backup_rel
            backup.parent.mkdir(parents=True, exist_ok=True)
            if dest.is_symlink():
                os.symlink(os.readlink(dest), backup)
            else:
                shutil.copy2(dest, backup, follow_symlinks=False)

        record = {
            "destination": item.rel.as_posix(),
            "source": str(item.src.relative_to(root)),
            "preexisting": preexisting,
            "backup": backup_rel.as_posix() if preexisting else None,
            "installed": None,
        }
        records.append(record)
        write_manifest("installing")

        dest.parent.mkdir(parents=True, exist_ok=True)
        if lexists(dest):
            dest.unlink()

        if item.src.is_symlink():
            target = os.readlink(item.src)
            os.symlink(target, dest)
        else:
            data = item.src.read_bytes().replace(
                b"@HOME@", str(home).encode("utf-8")
            )
            tmp = dest.with_name(dest.name + ".nyvorel-tmp")
            if lexists(tmp):
                tmp.unlink()
            with tmp.open("wb") as f:
                f.write(data)
            os.chmod(tmp, stat.S_IMODE(item.src.stat().st_mode))
            os.replace(tmp, dest)

        record["installed"] = installed_digest(dest)
        write_manifest("installing")

    # User/runtime config intentionally starts separate from the source tree.
    (home / ".config/nyvorel").mkdir(parents=True, exist_ok=True)

    current = home / ".local/state/nyvorel/current-install"
    current.parent.mkdir(parents=True, exist_ok=True)
    current.write_text(str(state) + "\n")

    write_manifest("installed")

except Exception:
    rollback()
    raise

# Final materialization gate: @HOME@ must not survive in any installed file
# whose source contained the token.
unresolved = []
for item in items:
    if item.src.is_symlink():
        continue
    if b"@HOME@" not in item.src.read_bytes():
        continue
    dest = home / item.rel
    if b"@HOME@" in dest.read_bytes():
        unresolved.append(item.rel.as_posix())

if unresolved:
    rollback()
    raise SystemExit(
        "unresolved @HOME@ token(s) after installation:\n  "
        + "\n  ".join(unresolved)
    )

print()
print("Installation payload: PASS")
print(f"Manifest            : {manifest_path}")
print(f"Backup root         : {backup_root}")
print(f"Current install     : {state}")
PYINSTALL

if (( DRY_RUN )); then
  exit 0
fi

if (( ACTIVATE )); then
  echo
  echo "Activating Nyvorel user services..."

  command -v systemctl >/dev/null 2>&1 || {
    echo "WARNING: systemctl not found; files are installed but services were not activated." >&2
    exit 4
  }

  systemctl --user daemon-reload

  path_units=(
    nyvorel-btop-style-sync.path
    nyvorel-dolphin-theme-sync.path
    nyvorel-fuzzel-style-sync.path
    nyvorel-kde-app-style-sync.path
    nyvorel-terminal-theme-sync.path
    nyvorel-zed-theme-sync.path
    nyvorel-zen-code-style-sync.path
  )

  systemctl --user enable --now "${path_units[@]}" nyvorel-operations-monitor.service

  systemctl --user import-environment \
    DISPLAY \
    WAYLAND_DISPLAY \
    HYPRLAND_INSTANCE_SIGNATURE \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_TYPE >/dev/null 2>&1 || true

  systemctl --user restart nyvorel-quickshell.service

  echo "Activation: PASS"
else
  echo
  echo "Nyvorel files are installed."
  echo "Services were not activated."
  echo "To activate on the current user/session:"
  echo "  ./install.sh --yes --activate"
fi

echo
echo "============================================================"
echo "NYVOREL INSTALL: PASS"
echo "============================================================"
