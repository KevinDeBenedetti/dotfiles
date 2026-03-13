# VS Code

VS Code settings, recommended extensions, and MCP server configuration.

## Location

| File                            | Symlinked to                          | Description            |
| ------------------------------- | ------------------------------------- | ---------------------- |
| `config/vscode/settings.json`   | `~/.config/Code/User/settings.json`   | Editor settings        |
| `config/vscode/extensions.json` | `~/.config/Code/User/extensions.json` | Recommended extensions |
| `config/vscode/mcp.json`        | `~/.config/Code/User/mcp.json`        | MCP servers            |

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

### GitHub Copilot

Copilot is enabled for all file types except plain text and SCM input. Custom instruction
files are loaded for commit messages, pull request descriptions, and code reviews from
`~/.config/dotfiles/copilot/instructions/`.

## Extensions

| Extension                                     | Category       |
| --------------------------------------------- | -------------- |
| `mechatroner.rainbow-csv`                     | CSV            |
| `ms-vscode-remote.remote-containers`          | Remote         |
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

| Server     | Type | Description                                                 |
| ---------- | ---- | ----------------------------------------------------------- |
| `github`   | HTTP | GitHub Copilot MCP (`https://api.githubcopilot.com/mcp/`)   |
| `context7` | HTTP | Context7 documentation API (`https://mcp.context7.com/mcp`) |

The `CONTEXT7_API_KEY` for the Context7 server is read from the environment variable set in `env.sh` / `env.local.sh`.
