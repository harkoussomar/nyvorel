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
assert policy["policy_status"] == "defined-not-fully-implemented"

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
assert target["implementation_phase"] == "6B"

same = policy["same_version_policy"]
assert set(same) == {"stable", "development", "explicit-source"}

inv = policy["release_invariants"]
assert inv["version_format"] == "MAJOR.MINOR.PATCH"
assert inv["tag_format"] == "v{version}"
assert inv["tag_must_match_version"] is True
assert inv["tag_must_be_immutable"] is True
assert inv["stable_release_must_not_be_draft"] is True
assert inv["stable_release_must_not_be_prerelease"] is True
assert inv["changelog_release_heading_required"] is True
assert inv["release_commit_must_be_clean"] is True
assert inv["release_ci_must_be_green"] is True

maintenance = policy["maintenance"]
assert maintenance["current_line"] == "0.1.x"
assert maintenance["versioning"] == "semver-patch"
assert maintenance["next_patch"] == "0.1.1"
assert maintenance["existing_release_tags_may_move"] is False
assert maintenance["existing_github_releases_may_be_retargeted"] is False
assert maintenance["separate_maintenance_branch_required_now"] is False

status = policy["implementation_status"]
assert status == {
    "stable_channel_resolution": "pending-6B",
    "development_channel_opt_in": "pending-6B",
    "release_preflight_automation": "pending-6C",
    "installer_general_version_support": "pending-6C",
    "upgrade_path_matrix": "pending-6D",
}

legacy = policy["legacy_behavior"]
assert legacy["fetch_currently_tracks"] == "origin/main"
assert legacy["classification"] == "development"
assert legacy["temporary_until"] == "6B"
assert legacy["must_not_be_documented_as_stable"] is True

print("release_policy_schema=1")
print("stable_default=immutable-semver-tag")
print("development=origin/main-explicit-opt-in")
print("same_version_stable=refuse")
print("same_version_development=allow")
print("maintenance_line=0.1.x")
PY

VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION_VALUE" == "0.1.0" ]] \
  || die "Phase 6A baseline expects development VERSION 0.1.0"

# Phase 6A is policy-only. Lock the legacy behavior in the test so 6A cannot
# accidentally claim stable-channel implementation before 6B actually changes it.
grep -q 'Fetching origin/main' bin/nyvorel-update \
  || die "legacy updater fetch behavior changed before Phase 6B"
grep -q '"origin", "main"' bin/nyvorel-update \
  || die "legacy origin/main update fetch is no longer detectable"
grep -q -- '--allow-downgrade' bin/nyvorel-update \
  || die "existing downgrade override disappeared"

# v0.1.1 cannot be published safely until the installer is generalized in 6C.
grep -Fq '[[ "$VERSION" == "0.1.0" ]]' install.sh \
  || die "installer version gate changed without updating Phase 6A implementation status"

grep -qF '**Stable is the user-default remote update channel.**' RELEASES.md \
  || die "RELEASES.md does not explain stable default semantics"
grep -q 'Development is explicitly opt-in' RELEASES.md \
  || die "RELEASES.md does not explain development opt-in"
grep -q 'same-version/different-commit' RELEASES.md \
  || die "RELEASES.md does not explain same-version channel semantics"
grep -q 'v0.1.x maintenance policy' RELEASES.md \
  || die "RELEASES.md does not document v0.1.x maintenance"

echo "PASS  release/update channel policy, invariants, and Phase 6A implementation boundary"
