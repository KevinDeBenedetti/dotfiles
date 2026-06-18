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

Filesystem sandbox enabled, with `.env` files excluded from both read and write,
plus a `network.allowedDomains` allowlist (see precedence below).

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

## Settings precedence and the sandbox allowlist

Claude Code resolves a setting from highest to lowest precedence:

1. **Managed** (`managed-settings.json`) — cannot be overridden, not even by CLI flags
2. **Command line arguments**
3. **Local** project settings (`.claude/settings.local.json`)
4. **Project** settings (`.claude/settings.json`)
5. **User** settings (`~/.claude/settings.json`)

Precedence alone doesn't tell you how a given key behaves, because keys merge
differently:

| Key kind                                    | Behaviour across scopes                                  |
| ------------------------------------------- | -------------------------------------------------------- |
| Booleans (`sandbox.enabled`, `failIfUnavailable`) | Highest-precedence value wins; lower scopes ignored |
| Arrays (`sandbox.network.allowedDomains`, `filesystem.allow*`/`deny*`, permission rules) | **Merged** — entries from every scope are unioned |

### Is `managed-settings.json` a hard ceiling for `network.allowedDomains`?

**No — not by default.** Because `allowedDomains` is an array key, the lists from
every scope are **merged (unioned)**, so a lower-precedence file *can widen* the
managed allowlist by appending hosts. Managed settings only become a hard ceiling
for network domains if they explicitly set:

```json
{ "sandbox": { "network": { "allowManagedDomainsOnly": true } } }
```

With `allowManagedDomainsOnly: true`, only the managed `allowedDomains` are
honored and any host added by user/project/local settings is ignored. (The
filesystem equivalent is `allowManagedReadPathsOnly`.)

Our `managed-settings.json` does **not** set `allowManagedDomainsOnly`, so the
allowlist remains a floor, not a ceiling: a private/VPN host kept out of the
committed config (e.g. `10.8.0.1`) can be re-authorized locally in
`~/.claude/settings.json` or `.claude/settings.local.json` and it will be unioned
with the managed list. If you ever want to *lock* the network allowlist to the
managed values, add `allowManagedDomainsOnly: true` to `managed-settings.json`
— at which point local re-authorization stops working by design.

Sources: Claude Code docs — [settings](https://code.claude.com/docs/en/settings),
[sandboxing](https://code.claude.com/docs/en/sandboxing),
[server-managed-settings](https://code.claude.com/docs/en/server-managed-settings).

## Machine-specific overrides

Per-project overrides go in `.claude/settings.local.json` inside the project
(ignored in every repo via the global gitignore — see [Git](./git.md)),
not in this file. Because the sandbox network allowlist merges across scopes
(see above), this is also where a machine-local VPN/private host can be
re-authorized without committing it.
