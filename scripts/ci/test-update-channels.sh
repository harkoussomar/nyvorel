#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

assert_log_contains() {
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
ORIGIN="$TMP/origin.git"
HOME_SANDBOX="$TMP/target"
PORT_FILE="$TMP/api-port"

echo "== Build synthetic stable/development repository =="
mkdir -p "$BUILDER" "$HOME_SANDBOX"
cp -a "$ROOT/." "$BUILDER/"
rm -rf "$BUILDER/.git"
find "$BUILDER" -type d -name __pycache__ -prune -exec rm -rf {} +

git -C "$BUILDER" init -b main >/dev/null
git -C "$BUILDER" config user.name "Nyvorel CI"
git -C "$BUILDER" config user.email "ci@nyvorel.invalid"
git -C "$BUILDER" add -A
git -C "$BUILDER" commit -m "fixture: stable v0.1.0" >/dev/null
git -C "$BUILDER" tag -a v0.1.0 -m "fixture stable v0.1.0"

STABLE_COMMIT="$(git -C "$BUILDER" rev-parse HEAD)"

git init --bare "$ORIGIN" >/dev/null
git -C "$BUILDER" remote add origin "$ORIGIN"
git -C "$BUILDER" push origin main --tags >/dev/null

# Install from a fresh checkout of the committed bytes. This prevents
# CRLF/LF worktree normalization in the builder from making the stable
# baseline differ from the later immutable-tag checkout.
git clone --quiet --branch main "$ORIGIN" "$WORK"
git -C "$WORK" config user.name "Nyvorel CI"
git -C "$WORK" config user.email "ci@nyvorel.invalid"
git -C "$WORK" config nyvorel.githubRepository "harkoussomar/nyvorel"

[[ "$(git -C "$WORK" rev-parse HEAD)" == "$STABLE_COMMIT" ]] \
  || die "clean fixture checkout is not the stable commit"
[[ -z "$(git -C "$WORK" status --porcelain)" ]] \
  || die "clean fixture checkout unexpectedly has worktree changes"

echo "== Install stable baseline =="
"$WORK/install.sh" \
  --target-home "$HOME_SANDBOX" \
  --yes \
  --no-activate >"$TMP/install.log"

CLI="$HOME_SANDBOX/.local/bin/nyvorel"
[[ -x "$CLI" ]] || die "installed Nyvorel CLI missing"

BASE_POINTER="$(cat "$HOME_SANDBOX/.local/state/nyvorel/current-install")"

echo "== Advance synthetic development/main at same VERSION =="
printf '\n# phase6b-development-marker\n' >>"$WORK/bin/nyvorel-settings"
git -C "$WORK" add bin/nyvorel-settings
git -C "$WORK" commit -m "fixture: development same-version commit" >/dev/null
git -C "$WORK" push origin main >/dev/null
DEV_COMMIT="$(git -C "$WORK" rev-parse HEAD)"
[[ "$DEV_COMMIT" != "$STABLE_COMMIT" ]] || die "fixture development commit did not advance"

echo "== Start deterministic fake GitHub Releases API =="
python3 - "$PORT_FILE" <<'PY' &
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import sys

port_file = Path(sys.argv[1])

releases = [
    {
        "tag_name": "v9.0.0",
        "draft": True,
        "prerelease": False,
    },
    {
        "tag_name": "v8.0.0",
        "draft": False,
        "prerelease": True,
    },
    {
        "tag_name": "v0.1.0",
        "draft": False,
        "prerelease": False,
    },
]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/repos/harkoussomar/nyvorel/releases"):
            body = json.dumps(releases).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self.send_response(404)
        self.end_headers()

    def log_message(self, format, *args):
        pass

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
port_file.write_text(str(server.server_port))
server.serve_forever()
PY
API_PID=$!

for _ in $(seq 1 50); do
  [[ -s "$PORT_FILE" ]] && break
  sleep 0.1
done
[[ -s "$PORT_FILE" ]] || die "fake GitHub Releases API did not start"

API_BASE="http://127.0.0.1:$(cat "$PORT_FILE")"

echo "== Stable is the default --fetch channel =="
NYVOREL_GITHUB_API_BASE="$API_BASE" \
  "$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --fetch \
  --dry-run \
  --no-activate >"$TMP/stable.log"

assert_log_contains \
  "$TMP/stable.log" \
  "Update channel        : stable" \
  "stable default channel"

assert_log_contains \
  "$TMP/stable.log" \
  "Resolved ref          : v0.1.0" \
  "stable resolved release"

assert_log_contains \
  "$TMP/stable.log" \
  "RESULT: already up to date." \
  "stable immutable-tag no-op"

[[ "$(cat "$HOME_SANDBOX/.local/state/nyvorel/current-install")" == "$BASE_POINTER" ]] \
  || die "stable no-op changed current-install"

if grep -q 'phase6b-development-marker' "$HOME_SANDBOX/.local/bin/nyvorel-settings"; then
  die "stable update consumed development/main payload"
fi

echo "== Development is explicit opt-in and same-version commit is allowed =="
NYVOREL_GITHUB_API_BASE="$API_BASE" \
  "$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --fetch \
  --channel development \
  --dry-run \
  --no-activate >"$TMP/development-dry-run.log"

grep -q 'Update channel        : development' "$TMP/development-dry-run.log"
grep -q 'Resolved ref          : origin/main' "$TMP/development-dry-run.log"
grep -q "$DEV_COMMIT" "$TMP/development-dry-run.log"

NYVOREL_GITHUB_API_BASE="$API_BASE" \
  "$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --fetch \
  --channel development \
  --yes \
  --no-activate >"$TMP/development-apply.log"

grep -q 'phase6b-development-marker' "$HOME_SANDBOX/.local/bin/nyvorel-settings" \
  || die "development update did not install same-version main payload"

DEV_STATE="$(tr -d '\r\n' <"$HOME_SANDBOX/.local/state/nyvorel/current-install")"

python3 - "$DEV_STATE/manifest.json" "$DEV_COMMIT" "$WORK" <<'PY'
from pathlib import Path
import json
import sys

manifest = json.loads(Path(sys.argv[1]).read_text())
dev_commit = sys.argv[2]
source_root = str(Path(sys.argv[3]).resolve())

assert manifest["version"] == "0.1.0"
assert manifest["source_commit"] == dev_commit
assert manifest["source_root"] == source_root
assert manifest["source_channel"] == "development"
assert manifest["update"]["channel"] == "development"
assert manifest["update"]["resolved_ref"] == "origin/main"
assert manifest["update"]["resolved_commit"] == dev_commit
PY

echo "== Stable refuses same-version different-commit rollback =="
POINTER_BEFORE_REFUSAL="$(cat "$HOME_SANDBOX/.local/state/nyvorel/current-install")"

set +e
NYVOREL_GITHUB_API_BASE="$API_BASE" \
  "$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --fetch \
  --dry-run \
  --no-activate >"$TMP/stable-refusal.out" 2>"$TMP/stable-refusal.err"
STABLE_REFUSAL_RC=$?
set -e

[[ "$STABLE_REFUSAL_RC" == "1" ]] \
  || die "stable same-version different-commit refusal expected exit 1"

grep -q 'stable channel refuses a same-version different-commit update' \
  "$TMP/stable-refusal.err"

[[ "$(cat "$HOME_SANDBOX/.local/state/nyvorel/current-install")" == "$POINTER_BEFORE_REFUSAL" ]] \
  || die "stable refusal mutated current-install"

grep -q 'phase6b-development-marker' "$HOME_SANDBOX/.local/bin/nyvorel-settings" \
  || die "stable refusal mutated development payload"

echo "== Channel/source/override argument boundaries =="
set +e
"$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --channel development \
  --dry-run >"$TMP/no-fetch.out" 2>"$TMP/no-fetch.err"
NO_FETCH_RC=$?

"$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --source "$WORK" \
  --fetch \
  --dry-run >"$TMP/source-fetch.out" 2>"$TMP/source-fetch.err"
SOURCE_FETCH_RC=$?

"$CLI" update \
  --target-home "$HOME_SANDBOX" \
  --fetch \
  --allow-downgrade \
  --dry-run >"$TMP/remote-downgrade.out" 2>"$TMP/remote-downgrade.err"
REMOTE_DOWNGRADE_RC=$?
set -e

[[ "$NO_FETCH_RC" == "1" ]] || die "--channel without --fetch should fail"
[[ "$SOURCE_FETCH_RC" == "1" ]] || die "--source + --fetch should fail"
[[ "$REMOTE_DOWNGRADE_RC" == "1" ]] || die "remote downgrade override should fail"

grep -q -- '--channel requires --fetch' "$TMP/no-fetch.err"
grep -q -- '--source selects an explicit local source' "$TMP/source-fetch.err"
grep -q -- '--allow-downgrade is not permitted' "$TMP/remote-downgrade.err"

echo "PASS  stable default, development opt-in, same-version policy, and argument boundaries"
