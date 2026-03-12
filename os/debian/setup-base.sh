#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

SUDO="${SUDO:-}"

install_lite_setup() {
  # Configure locale (prevents LC_* warnings on SSH login)
  printf "\n\n${red}[base] =>${no_color} Configure locale (en_US.UTF-8)\n\n"
  $SUDO apt-get install -y --no-install-recommends locales
  # Enable en_US.UTF-8 in locale.gen if not already present
  if ! grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen 2>/dev/null; then
    echo 'en_US.UTF-8 UTF-8' | $SUDO tee -a /etc/locale.gen
  fi
  $SUDO locale-gen en_US.UTF-8
  $SUDO update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

  # Install Docker CE from official upstream repository
  printf "\n\n${red}[base] =>${no_color} Install Docker CE\n\n"
  if ! command -v docker &>/dev/null; then
    $SUDO apt-get install -y --no-install-recommends \
      ca-certificates \
      gnupg
    $SUDO install -m 0755 -d /etc/apt/keyrings
    # Detect distro ID (debian or ubuntu) for the correct Docker repo URL
    _DOCKER_DISTRO=$(. /etc/os-release && echo "${ID}")
    _DOCKER_CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME}")
    curl -fsSL "https://download.docker.com/linux/${_DOCKER_DISTRO}/gpg" \
      | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    $SUDO chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${_DOCKER_DISTRO} \
${_DOCKER_CODENAME} stable" \
      | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
    $SUDO apt-get update -qq
    $SUDO apt-get install -y --no-install-recommends \
      docker-ce \
      docker-ce-cli \
      containerd.io \
      docker-buildx-plugin \
      docker-compose-plugin
    # Add current user to docker group
    if [[ -n "${SUDO_USER:-}" ]]; then
      $SUDO usermod -aG docker "$SUDO_USER"
    elif [[ "$(id -u)" -ne 0 ]]; then
      $SUDO usermod -aG docker "$(whoami)"
    fi
  else
    printf "${red}[base]${no_color} Docker already installed — skipping.\n"
  fi

  # Install apt packages
  printf "\n\n${red}[base] =>${no_color} Install apt packages (cli)\n\n"
  $SUDO apt-get install -y --no-install-recommends \
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
