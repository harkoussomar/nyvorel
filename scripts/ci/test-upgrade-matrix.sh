#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local needle="$2"
  local label="$3"

  if ! grep -qF "$needle" "$file"; then
    printf '\n--- %s ---\n' "$file" >&2
    cat "$file" >&2 || true
    printf '%s\n' '--- end captured output ---' >&2
    die "$label: expected output missing: $needle"
  fi
}

TMP="$(mktemp -d)"
API_PID=""

cleanup() {
  if [[ -n "$API_PID" ]]; then
    kill "$API_PID" >/dev/null 2>&1 || true
    wait "$API_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

BUILDER="$TMP/builder"
WORK="$TMP/source"
V010_SOURCE="$TMP/v010-source"
ORIGIN="$TMP/origin.git"
HOME_SANDBOX="$TMP/home"
PORT_FILE="$TMP/api-port"
API_MODE="$TMP/api-mode"

mkdir -p "$BUILDER" "$HOME_SANDBOX"

echo "== Build synthetic immutable v0.1.0 =="
cp -a "$ROOT/." "$BUILDER/"
rm -rf "$BUILDER/.git"
find "$BUILDER" -type d -name __pycache__ -prune -exec rm -rf {} +

git -C "$BUILDER" init -b main >/dev/null
git -C "$BUILDER" config user.name "Nyvorel Phase 6D"
git -C "$BUILDER" config user.email "phase6d@nyvorel.invalid"
git -C "$BUILDER" config core.autocrlf false
git -C "$BUILDER" config core.safecrlf false
git -C "$BUILDER" add -A
git -C "$BUILDER" commit -m "fixture: stable v0.1.0" >/dev/null
git -C "$BUILDER" tag -a v0.1.0 -m "fixture stable v0.1.0"

V010_COMMIT="$(git -C "$BUILDER" rev-parse HEAD)"

git init --bare "$ORIGIN" >/dev/null
git -C "$BUILDER" remote add origin "$ORIGIN"
git -C "$BUILDER" push origin main --tags >/dev/null

git clone --quiet --branch main "$ORIGIN" "$WORK"
git -C "$WORK" config user.name "Nyvorel Phase 6D"
git -C "$WORK" config user.email "phase6d@nyvorel.invalid"
git -C "$WORK" config nyvorel.githubRepository "harkoussomar/nyvorel"

[[ "$(git -C "$WORK" rev-parse HEAD)" == "$V010_COMMIT" ]] \
  || die "fresh v0.1.0 checkout commit mismatch"
[[ -z "$(git -C "$WORK" status --porcelain)" ]] \
  || die "fresh v0.1.0 checkout is dirty"

echo "== Install synthetic v0.1.0 with original-user backup =="
SENTINEL="pre-nyvorel-phase6d-shell"
mkdir -p "$HOME_SANDBOX/.config/quickshell/nyvorel"
printf '%s\n' "$SENTINEL" >"$HOME_SANDBOX/.config/quickshell/nyvorel/shell.qml"

"$WORK/install.sh" \
  --target-home "$HOME_SANDBOX" \
  --yes \
  --no-activate >"$TMP/install-v010.log"

CLI="$HOME_SANDBOX/.local/bin/nyvorel"
[[ -x "$CLI" ]] || die "installed CLI missing"

V010_STATE="$(tr -d '\r\n' <"$HOME_SANDBOX/.local/state/nyvorel/current-install")"

python3 - "$V010_STATE/manifest.json" "$V010_COMMIT" <<'PY'
from pathlib import Path
import json,sys

data=json.loads(Path(sys.argv[1]).read_text())
commit=sys.argv[2]

assert data["version"]=="0.1.0"
assert data["source_commit"]==commit
assert data["status"]=="installed"
PY

echo "== Create synthetic stable v0.1.1 release =="
printf '0.1.1\n' >"$WORK/VERSION"
printf '\n# phase6d-stable-v011\n' >>"$WORK/bin/nyvorel-settings"

cat >"$WORK/bin/nyvorel-phase6d-upgrade-fixture" <<'SH'
#!/usr/bin/env bash
echo "Nyvorel Phase 6D v0.1.1"
SH
chmod +x "$WORK/bin/nyvorel-phase6d-upgrade-fixture"

git -C "$WORK" add -A
git -C "$WORK" commit -m "fixture: stable v0.1.1" >/dev/null
git -C "$WORK" tag -a v0.1.1 -m "fixture stable v0.1.1"
V011_COMMIT="$(git -C "$WORK" rev-parse HEAD)"
git -C "$WORK" push origin main --tags >/dev/null

[[ "$V011_COMMIT" != "$V010_COMMIT" ]] || die "v0.1.1 fixture did not advance"

echo "== Prepare explicit v0.1.0 source for downgrade checks =="
git clone --quiet "$ORIGIN" "$V010_SOURCE"
V010_PEELED="$(git -C "$V010_SOURCE" rev-parse 'v0.1.0^{commit}')"
git -C "$V010_SOURCE" checkout --quiet --detach "$V010_PEELED"
[[ "$V010_PEELED" == "$V010_COMMIT" ]] || die "v0.1.0 peeled commit mismatch"

echo "== Start deterministic fake GitHub Releases API =="
printf 'latest\n' >"$API_MODE"

python3 - "$PORT_FILE" "$API_MODE" <<'PY' &
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import sys

port_file=Path(sys.argv[1])
mode_file=Path(sys.argv[2])

def releases():
    mode=mode_file.read_text().strip()

    noise=[
        {"tag_name":"v9.0.0","draft":True,"prerelease":False},
        {"tag_name":"v8.0.0","draft":False,"prerelease":True},
    ]

    if mode=="old-only":
        return noise + [
            {"tag_name":"v0.1.0","draft":False,"prerelease":False},
        ]

    return noise + [
        {"tag_name":"v0.1.1","draft":False,"prerelease":False},
        {"tag_name":"v0.1.0","draft":False,"prerelease":False},
    ]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/repos/harkoussomar/nyvorel/releases"):
            body=json.dumps(releases()).encode()
            self.send_response(200)
            self.send_header("Content-Type","application/json")
            self.send_header("Content-Length",str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        pass

server=ThreadingHTTPServer(("127.0.0.1",0),Handler)
port_file.write_text(str(server.server_port))
server.serve_forever()
PY
API_PID=$!

for _ in $(seq 1 50); do
  [[ -s "$PORT_FILE" ]] && break
  sleep 0.1
done
[[ -s "$PORT_FILE" ]] || die "fake GitHub API did not start"

API_BASE="http://127.0.0.1:$(cat "$PORT_FILE")"

echo "== Stable patch-upgrade dry-run is zero-mutation =="
POINTER_BEFORE="$(cat "$HOME_SANDBOX/.local/state/nyvorel/current-install")"

NYVOREL_GITHUB_API_BASE="$API_BASE" \
  "$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --fetch \
  --dry-run \
  --no-activate >"$TMP/stable-upgrade-dry.log"

assert_contains "$TMP/stable-upgrade-dry.log" \
  "Update channel        : stable" \
  "stable patch-upgrade channel"

assert_contains "$TMP/stable-upgrade-dry.log" \
  "Current version       : 0.1.0" \
  "stable patch-upgrade old version"

assert_contains "$TMP/stable-upgrade-dry.log" \
  "Candidate version     : 0.1.1" \
  "stable patch-upgrade candidate"

assert_contains "$TMP/stable-upgrade-dry.log" \
  "Resolved ref          : v0.1.1" \
  "stable patch-upgrade release ref"

[[ "$(cat "$HOME_SANDBOX/.local/state/nyvorel/current-install")" == "$POINTER_BEFORE" ]] \
  || die "stable patch-upgrade dry-run changed current-install"

[[ ! -e "$HOME_SANDBOX/.local/bin/nyvorel-phase6d-upgrade-fixture" ]] \
  || die "stable patch-upgrade dry-run installed payload"

echo "== Apply stable v0.1.0 -> v0.1.1 =="
NYVOREL_GITHUB_API_BASE="$API_BASE" \
  "$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --fetch \
  --yes \
  --no-activate >"$TMP/stable-upgrade-apply.log"

V011_STATE="$(tr -d '\r\n' <"$HOME_SANDBOX/.local/state/nyvorel/current-install")"
[[ "$V011_STATE" != "$V010_STATE" ]] || die "stable patch upgrade did not advance state"

grep -qF '# phase6d-stable-v011' "$HOME_SANDBOX/.local/bin/nyvorel-settings" \
  || die "stable v0.1.1 payload marker missing"

[[ -x "$HOME_SANDBOX/.local/bin/nyvorel-phase6d-upgrade-fixture" ]] \
  || die "stable v0.1.1 added payload missing"

python3 - "$V011_STATE/manifest.json" "$V010_STATE" "$V011_COMMIT" "$WORK" <<'PY'
from pathlib import Path
import json,sys

data=json.loads(Path(sys.argv[1]).read_text())
old_state=sys.argv[2]
commit=sys.argv[3]
source_root=str(Path(sys.argv[4]).resolve())

assert data["version"]=="0.1.1"
assert data["source_commit"]==commit
assert data["source_root"]==source_root
assert data["source_channel"]=="stable"
assert data["update"]["from_state"]==old_state
assert data["update"]["channel"]=="stable"
assert data["update"]["resolved_ref"]=="v0.1.1"
assert data["update"]["resolved_commit"]==commit
PY

echo "== Stable v0.1.1 is idempotent/no-op =="
POINTER_STABLE="$(cat "$HOME_SANDBOX/.local/state/nyvorel/current-install")"

NYVOREL_GITHUB_API_BASE="$API_BASE" \
  "$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --fetch \
  --dry-run \
  --no-activate >"$TMP/stable-noop.log"

assert_contains "$TMP/stable-noop.log" \
  "RESULT: already up to date." \
  "stable v0.1.1 no-op"

[[ "$(cat "$HOME_SANDBOX/.local/state/nyvorel/current-install")" == "$POINTER_STABLE" ]] \
  || die "stable no-op changed current-install"

echo "== Explicit downgrade is refused unless explicitly allowed =="
set +e
"$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --source "$V010_SOURCE" \
  --dry-run \
  --no-activate >"$TMP/explicit-downgrade-refuse.out" 2>"$TMP/explicit-downgrade-refuse.err"
DOWNGRADE_RC=$?
set -e

[[ "$DOWNGRADE_RC" == "1" ]] \
  || die "explicit downgrade without override should exit 1"

grep -q 'candidate 0.1.0 is older than installed 0.1.1' \
  "$TMP/explicit-downgrade-refuse.err"

"$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --source "$V010_SOURCE" \
  --allow-downgrade \
  --dry-run \
  --no-activate >"$TMP/explicit-downgrade-allowed.log"

assert_contains "$TMP/explicit-downgrade-allowed.log" \
  "Candidate version     : 0.1.0" \
  "explicit downgrade override"

[[ "$(cat "$HOME_SANDBOX/.local/state/nyvorel/current-install")" == "$POINTER_STABLE" ]] \
  || die "explicit downgrade dry-run changed current-install"

echo "== Stable remote downgrade is always refused =="
printf 'old-only\n' >"$API_MODE"

set +e
NYVOREL_GITHUB_API_BASE="$API_BASE" \
  "$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --fetch \
  --dry-run \
  --no-activate >"$TMP/stable-downgrade.out" 2>"$TMP/stable-downgrade.err"
STABLE_DOWNGRADE_RC=$?
set -e

[[ "$STABLE_DOWNGRADE_RC" == "1" ]] \
  || die "stable remote downgrade should exit 1"

grep -q 'candidate 0.1.0 is older than installed 0.1.1' \
  "$TMP/stable-downgrade.err"

[[ "$(cat "$HOME_SANDBOX/.local/state/nyvorel/current-install")" == "$POINTER_STABLE" ]] \
  || die "stable downgrade refusal changed current-install"

printf 'latest\n' >"$API_MODE"

echo "== Development same-version commit is explicitly allowed =="
printf '\n# phase6d-development-after-v011\n' >>"$WORK/bin/nyvorel-settings"
git -C "$WORK" add bin/nyvorel-settings
git -C "$WORK" commit -m "fixture: development after v0.1.1" >/dev/null
DEV_COMMIT="$(git -C "$WORK" rev-parse HEAD)"
git -C "$WORK" push origin main >/dev/null

NYVOREL_GITHUB_API_BASE="$API_BASE" \
  "$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --fetch \
  --channel development \
  --yes \
  --no-activate >"$TMP/development-apply.log"

grep -qF '# phase6d-development-after-v011' \
  "$HOME_SANDBOX/.local/bin/nyvorel-settings" \
  || die "development same-version payload not installed"

DEV_STATE="$(tr -d '\r\n' <"$HOME_SANDBOX/.local/state/nyvorel/current-install")"

python3 - "$DEV_STATE/manifest.json" "$DEV_COMMIT" <<'PY'
from pathlib import Path
import json,sys

data=json.loads(Path(sys.argv[1]).read_text())
commit=sys.argv[2]

assert data["version"]=="0.1.1"
assert data["source_commit"]==commit
assert data["source_channel"]=="development"
assert data["update"]["channel"]=="development"
assert data["update"]["resolved_ref"]=="origin/main"
assert data["update"]["resolved_commit"]==commit
PY

echo "== Switching development -> same-version stable is refused =="
POINTER_DEV="$(cat "$HOME_SANDBOX/.local/state/nyvorel/current-install")"

set +e
NYVOREL_GITHUB_API_BASE="$API_BASE" \
  "$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --fetch \
  --dry-run \
  --no-activate >"$TMP/stable-return.out" 2>"$TMP/stable-return.err"
STABLE_RETURN_RC=$?
set -e

[[ "$STABLE_RETURN_RC" == "1" ]] \
  || die "development -> same-version stable should be refused"

grep -q 'stable channel refuses a same-version different-commit update' \
  "$TMP/stable-return.err"

[[ "$(cat "$HOME_SANDBOX/.local/state/nyvorel/current-install")" == "$POINTER_DEV" ]] \
  || die "same-version stable refusal changed current-install"

grep -qF '# phase6d-development-after-v011' \
  "$HOME_SANDBOX/.local/bin/nyvorel-settings" \
  || die "same-version stable refusal mutated development payload"

echo "== Recovery after multi-step upgrade restores original user file =="
"$WORK/uninstall.sh" \
  --target-home "$HOME_SANDBOX" \
  --yes \
  --no-deactivate >"$TMP/uninstall.log"

[[ ! -e "$HOME_SANDBOX/.local/state/nyvorel/current-install" ]] \
  || die "current-install pointer survived recovery"

[[ "$(cat "$HOME_SANDBOX/.config/quickshell/nyvorel/shell.qml")" == "$SENTINEL" ]] \
  || die "multi-step recovery did not restore original pre-Nyvorel shell"

[[ ! -e "$HOME_SANDBOX/.local/bin/nyvorel-phase6d-upgrade-fixture" ]] \
  || die "upgrade-added managed file survived recovery"

echo "PASS  v0.1.0->v0.1.1 stable upgrade, no-op, downgrade policy, development switching and recovery"
