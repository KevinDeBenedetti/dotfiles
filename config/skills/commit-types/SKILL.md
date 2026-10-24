---
name: commit-types
description: Conventional Commits format, type selection and changelog/release impact rules. Use whenever writing, generating or reviewing ANY commit message (every message must be a Conventional Commit), generating one with git aicommit, or choosing between feat, fix, perf, chore, deps, docs, style, test, build, ci, or refactor.
---

# Commit Types

Conventional Commits type selection for this repository's releases. Use when
writing or reviewing a commit message, generating one with `git aicommit`, or
predicting how a change will land in the changelog.

## Format (always)

Every commit message is a Conventional Commit — never free-form text:

```text
<type>(<optional scope>)<optional !>: <summary>

<optional body: what changed and why, as "- " bullets>

<optional footer, e.g. BREAKING CHANGE: <what broke>>
```

- `<type>` is one of the types in the table below; `<scope>` is the main
  module/area touched, omitted when the change spans unrelated areas.
- Summary: imperative mood, present tense, lowercase start, no trailing period;
  the whole header (type, scope and summary) stays ≤ 100 characters, like
  commitlint's `header-max-length` default.
- Body after one blank line, required when the change is non-trivial or
  touches several files; explain WHY rather than how.
- Breaking change: `!` immediately before the colon (`feat(api)!: …`). The
  spec makes the footer optional with `!`; add `BREAKING CHANGE: <what broke>`
  (uppercase, the only case-sensitive token) when the summary alone does not
  say what breaks.
- Other footers follow git trailer syntax, one blank line after the body:
  `Token: value` or `Token #value`, `-` instead of spaces (`Refs: #42`).
- Output only the message: no code fences, quotes, emojis or preamble.

Spec: <https://www.conventionalcommits.org/en/v1.0.0/>.

The same rules are inlined for VS Code's "Generate commit message" button in
`config/vscode/settings.json`
(`github.copilot.chat.commitMessageGeneration.instructions`): keep both in sync.

## Type → release effect

The release-please config (`release-type: "simple"`, no custom
`changelog-sections`, `bump-minor-pre-major: true`) uses release-please's
default changelog sections:

| Type | Changelog |
| ---- | --------- |
| `feat` | shown (Features) |
| `fix` | shown (Bug Fixes) |
| `perf` | shown (Performance Improvements) |
| `revert` | shown (Reverts) |
| `chore`, `docs`, `style`, `refactor`, `test`, `build`, `ci` | hidden |
| `deps` | hidden (not a default section) |

Version bump (default strategy): a breaking change bumps major, `feat` bumps
minor, `fix` bumps patch. While the version is `0.x`, `bump-minor-pre-major`
turns a breaking change into a **minor** bump. A breaking commit of a hidden
type (`refactor!:`) still appears in the changelog.

## Rules

- House rule: do not use `refactor`. release-please would accept it (hidden,
  like `chore`), but this repo standardises on `chore` for a pure refactor with
  no user-facing effect.
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
