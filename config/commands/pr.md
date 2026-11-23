---
description: Bring the current branch's pull request up to date - its title and description, from the branch's commits - or hand the runnable commands that get it there - branch off main or dev, commit, push, gh pr create.
argument-hint: "[base branch]"
---

Take the current branch to an up-to-date pull request, following the
`git-workflow` skill (`~/.claude/skills/git-workflow/SKILL.md`): load it first,
and hand every command over in its runnable format. The title and the body
read as the owner's own work: no AI attribution.

<!-- Single source shared by Claude Code, OpenCode and VS Code Copilot
     (linked by os/helpers/links.sh). Keep it tool-neutral. -->

The argument is `$ARGUMENTS`. If that placeholder was left as-is (the tool did
not substitute it), the argument is whatever the user typed after the `/pr`
command instead. A branch name is the base of a new pull request; none lets
the skill pick it.

## 1. State

Read it, without changing anything:

```sh
git status --short --branch
git log --format='%h %s' '@{upstream}..HEAD'
gh pr view --json number,state,title,body,url,baseRefName,mergeable
```

A `git log` that fails on `@{upstream}` means the branch was never pushed; a
`gh pr view` that finds nothing means it has no pull request yet.

## 2. Next step

Take the first case that holds, then carry the sequence to the end:

| State                                             | Hand over or do                                                              |
| ------------------------------------------------- | ---------------------------------------------------------------------------- |
| on a shared branch (`main`, `dev`, …)             | the branch command, named after the changes, then the rows below             |
| uncommitted changes                               | the commit hand-over, then the push and the pull request step                |
| commits not pushed                                | the push command, then the pull request step                                 |
| an open pull request that conflicts with its base | the rebase: its command, your resolution, then the owner's continue and push |
| pushed, with an open pull request                 | sync it: run `gh pr edit` yourself, or hand it when you cannot               |
| pushed, without one                               | the `gh pr create` command                                                   |

Uncommitted changes that do not all belong to one piece of work: list them,
propose the commit for the ones that do, and ask about the rest. The commit
message follows `commit-types`; the pull request title and body follow the
skill's "Write it".

## 3. Report

One line of state (branch, commits ahead, pull request number or none), then
the runnable commands in order, then the pull request body you wrote and its
URL once it exists. Nothing to do: say so, with the URL.
