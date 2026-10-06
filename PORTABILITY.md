# Portability

Nyvorel's public source is structured so it can be installed for a target user
without embedding the maintainer's home directory or local runtime state.

## Public-source boundaries

The repository intentionally excludes:

- live `~/.config/nyvorel` runtime/user state;
- maintainer backup and history trees;
- generated package/file inventory such as `installed_listfile`;
- legacy nested Quickshell configuration copies;
- systemd enablement symlinks;
- machine-local secrets, credentials, and user data.

Only Nyvorel source, portable templates, helpers, integrations, documentation,
and redistributable project/third-party assets belong in the release tree.

## Install-time home token

Files that require an absolute target-user home path use the literal token:

```text
@HOME@
```

For v0.1.0 there are 29 occurrences across 10 source template files.

`install.sh` replaces every `@HOME@` token with the selected target home while
copying files into the installed tree. The public source files themselves stay
unchanged.

The release verification suite confirms that:

- all 29 source tokens remain present in the portable repository;
- installed sandbox copies contain zero unresolved `@HOME@` tokens;
- systemd `.in` templates are materialized to their runtime filenames.

## systemd templates

Nyvorel publishes systemd user units as portable source templates under
`systemd/`.

At install time:

- `.service.in` becomes `.service`;
- `.path.in` becomes `.path`;
- drop-in `.conf.in` files become `.conf`;
- target-user home tokens are rendered before installation.

The resulting units are installed under:

```text
~/.config/systemd/user/
```

## Installation safety

The installer creates a timestamped manifest and backs up every managed file
that existed before installation.

The uninstaller uses that manifest to:

- restore pre-install files exactly;
- remove files created by Nyvorel;
- refuse to overwrite post-install user edits by default;
- archive changed files before forced recovery.

Runtime/user state under `~/.config/nyvorel` is intentionally retained by the
uninstaller.

See `INSTALL.md` for the complete install and recovery workflow.

## Environment-specific configuration

Nyvorel targets Arch Linux, Hyprland, and Quickshell. Some desktop settings are
naturally environment-specific, especially monitor/workspace configuration,
hardware-related defaults, and integrations that depend on optional
applications.

Users should review those settings for their own machine after installation.
They are configuration choices, not publication-portability blockers.
