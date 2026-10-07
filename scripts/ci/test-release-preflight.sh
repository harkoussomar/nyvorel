#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CANDIDATE="$TMP/candidate"
cp -a "$ROOT/." "$CANDIDATE/"
rm -rf "$CANDIDATE/.git"
find "$CANDIDATE" -type d -name __pycache__ -prune -exec rm -rf {} +

echo "== Build synthetic v0.1.1 release candidate =="
printf '0.1.1\n' >"$CANDIDATE/VERSION"
python3 - "$CANDIDATE/CHANGELOG.md" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
marker = "## [Unreleased]\n"
release = "## [Unreleased]\n\n## [0.1.1] - 2026-10-07\n\nSynthetic release-preflight fixture.\n"
if text.count(marker) != 1:
    raise SystemExit("fixture changelog marker mismatch")
p.write_text(text.replace(marker, release, 1))
PY

git -C "$CANDIDATE" init -b main >/dev/null
git -C "$CANDIDATE" config user.name "Nyvorel Release CI"
git -C "$CANDIDATE" config user.email "release-ci@nyvorel.invalid"
git -C "$CANDIDATE" add -A
git -C "$CANDIDATE" commit -m "fixture: v0.1.1 candidate" >/dev/null

echo "== Future semantic VERSION is accepted by installer =="
"$CANDIDATE/install.sh" --target-home "$TMP/home-v011" --dry-run --no-activate >"$TMP/install-v011.log"
grep -q 'Version      : 0.1.1' "$TMP/install-v011.log"
grep -q 'DRY RUN — no files changed.' "$TMP/install-v011.log"

echo "== Candidate preflight passes before tag creation =="
"$CANDIDATE/scripts/release/preflight.sh" --source "$CANDIDATE" --version 0.1.1 --tag v0.1.1 --require-clean --json >"$TMP/preflight.json"
python3 - "$TMP/preflight.json" <<'PY'
from pathlib import Path
import json, sys
data = json.loads(Path(sys.argv[1]).read_text())
assert data["schema"] == 1
assert data["version"] == "0.1.1"
assert data["tag"] == "v0.1.1"
assert data["mutation_performed"] is False
assert data["publish_performed"] is False
assert data["worktree_dirty"] is False
assert data["checks"]["installer_accepts_version"] is True
assert data["checks"]["tag_points_to_head"] is None
PY

echo "== Annotated release tag can be required and must peel to HEAD =="
git -C "$CANDIDATE" tag -a v0.1.1 -m "fixture release v0.1.1"
"$CANDIDATE/scripts/release/preflight.sh" --source "$CANDIDATE" --version 0.1.1 --require-clean --require-tag --json >"$TMP/tagged.json"
python3 - "$TMP/tagged.json" <<'PY'
from pathlib import Path
import json, sys
data = json.loads(Path(sys.argv[1]).read_text())
assert data["tag"] == "v0.1.1"
assert data["tag_commit"] == data["head_commit"]
assert data["checks"]["tag_points_to_head"] is True
assert data["publish_performed"] is False
PY

echo "== Mismatched expected version is refused =="
set +e
"$CANDIDATE/scripts/release/preflight.sh" --source "$CANDIDATE" --version 0.1.2 >"$TMP/version.out" 2>"$TMP/version.err"
VERSION_RC=$?
set -e
[[ "$VERSION_RC" == "1" ]] || die "version mismatch should fail"
grep -q 'does not match expected 0.1.2' "$TMP/version.err"

echo "== Missing changelog release heading is refused =="
BROKEN="$TMP/broken"
cp -a "$CANDIDATE" "$BROKEN"
sed -i 's/^## \[0\.1\.1\] - 2026-10-07$/## [0.1.2] - 2026-10-07/' "$BROKEN/CHANGELOG.md"
set +e
"$BROKEN/scripts/release/preflight.sh" --source "$BROKEN" --version 0.1.1 >"$TMP/changelog.out" 2>"$TMP/changelog.err"
CHANGELOG_RC=$?
set -e
[[ "$CHANGELOG_RC" == "1" ]] || die "missing release heading should fail"
grep -q 'CHANGELOG.md lacks exact release heading' "$TMP/changelog.err"

echo "== Tag/version mismatch is refused =="
set +e
"$CANDIDATE/scripts/release/preflight.sh" --source "$CANDIDATE" --tag v0.1.2 >"$TMP/tag.out" 2>"$TMP/tag.err"
TAG_RC=$?
set -e
[[ "$TAG_RC" == "1" ]] || die "tag/version mismatch should fail"
grep -q 'does not match VERSION v0.1.1' "$TMP/tag.err"

echo "PASS  generic installer VERSION + deterministic non-publishing release preflight"
