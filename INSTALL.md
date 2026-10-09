# Installing and recovering Nyvorel

The complete setup workflow in this development checkout targets an installed
minimal Arch Linux system with working internet, a normal user account, and
working `sudo`. It installs desktop packages; it does not partition disks or
install Arch itself. This workflow has been validated on a fresh Arch VM but
is not in the immutable `v0.1.0` release or public `main` yet. The dependency
policy is in [`DEPENDENCIES.md`](DEPENDENCIES.md).

## From minimal Arch to the desktop

From a text console or interactive SSH terminal, clone this checkout and
review its complete plan:

```sh
git clone https://github.com/harkoussomar/nyvorel.git
cd nyvorel
./setup.sh --plan
```

The public clone will offer this workflow once the development commits are
published. Until then, the commands below describe this local candidate only.
Use a terminal with a PTY; SSH users can connect with `ssh -t`. The package
transaction is interactive even with `--yes` so you can review pacman's full
system upgrade and package selection:

```sh
./setup.sh --install --yes
```

For Zed, Kate, Ark, btop and extra appearance tools, choose
`--with-recommended`. For English OCR choose `--with-ocr-english`; for screen
recording choose `--with-recording`. Review `./setup.sh --help` for GPU-specific
Zed Vulkan selection, NetworkManager activation, local wheelhouse, and recovery
options. The default uses official Arch repositories and does not invoke an
AUR helper, enable a VPN, or expose remote services. Existing network
management stays in place unless `--enable-networkmanager` is selected.

The setup installs Hyprland, Quickshell 0.3.2 or newer, Qt modules and icon
fonts, portals, a Polkit agent, Kitty, Fish, Firefox, Dolphin, PipeWire,
WirePlumber, launcher, notifications, clipboard and screenshot tools. The
recommended group adds applications and utility tools; OCR and recording are
opt-in. Pacman may pull additional dependencies; review its transaction before
accepting. It then runs the backed-up user-file installer, creates an isolated
color environment, and seeds the first wallpaper and palette. The color
environment fetches a version-pinned binary wheel from PyPI unless
`--wheelhouse PATH` points to a reviewed local wheel.

At the next local text login run:

```sh
~/.local/bin/nyvorel session
```

This explicitly starts Hyprland with `~/.config/hypr/hyprland.conf`, then
activates Nyvorel's user services and Quickshell. The installed desktop entry
can be selected from a display manager if one is configured. The explicit path
works even when a fresh Arch login has not added `~/.local/bin` to `PATH`.
Before entering the desktop, `~/.local/bin/nyvorel first-run --check`,
`~/.local/bin/nyvorel session --check`, and
`~/.local/bin/nyvorel doctor --no-session` help diagnose setup.
After login, use `nyvorel doctor` and `nyvorel welcome`.

Hyprland 0.56 accepted the explicit `.conf` session entry in the clean VM;
the compositor warns that `.conf` support will be removed in 0.57. A future
Hyprland update needs a compatible Nyvorel configuration before that version
can be claimed as supported. A software-rendered QEMU VM may show high CPU use
and Quickshell shared-memory rendering; physical GPU behavior must be checked
on the target machine. Brightness, Bluetooth, fingerprints, battery controls,
recording and optional content-aware screenshot hints depend on the relevant
hardware or optional packages and are not guaranteed by the core setup.

If setup stops after installing packages, rerun `./setup.sh --install --yes
--resume`. It refuses existing managed-file replacements by default; review
the dry-run conflict list and use `--replace-existing` only when you intend to
back up and replace those files. Do not use setup on an existing Nyvorel
desktop; use `nyvorel update --dry-run` followed by `nyvorel update --yes`.

## Lower-level user-file installer

`./install.sh` is for an already provisioned desktop and for package workflows.
It does not install Arch packages or initialize the full first-run state. Its
read-only preview is `./install.sh --dry-run`; its mutation is
`./install.sh --yes`. The installer:

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

The lower-level installer does not activate services unless requested.

## First-run experience

After installing:

```sh
nyvorel welcome --no-session  # safe diagnostic even without a graphical session
nyvorel welcome               # live Hyprland/Quickshell check
nyvorel doctor                # complete diagnostic detail
```

`nyvorel welcome` reports missing required vs optional dependencies, displays
focused recovery guidance from Doctor, and suggests a read-only bootstrap plan
when required packages are missing. For scripts use `nyvorel welcome --json`.
For isolated test homes pass `--home PATH --no-session`.

These onboarding commands are read-only. The complete setup's first session
activates services. Existing-session or package users can activate explicitly
with `nyvorel activate --session` or the supported package workflow.

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

The stable/development channel contract is documented in
[`RELEASES.md`](RELEASES.md).

Remote update resolution is channel-aware. Stable is the default: `--fetch`
queries GitHub Releases, ignores draft/prerelease entries, chooses the highest
strict semantic-version tag, and evaluates that tag from an isolated temporary
checkout.

```sh
nyvorel update --fetch --dry-run
nyvorel update --fetch --yes
```

Development/main requires explicit opt-in:

```sh
nyvorel update --fetch --channel development --dry-run
nyvorel update --fetch --channel development --yes
```

`--source PATH` remains a separate explicit local-source mode and cannot be
combined with `--fetch`.

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

## Maintainer release preflight

The installer accepts strict semantic `MAJOR.MINOR.PATCH` versions rather than
being tied to `0.1.0`. Maintainers can test a prepared release candidate with:

```sh
scripts/release/preflight.sh --version 0.1.1 --require-clean
```

This is validation only; it does not create tags, push, or publish releases.

## Arch package workflow

Phase 7B provides a real local Arch package definition.

```sh
makepkg --cleanbuild
sudo pacman -U ./nyvorel-*.pkg.tar.zst
```

Pacman installs only package-owned `/usr` content. It does not write to your
home directory.

Review and materialize the user configuration explicitly:

```sh
nyvorel install --dry-run
nyvorel install --yes
```

After a package upgrade:

```sh
nyvorel update --dry-run
nyvorel update --yes
```

Existing source-clone installations require explicit migration:

```sh
/usr/bin/nyvorel install --migrate-source-clone --dry-run
/usr/bin/nyvorel install --migrate-source-clone --yes
```

Package removal preserves user configuration, installation state, and backups.

## Lower-level install and activate

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
