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

# Backup the destination if needed, then (re)create the symlink
link_with_backup() {
  local src="$1" dest="$2"
  backup_if_exists "$dest"
  ln -sf "$src" "$dest"
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
}
