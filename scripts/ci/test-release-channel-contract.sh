#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

POLICY="release/channel-policy.json"
[[ -s "$POLICY" ]] || die "release channel policy missing: $POLICY"
[[ -s RELEASES.md ]] || die "RELEASES.md missing"

python3 - "$POLICY" <<'PY'
from pathlib import Path
import json
import re
import sys

policy = json.loads(Path(sys.argv[1]).read_text())

assert policy["schema"] == 1
assert policy["product"] == "Nyvorel"
assert policy["policy_status"] == "partially-implemented"

stable = policy["current_stable"]
assert stable == {
    "version": "0.1.0",
    "tag": "v0.1.0",
    "commit": "76e1d24c3b1fb6d68e51795a48dd0fb8d2f88e02",
    "immutable": True,
    "github_release_required": True,
    "prerelease": False,
}
assert re.fullmatch(r"[0-9a-f]{40}", stable["commit"])

channels = policy["channels"]
assert set(channels) == {"stable", "development", "explicit-source"}

assert channels["stable"]["user_default"] is True
assert channels["stable"]["remote_ref_kind"] == "immutable-semver-tag"
assert channels["stable"]["github_release_required"] is True
assert channels["stable"]["prerelease_allowed"] is False
assert channels["stable"]["same_version_different_commit"] == "refuse"
assert channels["stable"]["downgrade"] == "refuse"
assert channels["stable"]["mutable"] is False

assert channels["development"]["user_default"] is False
assert channels["development"]["opt_in_required"] is True
assert channels["development"]["remote"] == "origin"
assert channels["development"]["branch"] == "main"
assert channels["development"]["same_version_different_commit"] == "allow"
assert channels["development"]["downgrade"] == "refuse"
assert channels["development"]["mutable"] is True

assert channels["explicit-source"]["user_default"] is False
assert channels["explicit-source"]["opt_in_required"] is True
assert channels["explicit-source"]["same_version_different_commit"] == "allow"
assert channels["explicit-source"]["downgrade"] == "explicit-override-only"
assert channels["explicit-source"]["dirty_source"] == "explicit-override-only"

target = policy["update_cli_target"]
assert target["fetch_default_channel"] == "stable"
assert target["development_channel"] == "explicit-opt-in"
assert target["implementation_phase"] == "6B-complete"
assert "GitHub Releases API" in target["stable_release_discovery"]
assert target["stable_checkout"] == "isolated temporary clone"
assert target["development_fetch"] == "origin/main fast-forward"

status = policy["implementation_status"]
assert status == {
    "stable_channel_resolution": "implemented-6B",
    "development_channel_opt_in": "implemented-6B",
    "release_preflight_automation": "candidate-preflight-implemented-6C1",
    "installer_general_version_support": "implemented-6C1",
    "upgrade_path_matrix": "pending-6D",
}

legacy = policy["legacy_behavior"]
assert legacy == {
    "origin_main_default_fetch_retired_in": "6B",
    "stable_fetch_default": "--fetch",
    "development_replacement": "--fetch --channel development",
    "history_rewrite_required": False,
}

maintenance = policy["maintenance"]
assert maintenance["current_line"] == "0.1.x"
assert maintenance["next_patch"] == "0.1.1"
assert maintenance["existing_release_tags_may_move"] is False

print("release_policy_schema=1")
print("stable_fetch_default=implemented-6B")
print("stable_discovery=github-release+immutable-semver-tag")
print("development=origin/main-explicit-opt-in")
print("same_version_stable=refuse")
print("same_version_development=allow")
print("maintenance_line=0.1.x")
PY

VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION_VALUE" == "0.1.0" ]] \
  || die "Phase 6B baseline expects development VERSION 0.1.0"

bin/nyvorel-update --help | grep -q -- '--channel'
bin/nyvorel-update --help >/dev/null

grep -q 'latest_stable_release' bin/nyvorel-update \
  || die "stable GitHub Release resolver missing"
grep -q 'clone_stable_candidate' bin/nyvorel-update \
  || die "isolated stable checkout missing"
grep -q 'fetch_development_source' bin/nyvorel-update \
  || die "explicit development resolver missing"
grep -q 'stable channel refuses a same-version different-commit update' \
  bin/nyvorel-update \
  || die "stable same-version invariant missing"
grep -q 'NYVOREL_GITHUB_API_BASE' bin/nyvorel-update \
  || die "GitHub API endpoint contract missing"

grep -q 'invalid semantic VERSION' install.sh \
  || die "installer strict semantic VERSION gate missing"

grep -q 'scripts/release/preflight.sh' release/channel-policy.json \
  || die "release candidate preflight policy missing"

grep -qF '**Stable is the user-default remote update channel.**' RELEASES.md \
  || die "RELEASES.md stable default missing"
grep -q 'nyvorel update --fetch --channel development' RELEASES.md \
  || die "RELEASES.md development command missing"
grep -q 'same-version/different-commit' RELEASES.md \
  || die "RELEASES.md same-version semantics missing"

echo "PASS  implemented stable/development update-channel contract"
