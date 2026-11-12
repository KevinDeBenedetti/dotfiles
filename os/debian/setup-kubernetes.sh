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
# the key with that fingerprint (2026-11-12; until then the key was piped from
# curl straight into `gpg --dearmor`). A rotated or swapped key aborts the run.
# The file must hold that one key only. Same function as in setup-base.sh
# (each script runs on its own).
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

load_kernel_modules() {
  printf '%b' "\n\n${red}[kubernetes] =>${no_color} Load required kernel modules (overlay, br_netfilter)\n\n"

  # Persist modules across reboots
  $SUDO mkdir -p /etc/modules-load.d
  $SUDO tee /etc/modules-load.d/k8s.conf > /dev/null <<'EOF'
overlay
br_netfilter
EOF

  # Best-effort: module loading needs a real (privileged) kernel; tolerated in
  # containers / minimal kernels where modprobe can't load these.
  $SUDO modprobe overlay || true
  $SUDO modprobe br_netfilter || true

  # CRI sysctl requirements. The file must sort AFTER 99-security.conf, which
  # sets ip_forward = 0: systemd-sysctl orders names as text, so the former
  # 100-kubernetes-cri.conf came BEFORE 99-… and lost at every boot (found on
  # an infra-managed node on 2026-11-04). 99-zz-… sorts after it.
  $SUDO rm -f /etc/sysctl.d/100-kubernetes-cri.conf
  $SUDO tee /etc/sysctl.d/99-zz-kubernetes-cri.conf > /dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

  $SUDO sysctl --system > /dev/null 2>&1 || true

  printf '%b' "${red}[kubernetes]${no_color} Kernel modules loaded and sysctl applied.\n"
}

install_lite_setup() {
  # Load kernel modules required for Kubernetes
  load_kernel_modules

  # Install kubectl via official Kubernetes apt repository
  printf '%b' "\n\n${red}[kubernetes] =>${no_color} Install kubectl\n\n"
  if ! command -v kubectl &>/dev/null; then
    # The key of pkgs.k8s.io (the "isv:kubernetes OBS Project" key): one key
    # for every minor's repository, v1.32 and v1.36 served the same one on
    # 2026-11-12. Its expiry (2026-12-29 that day) is extended on the same
    # key, so the fingerprint outlives it.
    install_apt_key https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key \
      "DE15B14486CD377B9E876E1A234654DA9A296436" /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' \
      | $SUDO tee /etc/apt/sources.list.d/kubernetes.list
    $SUDO chmod 644 /etc/apt/sources.list.d/kubernetes.list
    $SUDO apt-get update -qq
    $SUDO apt-get install -y kubectl
  else
    printf '%b' "${red}[kubernetes]${no_color} kubectl already installed — skipping.\n"
  fi
}

install_additional_setup() {
  # Install helm via the official get-helm-3 script (it verifies the release
  # tarball checksum). Downloaded to a file first so an HTTP error or a
  # truncated download never runs a partial script.
  printf '%b' "\n\n${red}[kubernetes] =>${no_color} Install helm\n\n"
  if ! command -v helm &>/dev/null; then
    local helm_installer
    helm_installer=$(mktemp)
    curl -fsSL -o "$helm_installer" https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    bash "$helm_installer"
    rm -f "$helm_installer"
  else
    printf '%b' "${red}[kubernetes]${no_color} helm already installed — skipping.\n"
  fi

  # Install k9s
  printf '%b' "\n\n${red}[kubernetes] =>${no_color} Install k9s\n\n"
  if ! command -v k9s &>/dev/null; then
    # `|| true` so a failed/rate-limited API call doesn't abort under `set -e`;
    # the guard below turns an empty/invalid tag into a clean skip instead of a
    # broken "download//k9s..." URL and a failing `dpkg -i`.
    K9S_VERSION=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name' || true)
    if [[ ! "$K9S_VERSION" =~ ^v[0-9] ]]; then
      printf "%b[error]%b Could not resolve latest k9s version from the GitHub API (got '%s') — skipping k9s install.\n" "$red" "$no_color" "$K9S_VERSION"
    else
      K9S_ARCH=$(dpkg --print-architecture)
      K9S_DEB="k9s_linux_${K9S_ARCH}.deb"
      K9S_URL="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}"
      # Private temp dir (not a predictable /tmp path) and checksum verified
      # against the release's checksums.sha256 before dpkg runs as root.
      K9S_TMP=$(mktemp -d)
      curl -fsSL -o "$K9S_TMP/$K9S_DEB" "$K9S_URL/$K9S_DEB"
      curl -fsSL -o "$K9S_TMP/checksums.sha256" "$K9S_URL/checksums.sha256"
      if (cd "$K9S_TMP" && awk -v f="$K9S_DEB" '$2 == f' checksums.sha256 | grep -q . \
          && awk -v f="$K9S_DEB" '$2 == f' checksums.sha256 | sha256sum -c --quiet -); then
        $SUDO dpkg -i "$K9S_TMP/$K9S_DEB"
      else
        printf "%b[error]%b k9s checksum verification failed — skipping k9s install.\n" "$red" "$no_color"
      fi
      rm -rf "$K9S_TMP"
    fi
  else
    printf '%b' "${red}[kubernetes]${no_color} k9s already installed — skipping.\n"
  fi
}


# Install lite setup
install_lite_setup

# Install full setup
if [ "$FULL_MODE_SETUP" = "true" ]; then
  install_additional_setup
fi
