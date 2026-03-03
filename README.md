# Dotfiles

> A big thank you to [Tobi](https://github.com/this-is-tobi), the supreme guide of dotfiles, for the inspiration and advice. [https://github.com/this-is-tobi/dotfiles](https://github.com/this-is-tobi/dotfiles)

Personal macOS dotfiles and setup scripts.

## Quick Start

### Fresh macOS install (remote)

```sh
# Full install — all profiles, dotfiles, completions
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/osx/init.sh) -a
```

> The script automatically clones the repository into a temporary directory if not found locally, then re-executes from there.

## Usage

```sh
# Full install (all profiles + dotfiles + completions + cleanup)
./osx/init.sh -a

# Full install in lite mode (skip optional/heavy packages)
./osx/init.sh -a -l

# Selective profiles
./osx/init.sh -p "base,javascript" -d -c

# Link dotfiles only
./osx/init.sh -d
```

## Flags

| Flag            | Description                                                       |
| --------------- | ----------------------------------------------------------------- |
| `-a`            | Full install: all profiles + dotfiles + completions + tmp cleanup |
| `-p <profiles>` | Comma-separated list of profiles to install                       |
| `-d`            | Link dotfiles into `$HOME` (symlinks, with automatic backup)      |
| `-c`            | Install zsh CLI completions                                       |
| `-l`            | Lite mode — skip optional/heavy packages                          |
| `-r`            | Remove the bootstrap temp directory after install                 |
| `-h`            | Print help                                                        |

> At least one flag is required. Running the script without any flag prints help and exits.

## Profiles

| Profile      | Tools                                                                                                            |
| ------------ | ---------------------------------------------------------------------------------------------------------------- |
| `base`       | `fzf`, `proto`, `sshs`, `cheat`, `yq`, `tree`, `watch`, `rsync`, Docker, browsers, `gh`, `lazygit`, `lazydocker` |
| `javascript` | `node`, `npm` via proto + `bun`, `pnpm`, `yarn`, `@antfu/ni`                                                     |
| `python`     | `python` via proto + `uv`, `ruff`, `ipython`, `httpie`                                                           |
| `ai`         | Ollama, GitHub Copilot CLI                                                                                       |
| `extras`     | VLC, Spotify, Audacity, Discord, Transmission…                                                                   |

## Dotfiles linking

Running `-d` symlinks config files from the repo into `$HOME`. Any existing file is backed up first (e.g. `~/.zshrc.bak.20260303`) before being replaced.

| Source (repo)                     | Target (`$HOME`)                                        | Method  |
| --------------------------------- | ------------------------------------------------------- | ------- |
| `dotfiles/.zshrc`                 | `~/.zshrc`                                              | copy¹   |
| `dotfiles/.gitconfig`             | `~/.gitconfig`                                          | symlink |
| `dotfiles/.prototools`            | `~/.proto/.prototools`                                  | symlink |
| `dotfiles/.oh-my-zsh/*.zsh-theme` | `~/.oh-my-zsh/custom/themes/`                           | symlink |
| `dotfiles/.config/*`              | `~/.config/`                                            | symlink |
| `dotfiles/.vscode/settings.json`  | `~/Library/Application Support/Code/User/settings.json` | symlink |
| `dotfiles/.vscode/mcp.json`       | `~/Library/Application Support/Code/User/mcp.json`      | symlink |

> ¹ `.zshrc` is copied (not symlinked) because the install script applies machine-specific patches to it (`gsed` alias, arm64 Homebrew paths).

## Local overrides

On first run with `-d`, three stub files are created automatically. They are **gitignored** and never committed — fill them in with machine-specific config:

| File                              | Purpose                                                             |
| --------------------------------- | ------------------------------------------------------------------- |
| `~/.zshrc.local`                  | Aliases, exports, path additions — sourced last in `.zshrc`         |
| `~/.gitconfig.local`              | Override `[user]` email, signing key, etc. — loaded via `[include]` |
| `~/.config/dotfiles/env.local.sh` | Secrets and env vars (API keys, tokens) — sourced after `env.sh`    |

Example `~/.gitconfig.local`:
```ini
[user]
    email = work@company.com
    signingkey = ~/.ssh/id_ed25519.pub
```

Example `~/.config/dotfiles/env.local.sh`:
```sh
export CONTEXT7_API_KEY="your-real-key-here"
```
