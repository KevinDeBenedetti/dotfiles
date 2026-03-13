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

## Machine-specific hosts

Add project- or machine-specific host blocks to `~/.ssh/config.local` (not tracked by git)
and include it with:

```
Include ~/.ssh/config.local
```

Or add host entries directly after the `Host *` block in a local, untracked file.
