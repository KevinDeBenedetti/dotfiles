#!/usr/bin/env bash
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "🚀 Installing dotfiles..."

# Détecter l'OS
OS="$(uname -s)"

case "$OS" in
  Linux)
    if [ -f /etc/debian_version ]; then
      DISTRO="debian"
    fi
    ;;
  Darwin)
    DISTRO="macos"
    ;;
  *)
    echo "Unsupported OS"
    exit 1
    ;;
esac

echo "Detected OS: $DISTRO"

# Installer les packages
"$DOTFILES_DIR/scripts/packages.sh" "$DISTRO"

# Créer les symlinks
"$DOTFILES_DIR/scripts/symlink.sh"

echo "✅ Dotfiles installed successfully"
