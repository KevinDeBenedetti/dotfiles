#!/bin/bash

set -euo pipefail

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

SUDO="${SUDO:-}"
# Default so `set -u` doesn't trip when run standalone (init.sh exports it)
FULL_MODE_SETUP="${FULL_MODE_SETUP:-false}"

# fetch_verified, install_deb_verified and install_apt_key: downloads kept only
# if their SHA-256 matches, apt keys trusted only with their pinned fingerprint.
# shellcheck source=../helpers/fetch.sh
source "$( cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P )/../helpers/fetch.sh"

# is_infra_managed: the steps the infra repo owns on its nodes step aside.
# shellcheck source=../helpers/infra.sh
source "$( cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P )/../helpers/infra.sh"

# Install Git Credential Manager from a pinned release .deb. The SHA-256 of
# each architecture's .deb is pinned here: following `latest` and checking it
# against the digest of the same release let a compromised release through.
# To bump: change the version, then copy the digest of each .deb asset:
#   gh release view <version> -R git-ecosystem/git-credential-manager --json assets -q '.assets[] | "\(.name) \(.digest)"'
install_gcm() {
  local arch asset_arch sha256
  # renovate: datasource=github-releases depName=git-ecosystem/git-credential-manager
  local version="v3.0.2"
  arch=$(dpkg --print-architecture)
  case "$arch" in
    amd64) asset_arch=x64 sha256="5e8d0d368c1fd5ff57bc33ffe4440e79638427490ef4691fea6bb08c07ed03ef" ;;
    arm64) asset_arch=arm64 sha256="ff118acac8550758c557be31730086e6eb356c91831daea0fd1d0af4aa75c8b1" ;;
    *)
      printf '%b' "${red}[error]${no_color} No pinned Git Credential Manager checksum for architecture '$arch' — not installed.\n"
      return 1 ;;
  esac
  install_deb_verified git-credential-manager \
    "https://github.com/git-ecosystem/git-credential-manager/releases/download/${version}/gcm-linux-${asset_arch}-${version#v}.deb" "$sha256"
}

install_lite_setup() {
  # Configure locale (prevents LC_* warnings on SSH login)
  printf '%b' "\n\n${red}[base] =>${no_color} Configure locale (en_US.UTF-8)\n\n"
  $SUDO apt-get install -y --no-install-recommends locales
  # Enable en_US.UTF-8 in locale.gen if not already present
  if ! grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen 2>/dev/null; then
    echo 'en_US.UTF-8 UTF-8' | $SUDO tee -a /etc/locale.gen
  fi
  $SUDO locale-gen en_US.UTF-8
  $SUDO update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

  # Install Docker CE from official upstream repository
  printf '%b' "\n\n${red}[base] =>${no_color} Install Docker CE\n\n"
  # Not on a node managed by the infra repo: k3s brings its own containerd,
  # the infra `common` role removes Docker on every run (since 2026-11-04),
  # and Docker's iptables rules forward published ports around the host
  # firewall's input chain. A re-run here would put Docker back, with those
  # rules, until the next Ansible run. The infra sshd drop-in means the node
  # is theirs (is_infra_managed, os/helpers/infra.sh).
  if is_infra_managed; then
    printf '%b' "${red}[base]${no_color} Node managed by the infra repo ($INFRA_MARKER) — skipping Docker.\n"
  elif ! command -v docker &>/dev/null; then
    $SUDO apt-get install -y --no-install-recommends \
      ca-certificates \
      gnupg
    $SUDO install -m 0755 -d /etc/apt/keyrings
    # Detect distro ID (debian or ubuntu) for the correct Docker repo URL
    _DOCKER_DISTRO=$(. /etc/os-release && echo "${ID}")
    _DOCKER_CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME}")
    # Docker's release key, the same for Debian and Ubuntu. Fingerprint as
    # Docker's install docs print it (9DC8 5822 9FC7 DD38 854A  E2D8 8D81 803C
    # 0EBF CD88), equal to the key served on 2026-11-12.
    install_apt_key "https://download.docker.com/linux/${_DOCKER_DISTRO}/gpg" \
      "9DC858229FC7DD38854AE2D88D81803C0EBFCD88" /etc/apt/keyrings/docker.gpg
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
    printf '%b' "${red}[base]${no_color} Docker already installed — skipping.\n"
  fi

  # Install apt packages
  printf '%b' "\n\n${red}[base] =>${no_color} Install apt packages (cli)\n\n"
  $SUDO apt-get install -y --no-install-recommends \
    ansible \
    fzf \
    ssh \
    tree \
    watch \
    yq \
    rsync

  # Install Terraform from HashiCorp's official apt repository
  printf '%b' "\n\n${red}[base] =>${no_color} Install Terraform\n\n"
  if ! command -v terraform &>/dev/null; then
    $SUDO install -m 0755 -d /etc/apt/keyrings
    # HashiCorp's package signing key. Fingerprint recorded on 2026-11-12 from
    # the key apt.releases.hashicorp.com served that day (created 2026-09-09,
    # expires 2031-09-08): trust on first use, not checked against a second
    # source. HashiCorp rotates this key; a new one aborts here until the
    # fingerprint is updated from its announcement.
    install_apt_key https://apt.releases.hashicorp.com/gpg \
      "D55C0D1AC78A8D8126CB631CFC9CA96ACA026560" /etc/apt/keyrings/hashicorp.gpg
    _HASHICORP_CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME}")
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp.gpg] \
https://apt.releases.hashicorp.com ${_HASHICORP_CODENAME} main" \
      | $SUDO tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
    $SUDO apt-get update -qq
    $SUDO apt-get install -y --no-install-recommends terraform
  else
    printf '%b' "${red}[base]${no_color} terraform already installed — skipping.\n"
  fi

  # Install Git Credential Manager: config/git/.gitconfig sets
  # `credential.helper = manager`. `git-credential-manager configure` is
  # deliberately NOT run: it would write the helper into ~/.gitconfig, the
  # tracked and linked config.
  printf '%b' "\n\n${red}[base] =>${no_color} Install Git Credential Manager\n\n"
  if ! command -v git-credential-manager &>/dev/null; then
    install_gcm
  else
    printf '%b' "${red}[base]${no_color} git-credential-manager already installed — skipping.\n"
  fi

  # Linux has no default GCM credential store. On a server without a desktop
  # the in-memory git credential cache is the safe choice (nothing on disk).
  # Set system-wide (/etc/gitconfig) so the tracked ~/.gitconfig stays
  # untouched, and only when no store is configured yet.
  if command -v git-credential-manager &>/dev/null && ! git config --get credential.credentialStore >/dev/null; then
    $SUDO git config --system credential.credentialStore cache
  fi
}

install_additional_setup() {
  # Install additional apt packages
  printf '%b' "\n\n${red}[base] =>${no_color} Install apt packages (cli)\n\n"
  $SUDO apt-get install -y --no-install-recommends \
    gh \
    nmap

  # proto is installed by os/helpers/proto.sh, which init.sh runs right after
  # this profile (pinned release, SHA-256 checked) — not from a remote script.
}


# Install lite setup
install_lite_setup

# Install full setup
if [ "$FULL_MODE_SETUP" = "true" ]; then
  install_additional_setup
fi
