# Dotfiles

Personal macOS & Debian dotfiles and setup scripts.

> Inspired by [this-is-tobi/dotfiles](https://github.com/this-is-tobi/dotfiles).

[![Documentation](https://img.shields.io/badge/docs-kevindebenedetti.github.io%2Fdotfiles-blue?style=for-the-badge)](https://kevindebenedetti.github.io/dotfiles/)

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

Full guides covering prerequisites, profiles, flags, dotfile linking, local overrides, and more:

- [Getting Started](https://kevindebenedetti.github.io/dotfiles/getting-started)
- [macOS Setup](https://kevindebenedetti.github.io/dotfiles/setup/macos)
- [Debian Setup](https://kevindebenedetti.github.io/dotfiles/setup/debian)
- [Git](https://kevindebenedetti.github.io/dotfiles/config/git) · [Zsh](https://kevindebenedetti.github.io/dotfiles/config/zsh) · [SSH](https://kevindebenedetti.github.io/dotfiles/config/ssh) · [VS Code](https://kevindebenedetti.github.io/dotfiles/config/vscode)

## Testing

```sh
bats tests/              # unit tests
make docker-test-full    # full integration test (Debian, Docker)
```
