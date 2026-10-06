# Portability work remaining

This staging tree is intentionally separate from the live desktop.

## Already handled

- Live `~/.config/nyvorel` user/runtime state is excluded.
- Hidden maintainer backup/history trees are excluded.
- `installed_listfile` is excluded.
- The legacy nested Quickshell configuration tree is excluded.
- systemd enablement symlinks are excluded.
- Nyvorel systemd units are staged as `.in` templates.
- Exact maintainer-home references in those systemd templates are rendered as
  `@HOME@`.
- Only Nyvorel-named local helpers/integration files are selected.

## Still requiring review

- Hyprland hardware-specific defaults such as monitor/workspace configuration.
- Any remaining exact maintainer paths inside source code.
- Machine/network defaults in Arch Remote / Operations Center.
- Third-party asset provenance and per-component licenses.
- Installer rendering of `systemd/*.in` templates.
- Final dependency manifest and supported-version policy.

## Install-time path token

`@HOME@` is the public-source install-time token for the target user's home directory. The installer must render this token before installing the affected files. The live maintainer configuration is never modified by this staging process.
