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

assert policy["schema"] == 2
assert policy["product"] == "Nyvorel"
assert policy["policy_status"] == "phase6-complete"
assert "current_stable" not in policy

anchors = policy["immutable_release_anchors"]
assert anchors == [{
    "version": "0.1.0",
    "tag": "v0.1.0",
    "commit": "76e1d24c3b1fb6d68e51795a48dd0fb8d2f88e02",
    "immutable": True,
    "github_release_required": True,
    "prerelease": False,
}]
assert re.fullmatch(r"[0-9a-f]{40}", anchors[0]["commit"])

stable_state = policy["stable_state"]
assert stable_state == {
    "authoritative_source": "GitHub Releases API",
    "selection": "highest non-draft, non-prerelease strict semver tag",
    "source_tree_pins_current_stable": False,
}

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
    "upgrade_path_matrix": "implemented-6D",
    "release_publication_tooling": "implemented-6C2",
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
assert maintenance["versioning"] == "semver-patch"
assert "next_patch" not in maintenance
assert maintenance["next_patch_policy"] == "increment-highest-stable-patch"
assert maintenance["existing_release_tags_may_move"] is False
assert maintenance["existing_github_releases_may_be_retargeted"] is False

upgrade = policy["upgrade_validation"]
assert upgrade == {
    "implementation_phase": "6D",
    "synthetic_path": "0.1.0 -> 0.1.1",
    "stable_patch_upgrade": "proven",
    "stable_post_upgrade_noop": "proven",
    "stable_remote_downgrade": "refused",
    "explicit_source_downgrade": "explicit-override-only",
    "development_same_version_commit": "allowed",
    "development_to_stable_same_version_different_commit": "refused",
    "original_backup_continuity_after_multi_step_update": "proven",
    "uninstall_recovery_after_upgrade": "proven",
    "pristine_arch_matrix": "proven",
}

tooling = policy["release_tooling"]
assert tooling["candidate_preflight"] == "scripts/release/preflight.sh"
assert tooling["preflight_mutates_repository"] is False
assert tooling["preflight_publishes_release"] is False
assert tooling["publication_tooling"] == "scripts/release/publish.sh"
assert tooling["publication_requires_explicit_action"] is True
assert tooling["publication_confirmation"] == "--publish --yes"
assert tooling["plan_mode_mutates_repository"] is False
assert tooling["main_ci_required"] is True
assert tooling["tag_ci_required"] is True
assert tooling["release_created_after_tag_ci"] is True
assert tooling["existing_tag_may_move"] is False
assert tooling["partial_publication_is_resumable"] is True
assert tooling["release_notes_source"] == "CHANGELOG release section"

print("release_policy_schema=2")
print("stable_state=dynamic-github-releases")
print("immutable_anchor=v0.1.0")
print("stable_fetch_default=implemented-6B")
print("publication_tooling=implemented-6C2")
print("publication_confirmation=--publish --yes")
print("main_ci_required=true")
print("tag_ci_required=true")
print("maintenance_line=0.1.x")
print("upgrade_matrix=implemented-6D")
print("phase6_status=complete")
PY

VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION_VALUE" =~ ^0\.1\.[0-9]+$ ]] \
  || die "current maintenance line requires VERSION 0.1.x, found $VERSION_VALUE"

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

grep -q 'invalid semantic VERSION' install.sh \
  || die "installer strict semantic VERSION gate missing"

[[ -x scripts/release/preflight.sh ]] \
  || die "release candidate preflight missing/not executable"
[[ -x scripts/release/publish.sh ]] \
  || die "release publication engine missing/not executable"

scripts/release/publish.sh --help | grep -q -- '--publish'
scripts/release/publish.sh --help | grep -q -- '--yes'

grep -qF '**Stable is the user-default remote update channel.**' RELEASES.md \
  || die "RELEASES.md stable default missing"
grep -q 'scripts/release/publish.sh --version 0.1.1 --publish --yes' RELEASES.md \
  || die "RELEASES.md explicit publication command missing"
grep -q 'GitHub Releases' RELEASES.md \
  || die "RELEASES.md dynamic stable authority missing"

echo "PASS  release/update channel and publication contract"
