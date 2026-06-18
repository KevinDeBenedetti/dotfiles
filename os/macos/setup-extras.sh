#!/usr/bin/env bash

set -euo pipefail

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Default so `set -u` doesn't trip when run standalone (init.sh exports it)
FULL_MODE_SETUP="${FULL_MODE_SETUP:-false}"


install_lite_setup() {
  # Install homebrew graphic app packages
  printf '%b' "\n\n${red}[extras] =>${no_color} Install homebrew packages (graphic)\n\n"
  brew install --cask \
    vlc
}

install_additional_setup() {
  # Install homebrew graphic app packages
  printf '%b' "\n\n${red}[extras] =>${no_color} Install homebrew packages (graphic)\n\n"
  brew install --cask \
    audacity \
    discord \
    raspberry-pi-imager \
    spotify \
    macs-fan-control \
    radio-silence \
    kdrive
}


# Install lite setup
install_lite_setup

# Install full setup
if [ "$FULL_MODE_SETUP" = "true" ]; then
  install_additional_setup
fi
