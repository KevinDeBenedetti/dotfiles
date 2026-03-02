#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'


install_lite_setup() {
  # Install homebrew cli packages
  printf "\n\n${red}[base] =>${no_color} Install homebrew packages (cli)\n\n"
  brew install --formula \
    cheat \
    fzf \
    proto \
    sshs \
    tree \
    watch \
    yq \
    rsync


  # Install homebrew graphic app packages
  printf "\n\n${red}[base] =>${no_color} Install homebrew packages (graphic)\n\n"
  brew install --cask \
    docker \


  # Install addition cheatsheets
  curl -fsSL https://raw.githubusercontent.com/kevindebenedetti/tools/main/shell/clone-subdir.sh | bash -s -- \
    -u "https://github.com/kevindebenedetti/cheatsheets" -s "sheets" -o "$HOME/.config/cheat/cheatsheets/personal" -d
}

install_additional_setup() {
  # Install homebrew cli packages
  printf "\n\n${red}[base] =>${no_color} Install homebrew packages (cli)\n\n"
  brew install --formula \
    gh \
    lazydocker \
    lazygit \
    nmap

  # Install homebrew graphic app packages
  printf "\n\n${red}[base] =>${no_color} Install homebrew packages (graphic)\n\n"
  brew install --cask \
    brave-browser \
    firefox \
    insomnia \
    mattermost \
    openvpn-connect \
    visual-studio-code \
    arc
}


# Install lite setup
install_lite_setup

# Install full setup
if [ "$FULL_MODE_SETUP" = "true" ]; then
  install_additional_setup
fi