# Nyvorel dependency contract

Nyvorel targets an existing **Arch Linux + Hyprland + Quickshell** desktop.

The canonical machine-readable contract is [`dependencies/arch.json`](dependencies/arch.json).
This document explains the policy around it.

## Classification

### Required

`required` entries are part of the supported Nyvorel core contract. They are
needed for installation, the primary Hyprland/Quickshell session, diagnostics,
or the safe update/recovery lifecycle.

A missing required dependency means the machine does not satisfy the supported
Nyvorel baseline.

The current required baseline is intentionally small:

- Bash and standard GNU userland used by lifecycle/runtime scripts;
- Python 3;
- Hyprland (`hyprctl`);
- Quickshell (`qs` or `quickshell`);
- systemd user services;
- D-Bus session environment integration;
- Git for the safe updater source contract.

Quickshell is provider-based: either the repository package name `quickshell`
or the development provider `quickshell-git` may satisfy the package hint,
while runtime detection is based on the executable.

### Optional

`optional` entries belong to bounded features such as clipboard history,
screenshots, OCR, recording, media controls, appearance processing, keyring,
fingerprint, WARP and other integrations.

A missing optional dependency must not make unrelated Nyvorel functionality
unsupported. Phase 5B will expose these as feature-level diagnostics rather
than core failures.

### Test-only

`test-only` entries are release/validation infrastructure. They are not user
runtime dependencies. For example, Podman/Docker is used by the pristine-Arch
clean-machine regression.

## Package names are hints, commands are the runtime truth

The contract keeps runtime executables separate from Arch package-provider
hints. This matters for provider variants such as Quickshell and for tools
whose package origin can differ between official repositories and the AUR.

Phase 5A does **not** install packages and does not mutate the live desktop.

## Bootstrap policy

Automatic dependency installation is deliberately disabled in schema 1.

The next phases will use this contract to add read-only preflight diagnostics,
then explicitly decide which packages Nyvorel may offer to bootstrap. No
package-manager mutation is implied by this file.
