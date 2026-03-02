#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Install a cask only if not already installed (avoids errors on existing apps)
install_cask() {
  if brew list --cask "$1" &>/dev/null; then
    printf "${red}[base]${no_color} $1 already installed via Homebrew — skipping.\n"
  elif [ -d "/Applications/$(ls /Applications | grep -i "^$(echo "$1" | sed 's/-/ /g')" | head -1)" ] 2>/dev/null; then
    printf "${red}[base]${no_color} $1 already present in /Applications — skipping.\n"
  else
    brew install --cask "$1"
  fi
}


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
  install_cask docker-desktop

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
  for cask in brave-browser firefox insomnia mattermost openvpn-connect arc; do
    install_cask "$cask"
  done
}


# Install lite setup
install_lite_setup

# Install full setup
if [ "$FULL_MODE_SETUP" = "true" ]; then
  install_additional_setup
fi