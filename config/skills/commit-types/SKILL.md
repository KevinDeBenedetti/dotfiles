---
name: commit-types
description: Conventional Commits format, type selection and changelog/release impact rules. Use whenever writing, generating or reviewing ANY commit message (every message must be a Conventional Commit), generating one with git aicommit, or choosing between feat, fix, perf, chore, deps, docs, style, test, build, ci, or refactor.
---

# Commit Types

Conventional Commits format and type selection for the owner's repositories,
which share one release-please configuration. Use when writing or reviewing a
commit message, generating one with `git aicommit`, or predicting how a change
will land in the changelog.

## Format (always)

Every commit message is a Conventional Commit — never free-form text:

```text
<type>(<optional scope>)<optional !>: <summary>

<optional body: what changed and why, as "- " bullets>

<optional footer, e.g. BREAKING CHANGE: <what broke>>
```

- English, whatever the language of the conversation, the code or the diff.
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
- When the message is the whole output (`git aicommit`, a commit-message
  box), output only the message: no code fences, quotes, emojis or preamble.
  A commit you propose to the owner is handed over as a runnable
  `git add … && git commit -m …` command instead: see the `git-workflow` skill.
- The message reads as the owner's own: no AI attribution, no
  `Co-Authored-By` trailer naming an AI.

Spec: <https://www.conventionalcommits.org/en/v1.0.0/>.

## Type → release effect

The shared release-please config (`release-type: "simple"`, no custom
`changelog-sections`, `bump-minor-pre-major: true`) uses release-please's
default changelog sections. A repository whose own
`.github/release/release-please-config.json` sets `changelog-sections` follows
that file instead: read it before predicting a changelog.

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
  like `chore`), but the owner's repositories standardise on `chore` for a pure refactor with
  no user-facing effect.
- Prefer the narrowest type that is true: `fix` over `feat` when the change
  repairs existing behavior, `perf` when the goal is speed.
- Hidden types (`docs`, `test`, `ci`, …) are correct for changes that must not
  bump the version.

## Source of truth

The shared release-please configuration lives in the owner's
`github-workflows` repository, at `.github/release/release-please-config.json`;
each repository mirrors it at the same path.
