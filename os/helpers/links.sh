#!/usr/bin/env bash
# Shared symlink logic — the single source of truth for which configs are
# linked into $HOME. Sourced by scripts/symlink.sh and the OS init scripts
# (os/macos/init.sh, os/debian/init.sh) so the three entry points cannot
# drift apart again.
#
# .zshrc is intentionally NOT handled here: scripts/symlink.sh symlinks it,
# while the init scripts copy it to apply machine-specific edits.

# Backup a file if it exists and is not already a symlink
backup_if_exists() {
  local target="$1"
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    cp "$target" "${target}.bak.$(date +%Y%m%d)"
    printf '[backup] Backed up %s\n' "$target"
  fi
}

# Backup the destination if needed, then (re)create the symlink.
# -n (--no-dereference): if $dest is already a symlink to a directory, replace
# the link itself instead of dereferencing it and creating a self-referential
# loop *inside* the target dir (e.g. config/ai-tools/ai-tools). Harmless for
# file and non-existent destinations.
link_with_backup() {
  local src="$1" dest="$2"
  backup_if_exists "$dest"
  ln -sfn "$src" "$dest"
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

  # Proto
  mkdir -p "$HOME/.proto"
  link_with_backup "$config_dir/proto/.prototools" "$HOME/.proto/.prototools"

  # Git
  link_with_backup "$config_dir/git/.gitconfig" "$HOME/.gitconfig"

  # Git global ignore (default XDG location, no .gitconfig entry needed)
  mkdir -p "$HOME/.config/git"
  link_with_backup "$config_dir/git/ignore" "$HOME/.config/git/ignore"

  # SSH client config. The drop-in dir ~/.ssh/config.d/ holds ALL host-specific
  # entries (github accounts, infra hosts with real IPs) as LOCAL UNVERSIONED
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

  # Claude Code global commands → ~/.claude/commands/
  if [ -d "$config_dir/claude/commands" ]; then
    mkdir -p "$HOME/.claude/commands"
    for item in "$config_dir/claude/commands/"*; do
      link_with_backup "$item" "$HOME/.claude/commands/$(basename "$item")"
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
