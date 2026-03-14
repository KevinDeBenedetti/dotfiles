#!/usr/bin/env bash
set -e

DISTRO=$1

install_debian() {
  echo "📦 Installing packages for Debian/Ubuntu"

  sudo apt update
  sudo apt install -y \
    git \
    zsh \
    curl \
    wget \
    fzf \
    ripgrep \
    build-essential
}

install_macos() {
  echo "📦 Installing packages for macOS"

  if ! command -v brew >/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  brew install \
    git \
    zsh \
    fzf \
    ripgrep \
    tree \
    watch
}

case "$DISTRO" in
  debian)
    install_debian
    ;;
  macos)
    install_macos
    ;;
  *)
    echo "Unsupported distro"
    exit 1
    ;;
esac
