---
title: Git
---

# Git

Global Git configuration symlinked to `~/.gitconfig`.

## Location

| File                    | Symlinked to           |
| ----------------------- | ---------------------- |
| `config/git/.gitconfig` | `~/.gitconfig`         |
| `config/git/ignore`     | `~/.config/git/ignore` |

## Global ignore

`~/.config/git/ignore` is git's default global excludes file (XDG location, no
`core.excludesfile` entry needed). It ignores files across **all** repositories:

| Pattern                          | Reason                                                   |
| -------------------------------- | -------------------------------------------------------- |
| `**/.claude/settings.local.json` | Claude Code per-project local overrides, never committed |
| `**/.claude/.cc-writes/`         | Claude Code internal state, never committed              |

## Key settings

### Identity

`user.useConfigOnly = true`: Git never guesses `user.name` / `user.email` from
the host. Set them in `~/.gitconfig.local` (see
[Machine-specific overrides](#machine-specific-overrides)), otherwise
`git commit` stops and asks for an identity.

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

The signing key itself (`user.signingkey`) is not in the tracked file: set it in
`~/.gitconfig.local`.

### Credentials & connection

| Setting                                        | Value             | Description                                                        |
| ---------------------------------------------- | ----------------- | ------------------------------------------------------------------ |
| `credential.helper`                            | `manager`         | Git Credential Manager handles HTTPS auth¹                         |
| `credential.https://dev.azure.com.useHttpPath` | `true`            | One credential per Azure DevOps repository path                    |
| `url.https://github.com/.insteadOf`            | `git@github.com:` | GitHub SSH remotes are rewritten to HTTPS, so GCM handles them too |
| `rerere.enabled`                               | `true`            | Remember resolved conflicts                                        |
| `color.ui`                                     | `true`            | Color terminal output                                              |

¹ Git Credential Manager (`git-credential-manager`) is installed by the `base`
profile — see [macOS](../setup/macos.md) and [Debian](../setup/debian.md). The
empty `helper =` line written before it clears any helper inherited from a
system-level config.

### Defaults

| Setting                     | Value  |
| --------------------------- | ------ |
| `init.defaultBranch`        | `main` |
| `status.showUntrackedFiles` | `all`  |
| `diff.wordRegex`            | `.`    |
| `diff.tool`                 | `meld` |

## Machine-specific overrides

Settings that differ per machine (identity, signing key, etc.) go in `~/.gitconfig.local`, which is not tracked by git.

```ini
# ~/.gitconfig.local
[user]
  name = Your Name
  email = you@example.com
  signingkey = ~/.ssh/id_ed25519.pub
```

This file is included at the bottom of `.gitconfig`:

```ini
[include]
  path = ~/.gitconfig.local
```
