---
title: Agent Skills
---

# Agent Skills

Shared skills for AI coding assistants, exposed to **Claude Code**, **OpenCode**
and **VS Code Copilot** from a single location.

## Location

| Source                  | Installed to               | Method              |
| ----------------------- | -------------------------- | ------------------- |
| `config/skills/<name>/` | `~/.claude/skills/<name>/` | symlink (per skill) |

Each skill folder is symlinked **individually** — never the `skills/` directory
itself. Claude Code manages its own `synced/` and `.trash/` subdirectories
inside `~/.claude/skills/`, and a directory-level symlink would clobber them.

## Why `~/.claude/skills/` is the pivot

| Tool            | Reads `~/.claude/skills/` | Mechanism                                                                              |
| --------------- | ------------------------- | -------------------------------------------------------------------------------------- |
| Claude Code     | yes (native)              | personal skills location                                                               |
| OpenCode        | yes                       | Claude Code compatibility layer (disable with `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1`) |
| VS Code Copilot | yes                       | personal skills (also reads `~/.agents/skills/` and `~/.copilot/skills/`)              |

One symlink per skill therefore shares it with all three tools at once.

## Writing an interoperable skill

A skill is a folder with a `SKILL.md` whose YAML frontmatter follows the
[Agent Skills spec](https://agentskills.io). Fields all three tools understand:

| Field         | Constraint                                                         |
| ------------- | ------------------------------------------------------------------ |
| `name`        | `^[a-z0-9]+(-[a-z0-9]+)*$`, 1–64 chars, must match the folder name |
| `description` | 1–1024 chars, keyword-rich — this is what tools match on           |

Rules to stay portable:

- Only `name` and `description` are required; unknown fields are silently
  ignored by some tools, so avoid tool-specific extras in shared skills.
- No Claude-only placeholders (`${CLAUDE_SKILL_DIR}`, `!`command`` injection
  syntax) — reference bundled files with relative paths (`./`).
- Keep `SKILL.md` under ~500 lines; move bulk content to adjacent files in the
  skill folder.

## Existing skills

| Skill               | Purpose                                                                     |
| ------------------- | --------------------------------------------------------------------------- |
| [`commit-types`](#) | Conventional Commits format and type for every commit message               |
| [`readme`](#)       | Generate or restructure a `README.md` to the canonical repo architecture    |
| [`docs-hub`](#)     | Edit `docs/` following the kevindebenedetti.github.io hub contract          |

They also run without being asked:

- the Claude Code `Stop` hook asks for `docs-hub` / `readme` when code changed
  but the docs did not (see [Claude Code](./claude-code.md));
- VS Code's *Generate commit message* button follows the same Conventional
  Commits rules as `commit-types` (see [VS Code](./vscode.md)).

## Shared commands

Slash commands shared by the three tools live in `config/commands/<name>.md` —
**edit them there only**. `os/helpers/links.sh` links each file into every
tool's command directory:

| Tool            | Linked to                                 | Invoke                         |
| --------------- | ----------------------------------------- | ------------------------------ |
| Claude Code     | `~/.claude/commands/<name>.md`            | `/next-task`, `/next-task all` |
| OpenCode        | `~/.config/opencode/commands/<name>.md`   | `/next-task`, `/next-task all` |
| VS Code Copilot | `<VS Code User>/prompts/<name>.prompt.md` | `/next-task`, `/next-task all` |

Portability rules: frontmatter limited to `description` and `argument-hint`
(no `agent`: its values differ per tool), and `$ARGUMENTS` is written so the
model falls back to the text typed after the command (Copilot does not
substitute it). Run edit-capable modes (OpenCode **Build**, Copilot **Agent**),
not plan/ask. Claude-only commands stay in `config/claude/commands/`.

## Global rules fallback

OpenCode reads `~/.claude/CLAUDE.md` as a global-rules fallback (after its own
`~/.config/opencode/AGENTS.md`), and project-level `CLAUDE.md` files too — so
Claude-style rules keep working there without duplication.

## Scope boundaries

| Layer                | Location                               | Managed by          |
| -------------------- | -------------------------------------- | ------------------- |
| Personal (this repo) | `config/skills/` → `~/.claude/skills/` | dotfiles symlink    |
| Project              | `<repo>/.claude/skills/`               | each repository     |
| Published            | plugin / registry                      | the publishing tool |

MCP servers are configured per-tool (see `config/vscode/mcp.json`) and are out
of scope for this sharing mechanism.
