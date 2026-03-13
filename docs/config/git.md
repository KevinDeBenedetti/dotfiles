# Git

Global Git configuration symlinked to `~/.gitconfig`.

## Location

| File                    | Symlinked to   |
| ----------------------- | -------------- |
| `config/git/.gitconfig` | `~/.gitconfig` |

## Key settings

### Push & pull

| Setting                  | Value    | Description                          |
| ------------------------ | -------- | ------------------------------------ |
| `push.default`           | `simple` | Push current branch to its upstream  |
| `pull.rebase`            | `true`   | Rebase instead of merge on pull      |
| `branch.autosetuprebase` | `always` | Auto-rebase on new tracking branches |

### Signing

Commits and tags are signed with an SSH key.

| Setting                      | Value                    |
| ---------------------------- | ------------------------ |
| `commit.gpgsign`             | `true`                   |
| `tag.gpgSign`                | `true`                   |
| `gpg.format`                 | `ssh`                    |
| `gpg.ssh.allowedSignersFile` | `~/.ssh/allowed_signers` |
| `user.signingkey`            | `~/.ssh/id_rsa.pub`      |

### Credentials & connection

| Setting             | Value                  | Description                  |
| ------------------- | ---------------------- | ---------------------------- |
| `credential.helper` | `cache --timeout=3600` | Cache credentials for 1 hour |
| `rerere.enabled`    | `true`                 | Remember resolved conflicts  |
| `color.ui`          | `true`                 | Color terminal output        |

### Defaults

| Setting                     | Value  |
| --------------------------- | ------ |
| `init.defaultBranch`        | `main` |
| `status.showUntrackedFiles` | `all`  |
| `diff.wordRegex`            | `.`    |

## Machine-specific overrides

Settings that differ per machine (email, signing key, corporate identity, etc.) go in `~/.gitconfig.local`, which is not tracked by git.

```ini
# ~/.gitconfig.local
[user]
  email = work@company.com
  signingkey = ~/.ssh/work_key.pub
```

This file is included at the bottom of `.gitconfig`:

```ini
[include]
  path = ~/.gitconfig.local
```
