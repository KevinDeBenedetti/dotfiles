# AGENTS.md

Personal macOS / Debian dotfiles and bootstrap scripts. Tool-neutral guide for
AI coding agents (Claude Code, OpenCode, VS Code Copilot). Claude Code reaches
it through [`CLAUDE.md`](CLAUDE.md).

## Commands

Run `make ci` before declaring a change done (`make submodules` first on a
fresh clone; `make help` lists every target). Docker targets
(`docker-test-*`) are slow integration runs: only on request.

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

Shared skills in `config/skills/` (`commit-types`, `readme`, `docs-hub`,
`todo-md`, `manual-steps`) load automatically in every tool. Use them instead
of improvising. The shared `/next-task` command (`config/commands/`) works a
project's `TODO.md` with `todo-md`, and `/next-task manual` guides the owner
through its manual steps with `manual-steps`. `/next-issue` is its twin over
GitHub issues, and the one this repository uses. `/audit` inspects the whole
repository, read-only, and files its findings as `needs-triage` issues.
`/new-issue` files the owner's own requests as issues, grouped by change.

Rules for editing skills: edit them in `config/skills/<name>/` only (never in
`~/.claude/skills/`), keep frontmatter to `name` + `description`, no
tool-specific syntax, `SKILL.md` under ~500 lines. See `docs/config/skills.md`;
update its "Existing skills" table when adding one.

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

## Agent skills

### Issue tracker

Tickets are GitHub issues of this public repository, worked by `/next-issue`; write there only what could go in a commit. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), plus `urgent` and `done` (finished by an agent, waiting for the owner's commit). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root, created only when needed. See `docs/agents/domain.md`.
