#!/bin/bash

set -euo pipefail

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

SUDO="${SUDO:-}"
# Default so `set -u` doesn't trip when run standalone (init.sh exports it)
FULL_MODE_SETUP="${FULL_MODE_SETUP:-false}"

# install_apt_key <url> <fingerprint> <keyring>
# Downloads an apt repository key and writes it into <keyring> only when it is
# the key with that fingerprint. Until 2026-11-12 the keys were piped from curl
# straight into `gpg --dearmor`: apt then trusted, for every package of that
# repository, whatever the URL served that day. A rotated or swapped key now
# aborts the run instead. The file must hold that one key only: an extra key
# appended to it would land in the keyring too. Same check as
# install_configure_crowdsec in setup-security.sh and install_apt_key in
# setup-kubernetes.sh (each script runs on its own).
install_apt_key() {
  local url="$1" key_fpr="$2" keyring="$3"
  local key_tmp gnupg_tmp
  key_tmp=$(mktemp)
  gnupg_tmp=$(mktemp -d)
  curl -fsSL -o "$key_tmp" "$url"
  if ! GNUPGHOME="$gnupg_tmp" gpg --show-keys --with-colons "$key_tmp" 2>/dev/null \
      | awk -F: '$1 == "pub" { n++ } $1 == "fpr" && !fpr { fpr = $10 } END { if (n == 1) print fpr }' \
      | grep -qx "$key_fpr"; then
    rm -rf "$key_tmp" "$gnupg_tmp"
    printf '%b' "${red}[error]${no_color} apt key from $url does not match fingerprint $key_fpr — not trusting it.\n"
    return 1
  fi
  $SUDO install -m 0755 -d "$(dirname "$keyring")"
  GNUPGHOME="$gnupg_tmp" gpg --dearmor < "$key_tmp" | $SUDO tee "$keyring" > /dev/null
  rm -rf "$key_tmp" "$gnupg_tmp"
  $SUDO chmod 644 "$keyring"
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
  # rules, until the next Ansible run. Same marker as configure_ssh: the infra
  # sshd drop-in means the node is theirs.
  local infra_conf="/etc/ssh/sshd_config.d/00-infra-hardening.conf"
  if [[ -f "$infra_conf" ]]; then
    printf '%b' "${red}[base]${no_color} Node managed by the infra repo ($infra_conf) — skipping Docker.\n"
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
  # `credential.helper = manager`. Latest release .deb, checked against the
  # SHA-256 digest GitHub publishes for the asset before apt installs it as
  # root. `git-credential-manager configure` is deliberately NOT run: it would
  # write the helper into ~/.gitconfig, the tracked and linked config.
  printf '%b' "\n\n${red}[base] =>${no_color} Install Git Credential Manager\n\n"
  if ! command -v git-credential-manager &>/dev/null; then
    case "$(dpkg --print-architecture)" in
      amd64) _GCM_ARCH=x64 ;;
      arm64) _GCM_ARCH=arm64 ;;
      *) _GCM_ARCH="" ;;
    esac
    # `|| true` so a failed/rate-limited API call skips GCM instead of aborting
    # the whole profile under `set -e`; the guard below reports it.
    _GCM_URL="" _GCM_DIGEST=""
    read -r _GCM_URL _GCM_DIGEST < <(curl -fsSL https://api.github.com/repos/git-ecosystem/git-credential-manager/releases/latest 2>/dev/null \
      | jq -r --arg a "$_GCM_ARCH" '.assets[] | select(.name | test("^gcm-linux-" + $a + "-[0-9.]+\\.deb$")) | "\(.browser_download_url) \(.digest)"' 2>/dev/null \
      | head -n 1) || true
    if [[ -z "$_GCM_ARCH" || "$_GCM_URL" != https://* || "$_GCM_DIGEST" != sha256:* ]]; then
      printf "%b[error]%b Could not resolve a Git Credential Manager .deb for %s — skipping.\n" "$red" "$no_color" "$(dpkg --print-architecture)"
    else
      _GCM_TMP=$(mktemp -d)
      curl -fsSL -o "$_GCM_TMP/gcm.deb" "$_GCM_URL"
      if printf '%s  %s\n' "${_GCM_DIGEST#sha256:}" "$_GCM_TMP/gcm.deb" | sha256sum -c --quiet -; then
        $SUDO apt-get install -y --no-install-recommends "$_GCM_TMP/gcm.deb"
      else
        printf "%b[error]%b Git Credential Manager checksum verification failed — skipping.\n" "$red" "$no_color"
      fi
      rm -rf "$_GCM_TMP"
    fi
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

  # Install proto
  if ! command -v proto &>/dev/null; then
    printf '%b' "\n\n${red}[base] =>${no_color} Install proto\n\n"
    curl -fsSL https://moonrepo.dev/install/proto.sh | bash -s -- --yes
  fi
}


# Install lite setup
install_lite_setup

# Install full setup
if [ "$FULL_MODE_SETUP" = "true" ]; then
  install_additional_setup
fi
