---
title: Git Workflow
---

# Git Workflow

Agents never commit or push: you do. The shared `git-workflow` skill
(`config/skills/git-workflow/`) splits the work around that rule. The agent
prepares the branch name, the commit message and the pull request's title and
description; you run the steps that publish them, from the chat itself.
`/next-issue`, `/next-task`, the manual steps and `/pr` all hand their commands
over this way.

## Runnable commands

Every command the agent leaves to you is a one-line `bash` block, complete
(real paths, branch, issue and PR numbers, the whole message), in the order to
run:

| Where              | How to run it                     |
| ------------------ | --------------------------------- |
| Claude desktop app | the **Run** button on the block   |
| Claude Code CLI    | `!` followed by the command       |
| any terminal       | paste it at the repository's root |

Text is quoted with single quotes, or `$'…'` when it holds a newline, so
neither bash nor zsh expands anything in a commit message or a title. A command
that prompts (`git add -p`, `git rebase -i`) cannot run from the chat: the
agent marks it *in a terminal*.

## The sequence

1. **Branch**, when you are on a shared branch — `main`, `master`, `dev`,
   `develop` or the remote's default (you):

   ```bash
   git checkout -b fix/42-retry-uploads
   ```

   Commits already made there and not pushed move along; the agent then hands
   `git branch -f main origin/main`, which puts the shared branch back where
   the remote has it (the commits stay on the new branch).

2. **Stage and commit** (you), one `-m` per paragraph of the message:

   ```bash
   git add src/upload.ts tests/upload.test.ts && git commit -m 'fix(upload): retry on 503' -m $'- retry three times with backoff\n- log each retry' -m 'Fixes #42'
   ```

3. **Push** (you): `git push -u origin fix/42-retry-uploads` the first time,
   `git push` after.
4. **Pull request**: you open a new one, after the push; the agent syncs an
   open one itself with `gh pr edit`, or hands you that command.

   ```bash
   gh pr create --base main --title 'fix(upload): retry on 503' --body-file "$(git rev-parse --absolute-git-dir)/PR_BODY.md"
   ```

- **Branch**: `<type>/<slug>`, the type the commit will take (`commit-types`
  skill), or `<type>/<number>-<slug>` for an issue. `git checkout -b` takes the
  uncommitted changes along, so the agent hands it as soon as it knows what the
  work is, and you can run it at any point before the commit.
- **Title**: a Conventional Commit header covering the whole branch. A title
  GitHub cut at 72 characters (it ends in `…`) is put back whole.
- **Description**: the repository's or the account's pull request template
  when there is one, its sections filled in place, with its comments and a
  `pr-description` block left as they are; otherwise the template of the
  `mattpocock-skills` `pr` skill when it is installed, or a summary and the
  evidence (checks run). Then one `Fixes #<number>` line per issue the branch
  closes, and no AI attribution. The agent writes it to `PR_BODY.md` in the
  git directory (`git rev-parse --absolute-git-dir`): out of the working tree,
  never committed, one per worktree.
- **Base**: the open pull request's, the one you name, or the branch the work
  was cut from among the default branch and `dev` / `develop`.

## `/pr`

| Invocation | Effect                                                                  |
| ---------- | ----------------------------------------------------------------------- |
| `/pr`      | Hands the first missing step (branch, commit, push), then the PR step   |
| `/pr dev`  | The same, with `dev` as the base of a new pull request                  |

The pull request step syncs an open pull request, or hands the `gh pr create`
command when there is none.

An open pull request already in step with the branch is left alone: the agent
gives its URL. When it does not match, the agent keeps what you added by hand
(screenshots, links, notes) and rewrites the rest.

A pull request that conflicts with its base runs no check until it is rebased.
You start the rebase (`git rebase origin/main`), which stops at the conflicts
before making a commit; the agent resolves them and runs the checks; you
finish with the two commands it hands you:

```bash
git add AGENTS.md README.md && GIT_EDITOR=true git rebase --continue
```

```bash
git push --force-with-lease
```

## Automatic nudges

In Claude Code, three hooks (see [Claude Code](./claude-code.md#hooks)) keep
the sequence going without a command:

- a session that opens on a shared branch is told to hand you the branch
  command before the first commit (`skill-context.sh`);
- a `git commit` or `git push` you run from the chat that goes through gets
  its next step (`skill-router.sh`): the branch command when the commit landed
  on a shared branch, otherwise the push, then the pull request sync. A failed
  one, or another command that only names them (`git stash push`), gets none;
- the end of each turn shows what is left (`next-steps.sh`): `Branch first`
  on a shared branch with changes or unpushed commits (never a push there,
  unless the remote has no branch yet), the push command with `-u` on a
  branch's first push, and `Pull request: /pr` once everything is committed
  and pushed.

## Guardrails

`git commit` and `git push` are denied to agents in every tool (see
[Claude Code](./claude-code.md)). `gh pr edit` has no allow rule: whether the
agent runs it at once depends on the session's permission mode, and when it
cannot, it hands you the same command. `gh pr merge` always asks.
