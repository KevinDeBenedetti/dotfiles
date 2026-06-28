# dotfiles

[![CI/CD](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/dotfiles/ci-cd.yml?style=for-the-badge&label=CI%2FCD)](https://github.com/KevinDeBenedetti/dotfiles/actions/workflows/ci-cd.yml)

> Personal macOS and Debian dotfiles and setup scripts.

## Features

- One-liner bootstrap for macOS and Debian — clones to `~/.dotfiles` automatically
- Profile flags to install only what you need (`-a` for all)
- Managed configs: Git, Zsh, SSH, VS Code, oh-my-zsh, shell aliases, proto
- proto installed via its official installer; all tool versions pinned in `config/proto/.prototools`
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

## Git hooks (prek)

Git hooks are managed with [prek](https://prek.j178.dev) (a faster, dependency-free
pre-commit alternative), configured in [`prek.toml`](prek.toml):

```sh
brew install j178/tap/prek   # install prek
prek install                 # install the hooks (run once after cloning)
prek run --all-files         # run every hook manually
```

The configured hooks are the usual hygiene/lint set (whitespace, shellcheck,
yamllint, actionlint), `check-docs-links` (consumed from
[`KevinDeBenedetti/github-workflows`](https://github.com/KevinDeBenedetti/github-workflows)),
and the `pre-push` Bats suite.

Commit-message generation is handled by the local AI tooling in
[`scripts/ai/`](scripts/ai/) (backed by Ollama over HTTP), not by git hooks.
These are plain shell scripts usable straight from the terminal (`git aicommit`)
— **no Claude Code required**. See [`scripts/ai/README.md`](scripts/ai/README.md).

## Documentation

Full documentation is available at **https://kevindebenedetti.github.io/dotfiles/**.
It is generated from the `docs/` directory and published automatically on push.
