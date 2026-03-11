# Dotfiles

> A big thank you to [Tobi](https://github.com/this-is-tobi), the supreme guide of dotfiles, for the inspiration and advice. [https://github.com/this-is-tobi/dotfiles](https://github.com/this-is-tobi/dotfiles)

Personal macOS & Debian dotfiles and setup scripts.

## Quick Start

### Fresh macOS install (remote)

```sh
# Full install — all profiles, dotfiles, completions
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/macos/init.sh) -a
```

### Fresh Debian install (remote)

```sh
# Full install — all profiles, dotfiles, completions
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/debian/init.sh) -a
```

> The script automatically clones the repository if not found locally, then re-executes from there.

## Usage

### macOS

```sh
# Full install (all profiles + dotfiles + completions + cleanup)
./os/macos/init.sh -a

# Full install in lite mode (skip optional/heavy packages)
./os/macos/init.sh -a -l

# Selective profiles
./os/macos/init.sh -p "base,javascript" -d -c

# Link dotfiles only
./os/macos/init.sh -d
```

### Debian

```sh
# Full install
./os/debian/init.sh -a

# Full install in lite mode
./os/debian/init.sh -a -l

# Selective profiles
./os/debian/init.sh -p "base,python" -d -c

# Link dotfiles only
./os/debian/init.sh -d
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

| Profile      | macOS (Homebrew)                                                                                                 | Debian (apt)                                                    |
| ------------ | ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| `base`       | `fzf`, `proto`, `sshs`, `cheat`, `yq`, `tree`, `watch`, `rsync`, Docker, browsers, `gh`, `lazygit`, `lazydocker` | `fzf`, `docker.io`, `yq`, `tree`, `watch`, `rsync`, `ssh`, `gh` |
| `javascript` | `node`, `npm` via proto + `bun`, `pnpm`, `yarn`, `@antfu/ni`                                                     | `node`, `npm` via proto + `bun`, `pnpm`, `yarn`, `@antfu/ni`    |
| `python`     | `python` via proto + `uv`, `ruff`, `ipython`, `httpie`                                                           | `python` via proto + `uv`, `ruff`, `ipython`, `httpie`          |
| `ai`         | Ollama, GitHub Copilot CLI                                                                                       | Ollama                                                          |
| `extras`     | VLC, Spotify, Audacity, Discord, Transmission...                                                                 | VLC, Audacity, Transmission                                     |

## Dotfiles linking

Running `-d` symlinks config files from the repo into `$HOME`. Any existing file is backed up first (e.g. `~/.zshrc.bak.20260303`) before being replaced.

| Source (repo)                  | Target (`$HOME`)                                        | macOS | Debian | Method  |
| ------------------------------ | ------------------------------------------------------- | ----- | ------ | ------- |
| `config/zsh/.zshrc`            | `~/.zshrc`                                              | yes   | yes    | copy¹   |
| `config/git/.gitconfig`        | `~/.gitconfig`                                          | yes   | yes    | symlink |
| `config/proto/.prototools`     | `~/.proto/.prototools`                                  | yes   | yes    | symlink |
| `config/oh-my-zsh/*.zsh-theme` | `~/.oh-my-zsh/custom/themes/`                           | yes   | yes    | symlink |
| `config/shell/*`               | `~/.config/dotfiles/`                                   | yes   | yes    | symlink |
| `config/vscode/settings.json`  | `~/Library/Application Support/Code/User/settings.json` | yes   | —      | symlink |
| `config/vscode/settings.json`  | `~/.config/Code/User/settings.json`                     | —     | yes    | symlink |
| `config/vscode/mcp.json`       | `~/Library/Application Support/Code/User/mcp.json`      | yes   | —      | symlink |
| `config/vscode/mcp.json`       | `~/.config/Code/User/mcp.json`                          | —     | yes    | symlink |

> ¹ `.zshrc` is copied (not symlinked) because the install script applies machine-specific patches to it (`gsed` alias on macOS, arm64 Homebrew paths).

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

## Testing

### Bats unit tests (local)

```sh
brew install bats-core   # macOS
bats tests/
```

### Docker integration tests

Test the full Debian setup in an isolated container:

```sh
# Run all test stages
docker compose -f tests/docker/docker-compose.test.yml build

# Run individual stages
docker build -f tests/docker/Dockerfile.test --target test-bats -t dotfiles-test-bats .
docker build -f tests/docker/Dockerfile.test --target test-init -t dotfiles-test-init .
docker build -f tests/docker/Dockerfile.test --target test-dotfiles -t dotfiles-test-dotfiles .
```

| Stage           | Description                                         |
| --------------- | --------------------------------------------------- |
| `test-bats`     | Runs all Bats unit tests inside a Debian container  |
| `test-init`     | Validates init.sh flag parsing (no actual installs) |
| `test-dotfiles` | Runs a dotfile-only install and verifies symlinks   |
