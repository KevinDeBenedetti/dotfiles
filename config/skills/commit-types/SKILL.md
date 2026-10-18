---
name: commit-types
description: Conventional Commits type selection and changelog/release impact rules for this repository. Use when writing or reviewing a commit message, generating one with git aicommit, or choosing between feat, fix, perf, chore, deps, docs, style, test, build, ci, or refactor.
---

# Commit Types

Conventional Commits type selection for this repository's releases. Use when
writing or reviewing a commit message, generating one with `git aicommit`, or
predicting how a change will land in the changelog.

## Type → release effect

The release-please config (`release-type: "simple"`, no custom
`changelog-sections`) uses the default Conventional Commits parser:

| Type | Release effect | Changelog |
| ---- | -------------- | --------- |
| `feat` | minor | shown (Features) |
| `fix` | patch | shown (Bug Fixes) |
| `perf` | patch | shown |
| `deps`, `revert`, `docs`, `style`, `chore`, `test`, `build`, `ci` | none | hidden |
| `refactor` | **never emitted** | — |

## Rules

- `refactor` is deliberately excluded: the release config does not surface it,
  so a pure code refactor with no user-facing effect is committed as `chore`.
- Prefer the narrowest type that is true: `fix` over `feat` when the change
  repairs existing behavior, `perf` when the goal is speed.
- Hidden types (`docs`, `test`, `ci`, …) are correct for changes that must not
  bump the version.

## Source of truth

The release-please configuration lives in the `github-workflows` repo at
`.github/release/release-please-config.json` (mirrored here at the same path).
When it changes (e.g. a custom `changelog-sections` block is added), update
this table and the prompt in `scripts/ai/git-aicommit` to match — they must
stay in sync.
