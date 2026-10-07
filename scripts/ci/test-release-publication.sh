#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
C="$TMP/candidate"; O="$TMP/origin.git"; B="$TMP/bin"; S="$TMP/state"
mkdir -p "$C" "$B" "$S"
cp -a "$ROOT/." "$C/"; rm -rf "$C/.git"
find "$C" -type d -name __pycache__ -prune -exec rm -rf {} +
printf '0.1.1\n' >"$C/VERSION"

python3 - "$C/CHANGELOG.md" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); t=p.read_text(); m="## [Unreleased]\n"
r="## [Unreleased]\n\n## [0.1.1] - 2026-10-07\n\nSynthetic publication fixture.\n"
assert t.count(m)==1
p.write_text(t.replace(m,r,1))
PY

git -C "$C" init -b main >/dev/null
git -C "$C" config user.name "Nyvorel CI"
git -C "$C" config user.email "ci@nyvorel.invalid"
git -C "$C" add -A
git -C "$C" commit -m "fixture: v0.1.1" >/dev/null
git init --bare "$O" >/dev/null
git -C "$C" remote add origin "$O"
git -C "$C" push -u origin main >/dev/null

export FAKE_HEAD="$(git -C "$C" rev-parse HEAD)"
export FAKE_TAG="v0.1.1"
export FAKE_STATE="$S"
export NYVOREL_GH_BIN="$B/gh"
export NYVOREL_GITHUB_REPOSITORY="harkoussomar/nyvorel"

cat >"$B/gh" <<'GH'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-} ${2:-}" in
  "run list")
    python3 - "$FAKE_HEAD" "$FAKE_TAG" <<'PY'
import json,sys
h,t=sys.argv[1:]
print(json.dumps([
 {"databaseId":101,"headSha":h,"headBranch":"main","status":"completed","conclusion":"success","event":"push","workflowName":"CI"},
 {"databaseId":202,"headSha":h,"headBranch":t,"status":"completed","conclusion":"success","event":"push","workflowName":"CI"}
]))
PY
    ;;
  "run watch") exit 0 ;;
  "run view")
    id="${3:-}"
    python3 - "$FAKE_HEAD" "$id" <<'PY'
import json,sys
h,i=sys.argv[1:]
names=["Source integrity","Installer & recovery sandbox","Doctor sandbox","Update lifecycle","Clean-machine Arch install","Bootstrap planning"]
print(json.dumps({"headSha":h,"status":"completed","conclusion":"success","jobs":[{"name":n,"conclusion":"success"} for n in names],"url":f"https://invalid/{i}"}))
PY
    ;;
  "release view")
    [[ -s "$FAKE_STATE/release.json" ]] || exit 1
    cat "$FAKE_STATE/release.json"
    ;;
  "release create")
    tag="${3:-}"
    printf '%s\n' "$tag" >>"$FAKE_STATE/create.log"
    python3 - "$FAKE_STATE/release.json" "$tag" <<'PY'
from pathlib import Path
import json,sys
Path(sys.argv[1]).write_text(json.dumps({"tagName":sys.argv[2],"name":"Nyvorel "+sys.argv[2],"isDraft":False,"isPrerelease":False,"url":"https://invalid/release"})+"\n")
PY
    ;;
  *) echo "unsupported fake gh: $*" >&2; exit 2 ;;
esac
GH
chmod +x "$B/gh"

P="$C/scripts/release/publish.sh"

echo "== Plan is zero-mutation =="
"$P" --version 0.1.1 >"$TMP/plan.log"
grep -q 'PLAN: PASS' "$TMP/plan.log"
grep -q 'Mutation=NONE' "$TMP/plan.log"
[[ -z "$(git -C "$C" tag --list v0.1.1)" ]] || die "plan created local tag"
[[ -z "$(git ls-remote --tags "$O" refs/tags/v0.1.1)" ]] || die "plan pushed tag"
[[ ! -e "$S/release.json" ]] || die "plan created release"

echo "== Publication needs --yes =="
set +e
"$P" --version 0.1.1 --publish >/dev/null 2>"$TMP/no-yes.err"
rc=$?
set -e
[[ "$rc" == 2 ]] || die "--publish without --yes should exit 2"

echo "== Explicit publish =="
"$P" --version 0.1.1 --publish --yes >"$TMP/publish.log"
grep -q 'PUBLISH: PASS' "$TMP/publish.log"
local_commit="$(git -C "$C" rev-parse 'v0.1.1^{commit}')"
remote_commit="$(git ls-remote --tags "$O" 'refs/tags/v0.1.1^{}' | awk '{print $1}')"
[[ "$local_commit" == "$FAKE_HEAD" ]] || die "local tag wrong"
[[ "$remote_commit" == "$FAKE_HEAD" ]] || die "remote tag wrong"
[[ -s "$S/release.json" ]] || die "release not created"

echo "== Rerun is idempotent =="
"$P" --version 0.1.1 --publish --yes >"$TMP/rerun.log"
grep -q 'PUBLISH: ALREADY COMPLETE' "$TMP/rerun.log"
[[ "$(wc -l <"$S/create.log")" == 1 ]] || die "release created more than once"

echo "== Tag movement is refused =="
printf '\nnew development commit\n' >>"$C/README.md"
git -C "$C" add README.md
git -C "$C" commit -m "fixture: newer commit" >/dev/null
git -C "$C" push origin main >/dev/null
export FAKE_HEAD="$(git -C "$C" rev-parse HEAD)"
set +e
"$P" --version 0.1.1 --publish --yes >/dev/null 2>"$TMP/move.err"
rc=$?
set -e
[[ "$rc" == 1 ]] || die "tag movement should fail"
grep -q 'tags are immutable' "$TMP/move.err"
[[ "$(git ls-remote --tags "$O" 'refs/tags/v0.1.1^{}' | awk '{print $1}')" == "$local_commit" ]] \
  || die "remote tag moved"

echo "PASS  publication plan, explicit confirmation, CI gates, idempotence and immutable tags"
