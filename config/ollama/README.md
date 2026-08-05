# ollama

Reproducible configuration for the local Ollama install: which models to restore,
and the server settings that make them fit this machine.

| File | Role |
| ---- | ---- |
| `models.txt` | Pinned model tags, restored by `ollama-bootstrap` |
| `env.sh` | Server settings — single source of truth for the values |
| `launchd/*.plist` | LaunchAgent replaying `env.sh` into the launchd session at login |
| `modelfiles/` | Custom models built on top of a base model (empty for now) |

Scripts live in `scripts/ollama/` and are symlinked into `~/.local/bin`:
`ollama-bootstrap` restores the models, `ollama-setenv` applies `env.sh`.

## What this deliberately does NOT contain

- **The model weights.** `~/.ollama/models` is 14 GB of binaries, re-downloadable
  for free from the registry. `models.txt` records *which* models, not their bytes.
- **`~/.ollama/id_ed25519`.** That is Ollama's private identity key. It is
  generated per machine and must never be committed; the repo's `.gitignore`,
  the `detect-private-key` hook and gitleaks all guard against it.
- **`~/.ollama/config.json`.** Menu-bar app UI state (`last_selection`), not
  configuration worth versioning.

Nothing here mirrors `~/.ollama/`, and nothing symlinks into it.

## How the settings are applied

Ollama exposes **no configuration file** for these — the one documented JSON file
covers only `disable_ollama_cloud`. Environment variables are the mechanism, and
how you set them differs per platform. `ollama-setenv` detects the OS and does
the right thing; `env.sh` stays the single source of truth for the values either
way.

### macOS — LaunchAgent, not `~/.zshrc`

Ollama runs here as the **menu-bar application**, started by launchd
(`com.ollama.ollama` in the `gui/$UID` domain). launchd never reads a login
shell's rc files, so an `export OLLAMA_…` in `~/.zshrc` is silently ignored —
the single most common reason an Ollama setting appears to do nothing. Only
`ollama serve` run from a terminal picks up shell exports.

The supported path is `launchctl setenv`, but run by hand it is session-scoped
and lost at the next reboot. Hence `launchd/local.ollama-env.plist`: it replays
`env.sh` at every login.

The agent is labelled `local.ollama-env`. Apple's convention is a reverse-DNS
domain you own, but this repo is meant to be forked — an author's name baked
into the label would end up in every forker's `launchctl list`. `local.` claims
no domain and stays correct for anyone.

### Linux — systemd drop-in

The daemon runs under systemd, configured by
`/etc/systemd/system/ollama.service.d/override.conf`. That path needs root, so
`ollama-setenv` renders the file into `$XDG_STATE_HOME` and prints the two
commands to run rather than escalating on its own:

```sh
sudo install -Dm644 ~/.local/state/ollama-override.conf \
  /etc/systemd/system/ollama.service.d/override.conf
sudo systemctl daemon-reload && sudo systemctl restart ollama
```

### Either way: restart the server

**Ollama reads its environment once, at startup.** Quit and reopen Ollama.app
(or `systemctl restart ollama`) after any change to `env.sh` — reloading the
agent alone is not enough.

On macOS the app does not quit on request: `osascript -e 'quit app "Ollama"'`
returns error `-128` (user cancelled), because the Electron shell intercepts the
event, and the process keeps running with its old environment. Kill it instead,
then check the PID actually changed before concluding anything:

```sh
pkill -f 'Ollama.app'
open -a Ollama
launchctl print "gui/$(id -u)" | grep electron.ollama
```

Nothing is lost: the weights are on disk and the server holds no state worth
keeping.

`ollama-setenv` logs each run to `$XDG_STATE_HOME/ollama-env.log`
(`~/.local/state/` by default), because a LaunchAgent that fails does so
silently and leaves no other trace.

## Restoring on a fresh machine

In this order:

1. **Install Ollama** — handled by `os/macos/setup-ai.sh`, or directly:

   ```sh
   brew install --cask ollama-app
   ```

2. **Link the dotfiles** — creates `~/.config/ollama`, the `~/.local/bin`
   symlinks and the LaunchAgent. A full install (`os/macos/init.sh`) already
   does this; to relink on an existing machine:

   ```sh
   ./scripts/symlink.sh
   ```

   Nothing below works before this step: `ollama-setenv` and `ollama-bootstrap`
   live in the repo and only reach `$PATH` through those symlinks.

3. **Apply the server settings**, then quit and reopen Ollama.app:

   ```sh
   ollama-setenv
   ```

4. **Check what would be pulled**, prune `models.txt` if the machine has less
   memory, then restore. This downloads several GB:

   ```sh
   ollama-bootstrap --dry-run
   ollama-bootstrap
   ```

5. **Verify** (below).

## Verifying the settings took effect

Read them back from the launchd session:

```sh
launchctl getenv OLLAMA_KV_CACHE_TYPE
```

That proves the *agent* ran, not that the *server* picked the value up — the two
differ whenever Ollama.app was not restarted. For that, restart the server with
debug logging and read the startup lines, which echo the resolved configuration:

```sh
OLLAMA_DEBUG=1 ollama serve
```

Then confirm the runtime effect on a loaded model:

```sh
ollama ps
```

`CONTEXT` must match `OLLAMA_CONTEXT_LENGTH` for a request that sends no explicit
context, and `PROCESSOR` must read `100% GPU`. Any `CPU` share means the model
spilled out of the ~10.6 GB usable as VRAM on this 16 GB machine — lower
`OLLAMA_CONTEXT_LENGTH`, or keep `OLLAMA_MAX_LOADED_MODELS` at 1.

Test with `ollama run <model>` rather than `ai commit`: the AI tooling sends its
own `options.num_ctx` on every request, so it would report the right context even
if `OLLAMA_CONTEXT_LENGTH` were doing nothing at all.

Measured on qwen3.5:9b, this M2 Pro, and worth reproducing after a change —
these are what a working `q8_0` looks like:

| Context | K/V cache | Resident |
| ------- | --------- | -------- |
| 4096 | f16 | 5.6 GB |
| 16384 | f16 | 6.1 GB |
| 16384 | `q8_0` | 5.8 GB |

Four times the context for +0.2 GB instead of +0.5 — the cache is halved, as
documented.

## Relationship with `config/ai-tools/`

`env.sh` sets the *server-wide defaults*, which apply to every Ollama client.
`config/ai-tools/` drives `ai commit` / `ai ask` / `ai explain`, and sends its own
`options.num_ctx`, `options.temperature` and `options.presence_penalty` on each
request — per-request options always win over these defaults.

The two overlap on context length on purpose: `OLLAMA_CONTEXT_LENGTH` raises the
floor for clients that send nothing, while `AI_NUM_CTX` pins it for the tooling.
