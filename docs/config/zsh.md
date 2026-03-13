# Zsh

Zsh shell configuration symlinked to `~/.zshrc`.

## Location

| File                | Symlinked to |
| ------------------- | ------------ |
| `config/zsh/.zshrc` | `~/.zshrc`   |

## Environment

| Variable                | Value            | Description                   |
| ----------------------- | ---------------- | ----------------------------- |
| `ZSH`                   | `~/.oh-my-zsh`   | Oh My Zsh installation path   |
| `HISTSIZE` / `SAVEHIST` | `10000`          | Shell history size            |
| `HISTFILE`              | `~/.zsh_history` | History file location         |
| `HIST_STAMPS`           | `yyyy-mm-dd`     | Date format in history output |
| `LC_ALL` / `LANG`       | `en_US.UTF-8`    | Locale                        |
| `EDITOR`                | `vim`            | Default editor                |
| `XDG_CONFIG_HOME`       | `~/.config`      | XDG config base directory     |

## Theme

```zsh
ZSH_THEME="kevin-de-benedetti"
```

See [Oh My Zsh theme](./oh-my-zsh.md) for details.

## Plugins

| Plugin              | Description                        |
| ------------------- | ---------------------------------- |
| `aliases`           | Manage shell aliases               |
| `brew`              | Homebrew completions and helpers   |
| `colored-man-pages` | Colorized `man` output             |
| `docker`            | Docker completions                 |
| `docker-compose`    | Docker Compose completions         |
| `gh`                | GitHub CLI completions             |
| `git`               | Git aliases and completions        |
| `gitignore`         | Fetch `.gitignore` templates       |
| `rsync`             | Rsync aliases                      |
| `sudo`              | Double-tap `ESC` to prepend `sudo` |

## Aliases

### Shell utilities

| Alias   | Command                                        | Description                       |
| ------- | ---------------------------------------------- | --------------------------------- |
| `cs`    | `cheat_glow`                                   | Render a cheat sheet with glow    |
| `hs`    | `history \| grep`                              | Search history                    |
| `hsi`   | `history \| grep -i`                           | Case-insensitive history search   |
| `dsp`   | `docker system prune -a -f`                    | Prune all unused Docker data      |
| `lad`   | `lazydocker`                                   | Open Lazydocker TUI               |
| `lag`   | `lazygit`                                      | Open Lazygit TUI                  |
| `pubip` | `dig +short txt ch whoami.cloudflare @1.0.0.1` | Print public IP                   |
| `bcu`   | Upgrade all outdated casks                     | Reinstall outdated Homebrew casks |

### Kubernetes

| Alias      | Command                                 |
| ---------- | --------------------------------------- |
| `k`        | `kubectl`                               |
| `kc`       | `kubectx`                               |
| `kn`       | `kubens`                                |
| `kd`       | `kubectl delete`                        |
| `kdesc`    | `kubectl describe`                      |
| `ke`       | `kubectl exec`                          |
| `kexp`     | `kubectl explain`                       |
| `kg`       | `kubectl get`                           |
| `kgpw`     | `watch 'kubectl get pod'`               |
| `kgr`      | `kubectl get pod` with resource columns |
| `kl`       | `kubectl logs`                          |
| `kcert`    | `kubectl-cert_manager`                  |
| `kcnpg`    | `kubectl-cnpg`                          |
| `kdfpv`    | `kubectl-df_pv`                         |
| `kescape`  | `kubectl-kubescape`                     |
| `kkrew`    | `kubectl-krew`                          |
| `kktop`    | `kubectl-ktop`                          |
| `kkyverno` | `kubectl-kyverno`                       |
| `kneat`    | `kubectl-neat`                          |
| `kstern`   | `kubectl-stern`                         |
| `kvs`      | `kubectl-view_secret`                   |

### macOS only

| Alias   | Description                           |
| ------- | ------------------------------------- |
| `arm`   | Switch to ARM64 (Apple Silicon) shell |
| `intel` | Switch to x86_64 (Rosetta) shell      |

## Sourced files

Loaded in order at the end of `.zshrc`:

| File                                         | Description                               |
| -------------------------------------------- | ----------------------------------------- |
| `~/.config/dotfiles/env.sh`                  | Environment variables                     |
| `~/.config/dotfiles/functions.sh`            | Utility functions                         |
| `~/.config/dotfiles/functions-completion.sh` | Completion helpers (optional)             |
| `~/.config/dotfiles/functions-dso.sh`        | DSO-specific functions (optional)         |
| `~/.config/dotfiles/env.local.sh`            | Machine-specific env vars (not tracked)   |
| `~/.zshrc.local`                             | Machine-specific zsh config (not tracked) |

## Local overrides

Machine-specific or private configuration goes in files that are not tracked by git:

- **`~/.config/dotfiles/env.local.sh`** — Extra environment variables, API keys
- **`~/.zshrc.local`** — Aliases, `PATH` additions, functions specific to this machine
