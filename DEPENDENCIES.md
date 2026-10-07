# Nyvorel dependency contract

Nyvorel targets an existing **Arch Linux + Hyprland + Quickshell** desktop.

The canonical machine-readable contract is
[`dependencies/arch.json`](dependencies/arch.json). This document explains the
policy around it.

## Classification

### Required

`required` entries are part of the supported Nyvorel core contract. They are
needed for installation, the primary Hyprland/Quickshell session, diagnostics,
or the safe update/recovery lifecycle.

A missing required dependency means the machine does not satisfy the supported
Nyvorel baseline.

The core includes Bash/GNU userland, Python 3, Hyprland, Quickshell, systemd
user services, D-Bus session integration, and Git for the safe updater.

### Optional

`optional` entries belong to bounded features such as clipboard history,
screenshots, OCR, recording, media controls, appearance processing, keyring,
fingerprint, WARP, and other integrations.

A missing optional dependency does not make unrelated Nyvorel functionality
unsupported. `nyvorel doctor` reports it as a feature-level warning.

### Test-only

`test-only` entries are release/validation infrastructure. They are not user
runtime dependencies. Podman/Docker, for example, is used by pristine-Arch
regressions.

## Command and package group semantics

Schema 2 distinguishes alternatives from sets that must all exist:

- `commands_any_of`: one executable is enough, such as `qs` or `quickshell`;
- `commands_all_of`: every listed executable is required by that dependency
  group, such as both `grim` and `slurp`;
- `arch_packages_any_of`: provider alternatives; the planner selects the first
  package visible through the configured pacman repositories;
- `arch_packages_all_of`: every listed package is required for that group.

Runtime command detection remains the truth. Package names are planning hints.

## Bootstrap policy

Nyvorel bootstrap is deliberately **plan-only**.

```sh
nyvorel bootstrap
nyvorel bootstrap --json
nyvorel bootstrap --optional screenshots
nyvorel bootstrap --optional screenshots --optional ocr --json
```

The default scope contains only missing required dependencies. Optional
dependencies are included only when their exact contract IDs are requested.

The planner may perform the read-only repository probe `pacman -Si` to
distinguish packages available through the user's configured pacman
repositories from providers that need a manual decision.

Nyvorel bootstrap does **not**:

- install or remove packages;
- run `pacman -S`, `pacman -Sy`, or `pacman -Syu`;
- refresh the pacman sync database;
- invoke AUR helpers such as `yay` or `paru`;
- modify Nyvorel configuration or the desktop session.

The output is a reviewable package plan. Install reviewed packages through the
machine's normal Arch full-upgrade/package-management workflow, then rerun
`nyvorel doctor --dependencies`.

Automatic package installation remains disabled.
