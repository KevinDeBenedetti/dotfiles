# AGENTS.md

Personal macOS / Debian dotfiles and bootstrap scripts. Tool-neutral guide for
AI coding agents (Claude Code, OpenCode, VS Code Copilot). Claude Code reaches
it through [`CLAUDE.md`](CLAUDE.md).

## Layout

| Path                  | Content                                                                    |
| --------------------- | -------------------------------------------------------------------------- |
| `os/macos/`, `os/debian/` | `init.sh` entrypoints and per-OS setup scripts                         |
| `os/helpers/`         | Shared shell helpers; `links.sh` symlinks `config/` into `$HOME`           |
| `config/`             | Versioned configs (git, zsh, ssh, vscode, claude, opencode, copilot, …)    |
| `config/skills/`      | Shared agent skills, one folder each, linked into `~/.claude/skills/`      |
| `config/commands/`    | Shared slash commands (Claude Code, OpenCode, Copilot)                     |
| `config/claude/`      | Claude Code `settings.json`, `managed-settings.json`, Claude-only commands |
| `scripts/`            | Tooling linked to `~/.local/bin/` (`scripts/ai/`, `scripts/ollama/`)       |
| `tests/`              | Bats suites (`tests/ai/`, `tests/ollama/` in subdirs) and Docker/Lima rigs |
| `docs/`               | Documentation site sources                                                 |

## Commands

```sh
make test      # all Bats tests (run `make submodules` first on a fresh clone)
make lint      # ShellCheck (severity=warning) on every shell script
make validate  # yamllint on .github/workflows/
make ci        # lint + validate + test
```

Run `make ci` before declaring a change done. Docker/Lima targets
(`docker-test-*`, `vm-*`) are slow integration runs: only on request.

## Conventions

- Shell scripts are Bash and must pass ShellCheck at `warning`; keep the style
  of the surrounding file (helpers are sourced, not executed).
- Every config added under `config/` must be wired in `os/helpers/links.sh` and
  covered by a test in `tests/` (`configs.bats` for existence, `links.bats` for
  symlinks).
- Agent guardrails exist in three places and must change together:
  `config/claude/settings.json` (reference), `config/opencode/opencode.json`
  (`permission`) and `config/copilot/hooks/agent-guard.sh`. Update
  `tests/agent-hooks.bats` / `tests/configs.bats` with them.
- `managed-settings.json` is installed as a root-owned **copy**
  (`scripts/install-managed-settings.sh`), never a symlink. Mention that it
  must be re-installed after editing it.
- Documentation lives in `docs/` and is the source of truth; keep `README.md`
  short and link to it.

## Skills

Shared skills in `config/skills/` load automatically in every tool. Use them
instead of improvising:

| Skill          | Use it when                                                                                      |
| -------------- | ------------------------------------------------------------------------------------------------ |
| `commit-types` | Writing or reviewing a commit message, or choosing a Conventional Commits type. `refactor` is never emitted by the release config: use `chore`. |
| `readme`       | Creating, rewriting or auditing a `README.md`.                                                   |
| `docs-hub`     | Adding, editing or auditing anything under `docs/` (published on the kevindebenedetti.github.io hub), or updating docs after a code/config change. |

Rules for editing skills: edit them in `config/skills/<name>/` only (never in
`~/.claude/skills/`), keep frontmatter to `name` + `description`, no
tool-specific syntax, `SKILL.md` under ~500 lines. See `docs/config/skills.md`;
update its "Existing skills" table when adding one.

Shared commands (`config/commands/`): `/next-task` works the project's
`TODO.md`; `/next-task all` drains it.

## Guardrails (hard rules)

- **Never run `git commit` or `git push`.** The owner commits and pushes
  manually. Propose a message (following `commit-types`) instead.
- **Never read or write secrets**: `.env*`, `*.pem`, `*.key`, `~/.ssh`,
  `~/.aws`, `~/.gnupg`. Hand over the values to paste instead.
- **Never commit infrastructure details** (real IPs, host names): SSH hosts go
  in the local, unversioned `~/.ssh/config.d/`. This repository is public.
- **No local LLM inference**: do not run `ollama run/generate`, `git aicommit`
  or other `scripts/ai/` commands that call a model. Give the command to the
  owner.
- `kubectl` is read-only for agents; mutating verbs are denied.
- **Dev ports**: follow the slot convention in `~/.claude/dev-ports.md`
  when a project publishes host ports.
