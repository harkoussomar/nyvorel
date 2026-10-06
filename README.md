# Nyvorel Shell

Nyvorel is a custom desktop shell built around **Hyprland** and **Quickshell**.
It began as a derivative of `end-4/dots-hyprland` / Illogical Impulse and has
since been extensively redesigned with its own identity, modules, workflows,
services, UX, lifecycle management, and tooling.

**Current release target: v0.1.0**

> Nyvorel is an independent community project. It is not affiliated with or
> endorsed by third-party projects and services represented by inherited
> interface assets.

## What is included

- Quickshell-based Nyvorel desktop shell and modules.
- Hyprland configuration and shell integration.
- systemd user units for shell lifecycle and style synchronization.
- Nyvorel helper commands.
- Fish and Kitty integrations.
- Operations Center, backup/recovery, Arch Remote, project launcher, appearance,
  media, notification, session, and utility workflows.
- Portable public-source templates using the `@HOME@` install-time token.

## Requirements

Nyvorel v0.1.0 targets an **Arch Linux + Hyprland + Quickshell** environment.

Core requirements:

- Hyprland
- Quickshell (`qs`)
- systemd user services
- Python 3
- standard GNU/Linux userland tools

Nyvorel also integrates with tools used by the upstream shell ecosystem and
with optional applications such as Kitty, Fish, btop, Dolphin, Fuzzel, Zed,
and related Wayland utilities. Features for applications that are not
installed may remain unused.

v0.1.0 is a desktop-shell release, not a complete Arch Linux distribution
bootstrapper. A compatible Wayland/Hyprland environment is expected.

## Installation

Preview the installation plan:

```sh
./install.sh --dry-run
```

Install Nyvorel while backing up existing managed files:

```sh
./install.sh --yes
```

Install and activate the Nyvorel user services in the current
Hyprland/Wayland session:

```sh
./install.sh --yes --activate
```

The installer renders all public-source `@HOME@` tokens with the target user's
actual home path, installs the Nyvorel systemd user units, and records a
timestamped backup/manifest under `~/.local/state/nyvorel/installations/`.

## Uninstall / recovery

Restore every pre-install file and remove files created by Nyvorel:

```sh
./uninstall.sh --yes
```

The uninstaller verifies installed-file checksums before changing anything. If
a managed file was edited after installation it refuses to overwrite that
change. Explicit `--force-changed` archives those changed files inside the
installation state before recovery.

Nyvorel runtime/user state under `~/.config/nyvorel` is intentionally retained.

See `INSTALL.md` for the complete install, backup, and recovery model.


## Source layout

- `quickshell/` — Nyvorel Quickshell source.
- `hypr/` — Hyprland integration and configuration.
- `systemd/` — portable systemd user-unit templates.
- `bin/` — Nyvorel helper executables.
- `integrations/` — shell/application integrations.
- `assets/` — Nyvorel project assets.
- `runtime-config/` — documentation for runtime/user-state boundaries.
- `LICENSES/` — component and third-party license evidence.

## Portability

The public repository contains no maintainer-specific home path.

Where an absolute target-user home directory is required, source templates use:

```text
@HOME@
```

The installer replaces that token with the target user's actual home directory.

See `PORTABILITY.md` for the source portability model.

## Licensing and provenance

Nyvorel is distributed under **GPL-3.0** as a substantially modified derivative
of `end-4/dots-hyprland`.

Relevant documentation:

- `LICENSE`
- `NOTICE.md`
- `PROVENANCE.md`
- `THIRD_PARTY_NOTICES.md`
- `INHERITED_ASSETS.md`
- `TRADEMARKS.md`
- `LICENSES/`

Third-party names, logos, and marks remain the property of their respective
owners and are not claimed as Nyvorel-owned artwork.

## Contributing

See `CONTRIBUTING.md`.

## Version

The canonical source version is stored in `VERSION`.
