# Claude Code

User-level Claude Code settings and the system-wide managed policy.

## Location

| File                                  | Installed to                                              | Method            |
| ------------------------------------- | --------------------------------------------------------- | ----------------- |
| `config/claude/settings.json`         | `~/.claude/settings.json`                                  | symlink           |
| `config/claude/managed-settings.json` | `/Library/Application Support/ClaudeCode/` (macOS) / `/etc/claude-code/` (Linux) | copy (root-owned) |

## Managed settings — why a copy, not a symlink

`managed-settings.json` is the highest-precedence policy file: it cannot be
overridden by user or project settings, and Claude Code expects it to be
protected by root ownership. A symlink pointing into this repo would make the
policy user-writable (any process running as the user — including Claude Code
itself — could rewrite it), defeating the protection entirely.

Install or update it with:

```sh
./scripts/install-managed-settings.sh
```

The script validates the JSON, shows a diff against the currently installed
policy, then copies it with `sudo install -o root`. Re-run it after every
change to the repo file.

The policy enforces (non-exhaustive): hard deny on `git commit`/`git push`
and on reading/writing secrets (`.env`, SSH/AWS/GnuPG keys, `*.pem`, `*.key`),
mandatory sandbox with a network domain allowlist, no unsandboxed commands,
and bypass-permissions mode disabled.

## What it contains

### Permissions

Pre-approved commands (`curl`, `git`, `gh`, `kubectl`, `docker`, …) so Claude Code
does not prompt for them, and hard denies:

- `git commit` / `git push` — commits and pushes are always done manually
- read/write/edit on any `.env` file

### Sandbox

Filesystem sandbox enabled, with `.env` files excluded from both read and write.

### Hooks

| Hook           | Purpose                                                            |
| -------------- | ------------------------------------------------------------------ |
| `PreToolUse`   | Blocks any `git commit` / `git push` command before it runs        |
| `Notification` | macOS notification when Claude Code is waiting for input           |
| `Stop`         | macOS notification when a task finishes                            |

::: warning macOS-specific hooks
The `Notification` and `Stop` hooks use `osascript`, which only exists on macOS.
On Linux they fail silently — replace them with `notify-send` if needed.
:::

## Machine-specific overrides

Per-project overrides go in `.claude/settings.local.json` inside the project
(ignored in every repo via the global gitignore — see [Git](./git.md)),
not in this file.
