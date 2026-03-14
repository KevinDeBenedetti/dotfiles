#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Install a cask, adopting any existing manually-installed app into Homebrew management
install_cask() {
  if brew list --cask "$1" &>/dev/null; then
    printf "${red}[base]${no_color} $1 already managed by Homebrew — skipping.\n"
  else
    # --adopt takes ownership of apps already present in /Applications
    # without re-downloading or reinstalling them
    brew install --cask --adopt "$1"
  fi
}


install_lite_setup() {
  # Install homebrew cli packages
  printf "\n\n${red}[base] =>${no_color} Install homebrew packages (cli)\n\n"
  brew install --formula \
    cheat \
    direnv \
    docker \
    docker-compose \
    fzf \
    gettext \
    helm \
    kubectl \
    proto \
    sshs \
    tree \
    watch \
    yq \
    rsync


  # Install homebrew graphic app packages
  printf "\n\n${red}[base] =>${no_color} Install homebrew packages (graphic)\n\n"

}

install_additional_setup() {
  # Install homebrew cli packages
  printf "\n\n${red}[base] =>${no_color} Install homebrew packages (cli)\n\n"
  brew install --formula \
    gh \
    k9s \
    lazydocker \
    colima \
    lazygit \
    lima \
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