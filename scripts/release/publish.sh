#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
REMOTE="origin"
EXPECTED_VERSION=""
PUBLISH=0
YES=0
GH_BIN="${NYVOREL_GH_BIN:-gh}"
REPO_SLUG="${NYVOREL_GITHUB_REPOSITORY:-}"
WORKFLOW="${NYVOREL_RELEASE_CI_WORKFLOW:-CI}"

die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
Nyvorel release publisher

Default mode is plan-only and performs no mutation.

Usage:
  scripts/release/publish.sh [--version X.Y.Z] [--remote NAME]
  scripts/release/publish.sh --version X.Y.Z --publish --yes

Publication order:
  candidate preflight -> exact main CI GREEN -> immutable annotated tag
  -> push tag -> exact tag CI GREEN -> GitHub Release verification

Existing tags are never moved. A partially completed publication may be
resumed only when the existing tag still peels to the exact candidate HEAD.
USAGE
}

while (($#)); do
  case "$1" in
    --version) (($# >= 2)) || exit 2; EXPECTED_VERSION="$2"; shift 2 ;;
    --remote) (($# >= 2)) || exit 2; REMOTE="$2"; shift 2 ;;
    --publish) PUBLISH=1; shift ;;
    --yes) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

(( YES == 0 || PUBLISH == 1 )) || { echo "ERROR: --yes requires --publish" >&2; exit 2; }
(( PUBLISH == 0 || YES == 1 )) || { echo "ERROR: --publish requires --yes" >&2; exit 2; }

cd "$ROOT"
VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION_VALUE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid VERSION: $VERSION_VALUE"
[[ -z "$EXPECTED_VERSION" || "$EXPECTED_VERSION" == "$VERSION_VALUE" ]] \
  || die "VERSION $VERSION_VALUE does not match expected $EXPECTED_VERSION"
TAG="v$VERSION_VALUE"

[[ "$(git branch --show-current)" == main ]] || die "publication requires branch main"
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || die "publication requires a clean worktree"

HEAD_COMMIT="$(git rev-parse HEAD)"
REMOTE_URL="$(git remote get-url "$REMOTE" 2>/dev/null || true)"
[[ -n "$REMOTE_URL" ]] || die "remote unavailable: $REMOTE"
REMOTE_MAIN="$(git ls-remote "$REMOTE" refs/heads/main | awk '{print $1}')"
[[ "$REMOTE_MAIN" == "$HEAD_COMMIT" ]] \
  || die "candidate HEAD does not exactly match $REMOTE/main"

command -v "$GH_BIN" >/dev/null 2>&1 || die "GitHub CLI unavailable: $GH_BIN"

if [[ -z "$REPO_SLUG" ]]; then
  REPO_SLUG="$(
    python3 - "$REMOTE_URL" <<'PY'
from urllib.parse import urlparse
import sys
r=sys.argv[1]
if r.startswith("git@github.com:"):
    p=r.split(":",1)[1]
else:
    u=urlparse(r); p=u.path if u.hostname=="github.com" else ""
p=p.strip("/")
if p.endswith(".git"): p=p[:-4]
parts=p.split("/")
if len(parts)!=2 or not all(parts): raise SystemExit(1)
print("/".join(parts))
PY
  )" || die "cannot derive GitHub repository; set NYVOREL_GITHUB_REPOSITORY"
fi

scripts/release/preflight.sh \
  --source "$ROOT" --version "$VERSION_VALUE" --tag "$TAG" --require-clean >/dev/null

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

local_tag_commit() {
  git show-ref --verify --quiet "refs/tags/$TAG" && git rev-parse "$TAG^{commit}" || true
}

remote_tag_commit() {
  local rows
  rows="$(git ls-remote --tags "$REMOTE" "refs/tags/$TAG" "refs/tags/$TAG^{}")"
  python3 - "$TAG" "$rows" <<'PY'
import sys
tag, raw=sys.argv[1:]
base=peeled=""
for line in raw.splitlines():
    parts=line.split()
    if len(parts)!=2: continue
    sha,ref=parts
    if ref==f"refs/tags/{tag}^{{}}": peeled=sha
    elif ref==f"refs/tags/{tag}": base=sha
print(peeled or base)
PY
}

list_runs() {
  "$GH_BIN" run list --repo "$REPO_SLUG" --workflow "$WORKFLOW" \
    --commit "$HEAD_COMMIT" --limit 50 \
    --json databaseId,headSha,headBranch,status,conclusion,event,workflowName
}

main_run_id() {
  python3 - "$HEAD_COMMIT" "$WORKFLOW" "$(list_runs)" <<'PY'
import json,sys
head,wf,raw=sys.argv[1:]
for r in json.loads(raw):
    if r.get("headSha")==head and r.get("headBranch")=="main" and r.get("workflowName")==wf and r.get("event")=="push":
        print(r["databaseId"]); break
PY
}

tag_run_id() {
  local main_id="$1"
  python3 - "$HEAD_COMMIT" "$TAG" "$WORKFLOW" "$main_id" "$(list_runs)" <<'PY'
import json,sys
head,tag,wf,main_id,raw=sys.argv[1:]
rows=[r for r in json.loads(raw)
      if r.get("headSha")==head and r.get("workflowName")==wf and r.get("event")=="push"
      and str(r.get("databaseId"))!=main_id]
for r in rows:
    if r.get("headBranch")==tag:
        print(r["databaseId"]); raise SystemExit
if rows:
    rows.sort(key=lambda r:int(r["databaseId"]), reverse=True)
    print(rows[0]["databaseId"])
PY
}

verify_run() {
  local id="$1"
  local label="$2"
  local f="$TMP/run-$id.json"
  "$GH_BIN" run watch "$id" --repo "$REPO_SLUG" --exit-status
  "$GH_BIN" run view "$id" --repo "$REPO_SLUG" \
    --json headSha,status,conclusion,jobs,url >"$f"
  python3 - "$f" "$HEAD_COMMIT" "$label" <<'PY'
from pathlib import Path
import json,sys
data=json.loads(Path(sys.argv[1]).read_text()); head=sys.argv[2]; label=sys.argv[3]
assert data["headSha"]==head, f"{label}: wrong head"
assert data["status"]=="completed", f"{label}: not completed"
assert data["conclusion"]=="success", f"{label}: not successful"
jobs={j["name"]:j for j in data["jobs"]}
required={"Source integrity","Installer & recovery sandbox","Doctor sandbox","Update lifecycle","Clean-machine Arch install","Bootstrap planning"}
assert not (required-set(jobs)), f"{label}: missing jobs"
assert all(jobs[n].get("conclusion")=="success" for n in required), f"{label}: non-green jobs"
print(f"{label}_ci={data.get('url')}")
PY
}

release_exists() {
  "$GH_BIN" release view "$TAG" --repo "$REPO_SLUG" \
    --json tagName,name,isDraft,isPrerelease,url >"$TMP/release.json" 2>/dev/null
}

verify_release() {
  python3 - "$TMP/release.json" "$TAG" <<'PY'
from pathlib import Path
import json,sys
d=json.loads(Path(sys.argv[1]).read_text()); tag=sys.argv[2]
assert d["tagName"]==tag
assert d["isDraft"] is False
assert d["isPrerelease"] is False
print(f"release_url={d.get('url')}")
PY
}

extract_notes() {
  python3 - CHANGELOG.md "$VERSION_VALUE" "$TMP/notes.md" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); v=sys.argv[2]; out=Path(sys.argv[3])
lines=p.read_text().splitlines()
pat=re.compile(rf"^## \[{re.escape(v)}\] - \d{{4}}-\d{{2}}-\d{{2}}$")
start=next((i+1 for i,x in enumerate(lines) if pat.fullmatch(x)),None)
if start is None: raise SystemExit("release heading missing")
body=[]
for x in lines[start:]:
    if x.startswith("## ["): break
    body.append(x)
notes="\n".join(body).strip()
if not notes: raise SystemExit("release notes are empty")
out.write_text(notes+"\n")
PY
}

MAIN_RUN="$(main_run_id)"
[[ -n "$MAIN_RUN" ]] || die "no CI push run found for exact main candidate"
verify_run "$MAIN_RUN" main

LOCAL_TAG="$(local_tag_commit)"
REMOTE_TAG="$(remote_tag_commit)"

[[ -z "$LOCAL_TAG" || "$LOCAL_TAG" == "$HEAD_COMMIT" ]] \
  || die "local tag $TAG points to $LOCAL_TAG, not candidate $HEAD_COMMIT; tags are immutable"
[[ -z "$REMOTE_TAG" || "$REMOTE_TAG" == "$HEAD_COMMIT" ]] \
  || die "remote tag $TAG points to $REMOTE_TAG; refusing to move it"

RELEASE=0
if release_exists; then
  RELEASE=1
  [[ -n "$REMOTE_TAG" ]] || die "GitHub Release exists without matching remote tag"
  verify_release
fi

if (( ! PUBLISH )); then
  printf 'VERSION=%s\nTAG=%s\nHEAD=%s\nMAIN_CI=%s\nLOCAL_TAG=%s\nREMOTE_TAG=%s\nRELEASE=%s\n' \
    "$VERSION_VALUE" "$TAG" "$HEAD_COMMIT" "$MAIN_RUN" "${LOCAL_TAG:-absent}" "${REMOTE_TAG:-absent}" \
    "$([[ $RELEASE -eq 1 ]] && echo present || echo absent)"
  echo "Mutation=NONE"
  echo "Publication=NONE"
  echo "PLAN: PASS"
  exit 0
fi

if (( RELEASE )); then
  TAG_RUN=""
  for _ in $(seq 1 60); do TAG_RUN="$(tag_run_id "$MAIN_RUN")"; [[ -n "$TAG_RUN" ]] && break; sleep 3; done
  [[ -n "$TAG_RUN" ]] || die "tag CI run not found"
  verify_run "$TAG_RUN" tag
  echo "PUBLISH: ALREADY COMPLETE"
  exit 0
fi

if [[ -z "$LOCAL_TAG" ]]; then
  if [[ -n "$REMOTE_TAG" ]]; then
    git fetch "$REMOTE" "refs/tags/$TAG:refs/tags/$TAG"
  else
    git tag -a "$TAG" -m "Nyvorel $TAG"
  fi
  LOCAL_TAG="$(local_tag_commit)"
fi
[[ "$LOCAL_TAG" == "$HEAD_COMMIT" ]] || die "local tag does not peel to candidate HEAD"

scripts/release/preflight.sh \
  --source "$ROOT" --version "$VERSION_VALUE" --tag "$TAG" --require-clean --require-tag >/dev/null

if [[ -z "$REMOTE_TAG" ]]; then
  git push "$REMOTE" "refs/tags/$TAG:refs/tags/$TAG"
  REMOTE_TAG="$(remote_tag_commit)"
fi
[[ "$REMOTE_TAG" == "$HEAD_COMMIT" ]] || die "remote tag does not peel to candidate HEAD"

TAG_RUN=""
for _ in $(seq 1 60); do TAG_RUN="$(tag_run_id "$MAIN_RUN")"; [[ -n "$TAG_RUN" ]] && break; sleep 3; done
[[ -n "$TAG_RUN" ]] || die "tag CI run did not appear"
verify_run "$TAG_RUN" tag

extract_notes
if ! release_exists; then
  "$GH_BIN" release create "$TAG" --repo "$REPO_SLUG" --verify-tag \
    --title "Nyvorel $TAG" --notes-file "$TMP/notes.md"
fi
release_exists || die "release missing after publication"
verify_release
[[ "$(remote_tag_commit)" == "$HEAD_COMMIT" ]] || die "remote tag changed during publication"

echo "PUBLISH: PASS"
