#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
cd "$ROOT"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

CONTRACT="packaging/ownership-contract.json"

[[ -s "$CONTRACT" ]] || die "packaging ownership contract missing"
[[ -s PACKAGING.md ]] || die "PACKAGING.md missing"

python3 - "$CONTRACT" <<'PY'
from pathlib import Path
import json
import sys

data=json.loads(Path(sys.argv[1]).read_text())

assert data["schema"]==1
assert data["product"]=="Nyvorel"
assert data["phase"]=="7A"
assert data["status"]=="locked"
assert data["target_distribution"]=="Arch Linux"
assert data["package_manager"]=="pacman"
assert data["architecture"]=="split-package-and-user-lifecycle-ownership"

p=data["principles"]
assert p["package_build_or_install_writes_user_home"] is False
assert p["package_install_hook_writes_user_home"] is False
assert p["package_install_hook_starts_user_services"] is False
assert p["package_upgrade_silently_rewrites_user_config"] is False
assert p["package_removal_deletes_user_config_state_or_backups"] is False
assert p["package_owned_content_is_mutated_by_nyvorel_remote_updater"] is False
assert p["user_materialization_remains_manifest_backed"] is True
assert p["user_materialization_remains_backup_first"] is True
assert p["existing_release_tags_may_move"] is False

owned=data["package_owned"]
assert owned=={
    "public_cli":"/usr/bin/nyvorel",
    "helper_root":"/usr/lib/nyvorel/bin",
    "payload_root":"/usr/share/nyvorel",
    "dependency_contract":"/usr/share/nyvorel/dependencies/arch.json",
    "systemd_user_unit_root":"/usr/lib/systemd/user",
    "application_icon":"/usr/share/icons/hicolor/scalable/apps/nyvorel.svg",
    "documentation_root":"/usr/share/doc/nyvorel",
    "license_root":"/usr/share/licenses/nyvorel",
}

for value in owned.values():
    assert value.startswith("/usr/"), value
    assert "/home/" not in value

user=data["user_owned"]
assert user["materialized_shell"]=="~/.config/quickshell/nyvorel"
assert user["materialized_hyprland"]=="~/.config/hypr"
assert user["runtime_config"]=="~/.config/nyvorel"
assert user["installation_state"]=="~/.local/state/nyvorel"
assert user["backup_and_archive_state"]=="~/.local/state/nyvorel"

forbidden=set(data["package_mode_forbidden_owners"])
assert "~/.local/bin/nyvorel" in forbidden
assert "~/.local/bin/nyvorel-*" in forbidden
assert "~/.config/systemd/user/nyvorel-*.service" in forbidden
assert "~/.config/systemd/user/nyvorel-*.path" in forbidden

service=data["service_policy"]
assert service["package_unit_definitions"]=="/usr/lib/systemd/user"
assert service["user_specific_enable_disable_state"]=="user-owned"
assert service["package_mode_materializes_unit_definitions_into_home"] is False
assert service["literal_HOME_template_rendering_inside_package_units"] is False

update=data["update_policy"]
assert update["package_payload_updates"]=="pacman-or-AUR-package-manager"
assert update["package_mode_remote_source_fetch_mutates_usr"] is False
assert update["user_materialization_update"]=="Nyvorel-manifest-transaction"
assert update["package_upgrade_triggers_automatic_home_mutation"] is False
assert update["source_clone_mode_remote_channels_remain_supported_during_transition"] is True

migration=data["migration_policy"]
assert migration["legacy_source_clone_mode"]=="supported-during-7B-transition"
assert migration["package_mode"]=="pending-7B"
assert migration["source_kind_must_be_explicit_in_future_install_state"] is True
assert migration["source_clone_to_package_conversion_requires_explicit_migration"] is True
assert migration["dual_public_cli_ownership_allowed"] is False
assert migration["dual_systemd_unit_definition_ownership_allowed"] is False
assert migration["stale_user_helper_shadowing_must_be_detected"] is True

deps=data["dependency_mapping_policy"]
assert deps["semantic_source_of_truth"]=="dependencies/arch.json"
assert deps["optional_features"]=="candidate-for-optdepends"
assert deps["AUR_helper_invocation_by_package_or_bootstrap"] is False

hooks=data["package_hook_policy"]
assert hooks["allowed"]==["print-actionable-post-install-guidance"]
for required in {
    "write-real-user-home",
    "run-Nyvorel-user-materialization",
    "enable-or-start-user-services-for-arbitrary-users",
    "rewrite-user-configuration",
    "delete-user-state-or-backups",
}:
    assert required in hooks["forbidden"]

gates=set(data["phase7b_required_gates"])
required_gates={
    "exact-package-filesystem-map",
    "package-aware-source-discovery",
    "package-safe-helper-path-migration",
    "package-safe-systemd-user-units",
    "source-clone-to-package-migration-semantics",
    "package-upgrade-with-zero-automatic-home-mutation",
    "package-removal-preserves-user-state",
    "clean-makepkg-build",
    "clean-Arch-package-install",
    "source-clone-mode-regression",
}
assert gates==required_gates

audit=data["audit_evidence"]
assert audit["phase6d_baseline_commit"]=="b7da6435371ee812af4c873b73963807cc2528ef"
assert audit["current_user_managed_files"]==989
assert audit["installer_HOME_template_files"]==10
assert audit["installer_HOME_occurrences"]==29
assert audit["source_bin_files"]==22
assert audit["source_systemd_files"]==20
assert audit["source_quickshell_files"]==911
assert audit["source_hypr_files"]==32
assert audit["source_integrations_files"]==2
assert audit["local_bin_reference_files"]==28
assert audit["user_systemd_reference_files"]==7
assert audit["existing_arch_package_surface"]=="none"

status=data["implementation_status"]
assert status=={
    "ownership_contract":"implemented-7A",
    "pkgbuild":"pending-7B",
    "srcinfo":"pending-7B",
    "package_payload_layout":"pending-7B",
    "package_mode_installer":"pending-7B",
    "package_migration":"pending-7B",
    "package_lifecycle_regression":"pending-7C-or-later",
}

print("packaging_contract_schema=1")
print("phase7a_status=locked")
print("architecture=split-ownership")
print("package_home_mutation=false")
print("public_cli=/usr/bin/nyvorel")
print("systemd_user_units=/usr/lib/systemd/user")
print("package_payload_updates=pacman")
print("phase7b_status=pending")
PY

for path in PKGBUILD .SRCINFO nyvorel.install packaging/PKGBUILD packaging/.SRCINFO; do
  [[ ! -e "$path" ]] || die "Arch package implementation appeared during policy-only Phase 7A: $path"
done

grep -qF 'split ownership' PACKAGING.md \
  || die "PACKAGING.md split-ownership rule missing"
grep -qF '/usr/bin/nyvorel' PACKAGING.md \
  || die "PACKAGING.md public CLI path missing"
grep -qF '/usr/lib/nyvorel/bin/' PACKAGING.md \
  || die "PACKAGING.md helper root missing"
grep -qF '/usr/share/nyvorel/' PACKAGING.md \
  || die "PACKAGING.md payload root missing"
grep -qF '/usr/lib/systemd/user/' PACKAGING.md \
  || die "PACKAGING.md systemd package-unit root missing"
grep -qF '~/.config/systemd/user/' PACKAGING.md \
  || die "PACKAGING.md user-unit boundary missing"
grep -qF 'must not silently edit a real user' PACKAGING.md \
  || die "PACKAGING.md no-home-mutation rule missing"
grep -qF 'must never mutate package-owned' PACKAGING.md \
  || die "PACKAGING.md pacman/update ownership rule missing"

echo "PASS  Arch packaging ownership contract and Phase 7B gates"
