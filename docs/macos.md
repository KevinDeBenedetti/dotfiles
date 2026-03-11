# macOS Setup

Personal macOS dotfiles and setup scripts powered by [Homebrew](https://brew.sh), [proto](https://moonrepo.dev/proto), and [Oh My Zsh](https://ohmyz.sh).

## Prerequisites

The init script checks for both prerequisites at startup and offers to install them automatically.

| Prerequisite             | Check             | Install                    |
| ------------------------ | ----------------- | -------------------------- |
| Xcode Command Line Tools | `xcode-select -p` | `xcode-select --install`   |
| Homebrew                 | `brew --version`  | [brew.sh](https://brew.sh) |

## Installation

### Remote (fresh machine)

```sh
# Full install — all profiles, dotfiles, completions
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/macos/init.sh) -a
```

The script clones the repository to `~/.dotfiles` if not already present, then re-executes from there. Using a permanent path ensures symlinks remain valid after reboot.

### Local

```sh
# Clone
git clone https://github.com/KevinDeBenedetti/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# Full install
./os/macos/init.sh -a

# Dotfiles only
./os/macos/init.sh -d

# Specific profiles + completions
./os/macos/init.sh -p "base,python" -c
```

## Flags

| Flag            | Description                                                   |
| --------------- | ------------------------------------------------------------- |
| `-a`            | Full install: all profiles + dotfiles + completions + cleanup |
| `-p <profiles>` | Comma-separated list of profiles (e.g. `base,javascript`)     |
| `-d`            | Link dotfiles into `$HOME`                                    |
| `-c`            | Install zsh CLI completions                                   |
| `-l`            | Lite mode — skip optional/heavy packages                      |
| `-r`            | Remove bootstrap temp directory after install                 |
| `-h`            | Print help                                                    |

> At least one flag is required. Running without flags prints help and exits.

## Profiles

### `base`

Core CLI tools installed via Homebrew. Split into lite (always) and additional (full mode only).

**Lite:**

| Tool                                           | Description                                           |
| ---------------------------------------------- | ----------------------------------------------------- |
| [`fzf`](https://github.com/junegunn/fzf)       | Fuzzy finder for shell history, files, and more       |
| [`proto`](https://moonrepo.dev/proto)          | Multi-language toolchain version manager              |
| [`sshs`](https://github.com/quantumsheep/sshs) | Interactive SSH host selector (reads `~/.ssh/config`) |
| [`cheat`](https://github.com/cheat/cheat)      | Community-driven command cheatsheets                  |
| [`yq`](https://mikefarah.gitbook.io/yq)        | Portable YAML/JSON/TOML processor                     |
| `tree`                                         | Directory tree visualizer                             |
| `watch`                                        | Repeat a command at intervals                         |
| `rsync`                                        | Incremental file transfer                             |
| `docker` + `docker-compose`                    | Container build and orchestration CLI                 |

**Additional (full mode):**

| Tool                                                        | Description                                                          |
| ----------------------------------------------------------- | -------------------------------------------------------------------- |
| [`gh`](https://cli.github.com)                              | GitHub CLI — PRs, issues, repos from the terminal                    |
| [`lazygit`](https://github.com/jesseduffield/lazygit)       | Terminal UI for Git                                                  |
| [`lazydocker`](https://github.com/jesseduffield/lazydocker) | Terminal UI for Docker                                               |
| [`colima`](https://github.com/abiosoft/colima)              | Lightweight container runtime for macOS (Docker Desktop alternative) |
| [`nmap`](https://nmap.org)                                  | Network exploration and port scanning                                |
| Browsers                                                    | Brave, Firefox, Arc                                                  |
| Apps                                                        | Insomnia, Mattermost, OpenVPN Connect                                |

### `javascript`

Installs Node.js and package managers via proto.

**Lite:**

| Tool   | Version manager |
| ------ | --------------- |
| `node` | proto           |
| `npm`  | proto           |

**Additional (full mode):**

| Tool                                                  | Description                                            |
| ----------------------------------------------------- | ------------------------------------------------------ |
| `bun`                                                 | Fast all-in-one JS runtime and bundler                 |
| `pnpm`                                                | Efficient disk-space-saving package manager            |
| `yarn`                                                | Alternative npm-compatible package manager             |
| [`@antfu/ni`](https://github.com/antfu-collective/ni) | Universal package manager wrapper (`ni`, `nr`, `nun`…) |

### `python`

Installs Python via proto and tooling via uv.

**Lite:**

| Tool                              | Version manager                                 |
| --------------------------------- | ----------------------------------------------- |
| `python`                          | proto                                           |
| [`uv`](https://docs.astral.sh/uv) | Blazing-fast Python package and project manager |

**Additional (full mode):**

| Tool                                  | Description                                |
| ------------------------------------- | ------------------------------------------ |
| [`ruff`](https://docs.astral.sh/ruff) | Extremely fast Python linter and formatter |
| [`ipython`](https://ipython.org)      | Enhanced interactive Python shell          |
| [`httpie`](https://httpie.io)         | User-friendly HTTP client for the terminal |

### `ai`

Full mode only.

| Tool                           | Description                       |
| ------------------------------ | --------------------------------- |
| [`ollama`](https://ollama.com) | Run large language models locally |
| `copilot-cli`                  | GitHub Copilot for the CLI        |

### `extras`

Personal applications.

**Lite:** VLC

**Additional (full mode):** Audacity, Discord, Spotify, Transmission, Raspberry Pi Imager, Soulseek, Macs Fan Control, Radio Silence, kDrive

## Dotfiles Linking

Running `-d` symlinks (or copies) config files from the repository into `$HOME`. Any existing file is backed up with a datestamp (e.g. `~/.zshrc.bak.20260311`) before being replaced.

| Source                         | Target                                                  | Method  |
| ------------------------------ | ------------------------------------------------------- | ------- |
| `config/zsh/.zshrc`            | `~/.zshrc`                                              | copy¹   |
| `config/git/.gitconfig`        | `~/.gitconfig`                                          | symlink |
| `config/proto/.prototools`     | `~/.proto/.prototools`                                  | symlink |
| `config/oh-my-zsh/*.zsh-theme` | `~/.oh-my-zsh/custom/themes/`                           | symlink |
| `config/shell/*`               | `~/.config/dotfiles/`                                   | symlink |
| `config/vscode/settings.json`  | `~/Library/Application Support/Code/User/settings.json` | symlink |
| `config/vscode/mcp.json`       | `~/Library/Application Support/Code/User/mcp.json`      | symlink |

> ¹ `.zshrc` is copied rather than symlinked because the init script applies macOS-specific patches: `gsed` alias and Homebrew paths for Apple Silicon (`/opt/homebrew`).

## Completions

Running `-c` installs zsh completions for the following tools (placed in `$(brew --prefix)/share/zsh/site-functions`):

| Tool    | Source                                               |
| ------- | ---------------------------------------------------- |
| `fzf`   | Homebrew integration (`--completion --key-bindings`) |
| `gh`    | `gh completion -s zsh`                               |
| `proto` | `proto completions --shell zsh`                      |
| `uv`    | `uv generate-shell-completion zsh`                   |

## Homebrew Tips

```sh
# Update all installed packages
brew update && brew upgrade

# Remove outdated versions
brew cleanup

# List installed formulae
brew list --formula

# List installed casks
brew list --cask

# Check for issues
brew doctor
```

## Common Issues

**Xcode CLT broken after macOS update:**

```sh
sudo rm -rf /Library/Developer/CommandLineTools
xcode-select --install
```

**Homebrew not found on Apple Silicon:**

```sh
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Add the above line to your `~/.zshrc` if Homebrew is not found in a new shell session.
