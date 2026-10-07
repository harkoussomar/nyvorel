# Installing and recovering Nyvorel

Nyvorel v0.1.0 targets an existing **Arch Linux + Hyprland + Quickshell**
desktop. The supported required/optional/test-only dependency policy is defined
in [`DEPENDENCIES.md`](DEPENDENCIES.md) and `dependencies/arch.json`.

The installer does not currently bootstrap Arch Linux or automatically install
dependency packages.

## Preview

```sh
./install.sh --dry-run
```

No files are changed.

## Install

```sh
./install.sh --yes
```

The installer:

- installs Quickshell source to `~/.config/quickshell/nyvorel`;
- merges the published Hyprland tree into `~/.config/hypr`;
- installs `nyvorel-*` helpers into `~/.local/bin`;
- installs Fish and Kitty integration files;
- renders systemd `.in` templates into `~/.config/systemd/user`;
- installs the Nyvorel application icon;
- replaces every public-source `@HOME@` token with the target user's real home;
- backs up every existing managed file before replacement;
- writes a machine-readable manifest under
  `~/.local/state/nyvorel/installations/`.

The installer does not activate services unless requested.

## Verify the installation

After installation, run the read-only diagnostic command:

```sh
nyvorel doctor
```

For a complete manifest checksum pass:

```sh
nyvorel doctor --deep
```

Machine-readable output is available with `nyvorel doctor --json`. The doctor
reports installation state, managed-file drift, unresolved install templates,
runtime configuration health, systemd user-service state, Quickshell
availability, Hyprland configuration errors, and the installed dependency
contract without changing the system.

Normal live-session diagnostics also probe required and optional runtime
dependencies. For a dependency-only/preflight-style check outside the live
session, use:

```sh
nyvorel doctor --no-session --dependencies
nyvorel doctor --no-session --dependencies --json
```

Missing required dependency groups are failures. Missing optional dependency
groups are warnings and identify only feature-level capabilities; they do not
make unrelated Nyvorel functionality unsupported. Package names are reported
as Arch provider hints. The doctor never installs packages.

## Plan missing Arch dependencies

Nyvorel provides a read-only bootstrap planner:

```sh
nyvorel bootstrap
nyvorel bootstrap --json
nyvorel bootstrap --list-optional
nyvorel bootstrap --list-optional --json
nyvorel bootstrap --optional screenshots
```

The default plan covers missing required dependency groups only. Optional
groups are opt-in by exact dependency ID. `--list-optional` is a metadata-only
catalog and performs no pacman probe, so users can discover feature IDs before
planning. Normal planning uses `pacman -Si` only to probe configured
repositories. It never installs packages, refreshes sync databases, or invokes
`yay`/`paru`. Review the plan and use the machine's normal Arch
full-upgrade/package workflow for any installation.

## Update an existing installation

Preview the update first:

```sh
nyvorel update --dry-run
```

If the source checkout recorded in the current manifest is a clean `main`
checkout, Nyvorel can fast-forward it before planning:

```sh
nyvorel update --fetch --dry-run
nyvorel update --fetch --yes
```

Use `--activate` to reload/restart the Nyvorel user services after a successful
update.

The updater verifies the current manifest before mutation. Changed or missing
managed files cause a refusal by default. `--force-changed` is explicit: edited
files are archived under the new update state before replacement.

Every successful update creates another timestamped state directory while
carrying forward the **original pre-Nyvorel backups**. This keeps normal
`uninstall.sh` recovery pointed at the true pre-Nyvorel baseline even after
multiple updates.

Files removed from a newer Nyvorel source are retired safely: the updater
restores the original pre-Nyvorel file when one existed, otherwise it removes
the file that Nyvorel originally created.

## Install and activate

```sh
./install.sh --yes --activate
```

Activation reloads the systemd user manager, enables the Nyvorel style-sync
path units and Operations Center monitor, imports the current Wayland/Hyprland
session environment, and restarts `nyvorel-quickshell.service`.

## Uninstall and recover

```sh
./uninstall.sh --yes
```

The recovery tool reads `~/.local/state/nyvorel/current-install`, verifies that
managed files still match the versions installed by Nyvorel, restores every
file that existed before installation, and removes files that Nyvorel created.

It intentionally keeps:

```text
~/.config/nyvorel
~/.local/state/nyvorel/installations/
```

so user/runtime state and recovery history remain available.

## Protecting post-install edits

If an installed file was edited or removed after installation, normal uninstall
stops **before making filesystem changes**.

Review first:

```sh
./uninstall.sh --dry-run
```

To explicitly recover anyway:

```sh
./uninstall.sh --yes --force-changed
```

Existing changed files are archived beneath the installation state in
`uninstall-conflicts/<timestamp>/` before they are restored or removed.

## Testing another home

The installer and uninstaller support an alternate target home:

```sh
./install.sh \
  --target-home /tmp/nyvorel-test-home \
  --yes \
  --no-activate

./uninstall.sh \
  --target-home /tmp/nyvorel-test-home \
  --yes \
  --no-deactivate
```

This is how the v0.1.0 release verification tests installation/recovery without
touching the normal user's live configuration.

## Installation state

Each install creates:

```text
~/.local/state/nyvorel/installations/YYYYMMDD-HHMMSS/
```

with:

- `manifest.json` — exact destinations, source mapping, installed checksums,
  pre-existing status, and lifecycle status;
- `backup/` — original versions of replaced files;
- optional `uninstall-conflicts/` — post-install user changes archived during
  forced recovery.

The source tree itself remains portable: `@HOME@` is rendered only in installed
copies.

## Clean-machine validation

Nyvorel CI includes a pristine Arch Linux container regression. It creates a brand-new non-root home, installs with service activation disabled, validates the installation manifest and materialized files, runs the installed CLI and Doctor in `--no-session` mode, proves update/uninstall dry-runs are non-mutating, and exercises recovery.

Run the same validation locally with Podman or Docker:

```bash
bash scripts/ci/test-clean-machine.sh
```

The test is isolated from the caller's real home and does not activate Nyvorel services.
