# Dotfiles

> A big thank you to [@this-is-tobi](https://github.com/this-is-tobi), the supreme guide of dotfiles, for the inspiration and advice. [https://github.com/this-is-tobi/dotfiles](https://github.com/this-is-tobi/dotfiles)

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

# Copy dotfiles only
./osx/init.sh -d
```

## Flags

| Flag            | Description                                                       |
| --------------- | ----------------------------------------------------------------- |
| `-a`            | Full install: all profiles + dotfiles + completions + tmp cleanup |
| `-p <profiles>` | Comma-separated list of profiles to install                       |
| `-d`            | Copy dotfiles to `$HOME`                                          |
| `-c`            | Install zsh CLI completions                                       |
| `-l`            | Lite mode — skip optional/heavy packages                          |
| `-r`            | Remove `/tmp` files after install                                 |
| `-h`            | Print help                                                        |

## Profiles

| Profile      | Tools                                                                                                            |
| ------------ | ---------------------------------------------------------------------------------------------------------------- |
| `base`       | `fzf`, `proto`, `sshs`, `cheat`, `yq`, `tree`, `watch`, `rsync`, Docker, browsers, `gh`, `lazygit`, `lazydocker` |
| `javascript` | `node`, `npm` via proto + `bun`, `pnpm`, `yarn`, `@antfu/ni`                                                     |
| `python`     | `python` via proto + `uv`, `ruff`, `ipython`, `httpie`                                                           |
| `ai`         | Ollama, GitHub Copilot CLI                                                                                       |
| `extras`     | VLC, Spotify, Audacity, Discord, Transmission…                                                                   |

## Structure

```
osx/
  init.sh          # Entry point
  setup/           # Profile scripts
  helpers/
    proto.sh       # Injects PROTO_HOME into .zshrc
    completions.sh # Generates zsh completions (fzf, gh, proto, uv)
dotfiles/          # Config files to copy
```