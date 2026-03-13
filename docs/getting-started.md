---
title: Getting Started
---

# Getting Started

Personal macOS and Debian dotfiles with setup scripts for fast developer environment provisioning.

## Prerequisites

| Tool     | macOS                       | Debian / Ubuntu         |
| -------- | --------------------------- | ----------------------- |
| `bash`   | built-in                    | `apt install bash`      |
| `git`    | `xcode-select --install`    | `apt install git`       |
| `curl`   | built-in                    | `apt install curl`      |
| `make`   | `xcode-select --install`    | `apt install make`      |
| `bats`   | `brew install bats-core`    | `apt install bats`      |
| Homebrew | [brew.sh](https://brew.sh)  | —                       |
| Docker   | [Docker Desktop][docker-dl] | `apt install docker.io` |

[docker-dl]: https://www.docker.com/products/docker-desktop/

> The init scripts check for required prerequisites at startup and offer to install them automatically.

## Quick install

### macOS

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/macos/init.sh) -a
```

### Debian

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/debian/init.sh) -a
```

The script clones the repository to `~/.dotfiles` if not already present, then re-executes from there so that symlinks remain valid after reboot.

## Local install

```sh
# Clone
git clone https://github.com/KevinDeBenedetti/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# Full install (all profiles + dotfiles + completions)
./os/macos/init.sh -a        # macOS
./os/debian/init.sh -a       # Debian
```

## Flags

| Flag            | Description                                                   |
| --------------- | ------------------------------------------------------------- |
| `-a`            | Full install: all profiles + dotfiles + completions + cleanup |
| `-p <profiles>` | Comma-separated list of profiles (e.g. `base,python`)         |
| `-d`            | Link dotfiles into `$HOME` only                               |
| `-c`            | Install zsh CLI completions                                   |
| `-l`            | Lite mode — skip optional/heavy packages (macOS only)         |

## What gets installed

- **Oh My Zsh** with custom theme and plugins
- **proto** — version manager for Node.js, Bun, and other runtimes
- **Shell config** — `.zshrc`, aliases, environment variables
- **Git config** — commit signing, rebase-by-default, credential cache
- **SSH config** — host aliases and key references
- **VS Code** — settings and extension list

## Local overrides

Three stub files are created automatically on first run with `-d`. They are **gitignored** and never committed:

| File                              | Purpose                                                          |
| --------------------------------- | ---------------------------------------------------------------- |
| `~/.zshrc.local`                  | Aliases, exports, path additions — sourced last in `.zshrc`      |
| `~/.gitconfig.local`              | Override `[user]` email, signing key — loaded via `[include]`    |
| `~/.config/dotfiles/env.local.sh` | Secrets and env vars (API keys, tokens) — sourced after `env.sh` |

## Testing

Run Bats unit tests locally:

```sh
bats tests/
```

Run full integration tests in Docker (Debian):

```sh
make docker-test-full
```

See [Setup — macOS](./setup/macos) and [Setup — Debian](./setup/debian) for platform-specific details.
