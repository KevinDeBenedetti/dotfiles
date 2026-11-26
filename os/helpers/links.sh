#!/usr/bin/env bash
# Shared symlink logic — the single source of truth for which configs are
# linked into $HOME. Sourced by scripts/symlink.sh and the OS init scripts
# (os/macos/init.sh, os/debian/init.sh) so the three entry points cannot
# drift apart again.
#
# .zshrc is intentionally NOT handled here: scripts/symlink.sh symlinks it,
# while the init scripts copy it to apply machine-specific edits.

# Backup a file if it exists and is not already a symlink. The first backup of
# the day is kept: a re-run would otherwise copy the file this script installed
# on the first run over the backup of the user's original.
backup_if_exists() {
  local target="$1" backup
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    backup="${target}.bak.$(date +%Y%m%d)"
    if [ -e "$backup" ]; then
      printf '[backup] %s already backed up today — keeping %s\n' "$target" "$backup"
      return 0
    fi
    cp "$target" "$backup"
    printf '[backup] Backed up %s\n' "$target"
  fi
}

# Backup the destination if needed, then (re)create the symlink.
# -n (--no-dereference): if $dest is already a symlink to a directory, replace
# the link itself instead of dereferencing it and creating a self-referential
# loop *inside* the target dir (e.g. config/ai-tools/ai-tools). Harmless for
# file and non-existent destinations.
#
# A real (non-symlink) directory at $dest is moved aside first: ln cannot
# replace a directory, it would drop the link INSIDE it and leave the stale dir
# in place. It goes under ~/.local/state/dotfiles/backup/ rather than next to
# $dest, so e.g. a backed-up skill dir is not picked up as a duplicate skill.
link_with_backup() {
  local src="$1" dest="$2"
  if [ -d "$dest" ] && [ ! -L "$dest" ]; then
    local backup
    backup="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backup/${dest#"$HOME"/}.$(date +%Y%m%d%H%M%S)"
    mkdir -p "$(dirname "$backup")"
    mv "$dest" "$backup"
    printf '[backup] Moved directory %s to %s\n' "$dest" "$backup"
  fi
  backup_if_exists "$dest"
  ln -sfn "$src" "$dest"
}

# prune_stale_links <dir> <prefix>... — remove the symlinks of <dir> whose
# target starts with one of the prefixes and no longer exists: what an earlier
# version of this script linked from a path the repository has since dropped.
# A live link, a regular file or a link to anywhere else is left alone.
prune_stale_links() {
  local dir="$1" link target prefix
  shift
  [ -d "$dir" ] || return 0
  for link in "$dir"/*; do
    [ -L "$link" ] && [ ! -e "$link" ] || continue
    target=$(readlink "$link")
    for prefix in "$@"; do
      case $target in
        "$prefix"*)
          rm -f "$link"
          printf '[prune] Removed stale link %s\n' "$link"
          break
          ;;
      esac
    done
  done
}

# Print VS Code's "User" directory for this platform.
vscode_user_dir() {
  if [ "$(uname -s)" = "Darwin" ]; then
    printf '%s\n' "$HOME/Library/Application Support/Code/User"
  else
    printf '%s\n' "$HOME/.config/Code/User"
  fi
}

# Link the VS Code user config. $1 = config/ dir, $2 = VS Code "User" dir.
# extensions.json is not linked: install_vscode_config (dotfiles.sh) reads it.
link_vscode_configs() {
  local config_dir="$1" user_dir="$2" name
  for name in settings.json mcp.json; do
    [ -f "$config_dir/vscode/$name" ] || continue
    link_with_backup "$config_dir/vscode/$name" "$user_dir/$name"
  done
}

# Link every shared config file into $HOME. $1 = path to the repo's config/ dir.
link_shared_configs() {
  local config_dir="$1"

  # Oh-My-Zsh theme (only when oh-my-zsh is installed)
  local theme_src="$config_dir/oh-my-zsh/kevin-de-benedetti.zsh-theme"
  if [ -d "$HOME/.oh-my-zsh" ] && [ -f "$theme_src" ]; then
    mkdir -p "$HOME/.oh-my-zsh/custom/themes"
    link_with_backup "$theme_src" "$HOME/.oh-my-zsh/custom/themes/kevin-de-benedetti.zsh-theme"
  fi

  # VS Code user config (only when VS Code has a user dir: a machine without
  # VS Code gets none; the init scripts create it when `code` is installed).
  local vscode_user
  vscode_user=$(vscode_user_dir)
  if [ -d "$vscode_user" ]; then
    link_vscode_configs "$config_dir" "$vscode_user"
  fi

  # Proto
  mkdir -p "$HOME/.proto"
  link_with_backup "$config_dir/proto/.prototools" "$HOME/.proto/.prototools"

  # Git
  link_with_backup "$config_dir/git/.gitconfig" "$HOME/.gitconfig"

  # Git global ignore (default XDG location, no .gitconfig entry needed)
  mkdir -p "$HOME/.config/git"
  link_with_backup "$config_dir/git/ignore" "$HOME/.config/git/ignore"

  # SSH client config. The drop-in dir ~/.ssh/config.d/ holds ALL host-specific
  # entries (infra hosts with real IPs, internal servers) as LOCAL UNVERSIONED
  # files — nothing in there is tracked by the repo. We only create the empty
  # dir so the `Include ~/.ssh/config.d/*.conf` in config never errors.
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  mkdir -p "$HOME/.ssh/config.d"
  chmod 700 "$HOME/.ssh/config.d"
  link_with_backup "$config_dir/ssh/config" "$HOME/.ssh/config"

  # Shell config → ~/.config/dotfiles/
  mkdir -p "$HOME/.config/dotfiles"
  local item
  for item in "$config_dir/shell/"*; do
    link_with_backup "$item" "$HOME/.config/dotfiles/$(basename "$item")"
  done

  # Claude Code user settings
  mkdir -p "$HOME/.claude"
  link_with_backup "$config_dir/claude/settings.json" "$HOME/.claude/settings.json"

  # Global agent rules: config/agents/AGENTS.md is the single source, linked to
  # the user-level instruction file each tool reads on every session:
  #   Claude Code → ~/.claude/AGENTS.md, imported by ~/.claude/CLAUDE.md
  #                 (config/claude/CLAUDE.md), which also holds the imports
  #                 only Claude Code reads (RTK.md)
  #   OpenCode    → ~/.config/opencode/AGENTS.md
  #   VS Code     → ~/.copilot/copilot-instructions.md (Copilot sessions)
  # An existing file is backed up first (link_with_backup).
  if [ -f "$config_dir/agents/AGENTS.md" ]; then
    mkdir -p "$HOME/.config/opencode" "$HOME/.copilot"
    link_with_backup "$config_dir/agents/AGENTS.md" "$HOME/.claude/AGENTS.md"
    link_with_backup "$config_dir/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"
    link_with_backup "$config_dir/agents/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
    link_with_backup "$config_dir/agents/AGENTS.md" "$HOME/.copilot/copilot-instructions.md"
  fi

  # Claude Code hook scripts → ~/.claude/hooks/, linked one by one (the dir
  # may hold other hooks). Wired in config/claude/settings.json.
  if [ -d "$config_dir/claude/hooks" ]; then
    mkdir -p "$HOME/.claude/hooks"
    for item in "$config_dir/claude/hooks/"*; do
      [ -f "$item" ] || continue
      chmod +x "$item"
      link_with_backup "$item" "$HOME/.claude/hooks/$(basename "$item")"
    done
  fi

  # Shared agent skills, each skill folder linked individually into the two
  # personal skill directories the three tools read:
  #   ~/.claude/skills/  → Claude Code (native), OpenCode (Claude compat) and
  #                        VS Code sessions on the Claude or Local harness
  #   ~/.copilot/skills/ → VS Code Copilot sessions, GitHub Copilot CLI
  # ~/.agents/skills/ is left out on purpose: OpenCode reads it too and would
  # list every skill twice. NEVER link a skills dir itself: Claude Code manages
  # its own `synced/` and `.trash/` subdirs there and a symlink would clobber
  # them.
  if [ -d "$config_dir/skills" ]; then
    mkdir -p "$HOME/.claude/skills" "$HOME/.copilot/skills"
    for item in "$config_dir/skills/"*/; do
      [ -d "$item" ] || continue
      link_with_backup "$item" "$HOME/.claude/skills/$(basename "$item")"
      link_with_backup "$item" "$HOME/.copilot/skills/$(basename "$item")"
    done
  fi

  # User-invoked skills (`disable-model-invocation: true`, the former shared
  # commands) are slash commands in Claude Code and VS Code as they are.
  # OpenCode gets each one as a command file too, linked to the skill's own
  # SKILL.md, so `/<name>` works there whatever its version does with skills;
  # their `opencode/slash: "false"` metadata keeps it from listing them twice.
  if [ -d "$config_dir/skills" ]; then
    mkdir -p "$HOME/.config/opencode/commands"
    for item in "$config_dir/skills/"*/SKILL.md; do
      [ -f "$item" ] || continue
      grep -q '^disable-model-invocation: true$' "$item" || continue
      link_with_backup "$item" "$HOME/.config/opencode/commands/$(basename "$(dirname "$item")").md"
    done
  fi

  # The commands used to live in config/commands/ and config/claude/commands/,
  # linked into each tool's command dir. Those links now point nowhere:
  # remove them, and nothing else.
  prune_stale_links "$HOME/.claude/commands" "$config_dir/commands/" "$config_dir/claude/commands/"
  prune_stale_links "$HOME/.config/opencode/commands" "$config_dir/commands/"
  prune_stale_links "$vscode_user/prompts" "$config_dir/commands/"

  # opencode base config. Only the file is linked: ~/.config/opencode/ also holds
  # opencode's own node_modules/package.json, which must stay local. The tracked
  # provider is a placeholder; the real endpoint/models live in an untracked
  # override and the API key comes from $LLM_API_KEY (env.local.sh).
  if [ -f "$config_dir/opencode/opencode.json" ]; then
    mkdir -p "$HOME/.config/opencode"
    link_with_backup "$config_dir/opencode/opencode.json" "$HOME/.config/opencode/opencode.json"
  fi

  # VS Code Copilot agent hooks → ~/.copilot/hooks/ (user-level hook location).
  # agent-guard mirrors the hard denies of config/claude/settings.json
  # (git commit/push, mutating kubectl, secrets). Files are linked one by one:
  # ~/.copilot/ also holds Copilot's own local state.
  if [ -d "$config_dir/copilot/hooks" ]; then
    mkdir -p "$HOME/.copilot/hooks"
    for item in "$config_dir/copilot/hooks/"*; do
      [ -f "$item" ] || continue
      link_with_backup "$item" "$HOME/.copilot/hooks/$(basename "$item")"
    done
  fi

  # Local AI tooling config → ~/.config/ai-tools/ (sourced by scripts/ai/*)
  if [ -d "$config_dir/ai-tools" ]; then
    link_with_backup "$config_dir/ai-tools" "$HOME/.config/ai-tools"
  fi

  # Local tooling commands → ~/.local/bin/ (already on PATH via .zshrc).
  # $config_dir is <repo>/config, so the scripts live one level up. Every
  # scripts/<domain>/ directory is linked, so adding a domain needs no edit here.
  local scripts_dir="$config_dir/../scripts"
  if [ -d "$scripts_dir" ]; then
    mkdir -p "$HOME/.local/bin"
    for domain in "$scripts_dir"/*/; do
      [ -d "$domain" ] || continue
      for item in "$domain"*; do
        case "$item" in
          *.md) continue ;;
        esac
        [ -f "$item" ] || continue
        chmod +x "$item"
        link_with_backup "$item" "$HOME/.local/bin/$(basename "$item")"
      done
    done
  fi

  # Ollama server config → ~/.config/ollama/ (read by scripts/ollama/*)
  if [ -d "$config_dir/ollama" ]; then
    link_with_backup "$config_dir/ollama" "$HOME/.config/ollama"
  fi

  # Ollama LaunchAgent → ~/Library/LaunchAgents/ (macOS only).
  # This is what makes the OLLAMA_* settings survive a reboot: `launchctl setenv`
  # run by hand is session-scoped and lost. See config/ollama/README.md.
  if [ "$(uname -s)" = "Darwin" ] && [ -d "$config_dir/ollama/launchd" ]; then
    mkdir -p "$HOME/Library/LaunchAgents"
    for item in "$config_dir/ollama/launchd/"*.plist; do
      [ -f "$item" ] || continue
      link_with_backup "$item" "$HOME/Library/LaunchAgents/$(basename "$item")"
    done
  fi
}
