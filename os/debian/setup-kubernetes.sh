#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

SUDO="${SUDO:-}"

load_kernel_modules() {
  printf "\n\n${red}[kubernetes] =>${no_color} Load required kernel modules (overlay, br_netfilter)\n\n"

  # Persist modules across reboots
  $SUDO tee /etc/modules-load.d/k8s.conf > /dev/null <<'EOF'
overlay
br_netfilter
EOF

  $SUDO modprobe overlay
  $SUDO modprobe br_netfilter

  # CRI sysctl requirements — use priority 100 to override 99-security.conf for ip_forward
  $SUDO tee /etc/sysctl.d/100-kubernetes-cri.conf > /dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

  $SUDO sysctl --system > /dev/null 2>&1

  printf "${red}[kubernetes]${no_color} Kernel modules loaded and sysctl applied.\n"
}

install_lite_setup() {
  # Load kernel modules required for Kubernetes
  load_kernel_modules

  # Install kubectl via official Kubernetes apt repository
  printf "\n\n${red}[kubernetes] =>${no_color} Install kubectl\n\n"
  if ! command -v kubectl &>/dev/null; then
    $SUDO mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key \
      | $SUDO gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    $SUDO chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' \
      | $SUDO tee /etc/apt/sources.list.d/kubernetes.list
    $SUDO chmod 644 /etc/apt/sources.list.d/kubernetes.list
    $SUDO apt-get update -qq
    $SUDO apt-get install -y kubectl
  else
    printf "${red}[kubernetes]${no_color} kubectl already installed — skipping.\n"
  fi
}

install_additional_setup() {
  # Install helm via official apt repository
  printf "\n\n${red}[kubernetes] =>${no_color} Install helm\n\n"
  if ! command -v helm &>/dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  else
    printf "${red}[kubernetes]${no_color} helm already installed — skipping.\n"
  fi

  # Install k9s
  printf "\n\n${red}[kubernetes] =>${no_color} Install k9s\n\n"
  if ! command -v k9s &>/dev/null; then
    K9S_VERSION=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name')
    K9S_ARCH=$(dpkg --print-architecture)
    curl -fsSL -o /tmp/k9s.deb "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_linux_${K9S_ARCH}.deb"
    $SUDO dpkg -i /tmp/k9s.deb
    rm -f /tmp/k9s.deb
  else
    printf "${red}[kubernetes]${no_color} k9s already installed — skipping.\n"
  fi
}


# Install lite setup
install_lite_setup

# Install full setup
if [ "$FULL_MODE_SETUP" = "true" ]; then
  install_additional_setup
fi
