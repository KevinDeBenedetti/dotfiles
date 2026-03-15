# dotfiles

[![CI/CD](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/dotfiles/ci-cd.yml?style=for-the-badge&label=CI%2FCD)](https://github.com/KevinDeBenedetti/dotfiles/actions/workflows/ci-cd.yml)

> Personal macOS and Debian dotfiles and setup scripts.

## Features

- One-liner bootstrap for macOS and Debian — clones to `~/.dotfiles` automatically
- Profile flags to install only what you need (`-a` for all)
- Managed configs: Git, Zsh, SSH, VS Code, oh-my-zsh, shell aliases, proto
- Bats unit tests covering init flags, functions, and security profile
- Docker integration tests for full Debian install validation (no real machine required)
- ShellCheck and YAML linting on every push

## Prerequisites

- `bash`, `curl`
- Docker (for integration tests only)

## Usage

```sh
# macOS
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/macos/init.sh) -a

# Debian
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/debian/init.sh) -a
```

→ Full guide: [docs](https://kevindebenedetti.github.io/dotfiles/getting-started)

## Documentation

Full documentation is available at **https://kevindebenedetti.github.io/dotfiles/**.
It is generated from the `docs/` directory and published automatically on push.
