# Nyvorel Arch Packaging Contract

Phase 7A locks the ownership boundary for future Arch packaging.

This document is an architecture contract, not a statement that Nyvorel
already ships a `PKGBUILD`. Package implementation begins in Phase 7B.

The machine-readable source of truth is:

```text
packaging/ownership-contract.json
```

## Core rule

Nyvorel uses **split ownership**:

```text
pacman / Arch package
        |
        +-- immutable program + distribution payload under /usr
        |
        v
Nyvorel per-user lifecycle
        |
        +-- materialization
        +-- backups
        +-- manifests
        +-- runtime configuration/state
        +-- service activation
        |
        v
      $HOME
```

The package manager owns immutable distribution files. Nyvorel owns the
transaction that materializes and protects user configuration.

A package build, package installation, package upgrade, or package-removal hook
must not silently edit a real user's home directory.

## Package-owned paths

Phase 7B must converge on these ownership roots:

| Purpose | Package-owned path |
| --- | --- |
| Public CLI | `/usr/bin/nyvorel` |
| Internal executable helpers | `/usr/lib/nyvorel/bin/` |
| Immutable Nyvorel payload/templates | `/usr/share/nyvorel/` |
| Arch dependency contract | `/usr/share/nyvorel/dependencies/arch.json` |
| Package-provided systemd user units | `/usr/lib/systemd/user/` |
| Application icon | `/usr/share/icons/hicolor/scalable/apps/nyvorel.svg` |
| Documentation | `/usr/share/doc/nyvorel/` |
| Licenses | `/usr/share/licenses/nyvorel/` |

These paths follow Arch's package-directory guidance: application binaries
belong under `/usr/bin`, package-specific executable support files under
`/usr/lib/<package>`, application data under `/usr/share/<package>`, and
licenses/documentation under their standard `/usr/share` roots.

Arch package guideline:
https://wiki.archlinux.org/title/Arch_package_guidelines

## User-owned paths

The package must not claim ownership of Nyvorel's mutable per-user lifecycle:

- `~/.config/quickshell/nyvorel`
- the Nyvorel-managed materialized content under `~/.config/hypr`
- `~/.config/fish`
- `~/.config/kitty`
- `~/.config/nyvorel`
- `~/.local/state/nyvorel`
- `~/.local/state/quickshell`
- installation manifests, original backups, and changed-file archives

These remain governed by Nyvorel's manifest-backed, backup-first lifecycle.

## Public CLI ownership

The audit found that the current source-clone installer places Nyvorel helpers
under `~/.local/bin`, including the public `nyvorel` launcher.

Package mode must not also create a second independently owned launcher in
`~/.local/bin`.

The package-mode contract is:

```text
/usr/bin/nyvorel
```

is the single authoritative public CLI.

Internal helpers should converge on:

```text
/usr/lib/nyvorel/bin/
```

Phase 7B must migrate package-mode references atomically so package-owned
helpers cannot be shadowed by stale user-installed helper copies.

Source-clone mode remains supported during the migration, but the future
installation manifest must distinguish source-clone and package installations
explicitly.

## systemd user-unit ownership

Package-provided user unit definitions belong in:

```text
/usr/lib/systemd/user/
```

The user's own high-precedence unit area remains:

```text
~/.config/systemd/user/
```

Nyvorel package mode must not independently install the same unit definition
into both locations.

The package owns the unit definition. The user owns whether a unit is enabled
or started for that user's session.

Where package-owned units need the user's home directory, use systemd-safe
runtime mechanisms such as `%h` rather than package-time `@HOME@`
materialization.

Arch systemd user-unit reference:
https://wiki.archlinux.org/title/Systemd/User

## `@HOME@` boundary

The Phase 7A audit confirmed the current installer materializes 29 `@HOME@`
occurrences across 10 managed template files.

That contract is valid for the existing source-clone user installer, but
package files cannot be rendered differently for each user during `makepkg` or
package installation.

Therefore:

- immutable package files must be user-independent;
- package-owned systemd units must use runtime-safe specifiers where possible;
- remaining user-specific materialization stays in the Nyvorel user lifecycle;
- Phase 7B must not weaken the existing portability regression merely to make a
  `PKGBUILD` pass.

## Package update vs user materialization

Packaging introduces two separate update layers.

### 1. Package payload update

Pacman/AUR owns updates to files under `/usr`.

Nyvorel's GitHub stable/development updater must never mutate package-owned
`/usr` files behind pacman's back.

### 2. User materialization update

After a package payload changes, Nyvorel may preview and apply corresponding
user-home changes through the existing manifest transaction:

- preserve the original pre-Nyvorel backup baseline;
- detect user edits before mutation;
- archive changed files only when explicitly requested;
- write a fresh installation state;
- roll back safely on transaction failure.

A package upgrade itself must not silently rewrite the user's configuration.

The exact package-mode command UX is intentionally left to Phase 7B; Phase 7A
locks the ownership rule, not a premature command name.

## Package hooks

A future `.install` hook may print concise post-install guidance.

It must not:

- write into a real user's home directory;
- run Nyvorel user materialization;
- enable/start user services for arbitrary users;
- rewrite user configuration;
- delete user config, state, manifests, backups, or archives.

Package removal removes package-owned `/usr` content only. User lifecycle data
survives unless the user explicitly invokes Nyvorel recovery/removal semantics.

## Dependency mapping

`dependencies/arch.json` remains Nyvorel's semantic dependency source of truth.

Phase 7B will map it into packaging roles:

- required runtime providers -> `depends` when package names are resolved;
- optional feature providers -> `optdepends`;
- build-only providers -> `makedepends`;
- test-only providers -> `checkdepends` or CI-only;
- AUR-only providers must not be represented as guaranteed repository
  dependencies;
- neither the package nor `nyvorel bootstrap` invokes an AUR helper
  automatically.

## Source-clone transition

Phase 7B must keep the current source-clone install path working while package
mode is introduced.

The transition must explicitly solve:

1. `~/.local/bin/nyvorel` versus `/usr/bin/nyvorel`;
2. package helper path migration;
3. `~/.config/systemd/user` versus `/usr/lib/systemd/user`;
4. package-aware payload/source discovery;
5. source-clone -> package conversion;
6. package upgrade without automatic home mutation;
7. package removal while preserving user state/backups.

No hidden migration is allowed.

## Phase 7B acceptance gates

Before Nyvorel can claim a working Arch package, Phase 7B must prove:

1. an exact package filesystem map;
2. package-safe helper paths;
3. package-safe systemd user units;
4. package-aware source discovery;
5. explicit source-clone/package migration behavior;
6. zero automatic `$HOME` mutation on package upgrade;
7. user state preservation on package removal;
8. clean `makepkg` package creation;
9. clean package installation in isolated Arch;
10. source-clone regression compatibility.

Phase 7A is complete when this contract and its machine-readable validator are
green. It does **not** create or publish a package.
