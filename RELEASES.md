# Nyvorel release and update channels

This document defines Nyvorel's release/update policy. The machine-readable
source of truth is [`release/channel-policy.json`](release/channel-policy.json).

Phase 6B implements channel-aware remote resolution in `nyvorel update`.
Stable is now the default for `--fetch`; development/main requires explicit
opt-in.

## Stable

**Stable is the user-default remote update channel.**

A stable Nyvorel version is identified by one immutable semantic-version tag
and one non-draft, non-prerelease GitHub Release:

```text
VERSION 0.1.1
tag     v0.1.1
release Nyvorel v0.1.1
```

For stable updates:

- the tag must be exactly `v<VERSION>`;
- a released tag never moves;
- one stable version maps to one release commit;
- a different commit carrying the same `VERSION` is invalid;
- downgrades are refused by default;
- the release commit must have the complete CI suite green.

Stable state is resolved dynamically from GitHub Releases: the highest strict
semantic-version release that is neither draft nor prerelease is the current
stable release. Source policy therefore does not hard-code a mutable "current
stable" value.

`v0.1.0` remains recorded as an immutable historical release anchor and is
never moved, recreated, or retargeted.

## Development

Development is explicitly opt-in and tracks `origin/main`.

`main` is mutable and may contain multiple commits with the same `VERSION`
between releases. Therefore a same-version/different-commit update is valid on
the development channel but is not valid on stable.

Development selection is explicit:

```sh
nyvorel update --fetch --channel development --dry-run
nyvorel update --fetch --channel development --yes
```

A plain `--fetch` no longer tracks `main`; it resolves the highest strict
semantic-version GitHub Release that is neither draft nor prerelease, then
checks out that immutable tag in an isolated temporary clone.

## Explicit source

`nyvorel update --source PATH` is a direct source-tree override, not a remote
release channel.

It keeps the existing safety model:

- dirty Git sources are refused unless explicitly allowed;
- version downgrades are refused unless explicitly allowed;
- managed-file drift is refused unless explicitly forced and archived;
- transaction rollback and original pre-Nyvorel backup continuity remain
  mandatory.

## Same-version commit policy

The channel determines whether a same-version commit change is valid:

| Source | Same VERSION, different commit |
| --- | --- |
| Stable | Refuse |
| Development (`main`) | Allow |
| Explicit local source | Allow because the source was explicitly selected |

This distinction allows `main` to advance through unreleased commits without
turning a mutable development commit into a stable release identity.

## v0.1.x maintenance policy

`0.1.x` is the current maintenance line. Until a later minor line exists,
patch releases such as `0.1.1` are cut from a reviewed, clean `main` commit.

A `0.1.x` release requires:

1. `VERSION` bumped to the intended patch version;
2. an exact `## [<version>] - YYYY-MM-DD` changelog section;
3. release preflight passing on the exact release commit;
4. full GitHub Actions success;
5. an immutable `v<version>` tag;
6. a non-draft, non-prerelease GitHub Release for that tag.

There is no separate `release/0.1` branch requirement yet. When multiple minor
lines need simultaneous maintenance, a branch such as `release/0.1` may be
introduced explicitly; this policy does not create it automatically.

## Release candidate preflight

Before creating a new `v0.1.x` tag, prepare the candidate VERSION and exact
CHANGELOG release heading, then run:

```sh
scripts/release/preflight.sh --version 0.1.1 --require-clean
```

After creating the intended tag locally, require that it peels to the exact
candidate HEAD:

```sh
scripts/release/preflight.sh --version 0.1.1 --require-clean --require-tag
```

Preflight is read-only. It never creates a tag, pushes, or publishes a GitHub
Release. Phase 6C2 owns explicit publication tooling.

## Release publication

Publication is maintainer-triggered and never automatic.

First inspect the prepared candidate without mutation:

```sh
scripts/release/publish.sh --version 0.1.1
```

Actual publication requires both explicit confirmation flags:

```sh
scripts/release/publish.sh --version 0.1.1 --publish --yes
```

The publisher requires a clean `main` checkout whose HEAD exactly matches
`origin/main`. It verifies the complete six-job `CI` workflow on that exact
commit before creating an annotated release tag.

After the tag is pushed, the publisher waits for a second complete `CI` run for
the same tagged commit. The GitHub Release is created only after tag CI is
green, and its notes are extracted from the matching CHANGELOG release section.

Existing tags are never moved. If publication stops after a tag is pushed,
rerunning the same command is resumable only when the existing tag still peels
to the exact candidate commit. If code must change after an immutable tag has
been published, prepare a new semantic version rather than retargeting the old
tag.

## Release invariants

A future stable release is invalid if any of these disagree:

```text
VERSION
release tag
CHANGELOG release heading
release commit
GitHub Release
```

Existing published tags and releases are historical records. They are never
moved or silently retargeted to make a new preflight pass.

## Implementation phases

Phase 6 is intentionally split:

- **6A** — define this contract — **closed**;
- **6B** — implement stable vs development resolution in `nyvorel update` — **closed**;
- **6C1** — generic installer VERSION support + deterministic, non-publishing release candidate preflight — **closed**;
- **6C2A** — safe publication engine + isolated publication regression — **closed**;
- **6C2B** — machine-readable publication policy + maintainer documentation — **closed**;
- **6D** — prove upgrade, downgrade, channel, clean-machine, and recovery paths.
