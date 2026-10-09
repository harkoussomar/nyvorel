#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_KIND="${NYVOREL_SOURCE_KIND:-source-clone}"
ROOT="${NYVOREL_SOURCE_ROOT:-$SCRIPT_ROOT}"
PACKAGE_HELPER_ROOT="${NYVOREL_PACKAGE_HELPER_ROOT:-/usr/lib/nyvorel/bin}"

case "$SOURCE_KIND" in
  source-clone|package) ;;
  *)
    echo "ERROR: unsupported NYVOREL_SOURCE_KIND: $SOURCE_KIND" >&2
    exit 2
    ;;
esac

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

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "ERROR: invalid semantic VERSION: $VERSION" >&2
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

if (( ! DRY_RUN )) && [[ -s "$TARGET_HOME/.local/state/nyvorel/current-install" ]]; then
  echo "ERROR: an existing Nyvorel installation is recorded for this home." >&2
  echo "Use 'nyvorel update --dry-run' and then 'nyvorel update --yes' to preserve its backup chain and runtime state." >&2
  exit 3
fi

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
echo "Source kind  : $SOURCE_KIND"
echo "Source root  : $ROOT"
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
  "$DRY_RUN" \
  "$SOURCE_KIND" \
  "$PACKAGE_HELPER_ROOT" <<'PYINSTALL'
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
source_kind = sys.argv[7]
package_helper_root = Path(sys.argv[8]).resolve(strict=False)

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
        # Local Python runs can create ignored bytecode containing stale paths
        # and template tokens. Only distribute source, never interpreter caches.
        if "__pycache__" in rel_inside.parts or src.suffix in {".pyc", ".pyo"}:
            continue
        # Historical source snapshots document earlier design iterations but
        # must not become runnable files in a new user's desktop.
        if ".before-" in src.name or ".pre-" in src.name:
            continue
        items.append(Item(src=src, rel=dest_root / rel_inside))

items: list[Item] = []

add_tree(items, root / "quickshell", Path(".config/quickshell/nyvorel"))
add_tree(items, root / "hypr", Path(".config/hypr"))
add_tree(items, root / "matugen", Path(".config/matugen"))

for name in ("fish", "kitty"):
    src = root / "integrations" / name
    if src.is_dir():
        add_tree(items, src, Path(f".config/{name}"))

if source_kind == "source-clone":
    add_tree(items, root / "bin", Path(".local/bin"))
    add_tree(items, root / "dependencies", Path(".local/share/nyvorel/dependencies"))

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
else:
    package_meta = root / "package-metadata.json"
    if not package_meta.is_file():
        raise SystemExit(f"required package metadata missing: {package_meta}")
    package_data = json.loads(package_meta.read_text())
    if package_data.get("schema") != 1 or package_data.get("source_kind") != "package":
        raise SystemExit("invalid Nyvorel package metadata")
    if package_data.get("source_home_token_occurrences") != 29:
        raise SystemExit(
            "package metadata does not preserve the 29-token source contract"
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
print("Safety: replacements are backed up and tracked in an installation manifest.")

if source_kind == "source-clone" and token_occurrences != 29:
    raise SystemExit(
        f"portable source contract expects 29 @HOME@ occurrences, found {token_occurrences}"
    )

if dry_run:
    print()
    print("DRY RUN — no files changed.")
    print("Next: review the plan, then use --yes to explicitly install.")
    print("Install roots:")
    print(f"  {home / '.config/quickshell/nyvorel'}")
    print(f"  {home / '.config/hypr'}")
    if source_kind == "source-clone":
        print(f"  {home / '.local/bin'}")
        print(f"  {home / '.config/systemd/user'}")
    else:
        print("  package-owned helpers: " + str(package_helper_root))
        print("  package-owned user units: /usr/lib/systemd/user")
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
    if source_kind == "package":
        try:
            package_data = json.loads((root / "package-metadata.json").read_text())
            commit = str(package_data.get("source_commit") or "")
        except Exception:
            commit = ""
    else:
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
        "source_kind": source_kind,
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
    for index, item in enumerate(items, start=1):
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
        if item.rel.as_posix() in {
            ".config/hypr/custom/appearance-runtime.conf",
            ".config/hypr/hyprland/colors.conf",
            ".config/hypr/hyprlock/colors.conf",
            ".config/kitty/nyvorel-dynamic-theme.conf",
            ".config/fish/conf.d/99-nyvorel-dynamic-theme.fish",
        }:
            record["ownership"] = "runtime"
        records.append(record)
        write_manifest("installing")

        if record.get("ownership") == "runtime" and preexisting:
            if not dest.is_file() or dest.is_symlink():
                raise RuntimeError(f"runtime state must be a regular file: {dest}")
            record["installed"] = installed_digest(dest)
            write_manifest("installing")
            continue

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
        if index == 1 or index % max(1, len(items) // 5) == 0 or index == len(items):
            print(f"Installing managed files: {index}/{len(items)}", flush=True)

    # User/runtime config intentionally starts separate from the source tree.
    (home / ".config/nyvorel").mkdir(parents=True, exist_ok=True)

    current = home / ".local/state/nyvorel/current-install"
    current.parent.mkdir(parents=True, exist_ok=True)
    current.write_text(str(state) + "\n")

    write_manifest("installed")

except Exception:
    print("ERROR: installation failed; restoring managed destinations from backups.", file=sys.stderr)
    rollback()
    print("Recovery: review the error above and your previous installation manifest before retrying.", file=sys.stderr)
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

  systemctl --user daemon-reload || { echo "ERROR: user service reload failed; installation files remain backed up. Check systemctl --user status." >&2; exit 4; }

  path_units=(
    nyvorel-btop-style-sync.path
    nyvorel-dolphin-theme-sync.path
    nyvorel-fuzzel-style-sync.path
    nyvorel-kde-app-style-sync.path
    nyvorel-terminal-theme-sync.path
    nyvorel-zed-theme-sync.path
    nyvorel-zen-code-style-sync.path
  )

  systemctl --user enable --now "${path_units[@]}" nyvorel-operations-monitor.service || { echo "ERROR: service activation failed; inspect systemctl --user --failed." >&2; exit 4; }

  systemctl --user import-environment \
    DISPLAY \
    WAYLAND_DISPLAY \
    HYPRLAND_INSTANCE_SIGNATURE \
    XDG_CURRENT_DESKTOP \
    XDG_SESSION_TYPE >/dev/null 2>&1 || true

  systemctl --user restart nyvorel-quickshell.service || { echo "ERROR: Quickshell could not restart; inspect journalctl --user -u nyvorel-quickshell.service -n 40." >&2; exit 4; }

  echo "Activation: PASS"
else
  echo
  echo "Nyvorel files are installed."
  echo "Services were not activated."
  echo "At the first Hyprland login, Nyvorel activates its user services."
  echo "To activate an already running Nyvorel session: nyvorel activate --yes"
fi

echo
echo "============================================================"
echo "NYVOREL INSTALL: PASS"
echo "============================================================"
echo "Next: nyvorel welcome --no-session  # check files and dependencies safely"
echo "Then: nyvorel welcome               # check the live session when available"
echo "Help: nyvorel doctor                # details and actionable recovery"
