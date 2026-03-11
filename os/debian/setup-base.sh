#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

SUDO="${SUDO:-}"

install_lite_setup() {
  # Install apt packages
  printf "\n\n${red}[base] =>${no_color} Install apt packages (cli)\n\n"
  $SUDO apt-get install -y --no-install-recommends \
    docker.io \
    docker-compose \
    fzf \
    ssh \
    tree \
    watch \
    yq \
    rsync
}

install_additional_setup() {
  # Install additional apt packages
  printf "\n\n${red}[base] =>${no_color} Install apt packages (cli)\n\n"
  $SUDO apt-get install -y --no-install-recommends \
    gh \
    nmap

  # Install proto
  if ! command -v proto &>/dev/null; then
    printf "\n\n${red}[base] =>${no_color} Install proto\n\n"
    curl -fsSL https://moonrepo.dev/install/proto.sh | bash -s -- --yes
  fi
}


# Install lite setup
install_lite_setup

# Install full setup
if [ "$FULL_MODE_SETUP" = "true" ]; then
  install_additional_setup
fi
