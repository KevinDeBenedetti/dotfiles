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

  # Claude Code global skills → ~/.claude/skills/ (one symlink per skill dir)
  if [ -d "$config_dir/claude/skills" ]; then
    mkdir -p "$HOME/.claude/skills"
    for item in "$config_dir/claude/skills/"*; do
      [ -d "$item" ] || continue
      link_with_backup "$item" "$HOME/.claude/skills/$(basename "$item")"
    done
  fi

  # Local AI tooling config → ~/.config/ai-tools/ (sourced by scripts/ai/*)
  if [ -d "$config_dir/ai-tools" ]; then
    link_with_backup "$config_dir/ai-tools" "$HOME/.config/ai-tools"
  fi

  # Local AI tooling commands → ~/.local/bin/ (already on PATH via .zshrc).
  # $config_dir is <repo>/config, so the scripts live one level up.
  local ai_dir="$config_dir/../scripts/ai"
  if [ -d "$ai_dir" ]; then
    mkdir -p "$HOME/.local/bin"
    for item in "$ai_dir/"*; do
      case "$item" in
        *.md) continue ;;
      esac
      [ -f "$item" ] || continue
      chmod +x "$item"
      link_with_backup "$item" "$HOME/.local/bin/$(basename "$item")"
    done
  fi
}
