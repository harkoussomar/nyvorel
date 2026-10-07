# Installing and recovering Nyvorel

Nyvorel v0.1.0 targets an existing **Arch Linux + Hyprland + Quickshell**
desktop. It does not bootstrap Arch Linux or install every optional application
used by individual modules.

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
availability, and Hyprland configuration errors without changing the system.

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
