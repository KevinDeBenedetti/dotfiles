---
name: commit
description: Generate a Conventional Commits message from the staged diff and print it in the chat; if TODO.md is staged, strip its Done section and re-stage. Never runs git commit. Invoke with /commit.
disable-model-invocation: true
argument-hint: "[optional context to steer the message]"
allowed-tools: Bash(git diff:*), Bash(git status:*), Bash(git add:*), Read, Edit
---

## Staged changes

Files:
!`git diff --cached --name-only`

Diff:
!`git diff --cached`

## Task

You replace two git hooks: a commit-message generator and a TODO "Done" purger.
Optional user context (may be empty): $ARGUMENTS

HARD RULE: never run `git commit` (the user commits themselves, and has it
blocked). The ONLY file you may edit/stage is TODO.md.

1. **Nothing staged?** If the diff above is empty, say so and stop (suggest `git add`).
2. **Purge TODO (only if staged).** If `TODO.md` is in the staged file list above
   AND has a heading containing "Fait" or "Done" with `- [x]` items beneath it,
   remove those `- [x]` lines (keep the heading and every other section/line),
   then run `git add TODO.md`. Otherwise leave TODO.md untouched.
3. **Write the message** in Conventional Commits format, based ONLY on the diff:
   - First line `<type>(scope): summary` — imperative, ≤72 chars
     (feat|fix|docs|chore|refactor|test|perf|build|ci).
   - Blank line, then a `- ` bullet body for notable changes (omit if trivial).
4. **Output, do NOT commit:**
   - The raw message in a fenced ```text block (easy to copy).
   - A ready-to-run ```bash block: `git commit -m … -m …`.
   - One line stating whether TODO.md was purged.
