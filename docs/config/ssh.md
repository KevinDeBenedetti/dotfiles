---
title: SSH
---

# SSH

SSH client configuration symlinked to `~/.ssh/config`.

## Location

| File                | Symlinked to    |
| ------------------- | --------------- |
| `config/ssh/config` | `~/.ssh/config` |

## Global host settings (`Host *`)

### Locale

macOS forwards `LC_*` and `LANG` variables to remote hosts by default. Remote servers
(e.g. Debian) may not have the same locale installed, which causes warning messages on login.
This is disabled globally:

```
SendEnv -LC_* -LANG
```

### Connection multiplexing

Reuses existing SSH connections for faster subsequent logins to the same host.

| Setting          | Value                | Description                              |
| ---------------- | -------------------- | ---------------------------------------- |
| `ControlMaster`  | `auto`               | Automatically start multiplexing         |
| `ControlPath`    | `~/.ssh/cm-%r@%h:%p` | Socket path per user/host/port           |
| `ControlPersist` | `60s`                | Keep master open 60 s after last session |

### Keepalive

Prevents idle connections from being dropped by firewalls or routers.

| Setting               | Value | Description                         |
| --------------------- | ----- | ----------------------------------- |
| `ServerAliveInterval` | `60`  | Send keepalive packet every 60 s    |
| `ServerAliveCountMax` | `3`   | Disconnect after 3 missed responses |

### Key handling (passphrase)

| Setting          | Value | Description                                         |
| ---------------- | ----- | --------------------------------------------------- |
| `UseKeychain`    | `yes` | Read/store the key passphrase in the macOS keychain |
| `AddKeysToAgent` | `yes` | Add keys to `ssh-agent` automatically on first use  |

## Machine-specific hosts

Host blocks for specific machines (infra IPs, internal servers) live in
`~/.ssh/config.d/*.conf`, which is **not tracked by git** (this repo is public).
They are included first so their settings take precedence:

```ssh-config
Include ~/.ssh/config.d/*.conf
```

Example `~/.ssh/config.d/servers.conf`:

```ssh-config
Host my-server
  HostName 203.0.113.10
  User deploy
  IdentityFile ~/.ssh/id_ed25519
  IdentitiesOnly yes
```

GitHub needs no host block: `config/git/.gitconfig` rewrites `git@github.com:`
remotes to HTTPS, authenticated by Git Credential Manager (see [Git](./git.md)).
