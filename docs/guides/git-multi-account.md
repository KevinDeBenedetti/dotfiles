---
title: Git multi-account (personal / work) over SSH
---

# Clone and use multiple Git accounts (personal / work) over SSH

This guide explains how to clone a repository **with the right account** (personal
or professional) using two complementary mechanisms already wired into these
dotfiles:

1. **SSH** — one host alias per account, each pointing to its own key
   (`~/.ssh/config.d/*.conf`, not tracked by git).
2. **Git** — the identity (`user.email`, `user.signingkey`) switches automatically
   based on the repository's **directory**, via `includeIf "gitdir:…"` in
   [`config/git/.gitconfig`](https://github.com/KevinDeBenedetti/dotfiles/blob/main/config/git/.gitconfig).

The idea: **clone the right repo in the right place**, and everything else (SSH
key, commit e-mail, signing key) is selected automatically.

## TL;DR

```sh
# Personal → personal key + personal identity (auto under ~/dev/)
git clone git@github.com:KevinDeBenedetti/my-repo.git ~/dev/my-repo

# Work → SSH alias "github.com-pro" + work identity (auto under ~/pro/)
git clone git@github.com-pro:client-org/project.git ~/pro/project
```

The only thing that changes in the command is the **host** in the URL:
`github.com` (personal) vs `github.com-pro` (work). Everything else is resolved by
the configuration.

---

## 1. Generate one SSH key per account

Use a separate key per identity (recommended: `ed25519`). The passphrase is stored
in the macOS keychain (`UseKeychain yes`, already enabled in
[`config/ssh/config`](https://github.com/KevinDeBenedetti/dotfiles/blob/main/config/ssh/config)).

```sh
# Personal key
ssh-keygen -t ed25519 -C "contact@kevindb.dev" -f ~/.ssh/id_ed25519

# Work key
ssh-keygen -t ed25519 -C "work@company.com" -f ~/.ssh/id_ed25519_pro
```

Load the keys into the agent and keychain:

```sh
ssh-add --apple-use-keychain ~/.ssh/id_ed25519
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_pro
```

Then add **each public key** (`*.pub`) to the matching GitHub account:
- personal → [github.com/settings/keys](https://github.com/settings/keys)
- work → same settings page on the work account/organization

```sh
# Copy the public key to the clipboard
pbcopy < ~/.ssh/id_ed25519.pub
```

> A single key can only be registered on **one** GitHub account at a time — hence
> the need for one key per account.

---

## 2. Configure the SSH host aliases

Per-account host blocks live in `~/.ssh/config.d/*.conf`, which is **not tracked by
git** (see [`.gitignore`](https://github.com/KevinDeBenedetti/dotfiles/blob/main/.gitignore)) because this repository is public. They
are included first by [`config/ssh/config`](https://github.com/KevinDeBenedetti/dotfiles/blob/main/config/ssh/config):

```ssh-config
Include ~/.ssh/config.d/*.conf
```

Create `~/.ssh/config.d/github.conf`:

```ssh-config
# Personal account — real host "github.com"
Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes

# Work account — alias "github.com-pro"
Host github.com-pro
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_pro
  IdentitiesOnly yes
```

| Directive            | Purpose                                                                          |
| -------------------- | -------------------------------------------------------------------------------- |
| `Host`               | Name used in the clone URL (`git@<Host>:…`). The alias does not need to exist as a real host. |
| `HostName`           | Actual server reached over SSH (always `github.com` here).                       |
| `IdentityFile`       | Private key presented for this account.                                          |
| `IdentitiesOnly yes` | Only offer this key (prevents the agent from presenting the wrong key first).    |

> Official format for multiple accounts on the same provider — see
> [git-scm.com/docs/gitfaq](https://git-scm.com/docs/gitfaq).

Verify that each alias authenticates against the right account:

```sh
ssh -T git@github.com         # → Hi KevinDeBenedetti!
ssh -T git@github.com-pro     # → Hi <work-account>!
```

---

## 3. Switch the Git identity per directory

[`config/git/.gitconfig`](https://github.com/KevinDeBenedetti/dotfiles/blob/main/config/git/.gitconfig) defines a **personal
identity by default**, then selects the right identity based on **where the repo
lives**: personal under `~/dev/`, professional under `~/pro/`:

```ini
[user]
  email = contact@kevindb.dev
  name  = KevinDeBenedetti
  signingkey = ~/.ssh/id_rsa.pub

# Per-directory identity (placed last → takes precedence over the default [user])
[includeIf "gitdir:~/dev/"]
  path = ~/.gitconfig-perso
[includeIf "gitdir:~/pro/"]
  path = ~/.gitconfig-pro
```

Each `gitdir:` condition triggers as soon as the repository's `.git` directory is
located under that path (the trailing `/` implicitly appends `**`). See
[git-scm.com/docs/git-config](https://git-scm.com/docs/git-config) →
*Conditional includes*.

Create `~/.gitconfig-perso` and `~/.gitconfig-pro` (untracked, gitignored like
`~/.gitconfig.local`), each with its own `[user]` block:

```ini
# ~/.gitconfig-perso — personal identity (repos under ~/dev/)
[user]
  email = contact@kevindb.dev
  name  = KevinDeBenedetti
  signingkey = ~/.ssh/id_ed25519.pub
```

```ini
# ~/.gitconfig-pro — professional identity (repos under ~/pro/)
[user]
  email = work@company.com
  name  = Kevin De Benedetti
  signingkey = ~/.ssh/id_ed25519_pro.pub
```

> **Layout convention**: personal projects live under `~/dev/…`, work projects under
> `~/pro/…`. The directory layout drives the identity — not the URL.

### Commit signing (SSH)

Commits are signed with an SSH key (`gpg.format = ssh`). For the work signature to
be accepted, add the work public key to `~/.ssh/allowed_signers`:

```sh
echo "work@company.com $(cat ~/.ssh/id_ed25519_pro.pub)" >> ~/.ssh/allowed_signers
```

---

## 4. Clone with the right account

The SSH URL has the form `git@<host>:<owner>/<repo>.git`. The **host** selects the
key; the **destination directory** selects the identity.

```sh
# Personal — host "github.com", destination under ~/dev/
git clone git@github.com:KevinDeBenedetti/dotfiles.git ~/dev/dotfiles

# Work — host "github.com-pro" + destination under ~/pro/
git clone git@github.com-pro:client-org/api.git ~/pro/api
```

> ⚠️ For work, **both** matter: the `github.com-pro` alias (correct SSH key) **and**
> the `~/pro/` directory (correct commit identity). Cloning a work repo elsewhere
> will still authenticate over SSH but sign commits with the personal e-mail.

### Verify the identity after cloning

```sh
cd ~/pro/api
git config user.email      # → work@company.com
git config user.name       # → Kevin De Benedetti
git config user.signingkey # → ~/.ssh/id_ed25519_pro.pub
```

---

## 5. Common Git commands (reference)

Once the repository is cloned in the right place, **no command needs to be
adjusted** — the identity and key are already resolved.

```sh
# State & history
git status
git log --oneline -10
git branch -vv                       # branches + upstream

# Working
git switch -c feature/my-branch      # create + switch
git add -p                           # stage interactively
git commit -m "feat: ..."            # signed automatically
git push -u origin feature/my-branch

# Sync (rebase by default, see config/git/.gitconfig)
git fetch --all --prune
git pull                             # = pull --rebase

# Check the signature
git log --show-signature -1
```

### Convert an existing HTTPS clone to SSH (right account)

```sh
# Personal repo
git remote set-url origin git@github.com:KevinDeBenedetti/repo.git

# Work repo
git remote set-url origin git@github.com-pro:client-org/repo.git
git remote -v                        # verify
```

### Move an existing work repo under ~/pro/

If a work repository was cloned in the wrong place (personal identity applied):

```sh
mv ~/dev/api ~/pro/api
cd ~/pro/api
git config user.email                # should now return the work e-mail
# Optional: re-attribute the last commit to the correct identity
git commit --amend --reset-author --no-edit
```

---

## Summary

| Item             | Personal                          | Work                               |
| ---------------- | --------------------------------- | ---------------------------------- |
| SSH key          | `~/.ssh/id_ed25519`               | `~/.ssh/id_ed25519_pro`            |
| Host in the URL  | `github.com`                      | `github.com-pro`                   |
| Directory        | `~/dev/…`                         | `~/pro/…`                          |
| Git identity     | `~/.gitconfig-perso` (via `includeIf`) | `~/.gitconfig-pro` (via `includeIf`) |
| Commit e-mail    | `contact@kevindb.dev`             | `work@company.com`                 |

See also: [Config — SSH](../config/ssh.md) · [Config — Git](../config/git.md).
