#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$DOTFILES_DIR/config"

# shellcheck source=../os/helpers/links.sh
source "$DOTFILES_DIR/os/helpers/links.sh"

echo "🔗 Creating symlinks..."

# Zsh — symlinked here; the OS init scripts copy it instead (machine-specific edits)
link_with_backup "$CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc"

# Everything shared with the OS init scripts (git, proto, shell, claude, …)
link_shared_configs "$CONFIG_DIR"

# SSH client config
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
link_with_backup "$CONFIG_DIR/ssh/config" "$HOME/.ssh/config"

echo "✅ Symlinks created"
