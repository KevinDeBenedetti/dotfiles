#!/usr/bin/env bash

set -euo pipefail

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Default so `set -u` doesn't trip when run standalone (init.sh exports it)
FULL_MODE_SETUP="${FULL_MODE_SETUP:-false}"

# Install a cask, adopting any existing manually-installed app into Homebrew management
install_cask() {
  if brew list --cask "$1" &>/dev/null; then
    printf '%b' "${red}[base]${no_color} $1 already managed by Homebrew — skipping.\n"
  else
    # --adopt takes ownership of apps already present in /Applications
    # without re-downloading or reinstalling them
    brew install --cask --adopt "$1"
  fi
}


install_lite_setup() {
  # Install homebrew cli packages
  printf '%b' "\n\n${red}[base] =>${no_color} Install homebrew packages (cli)\n\n"
  brew install --formula \
    ansible \
    cheat \
    direnv \
    fzf \
    gettext \
    helm \
    kubectl \
    sshs \
    terraform \
    tree \
    watch \
    yq \
    rsync
}

install_additional_setup() {
  # Install homebrew cli packages
  printf '%b' "\n\n${red}[base] =>${no_color} Install homebrew packages (cli)\n\n"
  brew install --formula \
    gh \
    k9s \
    lazydocker \
    lazygit \
    nmap

  # Install homebrew graphic app packages
  printf '%b' "\n\n${red}[base] =>${no_color} Install homebrew packages (graphic)\n\n"
  for cask in brave-browser firefox insomnia mattermost openvpn-connect arc docker-desktop; do
    install_cask "$cask"
  done
}


# Install lite setup
install_lite_setup

# Install full setup
if [ "$FULL_MODE_SETUP" = "true" ]; then
  install_additional_setup
fi
