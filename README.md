# Dotfiles

[![CI/CD](https://img.shields.io/github/actions/workflow/status/KevinDeBenedetti/dotfiles/ci-cd.yml?style=for-the-badge&label=CI%2FCD)](https://github.com/KevinDeBenedetti/dotfiles/actions/workflows/ci-cd.yml) [![Release](https://img.shields.io/github/v/release/KevinDeBenedetti/dotfiles?style=for-the-badge)](https://github.com/KevinDeBenedetti/dotfiles/releases) [![License](https://img.shields.io/github/license/KevinDeBenedetti/dotfiles?style=for-the-badge)](LICENSE)

> Personal dotfiles and bootstrap scripts that provision macOS workstations and Debian servers, with shared guardrails for AI coding agents.

## Features

- One-liner bootstrap for macOS and Debian, with profile flags to install only what you need (`-a` for everything)
- Debian server hardening: key-only SSH, UFW, Fail2Ban, CrowdSec, sysctl and automatic security updates
- Managed configs for Git (SSH signing, Git Credential Manager), Zsh, SSH, VS Code and a proto-pinned toolchain
- AI agent guardrails shared by Claude Code, OpenCode and VS Code Copilot: sandbox, secret deny rules, read-only `kubectl` and `gh`, root-owned managed policy
- Shared agent skills and commands (Conventional Commits, README, docs) linked into every tool from `config/skills/` and `config/commands/`
- ShellCheck, yamllint and Bats in CI, plus Docker and Lima integration rigs for the Debian setup

## Prerequisites

- `bash` and `curl`
- macOS: the script offers to install the Xcode Command Line Tools and Homebrew; Debian: `root` or `sudo`
- Docker, for the integration tests only

## Usage

```sh
# macOS
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/macos/init.sh) -a

# Debian
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/debian/init.sh) -a
```

→ Full usage guide: [docs](https://kevindebenedetti.github.io/dotfiles/getting-started)

## Git hooks (prek)

Hooks are managed with [prek](https://prek.j178.dev) and configured in [`prek.toml`](prek.toml):

```sh
brew install j178/tap/prek
prek install           # pre-commit + pre-push hooks
prek run --all-files   # run every hook once
```

They cover file hygiene, gitleaks secret scanning, ShellCheck, yamllint,
actionlint, docs link checks and the Bats suite. Commit messages follow
Conventional Commits; `git aicommit` drafts one from the staged diff (a
tool-less `claude -p` call by default, or a local Ollama model) — see
[`config/ai-tools/README.md`](config/ai-tools/README.md).

## Documentation

Full documentation is available at **https://kevindebenedetti.github.io/dotfiles/**.
It is generated from the `docs/` directory and published by the docs hub, which picks up pushed changes within 12 hours.

## Security

To report a vulnerability, see [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE).
