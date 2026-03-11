# Debian Setup

Personal Debian VPS dotfiles and setup scripts powered by `apt`, [proto](https://moonrepo.dev/proto), and [Oh My Zsh](https://ohmyz.sh).

## Prerequisites

The script requires either `root` or a user with `sudo` access. It will exit early with an error if neither is available.

| Prerequisite   | Notes                                                        |
| -------------- | ------------------------------------------------------------ |
| `sudo` or root | Required to install packages and write to system directories |
| `curl`         | Used to bootstrap Oh My Zsh, proto, Helm, and k9s            |
| `git`          | Installed automatically via `apt` in the common step         |

## Installation

### Remote (fresh server)

```sh
# Full install — all profiles, dotfiles, completions
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/debian/init.sh) -a
```

The script clones the repository to `~/.dotfiles` if not already present, then re-executes from there.

### Local

```sh
# Clone
git clone https://github.com/KevinDeBenedetti/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# Full install
./os/debian/init.sh -a

# Dotfiles only
./os/debian/init.sh -d

# Specific profiles + completions
./os/debian/init.sh -p "base,kubernetes" -c
```

## Flags

| Flag            | Description                                                   |
| --------------- | ------------------------------------------------------------- |
| `-a`            | Full install: all profiles + dotfiles + completions + cleanup |
| `-p <profiles>` | Comma-separated list of profiles (e.g. `base,kubernetes`)     |
| `-d`            | Link dotfiles into `$HOME`                                    |
| `-c`            | Install zsh CLI completions                                   |
| `-l`            | Lite mode — skip optional/heavy packages                      |
| `-r`            | Remove bootstrap temp directory after install                 |
| `-h`            | Print help                                                    |

> At least one flag is required. Running without flags prints help and exits.

## Common Packages

Installed unconditionally before any profile (via `apt`):

`ca-certificates`, `curl`, `gnupg`, `gzip`, `jq`, `unzip`, `wget`, `xz-utils`, `git`, `build-essential`

[Oh My Zsh](https://ohmyz.sh) is also installed at this stage if `~/.oh-my-zsh` does not exist.

## Profiles

### `base`

Core CLI tools installed via `apt`. Split into lite (always) and additional (full mode only).

**Lite:**

| Tool                                     | Description                                     |
| ---------------------------------------- | ----------------------------------------------- |
| `docker.io` + `docker-compose`           | Container runtime and orchestration             |
| [`fzf`](https://github.com/junegunn/fzf) | Fuzzy finder for shell history, files, and more |
| `ssh`                                    | OpenSSH client                                  |
| `tree`                                   | Directory tree visualizer                       |
| `watch`                                  | Repeat a command at intervals                   |
| [`yq`](https://mikefarah.gitbook.io/yq)  | Portable YAML/JSON/TOML processor               |
| `rsync`                                  | Incremental file transfer                       |

**Additional (full mode):**

| Tool                                  | Description                                                                  |
| ------------------------------------- | ---------------------------------------------------------------------------- |
| [`gh`](https://cli.github.com)        | GitHub CLI — PRs, issues, repos from the terminal                            |
| `nmap`                                | Network exploration and port scanning                                        |
| [`proto`](https://moonrepo.dev/proto) | Multi-language toolchain version manager (installed via curl if not present) |

### `kubernetes`

Tools for Kubernetes cluster management.

**Lite:**

| Tool                                                       | Description                                                                                      |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| [`kubectl`](https://kubernetes.io/docs/reference/kubectl/) | Kubernetes command-line client (installed from the official `pkgs.k8s.io` repo, currently v1.32) |

**Additional (full mode):**

| Tool                       | Description                                                               |
| -------------------------- | ------------------------------------------------------------------------- |
| [`helm`](https://helm.sh)  | Kubernetes package manager (installed via the official get-helm-3 script) |
| [`k9s`](https://k9scli.io) | Terminal UI for Kubernetes clusters (latest release fetched from GitHub)  |

## Dotfiles Linking

Running `-d` symlinks (or copies) config files from the repository into `$HOME`. Any existing file is backed up with a datestamp (e.g. `~/.zshrc.bak.20260311`) before being replaced.

| Source                         | Target                              | Method                           |
| ------------------------------ | ----------------------------------- | -------------------------------- |
| `config/zsh/.zshrc`            | `~/.zshrc`                          | copy¹                            |
| `config/git/.gitconfig`        | `~/.gitconfig`                      | symlink                          |
| `config/proto/.prototools`     | `~/.proto/.prototools`              | symlink                          |
| `config/oh-my-zsh/*.zsh-theme` | `~/.oh-my-zsh/custom/themes/`       | symlink                          |
| `config/shell/*`               | `~/.config/dotfiles/`               | symlink                          |
| `config/vscode/settings.json`  | `~/.config/Code/User/settings.json` | symlink (if `code` is available) |
| `config/vscode/mcp.json`       | `~/.config/Code/User/mcp.json`      | symlink (if `code` is available) |

> ¹ `.zshrc` is copied rather than symlinked so machine-specific patches can be applied without affecting the tracked file.

### Local override stubs

The `-d` step also creates the following stub files if they do not already exist. They are never tracked by git and always take precedence:

| File                              | Purpose                                                          |
| --------------------------------- | ---------------------------------------------------------------- |
| `~/.zshrc.local`                  | Machine-specific zsh aliases, exports, and path additions        |
| `~/.gitconfig.local`              | Machine-specific git overrides (e.g. `user.email`, `signingkey`) |
| `~/.config/dotfiles/env.local.sh` | Machine-specific environment variable overrides                  |

### SSH allowed signers

If `~/.ssh/id_rsa.pub` exists, the script automatically creates `~/.ssh/allowed_signers` for local SSH commit signature verification.

## Completions

Running `-c` installs zsh completions for:

| Tool                                                              | Source                                                    |
| ----------------------------------------------------------------- | --------------------------------------------------------- |
| `gh`                                                              | `gh completion -s zsh`                                    |
| `proto`                                                           | `proto completions --shell zsh`                           |
| `uv`                                                              | `uv generate-shell-completion zsh`                        |
| [`zsh-completions`](https://github.com/zsh-users/zsh-completions) | Cloned into Oh My Zsh custom plugins and added to `fpath` |

Completions are written to `/usr/local/share/zsh/site-functions` (with `sudo` when not root).

## Useful `apt` Commands

```sh
# Refresh package index
sudo apt-get update

# Upgrade all installed packages
sudo apt-get upgrade

# Install a package without recommended extras
sudo apt-get install -y --no-install-recommends <package>

# Search for a package
apt-cache search <keyword>

# Remove a package and its config
sudo apt-get purge <package> && sudo apt-get autoremove
```

## Common Issues

**`sudo` not available on a fresh VPS:**

```sh
# As root, install sudo and add your user
apt-get install -y sudo
usermod -aG sudo <username>
# Then log out and back in
```

**Docker daemon not started after install:**

```sh
sudo systemctl enable docker
sudo systemctl start docker
# Allow current user to run docker without sudo
sudo usermod -aG docker $USER
```

**`kubectl` not found after install:**

```sh
# Verify the apt source was added correctly
cat /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubectl
```
