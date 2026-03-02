# Dotfiles

Personal macOS dotfiles and setup scripts.

## Quick Start

### Fresh macOS install (remote)

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/osx/init.sh) -p "base,javascript" -d -c
```

> Le script clone automatiquement le repo dans un dossier temporaire s'il n'est pas présent localement, puis s'exécute.

### Depuis une copie locale

```sh
git clone https://github.com/KevinDeBenedetti/dotfiles.git && cd dotfiles
./osx/init.sh -h
```

## Usage

```sh
# Full setup with profiles
./osx/init.sh -p "base,javascript" -d -c

# Lite mode (core tools only)
./osx/init.sh -p "base" -l

# Copy dotfiles only
./osx/init.sh -d
```

## Flags

| Flag            | Description                                 |
| --------------- | ------------------------------------------- |
| `-p <profiles>` | Comma-separated list of profiles to install |
| `-d`            | Copy dotfiles to `$HOME`                    |
| `-c`            | Install zsh CLI completions                 |
| `-l`            | Lite mode — skip optional/heavy packages    |
| `-r`            | Remove `/tmp` files after install           |
| `-h`            | Print help                                  |

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