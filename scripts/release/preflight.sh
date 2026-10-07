#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE=""
EXPECTED_VERSION=""
EXPECTED_TAG=""
REQUIRE_TAG=0
REQUIRE_CLEAN=0
JSON=0

usage() {
  cat <<'USAGE'
Nyvorel release candidate preflight

Usage:
  scripts/release/preflight.sh [options]

Options:
  --source PATH       Candidate source tree (default: repository root).
  --version X.Y.Z     Require VERSION to equal this semantic version.
  --tag vX.Y.Z        Expected release tag (default: v<VERSION>).
  --require-tag       Require the expected tag to exist and peel to HEAD.
  --require-clean     Require a clean Git worktree.
  --json              Emit machine-readable JSON.
  -h, --help          Show this help.

This command is read-only. It never creates tags, pushes, or publishes a
GitHub Release.
USAGE
}

while (($#)); do
  case "$1" in
    --source)
      (($# >= 2)) || { echo "ERROR: --source requires PATH" >&2; exit 2; }
      SOURCE="$2"; shift 2 ;;
    --version)
      (($# >= 2)) || { echo "ERROR: --version requires X.Y.Z" >&2; exit 2; }
      EXPECTED_VERSION="$2"; shift 2 ;;
    --tag)
      (($# >= 2)) || { echo "ERROR: --tag requires vX.Y.Z" >&2; exit 2; }
      EXPECTED_TAG="$2"; shift 2 ;;
    --require-tag) REQUIRE_TAG=1; shift ;;
    --require-clean) REQUIRE_CLEAN=1; shift ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd -P)"
[[ -n "$SOURCE" ]] || SOURCE="$DEFAULT_ROOT"
SOURCE="$(python3 - "$SOURCE" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).expanduser().resolve(strict=False))
PY
)"

[[ -d "$SOURCE" ]] || { echo "ERROR: source directory missing: $SOURCE" >&2; exit 1; }
[[ -s "$SOURCE/VERSION" ]] || { echo "ERROR: VERSION missing: $SOURCE/VERSION" >&2; exit 1; }
[[ -s "$SOURCE/CHANGELOG.md" ]] || { echo "ERROR: CHANGELOG.md missing" >&2; exit 1; }
[[ -x "$SOURCE/install.sh" ]] || { echo "ERROR: install.sh missing/not executable" >&2; exit 1; }

VERSION_VALUE="$(tr -d '[:space:]' <"$SOURCE/VERSION")"
[[ "$VERSION_VALUE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ERROR: VERSION is not strict semantic x.y.z: $VERSION_VALUE" >&2; exit 1; }
if [[ -n "$EXPECTED_VERSION" && "$VERSION_VALUE" != "$EXPECTED_VERSION" ]]; then
  echo "ERROR: VERSION $VERSION_VALUE does not match expected $EXPECTED_VERSION" >&2
  exit 1
fi
TAG="${EXPECTED_TAG:-v$VERSION_VALUE}"
[[ "$TAG" == "v$VERSION_VALUE" ]] || { echo "ERROR: tag $TAG does not match VERSION v$VERSION_VALUE" >&2; exit 1; }

CHANGELOG_HEADING="$(grep -E "^## \\[$VERSION_VALUE\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$SOURCE/CHANGELOG.md" | head -n1 || true)"
[[ -n "$CHANGELOG_HEADING" ]] || { echo "ERROR: CHANGELOG.md lacks exact release heading: ## [$VERSION_VALUE] - YYYY-MM-DD" >&2; exit 1; }

GIT_REPO=0
HEAD_COMMIT=""
TAG_COMMIT=""
DIRTY="not-applicable"
if git -C "$SOURCE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_REPO=1
  HEAD_COMMIT="$(git -C "$SOURCE" rev-parse HEAD)"
  STATUS="$(git -C "$SOURCE" status --porcelain=v1 --untracked-files=all)"
  [[ -z "$STATUS" ]] && DIRTY="false" || DIRTY="true"
  if (( REQUIRE_CLEAN )) && [[ -n "$STATUS" ]]; then
    printf '%s\n' "$STATUS" >&2
    echo "ERROR: release candidate worktree is not clean" >&2
    exit 1
  fi
  if git -C "$SOURCE" show-ref --verify --quiet "refs/tags/$TAG"; then
    TAG_COMMIT="$(git -C "$SOURCE" rev-parse "$TAG^{commit}")"
    [[ -n "$TAG_COMMIT" ]] || { echo "ERROR: tag $TAG cannot be peeled to a commit" >&2; exit 1; }
  fi
elif (( REQUIRE_TAG || REQUIRE_CLEAN )); then
  echo "ERROR: --require-tag/--require-clean requires a Git source tree" >&2
  exit 1
fi

if (( REQUIRE_TAG )); then
  [[ -n "$TAG_COMMIT" ]] || { echo "ERROR: required release tag does not exist: $TAG" >&2; exit 1; }
  [[ "$TAG_COMMIT" == "$HEAD_COMMIT" ]] || { echo "ERROR: tag $TAG points to $TAG_COMMIT, not candidate HEAD $HEAD_COMMIT" >&2; exit 1; }
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home"
"$SOURCE/install.sh" --target-home "$TMP/home" --dry-run --no-activate >"$TMP/install-dry-run.log"
grep -q "Version      : $VERSION_VALUE" "$TMP/install-dry-run.log" || { cat "$TMP/install-dry-run.log" >&2; echo "ERROR: installer did not accept candidate VERSION" >&2; exit 1; }
grep -q 'DRY RUN — no files changed.' "$TMP/install-dry-run.log" || { cat "$TMP/install-dry-run.log" >&2; echo "ERROR: installer dry-run did not complete" >&2; exit 1; }

if (( JSON )); then
  python3 - "$SOURCE" "$VERSION_VALUE" "$TAG" "$CHANGELOG_HEADING" "$GIT_REPO" "$HEAD_COMMIT" "$TAG_COMMIT" "$DIRTY" "$REQUIRE_TAG" <<'PY'
import json, sys
source, version, tag, changelog, git_repo, head, tag_commit, dirty, require_tag = sys.argv[1:]
print(json.dumps({
    "schema": 1,
    "product": "Nyvorel",
    "mode": "release-candidate-preflight",
    "mutation_performed": False,
    "publish_performed": False,
    "source": source,
    "version": version,
    "tag": tag,
    "changelog_heading": changelog,
    "git_repository": git_repo == "1",
    "head_commit": head or None,
    "tag_commit": tag_commit or None,
    "worktree_dirty": None if dirty == "not-applicable" else dirty == "true",
    "tag_required": require_tag == "1",
    "checks": {
        "strict_semver": True,
        "tag_matches_version": True,
        "changelog_release_heading": True,
        "installer_accepts_version": True,
        "installer_dry_run": True,
        "tag_points_to_head": (tag_commit == head) if require_tag == "1" else None,
    },
}, indent=2))
PY
else
  echo "============================================================"
  echo "NYVOREL RELEASE CANDIDATE PREFLIGHT"
  echo "============================================================"
  echo "Source           : $SOURCE"
  echo "VERSION          : $VERSION_VALUE"
  echo "Expected tag     : $TAG"
  echo "Changelog        : $CHANGELOG_HEADING"
  echo "Git repository   : $([[ $GIT_REPO -eq 1 ]] && echo yes || echo no)"
  echo "HEAD             : ${HEAD_COMMIT:-<not-applicable>}"
  echo "Tag commit       : ${TAG_COMMIT:-<not-created>}"
  echo "Require tag      : $([[ $REQUIRE_TAG -eq 1 ]] && echo yes || echo no)"
  echo "Require clean    : $([[ $REQUIRE_CLEAN -eq 1 ]] && echo yes || echo no)"
  echo "Mutation         : NONE"
  echo "Publication      : NONE"
  echo
  echo "PREFLIGHT: PASS"
fi
