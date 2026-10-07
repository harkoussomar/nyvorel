# Changelog

All notable Nyvorel changes intended for public releases are recorded here.

## [Unreleased]

### Post-release infrastructure — Phase 6B
- Made stable the default `nyvorel update --fetch` channel using non-draft/non-prerelease semantic GitHub Releases and isolated tagged checkouts.
- Added explicit `--channel development` resolution for `origin/main`.
- Enforced stable same-version/different-commit refusal while preserving development/explicit-source same-version workflows and all existing drift/rollback safety.

### Post-release infrastructure — Phase 6A
- Defined stable, development, and explicit-source update semantics in a versioned release-channel contract.
- Defined stable same-version commit refusal, development same-version commit allowance, immutable release invariants, and the `0.1.x` maintenance policy.
- Documented the existing `--fetch -> origin/main` behavior as legacy development behavior pending Phase 6B.

### Post-release infrastructure — Phase 5D
- Added discoverable optional-dependency catalog UX with human and JSON output.
- Added actionable invalid-ID guidance without package-manager probing or mutation.
- Added Phase 5 doctor/bootstrap compatibility and documentation readiness regression coverage.
- Closed the Phase 5 dependency/bootstrap contract after full lifecycle and GitHub Actions validation.

### Post-release infrastructure — Phase 5C
- Added a plan-only `nyvorel bootstrap` command for required and explicitly selected optional dependencies.
- Upgraded the dependency contract to schema 2 with explicit any/all command and package semantics.
- Added pristine-Arch bootstrap planning regression coverage proving that only read-only `pacman -Si` probes occur.

### Post-release infrastructure — Phase 5B
- Installed the canonical Arch dependency contract as managed Nyvorel state.
- Added read-only required/optional dependency preflight diagnostics to `nyvorel doctor`.
- Added structured dependency results to doctor JSON and deterministic missing-required/optional regression coverage.

### Post-release infrastructure — Phase 5A
- Added a versioned Arch dependency contract with required, optional, and test-only classifications.
- Added semantic dependency-contract validation and source-integrity enforcement.
- Documented that Phase 5A is read-only policy: it does not automatically install packages.

### Added

- `nyvorel doctor` read-only diagnostics for installation manifests, managed-file integrity, install-time materialization, runtime configuration, systemd user services, Quickshell, and Hyprland health.
- JSON, deep-scan, strict, and alternate-home diagnostic modes.
- GitHub Actions regression coverage for clean doctor state, managed-file drift, and missing-file failures.
- `nyvorel update` manifest-aware update workflow with dry-run planning, optional clean-source fast-forward, original-backup carry-forward, retired-file handling, explicit changed-file archival, and transaction rollback.
- GitHub Actions update-lifecycle coverage for dry-run safety, baseline preservation, managed-file retirement, drift refusal, forced archival, and uninstall recovery after update.

## [0.1.0] - 2026-10-06

Initial public Nyvorel source release.

### Added

- Nyvorel-branded Quickshell desktop shell.
- Hyprland integration and Nyvorel runtime configuration.
- systemd user-unit templates for shell lifecycle and style synchronization.
- Nyvorel helper commands and Fish/Kitty integrations.
- Operations Center, backup/recovery, Arch Remote, project launcher, and related shell modules.
- Portable `@HOME@` source-token policy for machine-independent publication.
- GPL-3.0 licensing, upstream provenance, third-party notices, inherited-asset documentation, and trademark notices.

### Changed

- The original Illogical Impulse/end-4 derived environment has been extensively redesigned around the Nyvorel identity, modules, workflows, services, UX, and tooling.

### Notes

- Nyvorel remains derived from `end-4/dots-hyprland`; upstream attribution and applicable third-party notices are preserved.
- v0.1.0 includes a manifest-backed installer, portable `@HOME@` materialization, safe backup recovery, and an uninstaller that protects post-install user changes.

### Post-release infrastructure — Phase 4
- Added pristine Arch Linux clean-machine installation validation in an isolated container.
- CI now proves non-root install, manifest/materialization integrity, installed CLI/doctor behavior, update dry-run immutability, and uninstall recovery without touching the runner's real home.
