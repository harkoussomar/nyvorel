#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
IMAGE="${NYVOREL_CLEAN_MACHINE_IMAGE:-archlinux:base}"
RUNTIME="${NYVOREL_CONTAINER_RUNTIME:-}"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

if [[ -z "$RUNTIME" ]]; then
  if command -v podman >/dev/null 2>&1; then
    RUNTIME="podman"
  elif command -v docker >/dev/null 2>&1; then
    RUNTIME="docker"
  else
    die "neither podman nor docker is available"
  fi
fi

case "$RUNTIME" in
  podman|docker) ;;
  *) die "unsupported container runtime: $RUNTIME" ;;
esac

echo "== Nyvorel pristine Arch clean-machine validation =="
echo "runtime=$RUNTIME"
echo "image=$IMAGE"

"$RUNTIME" run --rm \
  -v "$ROOT:/src:ro" \
  "$IMAGE" \
  bash -lc '
set -Eeuo pipefail
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

echo "== Bootstrap pristine Arch userspace =="
pacman -Syu --noconfirm --needed \
  bash coreutils findutils grep sed gawk git python jq shadow util-linux >/dev/null

id nyvoreltest >/dev/null 2>&1 || useradd -m -U -s /bin/bash nyvoreltest
install -d -o nyvoreltest -g nyvoreltest /work
cp -a /src /work/source
chown -R nyvoreltest:nyvoreltest /work/source

cat >/work/run-as-user.sh <<'"'"'USERTEST'"'"'
#!/usr/bin/env bash
set -Eeuo pipefail

export HOME=/home/nyvoreltest
export USER=nyvoreltest
export LOGNAME=nyvoreltest
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"

SOURCE=/work/source
TARGET="$HOME"
STATE_ROOT="$TARGET/.local/state/nyvorel"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

snapshot_tree() {
  python3 - "$TARGET" <<'"'"'PY'"'"'
from pathlib import Path
import hashlib, json, os, sys
root = Path(sys.argv[1])
rows = {}
for p in sorted(root.rglob("*")):
    rel = p.relative_to(root).as_posix()
    if rel == ".cache" or rel.startswith(".cache/"):
        continue
    if p.is_symlink():
        rows[rel] = {"type": "symlink", "target": os.readlink(p)}
    elif p.is_file():
        h = hashlib.sha256()
        with p.open("rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                h.update(chunk)
        rows[rel] = {"type": "file", "sha256": h.hexdigest(), "size": p.stat().st_size}
    elif p.is_dir():
        rows[rel] = {"type": "dir"}
print(json.dumps(rows, sort_keys=True))
PY
}

echo "== Installer dry-run =="
"$SOURCE/install.sh" --target-home "$TARGET" --dry-run --no-activate
[[ ! -e "$STATE_ROOT/current-install" ]] || die "installer dry-run created current-install"

echo "== Clean install into brand-new non-root HOME =="
"$SOURCE/install.sh" --target-home "$TARGET" --yes --no-activate

CURRENT="$STATE_ROOT/current-install"
[[ -s "$CURRENT" ]] || die "current-install pointer missing"
STATE="$(tr -d "\r\n" <"$CURRENT")"
[[ -d "$STATE" ]] || die "current-install does not point to an installation state directory"
MANIFEST="$STATE/manifest.json"
[[ -s "$MANIFEST" ]] || die "manifest.json missing"

echo "== Manifest coherence / confinement =="
python3 - "$MANIFEST" "$TARGET" <<'"'"'PY'"'"'
from pathlib import Path
import json, sys
manifest_path = Path(sys.argv[1])
home = Path(sys.argv[2]).resolve()
data = json.loads(manifest_path.read_text())
assert data.get("status") == "installed", data.get("status")
assert data.get("product") == "Nyvorel", data.get("product")
assert Path(data["target_home"]).resolve() == home, data.get("target_home")
entries = data.get("entries")
assert isinstance(entries, list) and entries, "manifest has no entries"
print(f"manifest_entries={len(entries)}")
for entry in entries:
    assert isinstance(entry, dict), "manifest entry is not an object"
    rel = entry.get("destination")
    if rel is None:
        rel = entry.get("dest")
    assert isinstance(rel, str) and rel, "manifest destination missing"
    rp = Path(rel)
    assert not rp.is_absolute(), rel
    assert ".." not in rp.parts, rel
    dest = (home / rp).resolve(strict=False)
    assert dest == home or home in dest.parents, f"escaped target home: {dest}"
PY

echo "== Installed CLI =="
command -v nyvorel >/dev/null 2>&1 || die "installed nyvorel is not on PATH"
nyvorel help >/dev/null
nyvorel doctor --help >/dev/null
nyvorel update --help >/dev/null

echo "== Doctor structural validation in no-session mode =="
DOCTOR_JSON="$(mktemp)"
set +e
nyvorel doctor --home "$TARGET" --no-session --json >"$DOCTOR_JSON"
DOCTOR_RC=$?
set -e
python3 - "$DOCTOR_JSON" <<'"'"'PY'"'"'
from pathlib import Path
import json, sys
data = json.loads(Path(sys.argv[1]).read_text())
assert isinstance(data, (dict, list))
print("doctor_json=valid")
PY
if (( DOCTOR_RC != 0 )); then
  cat "$DOCTOR_JSON" >&2
  die "doctor returned $DOCTOR_RC in non-strict no-session mode"
fi

echo "== No unresolved install-time token =="
python3 - "$MANIFEST" "$TARGET" <<'"'"'PY'"'"'
from pathlib import Path
import json, sys
manifest = json.loads(Path(sys.argv[1]).read_text())
home = Path(sys.argv[2]).resolve()
sentinel = ("@" + "HOME" + "@").encode()
unresolved = []
missing = []
for entry in manifest["entries"]:
    rel = entry.get("destination", entry.get("dest"))
    if not isinstance(rel, str) or not rel:
        continue
    dest = home / rel
    if not dest.exists() and not dest.is_symlink():
        missing.append(rel)
        continue
    if dest.is_file() and sentinel in dest.read_bytes():
        unresolved.append(rel)
assert not missing, f"missing installed paths: {missing[:8]}"
assert not unresolved, f"unresolved @HOME@ token(s): {unresolved[:8]}"
print("materialization=PASS")
PY

echo "== Normalize disposable candidate checkout =="
if [[ -n "$(git -C "$SOURCE" status --porcelain=v1 --untracked-files=all)" ]]; then
  git -C "$SOURCE" config user.name "Nyvorel Phase 4"
  git -C "$SOURCE" config user.email "phase4@nyvorel.invalid"
  git -C "$SOURCE" add -A
  git -C "$SOURCE" commit -m "test: materialize local Phase 4 candidate" >/dev/null
fi

[[ -z "$(git -C "$SOURCE" status --porcelain=v1 --untracked-files=all)" ]] \
  || die "disposable candidate checkout is still dirty"
echo "candidate_source_commit=$(git -C "$SOURCE" rev-parse HEAD)"

echo "== Update dry-run must be zero-mutation =="
BEFORE="$(snapshot_tree)"
nyvorel update --target-home "$TARGET" --source "$SOURCE" --dry-run --no-activate
AFTER="$(snapshot_tree)"
[[ "$BEFORE" == "$AFTER" ]] || die "update dry-run mutated the clean installation"

echo "== Uninstall dry-run must be zero-mutation =="
BEFORE="$(snapshot_tree)"
"$SOURCE/uninstall.sh" --target-home "$TARGET" --dry-run --no-deactivate
AFTER="$(snapshot_tree)"
[[ "$BEFORE" == "$AFTER" ]] || die "uninstall dry-run mutated the clean installation"

echo "== Recovery / uninstall =="
"$SOURCE/uninstall.sh" --target-home "$TARGET" --yes --no-deactivate
[[ ! -e "$CURRENT" ]] || die "current-install pointer survived uninstall"

for p in \
  "$TARGET/.local/bin/nyvorel" \
  "$TARGET/.local/bin/nyvorel-doctor" \
  "$TARGET/.local/bin/nyvorel-update" \
  "$TARGET/.config/quickshell/nyvorel/shell.qml"
do
  [[ ! -e "$p" ]] || die "Nyvorel-created managed path survived uninstall: $p"
done

echo "PASS  non-root clean install, doctor, update dry-run, and recovery"
USERTEST

chmod +x /work/run-as-user.sh
chown nyvoreltest:nyvoreltest /work/run-as-user.sh
su -s /bin/bash nyvoreltest -c /work/run-as-user.sh
'

echo "PASS  pristine Arch clean-machine validation"
