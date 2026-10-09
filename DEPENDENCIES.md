# Nyvorel dependency contract

The complete `./setup.sh` workflow targets a minimal Arch Linux installation
with internet and sudo and installs Hyprland, Quickshell, and core desktop
packages. The lower-level `./install.sh` only materializes user files and
expects the runtime packages to be present already.

The canonical machine-readable contract is
[`dependencies/arch.json`](dependencies/arch.json). This document explains the
policy around it. The contract is a diagnostic floor, not the whole fresh
desktop package list; `setup.sh --plan` shows that list.

## Classification

### Required

`required` entries are part of the supported Nyvorel core contract. They are
needed for installation, the primary Hyprland/Quickshell session, diagnostics,
or the safe update/recovery lifecycle.

A missing required dependency means the machine does not satisfy the supported
Nyvorel baseline.

The core includes Bash/GNU userland, Python 3, Hyprland, Quickshell, systemd
user services, D-Bus session integration, and Git for the safe updater.
Settings also requires the Qt Positioning and Qt 5 compatibility QML modules
and the Material Symbols Rounded font. Appearance scripts require Matugen,
jq, and bc. Detecting these assets does not establish that the complete QML
application or color-generation environment is functional.

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
- `files_any_of` / `files_all_of`: installed runtime assets, using absolute
  paths instead of executable lookup. Qt QML modules and fonts are not commands;
  GeoClue supplies a daemon outside PATH, a session agent, and a service unit.
  File detection verifies installation only, not service activation, permissions,
  font rendering, or a successful location request;
- `arch_packages_any_of`: provider alternatives; the planner selects the first
  package visible through the configured pacman repositories;
- `arch_packages_all_of`: every listed package is required for that group.

Each entry has exactly one command or file selector. Runtime asset detection
remains the evidence for dependency presence. Package names are planning hints.

The source installer includes Nyvorel's Matugen templates. The complete setup
installs official `python-pillow` and `python-pip`, then explicitly invokes
`nyvorel color-env --install --yes` for a binary-only, version-pinned
`materialyoucolor` wheel in an isolated virtual environment. `--wheelhouse
PATH` supports a reviewed local wheel instead of PyPI. The lower-level
`./install.sh --yes` and package installation do not run pip. A dependency
PASS alone is not a desktop readiness certification.

## Bootstrap policy

Nyvorel bootstrap is deliberately **plan-only**.

```sh
nyvorel bootstrap
nyvorel bootstrap --json
nyvorel bootstrap --list-optional
nyvorel bootstrap --list-optional --json
nyvorel bootstrap --optional screenshots
nyvorel bootstrap --optional screenshots --optional ocr --json
```

The default scope contains only missing required dependencies. Optional
dependencies are included only when their exact contract IDs are requested.
Use `nyvorel bootstrap --list-optional` to discover every supported optional
ID, its feature description, command semantics, and Arch package hints. Catalog
mode is metadata-only: it does not require an Arch session and does not probe
pacman.

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

This last rule applies to `nyvorel bootstrap`; `./setup.sh --install --yes`
does install the selected official packages after a reviewable plan.
