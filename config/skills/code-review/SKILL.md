---
name: code-review
description: Two-axis review of a change - Standards (the repository's documented rules plus a code-smell baseline) and Spec (what the issue or task asked for), reported side by side. Use when the owner asks to review a branch, a pull request or work in progress, and on your own change before handing over its commit.
---

# Code review

<!-- Adapted from mattpocock/skills (MIT). Notice: config/skills/NOTICE.md in
     the dotfiles repository. Edit it there only. -->

Review one diff along two axes, kept apart so that neither hides the other:

- **Standards**: does the code follow the rules this repository documents?
- **Spec**: does it do what the originating issue, task or spec asked, no
  less and no more?

The review reports. It changes no file: the caller fixes what it finds.

## 1. Pin the diff

| Situation                                   | Diff                             |
| ------------------------------------------- | -------------------------------- |
| uncommitted work (the usual hand-over case) | `git diff HEAD`                  |
| a fixed point the owner named               | `git diff <fixed-point>...HEAD`  |
| a branch with its commits made              | `git diff origin/<base>...HEAD`  |

Untracked files are part of uncommitted work: list them with
`git status --short` and read them. Check that the ref resolves and the diff
is not empty before going on; ask the owner when neither case is clear.

## 2. Find the spec

In this order: the issue a commit, the branch name or the caller names (fetch
it as `.agents/issue-tracker.md` says, or `docs/agents/` in an older project,
when the project has that file); the `TODO.md` task being worked; a file the
owner passed; a spec under `docs/` or `specs/` matching the branch. None: the Spec axis reports "no spec
available".

## 3. Find the standards

Every file that says how code is written here: `AGENTS.md`, `CLAUDE.md`,
`CONTRIBUTING.md`, `CODING_STANDARDS.md`, the docs they point to, and the
linters' configuration. Leave to the tooling what the tooling enforces.

On top of them, the **smell baseline**. A documented rule of the repository
always wins over it, and each smell is a judgement call, labelled as one
("possible Feature Envy"):

- **Mysterious Name**: the name does not say what the thing does or holds.
- **Duplicated Code**: the same logic appears in more than one place of the
  change.
- **Feature Envy**: a function uses another module's data more than its own.
- **Data Clumps**: the same few values keep travelling together.
- **Primitive Obsession**: a string or number stands in for a domain concept.
- **Repeated Switches**: the same branching on the same value recurs.
- **Shotgun Surgery**: one logical change needed edits scattered over many
  files.
- **Divergent Change**: one file changed for several unrelated reasons.
- **Speculative Generality**: options or abstractions the spec does not need.
- **Middle Man**: a function that only passes the call on.

## 4. Run the two axes

With sub-agents: one per axis, in parallel, each on a fresh context, given the
diff command and, respectively, the standards files plus the baseline above
in full, or the spec. Without them: the Standards pass first, then the Spec
pass, each written down before the other starts.

- **Standards** reports every breach of a documented rule, citing the file
  and the rule, then the baseline smells, quoting the hunk. Under 400 words.
- **Spec** reports what the spec asked that is missing or partial, what the
  diff does that was not asked, and what looks implemented but wrong, quoting
  the spec line. Under 400 words.

## 5. Report

The two reports under `## Standards` and `## Spec`, unmerged and unranked
against each other. Close with one line: the number of findings per axis and
the worst one of each.
