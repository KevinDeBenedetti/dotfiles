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

| Tool                                                        | Description                                         |
| ----------------------------------------------------------- | --------------------------------------------------- |
| [Docker CE](https://docs.docker.com/engine/install/debian/) | Docker engine from the official upstream repository |
| `docker-ce`, `docker-ce-cli`, `containerd.io`               | Core engine, CLI client, and container runtime      |
| `docker-buildx-plugin`, `docker-compose-plugin`             | BuildKit and Compose v2 plugins                     |
| [`fzf`](https://github.com/junegunn/fzf)                    | Fuzzy finder for shell history, files, and more     |
| `ssh`                                                       | OpenSSH client                                      |
| `tree`                                                      | Directory tree visualizer                           |
| `watch`                                                     | Repeat a command at intervals                       |
| [`yq`](https://mikefarah.gitbook.io/yq)                     | Portable YAML/JSON/TOML processor                   |
| `rsync`                                                     | Incremental file transfer                           |

> Docker CE is installed from `https://download.docker.com/linux/debian` using the official GPG key. The calling user is automatically added to the `docker` group.

**Additional (full mode):**

| Tool                                  | Description                                                                  |
| ------------------------------------- | ---------------------------------------------------------------------------- |
| [`gh`](https://cli.github.com)        | GitHub CLI — PRs, issues, repos from the terminal                            |
| `nmap`                                | Network exploration and port scanning                                        |
| [`proto`](https://moonrepo.dev/proto) | Multi-language toolchain version manager (installed via curl if not present) |

### `security`

Hardens the system using a layered approach. Activated with `-p security` or included in `-a` (full install).

#### Environment variables

Set these before invoking the script to customize security behaviour:

| Variable            | Default | Description                                               |
| ------------------- | ------- | --------------------------------------------------------- |
| `SSH_PORT`          | `22`    | TCP port sshd listens on                                  |
| `SSH_ALLOWED_USERS` | *(all)* | Space-separated list of users permitted to log in via SSH |

```sh
# Example: custom port + restrict SSH to a single user
SSH_PORT=2222 SSH_ALLOWED_USERS="deploy" bash <(curl -fsSL ...) -a
```

#### SSH hardening (`/etc/ssh/sshd_config.d/99-hardening.conf`)

| Setting                  | Value                | Effect                                   |
| ------------------------ | -------------------- | ---------------------------------------- |
| `Port`                   | `$SSH_PORT`          | Configurable port (default: `22`)        |
| `PermitRootLogin`        | `no`                 | Disable direct root login                |
| `PasswordAuthentication` | `no`                 | Key-only authentication                  |
| `MaxAuthTries`           | `3`                  | Block brute-force attempts               |
| `X11Forwarding`          | `no`                 | No X11 tunnelling                        |
| `AllowTcpForwarding`     | `no`                 | No arbitrary port forwarding             |
| `ClientAliveInterval`    | `300`                | Disconnect after 5 min idle              |
| `AllowUsers`             | `$SSH_ALLOWED_USERS` | Restrict login to named users (optional) |

#### UFW firewall

Default policy: deny all incoming, allow all outgoing. Rules added:

| Rule            | Protocol | Comment                    |
| --------------- | -------- | -------------------------- |
| `$SSH_PORT/tcp` | TCP      | SSH (respects custom port) |
| `80/tcp`        | TCP      | HTTP                       |
| `443/tcp`       | TCP      | HTTPS                      |

#### Fail2Ban (`/etc/fail2ban/jail.local`)

| Setting     | Value      |
| ----------- | ---------- |
| `bantime`   | 1 hour     |
| `findtime`  | 10 minutes |
| `maxretry`  | 3 attempts |
| `backend`   | `systemd`  |
| `banaction` | `ufw`      |

#### Sysctl hardening (`/etc/sysctl.d/99-security.conf`)

**Network:**

| Parameter                            | Value | Effect                              |
| ------------------------------------ | ----- | ----------------------------------- |
| `net.ipv4.tcp_syncookies`            | `1`   | SYN flood protection                |
| `net.ipv4.tcp_rfc1337`               | `1`   | TIME_WAIT assassination protection  |
| `net.ipv4.ip_forward`                | `0`   | No IP forwarding                    |
| `net.ipv4.conf.all.accept_redirects` | `0`   | Ignore ICMP redirects (MITM)        |
| `net.ipv4.conf.all.rp_filter`        | `1`   | Reverse path filtering (anti-spoof) |
| `net.ipv6.conf.all.accept_ra`        | `0`   | Disable IPv6 router advertisements  |

**Kernel:**

| Parameter                   | Value   | Effect                                    |
| --------------------------- | ------- | ----------------------------------------- |
| `kernel.kptr_restrict`      | `2`     | Hide kernel pointer addresses in `/proc`  |
| `kernel.dmesg_restrict`     | `1`     | Restrict kernel log access to root        |
| `kernel.randomize_va_space` | `2`     | Full ASLR enabled                         |
| `kernel.yama.ptrace_scope`  | `1`     | Restrict `ptrace` to parent processes     |
| `net.core.bpf_jit_harden`   | `2`     | Harden BPF JIT compiler                   |
| `vm.mmap_min_addr`          | `65536` | Prevent null pointer dereference exploits |

**Filesystem:**

| Parameter                | Value | Effect                                               |
| ------------------------ | ----- | ---------------------------------------------------- |
| `fs.suid_dumpable`       | `0`   | No core dumps for setuid binaries                    |
| `fs.protected_symlinks`  | `1`   | Protect symlinks in world-writable sticky dirs       |
| `fs.protected_hardlinks` | `1`   | Only owner can follow hardlinks                      |
| `fs.protected_fifos`     | `2`   | Restrict FIFO creation in sticky directories         |
| `fs.protected_regular`   | `2`   | Restrict regular file creation in sticky directories |

#### Shared memory & `/tmp` (`/etc/fstab`)

| Mount point | Options                       |
| ----------- | ----------------------------- |
| `/run/shm`  | `noexec,nosuid`               |
| `/tmp`      | `noexec,nosuid,nodev,size=1G` |

#### AppArmor

Installs `apparmor` and `apparmor-utils`, adds GRUB boot parameters (`apparmor=1 security=apparmor`), enables the service, and sets all loaded profiles to `enforce` mode.

#### CrowdSec *(full mode only)*

Collaborative threat-intelligence IPS. Installs from `install.crowdsec.net` and adds:
- `crowdsec-firewall-bouncer-iptables` — automatic firewall banning
- Collections: `crowdsecurity/linux`, `crowdsecurity/sshd`

#### Unattended upgrades

Configures automatic security patches only (`${distro_id}:${distro_codename}-security`). Auto-reboot is **disabled**.

#### Security audit tools *(full mode only)*

| Tool         | Description                  |
| ------------ | ---------------------------- |
| `lynis`      | System and security auditing |
| `rkhunter`   | Rootkit scanner              |
| `chkrootkit` | Another rootkit checker      |
| `auditd`     | Kernel audit framework       |

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

**Docker CE daemon not started after install:**

```sh
sudo systemctl enable docker
sudo systemctl start docker
# Log out and back in for group membership to take effect
# (the script already runs: usermod -aG docker $USER)
```

**Docker GPG key or repository error:**

```sh
# Re-add the GPG key manually
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
```

**`kubectl` not found after install:**

```sh
# Verify the apt source was added correctly
cat /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubectl
```
