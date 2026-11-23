---
title: Claude Code
---

# Claude Code

User-level Claude Code settings and the system-wide managed policy.

## Location

| File                                  | Installed to                                                                     | Method            |
| ------------------------------------- | -------------------------------------------------------------------------------- | ----------------- |
| `config/claude/settings.json`         | `~/.claude/settings.json`                                                        | symlink           |
| `config/claude/managed-settings.json` | `/Library/Application Support/ClaudeCode/` (macOS) / `/etc/claude-code/` (Linux) | copy (root-owned) |
| `config/claude/commands/*`            | `~/.claude/commands/`                                                            | symlink           |
| `config/claude/hooks/*`               | `~/.claude/hooks/`                                                               | symlink           |

> Shared agent skills (also read by OpenCode and VS Code Copilot) live in
> `config/skills/` and are linked into `~/.claude/skills/` — see
> [Skills](./skills.md).

> This file is the **reference** for agent guardrails. OpenCode
> (`config/opencode/opencode.json` → `permission`) and VS Code Copilot
> (`config/copilot/hooks/agent-guard.sh`, see [VS Code](./vscode.md)) mirror
> its denies (commit/push, mutating kubectl, secrets) and asks — update all
> three together. `tests/agent-hooks.bats` fails when one of this file's Bash
> denies is missing from OpenCode or from the Copilot guard, or when a file
> denied for reading can still be edited.

## Project instructions (`AGENTS.md` / `CLAUDE.md`)

The repo root carries its own agent instructions: `AGENTS.md` is the
tool-neutral source (read natively by OpenCode and Copilot), and `CLAUDE.md`
only imports it with `@AGENTS.md` (Claude Code does not read `AGENTS.md` on its
own) and adds Claude-specific notes, including when to invoke the shared
skills. Edit `AGENTS.md`, not `CLAUDE.md`, for anything that applies to every
tool.

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

The policy enforces (non-exhaustive): hard deny on `git commit`/`git push`, on
reading/writing secrets (`.env` variants, `*.pem`, `*.key`, everything under
`~/.ssh` except public keys and client config, `~/.aws`, `~/.gnupg`,
`~/.kube/config`, `~/.config/dotfiles/env.local.sh`) and on printing stored
tokens (`gh auth token`, `git credential`); mandatory sandbox with a network
domain allowlist, no unsandboxed commands, and bypass-permissions mode disabled.

## What it contains

### Attribution

`"attribution": {"commit": "", "pr": ""}` turns off the footer Claude Code
adds by default: the `Co-Authored-By` trailer on commits and the
"Generated with Claude Code" line on pull request descriptions. Both keys
must be present: a missing key falls back to the default footer. Issues and
comments have no setting; the "no AI attribution" rule in `AGENTS.md`
covers them.

### Permissions

`permissions.defaultMode` is `auto`: a classifier reviews routine actions
(shell commands, web fetches, file edits) instead of prompting, and blocks what
strays from the request. It only takes effect from user settings, never from a
project's `.claude/settings.json`. Deny rules, `ask` rules and the sandbox
apply unchanged, and `AskUserQuestion` still waits for an answer. `Shift+Tab`
switches mode for one session; `/permissions` → *Recently denied* retries an
action the classifier refused.

Pre-approved commands (`curl`, `git`, `docker`, read-only `gh` and `kubectl`, …)
so neither the classifier nor a prompt is involved, and hard denies:

- `git commit` / `git push` — commits and pushes are always done manually
- mutating `kubectl` verbs (`apply`, `delete`, `exec`, …) — kubectl is read-only
- read/write/edit on any `.env` file
- reading anything under `~/.ssh` except `*.pub`, `config`, `config.d/` and
  `known_hosts` (private keys are not all named `id_*`), `~/.kube/config` and
  `~/.config/dotfiles/env.local.sh`
- `gh auth token`, `git credential …` (print stored tokens) and
  `kubectl get secret(s)`

`gh` is pre-approved for read-only subcommands (`gh pr view`, `gh run list`,
…), plus the three issue writes [`/next-issue`](./issue-workflow.md) needs:
`gh issue comment`, `gh issue edit` and `gh issue create`. Closing or deleting
an issue is not among them. These ask first: `gh api` (it can push, merge or delete
through the REST API), `gh pr merge`, `terraform apply` / `destroy` and
`kubectl config view`.

The `rtk hook claude` hook rewrites many commands before the rules are matched
(`git status` → `rtk git status`, `cat f` → `rtk read f`, `gh api …` →
`rtk gh api …`), so every Bash rule has an `rtk` twin in the same list
(`Bash(rtk git *)`, `Bash(rtk gh api *)` in ask, `Bash(rtk git push *)` in
deny, …); `tests/configs.bats` enforces it. `kubectl` read verbs are also
allowed with leading flags (`Bash(kubectl * get *)` matches `kubectl -n vault
get pods`): mutating verbs and Secret reads stay denied by the hooks whatever
precedes them.

### Sandbox

Filesystem sandbox enabled, with `.env` files and the secrets above excluded,
plus a `network.allowedDomains` allowlist (see precedence below). Tool caches
(`~/.cache`, Go's build and module caches, bun's install cache) are writable,
so tools use their normal caches instead of Claude redirecting them through
`PATH=` / `*_CACHE=` prefixes, which no allow rule can match.

`sandbox.enableWeakerNetworkIsolation` is on: without it, Go tools such as
`gh` cannot verify TLS certificates inside the macOS sandbox
(`x509: OSStatus -26276`), and `/next-issue` needs `gh`. It weakens the
sandbox (see the
[sandboxing documentation](https://code.claude.com/docs/en/sandboxing)); `gh`
itself stays sandboxed and bound by the permission rules.

::: warning
Configs linked into `$HOME` are executed outside the sandbox (shell rc files,
LaunchAgent, Copilot hook, scripts on `PATH`). Link them from a clean checkout
that agents cannot write — `~/.dotfiles`, denied in `sandbox.filesystem.denyWrite`
— not from the working copy agents edit:

```sh
git clone https://github.com/KevinDeBenedetti/dotfiles.git ~/.dotfiles
~/.dotfiles/os/macos/init.sh -d
```

Changes made in the working copy go live only after review, commit and
`git -C ~/.dotfiles pull`.
:::

### Hooks

| Event              | Command              | Purpose                                                                                                            |
| ------------------ | -------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `PreToolUse`       | inline `jq` + `grep` | Blocks `git commit` / `git push`, including wrapped (`bash -c`, `$(…)`) and `-c`/`-C` forms                        |
| `PreToolUse`       | inline `jq` + `grep` | Blocks mutating `kubectl` verbs — kubectl is read-only for agents                                                  |
| `PreToolUse`       | inline `jq` + `grep` | Blocks `kubectl … get secret(s)` whatever the flags, namespace or `rtk` prefix — deny rules only match plain forms |
| `PreToolUse`       | `rtk hook claude`    | Rewrites Bash commands through `rtk` for token-optimized output                                                    |
| `Stop`             | `docs-sync-check.sh` | Code changed but neither `docs/` nor `README.md` did → asks for the `docs-hub` / `readme` skills, once per turn    |
| `Stop`             | `next-steps.sh`      | Shows the next steps (branch, re-stage, commit, push, `/pr`, blocked or next task, triage) and `🖐 Manual` steps    |
| `SessionStart`     | `skill-context.sh`   | Tells Claude when to use the `mattpocock-skills` skills unasked, and to branch off a shared branch first           |
| `UserPromptSubmit` | `skill-router.sh`    | Names the skills a prompt matches (at most two); after your commit or push from the chat, the next git step        |

The `git commit` / `git push` and `kubectl … get secret(s)` hooks are also in
`managed-settings.json`. These regex hooks catch mistakes, not a determined
bypass: the sandbox and the secret deny rules are the actual security boundary.

Hook scripts live in `config/claude/hooks/` and are linked into
`~/.claude/hooks/`. A hook cannot invoke a skill itself: `docs-sync-check.sh`
blocks the end of the turn with a reason naming the skills, and lets the next
stop through (`stop_hook_active`), so it never loops.

`next-steps.sh` never blocks. It reads the git state and the project's
`TODO.md` ([TODO Workflow](./todo-workflow.md)) and returns a `systemMessage`,
which Claude Code shows to you and does not send to Claude, so it costs no
extra turn; it must stay synchronous, since an async hook hands its message to
Claude instead. A message shows once per session, then again only when it
changes. On a shared branch (`main`, `master`, `dev`, `develop` or the
remote's default) with changes or unpushed commits, it asks for a branch
first, in place of a push; elsewhere it gives the push command, with `-u` on a
branch's first push; once a branch of its own is committed and pushed, it
points to `/pr` for the pull request (see [Git Workflow](./git-workflow.md)).
Two variables, set in the `env` block, tune it:

| Variable                     | Default   | Effect                                                    |
| ---------------------------- | --------- | --------------------------------------------------------- |
| `DOTFILES_NEXT_STEPS`        | `changed` | `always` shows the message after every turn, `off` never  |
| `DOTFILES_NEXT_STEPS_MANUAL` | `10`      | Manual steps listed before "… N more"; `0` lists them all |

#### Skill hooks

Two hooks make Claude reach for the `mattpocock-skills` skills (see
Plugins below) during ordinary work, not only when you type their slash
command. Both return `additionalContext`, which Claude reads with the session
or the prompt; neither blocks anything, and both stay silent when the plugin is
not enabled, except for the two git lines below, which come from the
`git-workflow` skill of this repository.

- `skill-context.sh` runs at session start, after `/clear` and after a
  compaction. It gives the standing policy: `diagnosing-bugs` before fixing a
  reported failure, `codebase-design` for a new or reshaped module,
  `code-review` on a multi-file change before the commit is proposed,
  `writing-for-agents` for `SKILL.md` / `AGENTS.md` / `CLAUDE.md`, `pr` for a
  pull request body. It adds what fits the repository's tracked files: `tdd`
  when there is a test suite, `domain-modeling` when there is a `GLOSSARY.md`
  or `docs/adr/`, the `audit` command when there is infrastructure (Terraform,
  Ansible, Helm, Kustomize, Kubernetes manifests, Docker), `debug-action` when
  there are GitHub workflows, `/next-task` when there is a `TODO.md`. It always
  forbids `implement` and `implement-spec`, which commit. A session that
  opens on a shared branch is told to hand you the `git checkout -b` command
  before the first commit. At startup, in a
  repository with an `AGENTS.md` or `CLAUDE.md` but no
  `docs/agents/issue-tracker.md`, it also tells you (not Claude) to run
  `/mattpocock-skills:setup-matt-pocock-skills`.
- `skill-router.sh` reads each prompt and matches it, in English or French,
  against the kinds of work the skills cover: a failure (`diagnosing-bugs`, or
  `debug-action` for a CI run), a review of changes, an infrastructure audit,
  a refactor, a plan to grill, a prototype, research, a pull request, agent
  docs, and a feature or fix in a repository with tests (`tdd`). It skips
  slash commands, replies shorter than 12 characters, prompts that already
  name a skill, and the reports of subagents and events of the app
  (`<agent-message>`, `<task-notification>`, …), which arrive as prompts but
  describe work already done. It skips too a command the owner runs in the
  app (`<bash-input>`), whose output carries no request, but one: a
  `git commit` or `git push` that went through gets its next step (the branch
  command for a commit on a shared branch, else the push, then the pull
  request's title and description).

`DOTFILES_SKILL_ROUTER=off` in the `env` block silences both.

### Plugins

Two plugins are enabled in `enabledPlugins`:

| Plugin                                      | Source                                                                                  | Ships                                                |
| ------------------------------------------- | --------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `hyperframes@hyperframes`                   | marketplace `heygen-com/hyperframes` (declared in `extraKnownMarketplaces`)             | Video skills (HTML rendered to video)                |
| `mattpocock-skills@claude-plugins-official` | Anthropic's built-in marketplace, which pins `mattpocock/skills` to a commit            | Engineering skills only (no hooks, no MCP servers)   |

Plugin hooks and MCP servers run outside the Bash sandbox, so each plugin added
is trusted with your account. Install one with
`claude plugin install <plugin>@<marketplace>`: it writes `enabledPlugins`
through the `~/.claude/settings.json` symlink into the tracked file.

`mattpocock-skills` skills are namespaced (`/mattpocock-skills:tdd`, …). Its
workflow skills (`triage`, `to-spec`, `to-tickets`, `wayfinder`) read a
per-repository setup: run `/mattpocock-skills:setup-matt-pocock-skills` once in
each repository that uses them. In this repository that setup makes GitHub
Issues their tracker, so the tickets they write are worked by `/next-issue`:
see [Issue Tracker](../agents/issue-tracker.md) and
[Issue Workflow](./issue-workflow.md). A repository whose setup names `TODO.md`
is worked by `/next-task` instead
([TODO Workflow](./todo-workflow.md#agent-skills-in-claude-code)).

Unused skills are hidden from the model through `skillOverrides` (value
`user-invocable-only`): they leave the skill listing Claude reads at the start
of every session but stay available by hand as `/<name>`. The claude.ai-synced
skills, `langfuse` and `context7-mcp` are hidden this way, which keeps the
listing within its budget so the descriptions of the visible skills are not
truncated. Delete an entry to make the skill visible again.

`disableClaudeAiConnectors: true` keeps the claude.ai connectors (Gmail, Google
Calendar, …) out of Claude Code; they stay available on claude.ai.

## Settings precedence and the sandbox allowlist

Claude Code resolves a setting from highest to lowest precedence:

1. **Managed** (`managed-settings.json`) — cannot be overridden, not even by CLI flags
2. **Command line arguments**
3. **Local** project settings (`.claude/settings.local.json`)
4. **Project** settings (`.claude/settings.json`)
5. **User** settings (`~/.claude/settings.json`)

Precedence alone doesn't tell you how a given key behaves, because keys merge
differently:

| Key kind                                                                                 | Behaviour across scopes                             |
| ---------------------------------------------------------------------------------------- | --------------------------------------------------- |
| Booleans (`sandbox.enabled`, `failIfUnavailable`)                                        | Highest-precedence value wins; lower scopes ignored |
| Arrays (`sandbox.network.allowedDomains`, `filesystem.allow*`/`deny*`, permission rules) | **Merged** — entries from every scope are unioned   |

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
