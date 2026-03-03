#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Install a cask, adopting any existing manually-installed app into Homebrew management
install_cask() {
  if [ "${FORCE_INSTALL:-false}" = "true" ]; then
    printf "${red}[base]${no_color} Force reinstalling $1...\n"
    brew reinstall --cask "$1"
    return
  fi
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
  if [ "${FORCE_INSTALL:-false}" = "true" ]; then
    brew reinstall --formula \
      cheat \
      fzf \
      proto \
      sshs \
      tree \
      watch \
      yq \
      rsync
  else
    brew install --formula \
      cheat \
      fzf \
      proto \
      sshs \
      tree \
      watch \
      yq \
      rsync
  fi


  # Install homebrew graphic app packages
  printf "\n\n${red}[base] =>${no_color} Install homebrew packages (graphic)\n\n"
  install_cask docker-desktop

}

install_additional_setup() {
  # Install homebrew cli packages
  printf "\n\n${red}[base] =>${no_color} Install homebrew packages (cli)\n\n"
  if [ "${FORCE_INSTALL:-false}" = "true" ]; then
    brew reinstall --formula \
      gh \
      lazydocker \
      lazygit \
      nmap
  else
    brew install --formula \
      gh \
      lazydocker \
      lazygit \
      nmap
  fi

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