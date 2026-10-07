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

## Testing

At minimum, validate the files you changed.

For Bash:

```sh
bash -n path/to/script
```

For Python, ensure modified files parse successfully and run the relevant functional checks.

For installation, lifecycle, systemd, Hyprland, or Quickshell startup changes, include the validation performed in the pull request description.
