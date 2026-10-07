# Contributing to Nyvorel

Thanks for improving Nyvorel.

## Development workflow

1. Fork or clone the repository.
2. Create a focused branch from `main`.
3. Keep changes scoped and avoid unrelated formatting churn.
4. Validate affected Bash and Python sources before opening a pull request.
5. Explain user-visible behavior changes and migration impact in the pull request.

## Source boundaries

Nyvorel contains upstream-derived and third-party material. Do not remove or weaken:

- `LICENSE`
- `NOTICE.md`
- `PROVENANCE.md`
- `THIRD_PARTY_NOTICES.md`
- `INHERITED_ASSETS.md`
- `TRADEMARKS.md`
- component license files under `LICENSES/`

New third-party assets or copied code must include enough provenance and licensing information to permit redistribution.

## Portability

Public source must not contain a maintainer-specific home path. Files that require an absolute target-user home directory use the literal `@HOME@` token and are rendered by the installer.

Do not commit local backup trees, generated runtime state, secrets, credentials, tokens, or user data.

## Release-sensitive changes

`main` is the development line. Stable releases are immutable semantic-version
tags/releases governed by [`RELEASES.md`](RELEASES.md) and
`release/channel-policy.json`.

Do not move or recreate an existing release tag. Changes to updater channel
resolution, VERSION/tag behavior, or release automation must preserve the
stable-vs-development distinction and include the relevant release-policy
regression coverage.

Maintainer publication is plan-first:

```sh
scripts/release/publish.sh --version 0.1.1
```

Actual publication requires `--publish --yes`. Do not bypass the publisher with
a manual tag move or release retarget: the tool requires exact `origin/main`,
main CI, immutable tag identity, tag CI, and only then a stable GitHub Release.

## Packaging-sensitive changes

Arch packaging is governed by [`PACKAGING.md`](PACKAGING.md) and
`packaging/ownership-contract.json`.

Do not introduce package scripts that write into a real user's home directory,
start user services for arbitrary users, or make package-owned `/usr` content
mutable through Nyvorel's remote updater.

Package mode must preserve the split-ownership boundary:

- pacman owns immutable `/usr` payload;
- Nyvorel owns per-user materialization, manifests, backups, and state;
- `/usr/bin/nyvorel` is the package-mode public CLI;
- package-provided user units belong under `/usr/lib/systemd/user`;
- package upgrades/removal must not silently rewrite or delete user data.

Phase 7B changes must advance the machine-readable contract and include
packaging regression coverage.

## Testing

At minimum, validate the files you changed.

For Bash:

```sh
bash -n path/to/script
```

For Python, ensure modified files parse successfully and run the relevant functional checks.

For installation, lifecycle, systemd, Hyprland, or Quickshell startup changes, include the validation performed in the pull request description.
