# Dotfiles

Personal macOS dotfiles and setup scripts.

## Quick Start

```sh
git clone https://github.com/kevindebenedetti/dotfiles.git && cd dotfiles
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

## Dotfiles

Configs copied to `$HOME` with `-d`:

- `.zshrc` — zsh config (oh-my-zsh + custom theme)
- `.gitconfig` — git globals
- `.prototools` — proto toolchain versions
- `.config/` — tool configs
- `.vscode/settings.json`, `mcp.json` — VS Code settings + MCP

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