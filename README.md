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

On top of the usual hygiene/lint hooks (whitespace, shellcheck, yamllint,
actionlint) and the `pre-push` Bats suite, the **`ai-commit-msg`**
(`prepare-commit-msg`) hook pre-fills commit messages — it is consumed from the
shared [`KevinDeBenedetti/github-workflows`](https://github.com/KevinDeBenedetti/github-workflows)
repo (pinned by SHA in [`prek.toml`](prek.toml)), not maintained here:

- On a plain `git commit`, it asks the **`claude` CLI** (headless `claude -p`)
  for a [Conventional Commits](https://www.conventionalcommits.org) message
  (title + body) built from the staged diff (`git diff --cached`), and pre-fills
  the editor. You review/edit before the commit completes.
- It is **fail-open** — never blocks a commit: a no-op when a message is already
  present (`-m`, template, amend, merge), nothing is staged, or `claude` is
  missing/offline.
- Tunable via env: `AI_COMMIT_NO_AI=1`, `AI_COMMIT_MODEL` (default `sonnet`),
  `AI_COMMIT_TIMEOUT` (needs `timeout(1)`), `AI_COMMIT_MAX_CHARS`.

To use the same hook in any other repo, add it to that repo's `prek.toml`:

```toml
[[repos]]
repo = "https://github.com/KevinDeBenedetti/github-workflows"
rev  = "<commit-sha-or-tag>"
hooks = [{ id = "ai-commit-msg" }]
```

then `prek install` (installs the `prepare-commit-msg` hook type). For the editor
to pre-fill in the VS Code UI, commit with an empty SCM box (the
`git.useEditorAsCommitInput` setting opens the editor).

> Caveat: re-staging relies on `git commit` building the commit from the index
> (the normal `git add` then `git commit` flow, and `git commit -a`). With an
> explicit pathspec (`git commit TODO.md other`) git uses a temporary index, so
> the strip lands in the working tree but not that commit.

## Documentation

Full documentation is available at **https://kevindebenedetti.github.io/dotfiles/**.
It is generated from the `docs/` directory and published automatically on push.
