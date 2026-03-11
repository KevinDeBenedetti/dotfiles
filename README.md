# Dotfiles

Personal macOS & Debian dotfiles and setup scripts.

> Inspired by [this-is-tobi/dotfiles](https://github.com/this-is-tobi/dotfiles).

## Quick Start

### macOS

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/macos/init.sh) -a
```

### Debian

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/debian/init.sh) -a
```

The script clones the repository to `~/.dotfiles` when not found locally, then re-executes from there.

## Documentation

Platform-specific guides covering prerequisites, profiles, flags, dotfile linking, and completions:

- [docs/macos.md](docs/macos.md)
- [docs/debian.md](docs/debian.md)

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
