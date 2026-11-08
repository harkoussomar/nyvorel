#!/usr/bin/env bash
set -Eeuo pipefail
export NYVOREL_SKIP_NATIVE_BUILD=1
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
CANDIDATE_VERSION="$(awk -F. 'NF == 3 { print $1 "." $2 "." ($3 + 1) }' VERSION)"
MISMATCH_VERSION="$(awk -F. '{ print $1 "." $2 "." ($3 + 1) }' <<<"$CANDIDATE_VERSION")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
CANDIDATE="$TMP/candidate"
mkdir -p "$CANDIDATE"
git -C "$ROOT" ls-files --cached --others --exclude-standard -z \
  | tar -C "$ROOT" --null -T - -cf - \
  | tar -C "$CANDIDATE" -xf -
rm -rf "$CANDIDATE/.git"
find "$CANDIDATE" -type d -name __pycache__ -prune -exec rm -rf {} +

echo "== Build synthetic v$CANDIDATE_VERSION release candidate =="
printf '%s\n' "$CANDIDATE_VERSION" >"$CANDIDATE/VERSION"
python3 - "$CANDIDATE/CHANGELOG.md" "$CANDIDATE_VERSION" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
marker = "## [Unreleased]\n"
release = f"## [Unreleased]\n\n## [{sys.argv[2]}] - 2026-10-07\n\nSynthetic release-preflight fixture.\n"
if text.count(marker) != 1:
    raise SystemExit("fixture changelog marker mismatch")
p.write_text(text.replace(marker, release, 1))
PY

git -C "$CANDIDATE" init -b main >/dev/null
git -C "$CANDIDATE" config user.name "Nyvorel Release CI"
git -C "$CANDIDATE" config user.email "release-ci@nyvorel.invalid"
git -C "$CANDIDATE" add -A
git -C "$CANDIDATE" commit -m "fixture: v$CANDIDATE_VERSION candidate" >/dev/null

echo "== Future semantic VERSION is accepted by installer =="
"$CANDIDATE/install.sh" --target-home "$TMP/home-v015" --dry-run --no-activate >"$TMP/install-v015.log"
grep -q "Version      : $CANDIDATE_VERSION" "$TMP/install-v015.log"
grep -q 'DRY RUN — no files changed.' "$TMP/install-v015.log"

echo "== Candidate preflight passes before tag creation =="
"$CANDIDATE/scripts/release/preflight.sh" --source "$CANDIDATE" --version "$CANDIDATE_VERSION" --tag "v$CANDIDATE_VERSION" --require-clean --json >"$TMP/preflight.json"
python3 - "$TMP/preflight.json" "$CANDIDATE_VERSION" <<'PY'
from pathlib import Path
import json, sys
data = json.loads(Path(sys.argv[1]).read_text())
assert data["schema"] == 1
assert data["version"] == sys.argv[2]
assert data["tag"] == f"v{sys.argv[2]}"
assert data["mutation_performed"] is False
assert data["publish_performed"] is False
assert data["worktree_dirty"] is False
assert data["checks"]["installer_accepts_version"] is True
assert data["checks"]["tag_points_to_head"] is None
PY

echo "== Annotated release tag can be required and must peel to HEAD =="
git -C "$CANDIDATE" tag -a "v$CANDIDATE_VERSION" -m "fixture release v$CANDIDATE_VERSION"
"$CANDIDATE/scripts/release/preflight.sh" --source "$CANDIDATE" --version "$CANDIDATE_VERSION" --require-clean --require-tag --json >"$TMP/tagged.json"
python3 - "$TMP/tagged.json" "$CANDIDATE_VERSION" <<'PY'
from pathlib import Path
import json, sys
data = json.loads(Path(sys.argv[1]).read_text())
assert data["tag"] == f"v{sys.argv[2]}"
assert data["tag_commit"] == data["head_commit"]
assert data["checks"]["tag_points_to_head"] is True
assert data["publish_performed"] is False
PY

echo "== Mismatched expected version is refused =="
set +e
"$CANDIDATE/scripts/release/preflight.sh" --source "$CANDIDATE" --version "$MISMATCH_VERSION" >"$TMP/version.out" 2>"$TMP/version.err"
VERSION_RC=$?
set -e
[[ "$VERSION_RC" == "1" ]] || die "version mismatch should fail"
grep -q "does not match expected $MISMATCH_VERSION" "$TMP/version.err"

echo "== Missing changelog release heading is refused =="
BROKEN="$TMP/broken"
cp -a "$CANDIDATE" "$BROKEN"
python3 - "$BROKEN/CHANGELOG.md" "$CANDIDATE_VERSION" "$MISMATCH_VERSION" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
p.write_text(p.read_text().replace(f"## [{sys.argv[2]}] - 2026-10-07", f"## [{sys.argv[3]}] - 2026-10-07"))
PY
set +e
"$BROKEN/scripts/release/preflight.sh" --source "$BROKEN" --version "$CANDIDATE_VERSION" >"$TMP/changelog.out" 2>"$TMP/changelog.err"
CHANGELOG_RC=$?
set -e
[[ "$CHANGELOG_RC" == "1" ]] || die "missing release heading should fail"
grep -q 'CHANGELOG.md lacks exact release heading' "$TMP/changelog.err"

echo "== Tag/version mismatch is refused =="
set +e
"$CANDIDATE/scripts/release/preflight.sh" --source "$CANDIDATE" --tag "v$MISMATCH_VERSION" >"$TMP/tag.out" 2>"$TMP/tag.err"
TAG_RC=$?
set -e
[[ "$TAG_RC" == "1" ]] || die "tag/version mismatch should fail"
grep -q "does not match VERSION v$CANDIDATE_VERSION" "$TMP/tag.err"

echo "PASS  generic installer VERSION + deterministic non-publishing release preflight"
