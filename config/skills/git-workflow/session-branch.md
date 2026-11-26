# Session branch

Reference of the `git-workflow` skill, for a session the Claude desktop app
opened in a worktree. The naming rule (`<type>/<slug>`) is the skill's
"Branch first".

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
