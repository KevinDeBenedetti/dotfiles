# Rebase a conflicting pull request

Reference of the `git-workflow` skill, for a pull request whose `mergeable`
is `CONFLICTING`. Every command is handed over as the skill's "Runnable
commands" says.

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
