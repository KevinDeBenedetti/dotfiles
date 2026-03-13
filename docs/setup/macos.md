# macOS Setup

Personal macOS dotfiles and setup scripts powered by [Homebrew](https://brew.sh), [proto](https://moonrepo.dev/proto), and [Oh My Zsh](https://ohmyz.sh).

## Prerequisites

The init script checks for both prerequisites at startup and offers to install them automatically.

| Prerequisite             | Check             | Install                    |
| ------------------------ | ----------------- | -------------------------- |
| Xcode Command Line Tools | `xcode-select -p` | `xcode-select --install`   |
| Homebrew                 | `brew --version`  | [brew.sh](https://brew.sh) |

## Installation

### Remote (fresh machine)

```sh
# Full install — all profiles, dotfiles, completions
bash <(curl -fsSL https://raw.githubusercontent.com/KevinDeBenedetti/dotfiles/main/os/macos/init.sh) -a
```

The script clones the repository to `~/.dotfiles` if not already present, then re-executes from there. Using a permanent path ensures symlinks remain valid after reboot.

### Local

```sh
# Clone
git clone https://github.com/KevinDeBenedetti/dotfiles.git ~/.dotfiles
cd ~/.dotfiles

# Full install
./os/macos/init.sh -a

# Dotfiles only
./os/macos/init.sh -d

# Specific profiles + completions
./os/macos/init.sh -p "base,python" -c
```

## Flags

| Flag            | Description                                                   |
| --------------- | ------------------------------------------------------------- |
| `-a`            | Full install: all profiles + dotfiles + completions + cleanup |
| `-p <profiles>` | Comma-separated list of profiles (e.g. `base,javascript`)     |
| `-d`            | Link dotfiles into `$HOME`                                    |
| `-c`            | Install zsh CLI completions                                   |
| `-l`            | Lite mode — skip optional/heavy packages                      |
| `-r`            | Remove bootstrap temp directory after install                 |
| `-h`            | Print help                                                    |

> At least one flag is required. Running without flags prints help and exits.

## Profiles

### `base`

Core CLI tools installed via Homebrew. Split into lite (always) and additional (full mode only).

**Lite:**

| Tool                                           | Description                                           |
| ---------------------------------------------- | ----------------------------------------------------- |
| [`fzf`](https://github.com/junegunn/fzf)       | Fuzzy finder for shell history, files, and more       |
| [`proto`](https://moonrepo.dev/proto)          | Multi-language toolchain version manager              |
| [`sshs`](https://github.com/quantumsheep/sshs) | Interactive SSH host selector (reads `~/.ssh/config`) |
| [`cheat`](https://github.com/cheat/cheat)      | Community-driven command cheatsheets                  |
| [`yq`](https://mikefarah.gitbook.io/yq)        | Portable YAML/JSON/TOML processor                     |
| `tree`                                         | Directory tree visualizer                             |
| `watch`                                        | Repeat a command at intervals                         |
| `rsync`                                        | Incremental file transfer                             |
| `docker` + `docker-compose`                    | Container build and orchestration CLI                 |

**Additional (full mode):**

| Tool                                                        | Description                                                          |
| ----------------------------------------------------------- | -------------------------------------------------------------------- |
| [`gh`](https://cli.github.com)                              | GitHub CLI — PRs, issues, repos from the terminal                    |
| [`lazygit`](https://github.com/jesseduffield/lazygit)       | Terminal UI for Git                                                  |
| [`lazydocker`](https://github.com/jesseduffield/lazydocker) | Terminal UI for Docker                                               |
| [`colima`](https://github.com/abiosoft/colima)              | Lightweight container runtime for macOS (Docker Desktop alternative) |
| [`lima`](https://github.com/lima-vm/lima)                   | Linux VMs on macOS — used for local Debian setup testing             |
| [`nmap`](https://nmap.org)                                  | Network exploration and port scanning                                |
| Browsers                                                    | Brave, Firefox, Arc                                                  |
| Apps                                                        | Insomnia, Mattermost, OpenVPN Connect                                |

### `javascript`

Installs Node.js and package managers via proto.

**Lite:**

| Tool   | Version manager |
| ------ | --------------- |
| `node` | proto           |
| `npm`  | proto           |

**Additional (full mode):**

| Tool                                                  | Description                                            |
| ----------------------------------------------------- | ------------------------------------------------------ |
| `bun`                                                 | Fast all-in-one JS runtime and bundler                 |
| `pnpm`                                                | Efficient disk-space-saving package manager            |
| `yarn`                                                | Alternative npm-compatible package manager             |
| [`@antfu/ni`](https://github.com/antfu-collective/ni) | Universal package manager wrapper (`ni`, `nr`, `nun`…) |

### `python`

Installs Python via proto and tooling via uv.

**Lite:**

| Tool                              | Version manager                                 |
| --------------------------------- | ----------------------------------------------- |
| `python`                          | proto                                           |
| [`uv`](https://docs.astral.sh/uv) | Blazing-fast Python package and project manager |

**Additional (full mode):**

| Tool                                  | Description                                |
| ------------------------------------- | ------------------------------------------ |
| [`ruff`](https://docs.astral.sh/ruff) | Extremely fast Python linter and formatter |
| [`ipython`](https://ipython.org)      | Enhanced interactive Python shell          |
| [`httpie`](https://httpie.io)         | User-friendly HTTP client for the terminal |

### `ai`

Full mode only.

| Tool                           | Description                       |
| ------------------------------ | --------------------------------- |
| [`ollama`](https://ollama.com) | Run large language models locally |
| `copilot-cli`                  | GitHub Copilot for the CLI        |

### `extras`

Personal applications.

**Lite:** VLC

**Additional (full mode):** Audacity, Discord, Spotify, Transmission, Raspberry Pi Imager, Soulseek, Macs Fan Control, Radio Silence, kDrive

## Dotfiles Linking

Running `-d` symlinks (or copies) config files from the repository into `$HOME`. Any existing file is backed up with a datestamp (e.g. `~/.zshrc.bak.20260311`) before being replaced.

| Source                         | Target                                                  | Method  |
| ------------------------------ | ------------------------------------------------------- | ------- |
| `config/zsh/.zshrc`            | `~/.zshrc`                                              | copy¹   |
| `config/git/.gitconfig`        | `~/.gitconfig`                                          | symlink |
| `config/proto/.prototools`     | `~/.proto/.prototools`                                  | symlink |
| `config/oh-my-zsh/*.zsh-theme` | `~/.oh-my-zsh/custom/themes/`                           | symlink |
| `config/shell/*`               | `~/.config/dotfiles/`                                   | symlink |
| `config/vscode/settings.json`  | `~/Library/Application Support/Code/User/settings.json` | symlink |
| `config/vscode/mcp.json`       | `~/Library/Application Support/Code/User/mcp.json`      | symlink |

> ¹ `.zshrc` is copied rather than symlinked because the init script applies macOS-specific patches: `gsed` alias and Homebrew paths for Apple Silicon (`/opt/homebrew`).

## Completions

Running `-c` installs zsh completions for the following tools (placed in `$(brew --prefix)/share/zsh/site-functions`):

| Tool    | Source                                               |
| ------- | ---------------------------------------------------- |
| `fzf`   | Homebrew integration (`--completion --key-bindings`) |
| `gh`    | `gh completion -s zsh`                               |
| `proto` | `proto completions --shell zsh`                      |
| `uv`    | `uv generate-shell-completion zsh`                   |

## VM Testing (Debian 13 / trixie)

Use [Lima](https://github.com/lima-vm/lima) to spin up a local Debian 13 (trixie) VM and test the Debian setup scripts without a remote server.

### Prerequisites

```sh
brew install lima
```

### Makefile targets

| Target              | Description                                         |
| ------------------- | --------------------------------------------------- |
| `make vm-create`    | Create and start the Debian 13 VM                   |
| `make vm-install`   | Run the full dotfiles install inside the VM         |
| `make vm-test`      | Verify packages, SSH hardening, UFW, AppArmor, etc. |
| `make vm-shell`     | Open an interactive shell in the VM                 |
| `make vm-status`    | Show Lima instance status                           |
| `make vm-stop`      | Stop the VM (preserve disk)                         |
| `make vm-start`     | Start a stopped VM                                  |
| `make vm-clean`     | Delete the VM and free disk space                   |
| `make vm-full`      | Full cycle: create + install + verify               |
| `make vm-reset`     | Full reset: delete, recreate, install, verify       |
| `make vm-lima-list` | List all Lima instances                             |

### Quick start

```sh
# One-shot: create VM, install dotfiles, run verification
make vm-full

# Connect to VM shell
make vm-shell

# Teardown
make vm-clean
```

The Lima config is at `tests/lima/debian-trixie.yaml`. It uses Debian 13 (trixie) daily cloud images and Apple Virtualization framework (`vz`) with Rosetta for best performance on Apple Silicon.

## Zsh Configuration

The `.zshrc` at `config/zsh/.zshrc` is **copied** (not symlinked) to `~/.zshrc` so that macOS-specific patches can be applied without affecting the tracked file.

### History

| Setting       | Value            | Effect                                           |
| ------------- | ---------------- | ------------------------------------------------ |
| `HISTSIZE`    | `10000`          | Number of commands kept in memory per session    |
| `SAVEHIST`    | `10000`          | Number of commands persisted to `~/.zsh_history` |
| `HIST_STAMPS` | `yyyy-mm-dd`     | Date prefix on every history entry               |
| `HISTFILE`    | `~/.zsh_history` | Persistent history file location                 |

### Theme

A custom Oh My Zsh theme `kevin-de-benedetti` is linked from `config/oh-my-zsh/` into `~/.oh-my-zsh/custom/themes/` and set via `ZSH_THEME`.

### Plugins

The following [Oh My Zsh](https://ohmyz.sh) plugins are enabled in `.zshrc`. Plugins must be listed **before** `source $ZSH/oh-my-zsh.sh`.

| Plugin              | What it provides                                                                  |
| ------------------- | --------------------------------------------------------------------------------- |
| `aliases`           | `als` command — lists all active aliases with descriptions                        |
| `brew`              | Brew completion and `bubo`/`bubc`/`bubu` update aliases                           |
| `colored-man-pages` | ANSI colour for `man` pages — much easier to read                                 |
| `docker`            | Docker CLI completion and aliases (`dbl`, `dcin`, `dco`, `dps`, etc.)             |
| `docker-compose`    | `docker compose` completion and shorthand aliases (`dco`, `dcup`, `dcdown`, etc.) |
| `gh`                | GitHub CLI (`gh`) shell completion                                                |
| `git`               | Extensive Git aliases (`gst`, `gco`, `glog`, `gcmsg`, etc.) and branch in prompt  |
| `gitignore`         | `gi <lang>` — fetches a `.gitignore` template from gitignore.io                   |
| `rsync`             | Aliases for common rsync patterns (`rsync-copy`, `rsync-move`, etc.)              |
| `sudo`              | Double-press `ESC` to prepend `sudo` to the current or previous command           |

### Built-in Aliases

Key aliases defined in `.zshrc` (beyond plugin aliases):

| Alias   | Expands to                                              | Purpose                                         |
| ------- | ------------------------------------------------------- | ----------------------------------------------- |
| `bcu`   | `brew outdated --cask --greedy \| xargs brew reinstall` | Upgrade all outdated Homebrew casks in one shot |
| `cs`    | `cheat_glow`                                            | Render a cheat sheet with `glow`                |
| `dsp`   | `docker system prune -a -f`                             | Free all unused Docker resources                |
| `hs`    | `history \| grep`                                       | Case-sensitive history search                   |
| `hsi`   | `history \| grep -i`                                    | Case-insensitive history search                 |
| `k`     | `kubectl`                                               | Short Kubernetes client                         |
| `kc`    | `kubectx`                                               | Switch Kubernetes context                       |
| `kg`    | `kubectl get`                                           | List Kubernetes resources                       |
| `kl`    | `kubectl logs`                                          | Stream pod logs                                 |
| `kn`    | `kubens`                                                | Switch Kubernetes namespace                     |
| `lad`   | `lazydocker`                                            | Terminal UI for Docker                          |
| `lag`   | `lazygit`                                               | Terminal UI for Git                             |
| `pubip` | `dig +short txt ch whoami.cloudflare @1.0.0.1`          | Show your public IP address                     |
| `arm`   | `arch -arm64 /bin/zsh` *(macOS only)*                   | Start an ARM64 shell on Apple Silicon           |
| `intel` | `arch -x86_64 /bin/zsh` *(macOS only)*                  | Start a Rosetta (x86_64) shell                  |

### fzf Integration

The `fzf` Oh My Zsh plugin is enabled by the Homebrew completion setup. The following key bindings are available in the terminal:

| Binding  | Action                                              |
| -------- | --------------------------------------------------- |
| `CTRL-T` | Fuzzy-search files/directories and paste the path   |
| `CTRL-R` | Fuzzy-search command history and run selected entry |
| `ALT-C`  | Fuzzy `cd` into a subdirectory                      |

`cheat` is also configured with `CHEAT_USE_FZF=true` so `cheat` queries are piped through fzf for interactive selection.

### Local Overrides

The following files are sourced at the end of `.zshrc` if they exist. They are **never tracked by git** and always take precedence:

| File                              | Purpose                                               |
| --------------------------------- | ----------------------------------------------------- |
| `~/.config/dotfiles/env.local.sh` | Machine-specific secrets and environment variables    |
| `~/.zshrc.local`                  | Machine-specific aliases, path additions, and exports |

## Shell Functions

Custom functions live in `config/shell/functions.sh` and are sourced automatically by `.zshrc`. Run `lsfn` to list all functions with their help text.

| Function     | Usage                              | Description                                                                     |
| ------------ | ---------------------------------- | ------------------------------------------------------------------------------- |
| `b64d`       | `b64d <string>`                    | Decode a base64 string                                                          |
| `b64e`       | `b64e <string>`                    | Encode a string to base64                                                       |
| `browser`    | `browser [-- <url>]`               | Start a [Browsh](https://www.brow.sh) terminal browser via Docker               |
| `cheat_glow` | `cheat_glow <sheet>`               | Render a `cheat` cheatsheet through `glow` at 150 columns for readability       |
| `check_cert` | `check_cert <url>`                 | Print TLS certificate details for a domain using `curl`                         |
| `dks`        | `dks <secret> [namespace]`         | Decode a Kubernetes secret — outputs all `.data` values base64-decoded via `yq` |
| `kbp`        | `kbp <port>`                       | Kill the process currently listening on the given TCP port                      |
| `randompass` | `randompass [length]`              | Generate a secure random password (default 24 chars) with mixed complexity      |
| `timestampd` | `timestampd <unix_ts>`             | Convert a Unix timestamp to a human-readable date (cross-platform)              |
| `timestampe` | `timestampe <YYYY-mm-ddTHH:MM:ss>` | Convert a date string to its Unix timestamp (cross-platform)                    |

> Run any function with `-h` or `--help` to see its usage message, e.g. `dks -h`.

## Git Configuration

`config/git/.gitconfig` is **symlinked** to `~/.gitconfig`. Key settings:

| Section      | Setting              | Value                    | Effect                                               |
| ------------ | -------------------- | ------------------------ | ---------------------------------------------------- |
| `push`       | `default`            | `simple`                 | Push to the tracking branch only (safe default)      |
| `pull`       | `rebase`             | `true`                   | Always rebase on pull instead of merge               |
| `branch`     | `autosetuprebase`    | `always`                 | New branches track their remote with rebase          |
| `rerere`     | `enabled`            | `true`                   | Record and replay conflict resolutions automatically |
| `commit`     | `gpgsign`            | `true`                   | Sign every commit with your SSH key                  |
| `tag`        | `gpgSign`            | `true`                   | Sign every tag with your SSH key                     |
| `gpg`        | `format`             | `ssh`                    | Use SSH key (not GPG keyring) for signing            |
| `gpg.ssh`    | `allowedSignersFile` | `~/.ssh/allowed_signers` | File that maps emails to trusted public keys         |
| `init`       | `defaultBranch`      | `main`                   | New repositories default to `main`                   |
| `credential` | `helper`             | `cache --timeout=3600`   | Cache credentials for 1 hour                         |
| `diff`       | `tool`               | `meld`                   | Use Meld as the visual diff tool                     |

### Machine-specific overrides

Create `~/.gitconfig.local` with any section you want to override locally — it cannot be committed since it is excluded from the repository:

```ini
# ~/.gitconfig.local — never tracked by git
[user]
  email = work@company.com
  signingkey = ~/.ssh/id_ed25519_work.pub
```

### SSH commit signing

When `~/.ssh/id_rsa.pub` exists the dotfiles install creates `~/.ssh/allowed_signers` automatically. This allows Git to verify signed commits locally with `git log --show-signature`.

## SSH Client Configuration

`config/ssh/config` is **symlinked** to `~/.ssh/config`. The global `Host *` block applies to every connection:

| Directive             | Value         | Effect                                                                   |
| --------------------- | ------------- | ------------------------------------------------------------------------ |
| `SendEnv -LC_* -LANG` | (off)         | Do not forward locale variables — avoids `setlocale` warnings on servers |
| `ControlMaster`       | `auto`        | Reuse an existing connection if one is already open                      |
| `ControlPath`         | `~/.ssh/cm-…` | Socket path for multiplexed connections                                  |
| `ControlPersist`      | `60s`         | Keep the master connection open for 60 s after the last session closes   |
| `ServerAliveInterval` | `60`          | Send a keepalive packet every 60 s                                       |
| `ServerAliveCountMax` | `3`           | Drop the connection after 3 missed keepalives (~3 min)                   |

> **Colima integration:** If `~/.colima/ssh_config` exists it is included at the top, which lets Colima VMs work seamlessly with `ssh colima-*` aliases.

## proto Toolchain

`config/proto/.prototools` is **symlinked** to `~/.proto/.prototools`. It pins global tool versions and configures proto's behaviour:

```toml
bun   = "latest"
node  = "latest"
npm   = "bundled"   # ships with the Node.js version
pnpm  = "latest"

[tools.node]
bundled-npm = true  # keep npm in sync with node

[tools.npm]
shared-globals-dir = true  # global npm packages in a single shared dir

[settings]
auto-install  = true     # install missing tool versions automatically
auto-clean    = true     # remove unused tool versions after upgrades
pin-latest    = "global" # record the resolved "latest" version globally
```

### Managing tool versions

```sh
# Install / pin a specific version
proto install node 22

# Use a version in the current directory only
proto use node 20 --local

# List all tools managed by proto
proto list

# Upgrade proto itself
proto upgrade
```

## Homebrew Tips

```sh
# Update all installed packages
brew update && brew upgrade

# Remove outdated versions
brew cleanup

# List installed formulae
brew list --formula

# List installed casks
brew list --cask

# Check for issues
brew doctor
```

## Common Issues

**Xcode CLT broken after macOS update:**

```sh
sudo rm -rf /Library/Developer/CommandLineTools
xcode-select --install
```

**Homebrew not found on Apple Silicon:**

```sh
eval "$(/opt/homebrew/bin/brew shellenv)"
```

Add the above line to your `~/.zshrc` if Homebrew is not found in a new shell session.
