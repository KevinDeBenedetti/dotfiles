---
title: VS Code
---

# VS Code

VS Code settings, recommended extensions, and MCP server configuration.

## Location

| File                            | Installed to                   | Method                               |
| ------------------------------- | ------------------------------ | ------------------------------------ |
| `config/vscode/settings.json`   | `<VS Code User>/settings.json` | symlink¹                             |
| `config/vscode/mcp.json`        | `<VS Code User>/mcp.json`      | symlink¹                             |
| `config/vscode/extensions.json` | —                              | read to install each recommendation¹ |

¹ Only when the `code` CLI is on `PATH`. `<VS Code User>` is
`~/Library/Application Support/Code/User` on macOS and `~/.config/Code/User` on
Debian. Each extension listed in `extensions.json` is installed with
`code --install-extension` unless it already is.

## Settings

### Visuals

| Setting        | Value                                                     |
| -------------- | --------------------------------------------------------- |
| Color theme    | GitHub Dark Default (dark) / GitHub Light Default (light) |
| Icon theme     | Material Icon Theme                                       |
| Editor font    | Input Mono, Fira Code, monospace                          |
| Terminal font  | Hack Nerd Font Mono                                       |
| Font ligatures | `ss01`, `ss02`, `ss03`, `ss06`, `zero`                    |
| Cursor         | Phase blinking                                            |
| Minimap        | Disabled                                                  |
| Tab size       | 2                                                         |

### Editor behavior

| Setting                                  | Value        |
| ---------------------------------------- | ------------ |
| `files.autoSave`                         | `afterDelay` |
| `editor.wordWrap`                        | `on`         |
| `editor.bracketPairColorization.enabled` | `true`       |
| `git.autofetch`                          | `true`       |
| `telemetry.telemetryLevel`               | `off`        |

### Formatters

| Language   | Formatter           |
| ---------- | ------------------- |
| TypeScript | ESLint              |
| JavaScript | ESLint              |
| HTML       | ESLint              |
| Markdown   | Markdown All in One |
| YAML       | Red Hat YAML        |

### Commit messages

`github.copilot.chat.commitMessageGeneration.instructions` makes the
**Generate commit message** button of the Source Control view write
Conventional Commits only: a type from the release-please set (never
`refactor`), a header of at most 100 characters, an imperative summary, a body
of `- ` bullets, and `!` for a breaking change. The rules mirror the
`commit-types` skill (see [Skills](./skills.md)); `tests/configs.bats` keeps the
two in sync.

### Security

| Setting                                           | Value    | Effect                                                          |
| ------------------------------------------------- | -------- | --------------------------------------------------------------- |
| `security.workspace.trust.untrustedFiles`         | `prompt` | Ask before opening an untrusted file in a trusted window        |
| `terminal.integrated.enableMultiLinePasteWarning` | `auto`   | Warn before a multi-line paste the shell would run line by line |
| `chat.tools.global.autoApprove`                   | `false`  | No blanket auto-approval of agent tools                         |

### Copilot agent guardrails

Copilot follows the same hard rules as Claude Code (`config/claude/settings.json`
is the reference) and OpenCode (`config/opencode/opencode.json`):

| Rule                                                                      | Copilot mechanism                                       |
| ------------------------------------------------------------------------- | ------------------------------------------------------- |
| `git commit` / `git push` / `gh repo delete` blocked                      | `agent-guard` hook → `deny`                             |
| `gh auth token`, `git credential`, `kubectl get secret`                   | `agent-guard` hook → `deny`                             |
| `kubectl` read-only (mutating verbs blocked)                              | `agent-guard` hook → `deny`; read verbs auto-approved   |
| `terraform apply/destroy`, `gh pr merge`, `gh api`, `kubectl config view` | `agent-guard` hook → `ask`                              |
| Secrets never read/written (`.env.example` allowed)                       | `agent-guard` hook → `deny` + edits never auto-approved |

Secrets = `.env`, `.env.*`, `*.env`, `*.pem`, `*.key`, everything under
`~/.ssh` except `*.pub` / `config` / `config.d/` / `known_hosts`, `~/.aws`,
`~/.gnupg`, `~/.kube/config`, `~/.config/dotfiles/env.local.sh`, `~/.netrc`,
`~/.npmrc`, `~/.claude/.credentials.json`.

Terminal auto-approval never covers universal prefixes (`command`, `npx`,
`bunx`, bare `docker` or `go`), and edits to the guardrail and live config
folders (`config/claude`, `config/copilot`, `config/vscode`, `config/shell`, …)
always ask, since Copilot has no sandbox.

| File                                    | Installed to                        | Method  |
| --------------------------------------- | ----------------------------------- | ------- |
| `config/copilot/hooks/agent-guard.json` | `~/.copilot/hooks/agent-guard.json` | symlink |
| `config/copilot/hooks/agent-guard.sh`   | `~/.copilot/hooks/agent-guard.sh`   | symlink |

Copilot has no OS sandbox and its tool names differ from Claude Code's, so the
hook is tool-agnostic: it inspects `tool_input.command` and every path-like
argument. It needs `jq` and fails closed without it. Hooks are enabled by
`chat.useHooks`. Keep the three configs in sync when changing a rule.

## Extensions

| Extension                                     | Category       |
| --------------------------------------------- | -------------- |
| `mechatroner.rainbow-csv`                     | CSV            |
| `ms-vscode-remote.remote-containers`          | Remote         |
| `coder.coder-remote`                          | Remote         |
| `ms-vsliveshare.vsliveshare`                  | Collaboration  |
| `oderwat.indent-rainbow`                      | General        |
| `pflannery.vscode-versionlens`                | General        |
| `wmaurer.change-case`                         | General        |
| `rangav.vscode-thunder-client`                | API            |
| `gruntfuggly.todo-tree`                       | General        |
| `github.vscode-github-actions`                | GitHub Actions |
| `GitHub.vscode-pull-request-github`           | Git            |
| `vivaxy.vscode-conventional-commits`          | Git            |
| `ms-kubernetes-tools.vscode-kubernetes-tools` | Kubernetes     |
| `shd101wyy.markdown-preview-enhanced`         | Markdown       |
| `yzhang.markdown-all-in-one`                  | Markdown       |
| `tomoki1207.pdf`                              | PDF            |
| `prisma.prisma`                               | ORM            |
| `GitHub.github-vscode-theme`                  | Theme          |
| `pkief.material-icon-theme`                   | Theme          |

## MCP servers

| Server     | Type  | Description                                                 |
| ---------- | ----- | ----------------------------------------------------------- |
| `context7` | HTTP  | Context7 documentation API (`https://mcp.context7.com/mcp`) |
| `shadcn`   | stdio | shadcn/ui component registry (`npx shadcn@4.11.0 mcp`)      |

The `CONTEXT7_API_KEY` header comes from the `context7-api-key` input (`password: true`):
VS Code prompts for it once and keeps it in its secret storage, so it is never
exported to the shell environment.
