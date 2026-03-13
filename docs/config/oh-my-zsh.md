# Oh My Zsh Theme

A minimal custom Oh My Zsh theme with git integration.

## Location

| File                                            | Symlinked to                                       |
| ----------------------------------------------- | -------------------------------------------------- |
| `config/oh-my-zsh/kevin-de-benedetti.zsh-theme` | `~/.oh-my-zsh/themes/kevin-de-benedetti.zsh-theme` |

## Prompt layout

```
<dir> (<branch>) ❯
```

| Segment           | Description                                 |
| ----------------- | ------------------------------------------- |
| `%c`              | Current directory name (bold cyan)          |
| `git_prompt_info` | Branch name with dirty/clean indicator      |
| `❯`               | Green on success, red on non-zero exit code |
| Right prompt      | Current time `HH:MM` (grey)                 |

## Git status indicators

| Symbol   | Meaning                                  |
| -------- | ---------------------------------------- |
| `✗`      | Dirty working tree (uncommitted changes) |
| _(none)_ | Clean working tree                       |

## Theme reference

```zsh
# Set in .zshrc
ZSH_THEME="kevin-de-benedetti"
```
