---
name: git-workflow
description: Hand-over of git and GitHub steps to an owner who stages, commits and pushes themselves, often from the agent chat - branch, commit, push and pull request as runnable one-line commands. Use whenever you hand the owner a command or propose a commit; when work that ends in a commit sits on main, master, dev or develop (hand the branch command first); after the owner commits or pushes (sync the pull request's title and description, or hand the gh pr create command); and for the pr command.
---

# Git workflow

The owner stages, commits and pushes; you prepare everything around it and
hand the rest over as **runnable** commands. The owner runs them from the chat
itself — the Run button the Claude desktop app shows on a one-line `bash`
block, `!<command>` in the Claude Code CLI — or from any terminal.

| Yours                                                                   | The owner's                                |
| ----------------------------------------------------------------------- | ------------------------------------------ |
| read-only git and `gh` (`status`, `log`, `diff`, `fetch`, `pr view`)    | `git checkout -b`, `git add`, `git commit` |
| `git branch -m` on the app's unpushed session branch (below)            |                                            |
| writing the body files (below), resolving conflicts in the working tree | `git push`, `git rebase`                   |
| `gh pr edit` on the open pull request of the current branch             | `gh pr create`                             |

Long text passed to `gh` — a pull request body, an issue body or comment —
goes through a file in the git directory (`git rev-parse --absolute-git-dir`)
and `--body-file <path>`: the shell never reads it, so its backticks, `$` and
quotes stay as written, and neither does the command guard that denies any
command line naming git's commit or push subcommand. Write the file with your
file tool; where that tool cannot reach the git directory (a worktree guard),
write it elsewhere and `cp` it in — a heredoc would put the text back on the
command line.

## Runnable commands

Every command you hand the owner:

- sits alone in a fenced block tagged `bash`, on one line, in the order to run;
- is complete: real paths, branch name, issue and PR numbers, the whole
  message. A `<placeholder>` is a question you have not asked yet: find the
  value or ask for it;
- runs from the repository root;
- quotes text in single quotes, or `$'…'` when the text holds a newline (`\n`)
  or a single quote (`\'`): bash and zsh read both alike and expand nothing
  inside them — no `$`, backtick or `!`;
- runs without a prompt or an editor: `git commit` always takes `-m`. A
  command that prompts — `git add -p`, `git rebase -i` — is marked *in a
  terminal*: the chat cannot answer it.

Chain with `&&` the steps that belong together (stage and commit); give its
own block to each step whose result the owner should read before the next
(the push, the pull request).

## Branch first

`main`, `master`, `dev`, `develop` and the remote's default branch
(`git symbolic-ref --short refs/remotes/origin/HEAD`) are **shared**: work
reaches them through a pull request. When the current branch
(`git branch --show-current`) is shared and the work will end in a commit,
hand the branch command as soon as you know what the work is — before the
first change when you can — and put it again at the top of the hand-over while
the owner has not run it:

```bash
git checkout -b fix/42-retry-uploads
```

- Name: `<type>/<slug>`, the type the commit will take (`commit-types`), the
  slug two to five lowercase words joined by `-`; `<type>/<number>-<slug>` for
  an issue. It must be free: `git branch --all --list '*<name>'` prints nothing.
- `git checkout -b` takes the uncommitted changes along: the owner can run it
  before, during or after the work. Carry on meanwhile.
- Commits already made on the shared branch, and not pushed, go along too.
  Once the new branch holds them, hand the command that puts the shared branch
  back where the remote has it — nothing is lost, the commits stay on the new
  branch:

  ```bash
  git branch -f main origin/main
  ```

## Session branch

A Claude desktop app session opens in a worktree on a branch the app
generated: `<prefix>/<words>-<6 hex>` (prefix `claude` by default), for
example `claude/fix-login-redirect-a1b2c3`. While that branch has no upstream
(`git config branch.<name>.merge` prints nothing), rename it after the work as
soon as you know what the work is, before the first change — yours to run,
since nothing outside this worktree knows the name yet:

```bash
git branch -m fix/login-redirect-safari
```

The name follows the rule above: `<type>/<slug>`, or `<type>/<number>-<slug>`
for an issue, and free. Once pushed, the name stays.

Where the sandbox keeps `.git/config` read-only, git renames the branch, then
fails to update that file ("could not lock config file", exit 128): with no
upstream there was nothing in it to move, so the rename is done once
`git branch --show-current` prints the new name. Any other failure: hand the
command to the owner.

## Commit hand-over

At the end of work that leaves changes to commit, in this order:

1. The branch command, when the branch is shared (above).
2. Stage and commit, in one line: `git add` with the exact paths of the work —
   the changes that were there before it stay out (when they share a file,
   that file goes hunk by hunk with `git add -p`, in a terminal) — then
   `git commit` with one `-m` per paragraph of the message (`commit-types`):
   header, body, footers.

   ```bash
   git add src/upload.ts tests/upload.test.ts && git commit -m 'fix(upload): retry on 503' -m $'- retry three times with backoff\n- log each retry' -m 'Fixes #42'
   ```

   A body longer than three lines is shown first as a `text` block, for
   review, then the command.
3. The push: `git push` when the branch tracks a remote
   (`git rev-parse --abbrev-ref '@{upstream}'` answers), else its first push:

   ```bash
   git push -u origin fix/42-retry-uploads
   ```

4. The pull request step (below), prepared now so the owner runs the whole
   sequence in one go.

The project's hooks run on the commit and the push. When the owner's output
shows one failed, read it, fix what is yours, and hand the command again.

## Pull request

### Find it

`gh pr view --json number,state,title,body,url,baseRefName,mergeable` on the
current branch. An `OPEN` result is the pull request to sync; nothing, or only
a `CLOSED` or `MERGED` one, means a new one. When `gh` is missing, signed out
or offline, hand the commands and say which. A shared branch has none: branch
first. `mergeable` at `CONFLICTING` comes first: no check runs on it until it
is rebased (below).

### Write it

- **Base**: the open pull request's base; else the base the owner named; else,
  of the default branch and `dev` / `develop` when the remote has them, the one
  with the fewest `git rev-list --count origin/<base>..HEAD` — the branch it
  was cut from. A tie goes to `dev` / `develop`.
- **Scope**: everything the branch brings to its base —
  `git log --format='%h %s' origin/<base>..HEAD` and
  `git diff --stat origin/<base>...HEAD` — plus the commit you are handing over
  when it is not made yet.
- **Title**: a Conventional Commit header (`commit-types`) for the whole
  branch: the commit's own header on a one-commit branch; otherwise the type
  with the highest release impact among the commits, and a summary that
  covers them.
- **Body**: the pull request template, when the repository or the account's
  `.github` repository has one — a pull request opened on GitHub already
  carries it: fill its sections in place, and keep its comments and any block
  a workflow rewrites (`<!-- pr-description:start -->` … `end`). Without a
  template, the `pr` skill's when it is available (mattpocock-skills);
  otherwise `## Summary` — what changed and why, a few bullets — and
  `## Evidence` — the checks run and their result. Then one `Fixes #<number>`
  line per issue the branch closes. In English, with nothing that could not go
  in a commit (no secret, no real IP address or host name), and no AI
  attribution.
- Write the body to `PR_BODY.md` in the git directory, as above: out of the
  working tree and of every commit, one per worktree. Show it in the chat
  too. When that directory is not writable at all, keep the file elsewhere
  and put its absolute path in the command.

### Sync an open one

Compare its title and body with what you wrote. Up to date: give its URL,
nothing to run. Otherwise fold in what the owner added by hand that still
holds — screenshots, links, notes, ticked boxes — and update it. A title that
ends in `…` was cut by GitHub at 72 characters, its end moved to the top of
the body: put both back.

```bash
gh pr edit 87 --title 'feat(issues): sync triage labels to the project board' --body-file "$(git rev-parse --absolute-git-dir)/PR_BODY.md"
```

- Branch pushed and up to date (`git status -sb` shows no `ahead`): run it
  yourself, then give the URL. It is the owner's branch and the request to
  sync is theirs.
- Commits still to push: hand it after the push command — a pull request
  describes pushed commits.
- Denied, waiting for a confirmation you cannot get, or failed (sandbox,
  network): hand that same command.

### Rebase a conflicting one

Fetch the base yourself (`git fetch origin main`); `git merge-tree
--write-tree --name-only origin/main HEAD` names the conflicting files without
touching the working tree. The owner starts the rebase, which stops at the
conflicts before making any commit:

```bash
git rebase origin/main
```

Resolve each file in the working tree — keep both sides where each added its
own line — check that no `<<<<<<<` marker is left, and run the project's
checks. Then hand the end of it, with the files you resolved; `GIT_EDITOR=true`
keeps the commit message and opens no editor:

```bash
git add AGENTS.md README.md && GIT_EDITOR=true git rebase --continue
```

The rebase rewrote the branch, so its push is forced, with a lease that
refuses when the remote branch moved meanwhile:

```bash
git push --force-with-lease
```

### Open a new one

The owner opens it, after the push:

```bash
gh pr create --base main --title 'fix(upload): retry on 503' --body-file "$(git rev-parse --absolute-git-dir)/PR_BODY.md"
```

Add `--draft` while the work is unfinished: a check still failing, a blocked
issue.

## After a commit or push

The owner says they committed or pushed, or the output of a `git commit` or
`git push` they ran from the chat lands in the conversation:

- **Failed** — a hook's `Failed`, `rejected`, `error:`: as in the commit
  hand-over, fix and hand the command again.
- **Committed** on a shared branch: the branch command first, which takes the
  commit along (Branch first); then the push of the new branch and the pull
  request step.
- **Committed** on a branch of its own: hand the push command next, then the
  pull request step.
- **Pushed**: sync the open pull request, or hand the `gh pr create` command.
  A push to a shared branch has no pull request: nothing to sync.
