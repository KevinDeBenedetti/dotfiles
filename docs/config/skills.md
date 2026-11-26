---
title: Agent Skills
---

# Agent Skills

Skills for AI coding assistants, written once and exposed to **Claude Code**,
**OpenCode** and **VS Code Copilot**. The slash commands are skills too.

## Location

| Source                           | Installed to                             | Method              |
| -------------------------------- | ---------------------------------------- | ------------------- |
| `config/skills/<name>/`          | `~/.claude/skills/<name>/`               | symlink (per skill) |
| `config/skills/<name>/`          | `~/.copilot/skills/<name>/`              | symlink (per skill) |
| `config/skills/<name>/SKILL.md`¹ | `~/.config/opencode/commands/<name>.md`  | symlink             |
| `config/agents/AGENTS.md`        | `~/.claude/AGENTS.md`                    | symlink             |
| `config/claude/CLAUDE.md`        | `~/.claude/CLAUDE.md`                    | symlink             |
| `config/agents/AGENTS.md`        | `~/.config/opencode/AGENTS.md`           | symlink             |
| `config/agents/AGENTS.md`        | `~/.copilot/copilot-instructions.md`     | symlink             |

> ¹ Only for a [user-invoked](#invocation) skill.

Each skill folder is symlinked **individually** — never a `skills/` directory
itself. Claude Code manages its own `synced/` and `.trash/` subdirectories
inside `~/.claude/skills/`, and a directory-level symlink would clobber them.

`os/helpers/links.sh` also removes the links an earlier version left in
`~/.claude/commands/`, `~/.config/opencode/commands/` and VS Code's `prompts/`
folder to the former `config/commands/` and `config/claude/commands/`
directories. Run `scripts/symlink.sh` after pulling a change that adds, renames
or removes a skill.

## Which directory each tool reads

| Tool                              | `~/.claude/skills/` | `~/.copilot/skills/` |
| --------------------------------- | ------------------- | -------------------- |
| Claude Code                       | yes (native)        | no                   |
| OpenCode                          | yes (Claude compat) | no                   |
| VS Code, Copilot session          | not documented      | yes                  |
| VS Code, Claude session           | yes                 | not documented       |
| VS Code, Local session (retiring) | yes                 | yes                  |

Two links per skill therefore cover the three tools. A VS Code **Local**
session reads both directories and lists every skill twice; VS Code is
retiring that session type, and its documentation asks for prompt files to
become skills (see
[Migrate Copilot customizations](https://code.visualstudio.com/docs/agent-customization/migrate-customizations)).
`~/.agents/skills/` is left out on purpose: OpenCode reads it as well as
`~/.claude/skills/` and would list every skill twice. Disable OpenCode's
Claude compatibility with `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1`.

## Invocation

Every skill is one of two kinds:

| Kind          | Reached by                         | Frontmatter                                                         |
| ------------- | ---------------------------------- | ------------------------------------------------------------------- |
| model-invoked | the agent, when the work matches   | `name`, `description`                                               |
| user-invoked  | you, typing `/<name>`              | plus `disable-model-invocation: true` and the two `opencode/*` keys |

```markdown
---
name: next-issue
description: Work the next GitHub issue of the project, verify it and propose a commit.
argument-hint: "[all | N | #number]"
disable-model-invocation: true
metadata:
  opencode/slash: "false"
  opencode/autoinvoke: "false"
---
```

- Claude Code and VS Code read `disable-model-invocation`: the skill leaves the
  model's reach and stays in the `/` menu.
- OpenCode ignores that key. `opencode/autoinvoke: "false"` keeps the skill out
  of its model's reach, and `/<name>` comes from the command file linked to the
  same `SKILL.md`; `opencode/slash: "false"` keeps a version of OpenCode that
  lists skills as commands from listing it twice.
- `argument-hint` is shown in the `/` menu. `$ARGUMENTS` is written so the
  model falls back to the text typed after the command (VS Code does not
  substitute it).

Run the workflow commands in an edit-capable mode (OpenCode **Build**, Copilot
**Agent**), not plan or ask.

## Writing an interoperable skill

A skill is a folder with a `SKILL.md` whose YAML frontmatter follows the
[Agent Skills spec](https://agentskills.io):

| Field         | Constraint                                                         |
| ------------- | ------------------------------------------------------------------ |
| `name`        | `^[a-z0-9]+(-[a-z0-9]+)*$`, 1–64 chars, must match the folder name |
| `description` | 1–1024 chars: what it is, then the cases that should trigger it    |

Rules to stay portable:

- No frontmatter key beyond the ones of [Invocation](#invocation):
  `tests/configs.bats` fails on any other.
- No Claude-only placeholders (`${CLAUDE_SKILL_DIR}`, `!`command`` injection
  syntax) — reference bundled files with relative paths (`./`).
- A skill reaches another by naming it ("load the `git-workflow` skill"). Only
  a model-invoked skill can be reached that way.
- Keep `SKILL.md` under ~500 lines; move what only some runs need to a file
  beside it (`git-workflow/rebase.md`, `tdd/tests.md`).

The `writing-for-agents` skill holds the full method.

## Existing skills

### Model-invoked: the owner's conventions

| Skill                                             | Purpose                                                                    |
| ------------------------------------------------- | -------------------------------------------------------------------------- |
| [`commit-types`](#)                               | Conventional Commits format and type for every commit message, in English  |
| [`git-workflow`](./git-workflow.md)               | Branch, commit, push and pull request handed over as runnable commands     |
| [`readme`](#)                                     | Generate or restructure a `README.md` to the canonical repo architecture   |
| [`docs-hub`](#)                                   | Edit `docs/` following the kevindebenedetti.github.io hub contract         |
| [`todo-md`](./todo-workflow.md)                   | English-only format of a project's `TODO.md`, used by `/next-task`         |
| [`manual-steps`](./todo-workflow.md#manual-steps) | Guided chat through a `TODO.md`'s manual steps, run by `/next-task manual` |
| [`debug-action`](#)                               | Find the cause of a failing GitHub Actions run before changing anything    |

### Model-invoked: engineering

Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) (MIT,
notice in `config/skills/NOTICE.md`), rewritten for these conventions: the
owner commits, the wording is tool-neutral, and `code-review` takes
uncommitted work.

| Skill                | Purpose                                                                         |
| -------------------- | ------------------------------------------------------------------------------- |
| `diagnosing-bugs`    | Red loop first, then minimise, hypothesise, probe, fix behind a regression test |
| `tdd`                | One failing test, then the least code that passes it, at seams agreed first     |
| `code-review`        | Two-axis review of a diff (Standards, Spec), uncommitted work included          |
| `grilling`           | Interview in rounds of numbered questions, each with a recommended answer       |
| `codebase-design`    | Vocabulary of deep modules: interface, seam, adapter, depth                     |
| `domain-modeling`    | Settle terms in `GLOSSARY.md`, record hard-to-reverse decisions as ADRs         |
| `prototype`          | Throwaway code that answers one design question                                 |
| `research`           | Check a claim against primary sources and cite each finding                     |
| `writing-for-agents` | How to write a skill, an `AGENTS.md` or any document an agent reads             |

### User-invoked: the commands

| Command                                                      | Purpose                                                                           |
| ------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| [`/next-task`](./todo-workflow.md)                           | Work a project's `TODO.md`; `manual` guides you through its manual steps          |
| [`/next-issue`](./issue-workflow.md)                         | The same over GitHub issues, picked by label and recorded as comments             |
| [`/new-issue`](./issue-workflow.md#filing-your-own-requests) | File your own requests as issues, one per change, grouped and deduplicated        |
| [`/audit`](./issue-workflow.md#auditing-a-repository)        | Inspect a whole repository, read-only, and file findings as `needs-triage` issues |
| [`/commit`](./git-workflow.md#commit)                        | Group uncommitted changes into Conventional Commits and hand you the commands     |
| [`/pr`](./git-workflow.md)                                   | Bring the branch's pull request up to date, or hand the commands that get there   |
| [`/explain`](#)                                              | Explain a file, a command or the selection in plain terms                         |

The workflow commands load the engineering skills at fixed steps:
`/next-task` and `/next-issue` use `diagnosing-bugs`, `grilling`, `tdd` and
`code-review`; `/audit` uses one per lens.

They also run without being asked:

- in Claude Code, a `SessionStart` hook and a `UserPromptSubmit` hook name the
  skills that fit the repository and the prompt (see
  [Claude Code](./claude-code.md#skill-hooks));
- the Claude Code `Stop` hook asks for `docs-hub` / `readme` when code changed
  but the docs did not;
- VS Code's *Generate commit message* button follows the same Conventional
  Commits rules as `commit-types` (see [VS Code](./vscode.md)).

## Global rules

`config/agents/AGENTS.md` holds the rules that apply in every project: the
owner commits and pushes, everything written reads as the owner's own work,
secrets stay unread, `kubectl` is read-only. It is linked to the user-level
instruction file of each tool (table above), so the three read the same text
on every session. A project's own `AGENTS.md` / `CLAUDE.md` adds to it.

Claude Code reads it through an entry file of its own:
`config/claude/CLAUDE.md`, linked to `~/.claude/CLAUDE.md`, imports
`~/.claude/AGENTS.md` and then the files only Claude Code reads (`RTK.md`).
Its imports are home-relative (`@~/.claude/<file>.md`), since the file is
reached through a symlink. A Cowork session of the Claude desktop app skips a
`~/.claude/CLAUDE.md` that is a symlink.

An existing `~/.claude/CLAUDE.md`, `~/.config/opencode/AGENTS.md` or
`~/.copilot/copilot-instructions.md` is copied to `<file>.bak.<date>` before
the link replaces it: move what you want to keep into
`config/agents/AGENTS.md`. Every line of that file is read on every turn, and
`tests/configs.bats` caps it at 60 lines.

## Scope boundaries

| Layer                | Location                                                      | Managed by          |
| -------------------- | ------------------------------------------------------------- | ------------------- |
| Personal (this repo) | `config/skills/` → `~/.claude/skills/`, `~/.copilot/skills/`  | dotfiles symlink    |
| Project              | `<repo>/.claude/skills/`                                      | each repository     |
| Published            | plugin / registry                                             | the publishing tool |

The `mattpocock-skills` plugin stays enabled in Claude Code for its
user-invoked planning flows (`triage`, `to-spec`, `to-tickets`, `wayfinder`);
its copies of the engineering skills above are hidden from the model (see
[Claude Code](./claude-code.md#plugins)).

MCP servers are configured per-tool (see `config/vscode/mcp.json`) and are out
of scope for this sharing mechanism.
