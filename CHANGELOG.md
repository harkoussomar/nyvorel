# Changelog

All notable Nyvorel changes intended for public releases are recorded here.

## [Unreleased]

### Added

- `nyvorel doctor` read-only diagnostics for installation manifests, managed-file integrity, install-time materialization, runtime configuration, systemd user services, Quickshell, and Hyprland health.
- JSON, deep-scan, strict, and alternate-home diagnostic modes.
- GitHub Actions regression coverage for clean doctor state, managed-file drift, and missing-file failures.

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
