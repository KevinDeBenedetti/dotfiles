#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$DOTFILES_DIR/config"

echo "🔗 Creating symlinks..."

link_file () {
  SRC=$1
  DEST=$2

  if [ -e "$DEST" ]; then
    echo "Backing up existing $DEST"
    mv "$DEST" "$DEST.backup"
  fi

  ln -s "$SRC" "$DEST"
}

# Git
link_file "$CONFIG_DIR/git/.gitconfig" "$HOME/.gitconfig"

# Zsh
link_file "$CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc"

# Oh-My-Zsh theme
if [ -d "$HOME/.oh-my-zsh" ]; then
  mkdir -p "$HOME/.oh-my-zsh/custom/themes"
  link_file "$CONFIG_DIR/oh-my-zsh/kevin-de-benedetti.zsh-theme" "$HOME/.oh-my-zsh/custom/themes/kevin-de-benedetti.zsh-theme"
fi

# Proto
mkdir -p "$HOME/.proto"
link_file "$CONFIG_DIR/proto/.prototools" "$HOME/.proto/.prototools"

# Shell config → ~/.config/dotfiles/
mkdir -p "$HOME/.config/dotfiles"
for item in "$CONFIG_DIR/shell/"*; do
  link_file "$item" "$HOME/.config/dotfiles/$(basename "$item")"
done

# SSH client config
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
link_file "$CONFIG_DIR/ssh/config" "$HOME/.ssh/config"

echo "✅ Symlinks created"
