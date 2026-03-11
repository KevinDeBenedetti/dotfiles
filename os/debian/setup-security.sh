#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

SUDO="${SUDO:-}"

# ──────────────────────────────────────────────
# SSH Hardening
# ──────────────────────────────────────────────
configure_ssh() {
  printf "\n\n${red}[security] =>${no_color} Harden SSH configuration\n\n"

  local sshd_config="/etc/ssh/sshd_config"
  local hardening_conf="/etc/ssh/sshd_config.d/99-hardening.conf"

  # Create a drop-in config for hardening (overrides defaults)
  $SUDO tee "$hardening_conf" > /dev/null <<'EOF'
# SSH Hardening — managed by dotfiles setup-security.sh

# Disable root login
PermitRootLogin no

# Disable password authentication (key-only)
PasswordAuthentication no

# Disable empty passwords
PermitEmptyPasswords no

# Use only SSH protocol 2
Protocol 2

# Limit authentication attempts
MaxAuthTries 3

# Disable X11 forwarding
X11Forwarding no

# Disable TCP forwarding (unless needed)
AllowTcpForwarding no

# Disable agent forwarding
AllowAgentForwarding no

# Log level
LogLevel VERBOSE

# Idle timeout: disconnect after 5 minutes of inactivity
ClientAliveInterval 300
ClientAliveCountMax 2

# Disable unused authentication methods
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
EOF

  $SUDO chmod 600 "$hardening_conf"

  # Validate sshd configuration before restarting
  if $SUDO sshd -t 2>/dev/null; then
    $SUDO systemctl restart sshd
    printf "${red}[security]${no_color} SSH hardening applied and service restarted.\n"
  else
    printf "${red}[error]${no_color} SSH config validation failed — not restarting sshd.\n"
    printf "${red}[error]${no_color} Review $hardening_conf and fix errors.\n"
    return 1
  fi
}

# ──────────────────────────────────────────────
# UFW (Uncomplicated Firewall)
# ──────────────────────────────────────────────
install_configure_ufw() {
  printf "\n\n${red}[security] =>${no_color} Install and configure UFW\n\n"

  $SUDO apt-get install -y --no-install-recommends ufw

  # Reset rules (non-interactive)
  $SUDO ufw --force reset

  # Default policies: deny incoming, allow outgoing
  $SUDO ufw default deny incoming
  $SUDO ufw default allow outgoing

  # Allow SSH (port 22)
  $SUDO ufw allow ssh

  # Allow HTTP/HTTPS for web servers
  $SUDO ufw allow http
  $SUDO ufw allow https

  # Enable UFW (non-interactive)
  $SUDO ufw --force enable

  printf "${red}[security]${no_color} UFW configured and enabled.\n"
  $SUDO ufw status verbose
}

# ──────────────────────────────────────────────
# Fail2Ban
# ──────────────────────────────────────────────
install_configure_fail2ban() {
  printf "\n\n${red}[security] =>${no_color} Install and configure Fail2Ban\n\n"

  $SUDO apt-get install -y --no-install-recommends fail2ban

  # Create local jail config (never edit jail.conf directly)
  $SUDO tee /etc/fail2ban/jail.local > /dev/null <<'EOF'
# Fail2Ban local configuration — managed by dotfiles setup-security.sh

[DEFAULT]
# Ban for 1 hour
bantime  = 1h
# Observation window
findtime = 10m
# Max failures before ban
maxretry = 3
# Use systemd backend on modern Debian
backend  = systemd
# Ban action using UFW
banaction = ufw

[sshd]
enabled  = true
port     = ssh
filter   = sshd
maxretry = 3
findtime = 5m
bantime  = 30m
EOF

  $SUDO systemctl enable fail2ban
  $SUDO systemctl restart fail2ban

  printf "${red}[security]${no_color} Fail2Ban configured and started.\n"
  $SUDO fail2ban-client status
}

# ──────────────────────────────────────────────
# CrowdSec (collaborative IDS/IPS)
# ──────────────────────────────────────────────
install_configure_crowdsec() {
  printf "\n\n${red}[security] =>${no_color} Install and configure CrowdSec\n\n"

  if ! command -v cscli &>/dev/null; then
    # Install CrowdSec repository and package
    curl -s https://install.crowdsec.net | $SUDO bash
    $SUDO apt-get install -y --no-install-recommends crowdsec

    # Install the firewall bouncer (works with iptables/nftables)
    $SUDO apt-get install -y --no-install-recommends crowdsec-firewall-bouncer-iptables
  else
    printf "${red}[security]${no_color} CrowdSec already installed — skipping.\n"
  fi

  # Install recommended collections
  $SUDO cscli collections install crowdsecurity/linux 2>/dev/null || true
  $SUDO cscli collections install crowdsecurity/sshd 2>/dev/null || true

  $SUDO systemctl enable crowdsec
  $SUDO systemctl restart crowdsec

  printf "${red}[security]${no_color} CrowdSec configured and started.\n"
  $SUDO cscli metrics 2>/dev/null || true
}

# ──────────────────────────────────────────────
# Unattended Upgrades (automatic security patches)
# ──────────────────────────────────────────────
install_configure_unattended_upgrades() {
  printf "\n\n${red}[security] =>${no_color} Install and configure unattended-upgrades\n\n"

  $SUDO apt-get install -y --no-install-recommends \
    unattended-upgrades \
    apt-listchanges

  # Enable automatic security updates
  $SUDO tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

  # Configure unattended-upgrades to only apply security patches
  $SUDO tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

  printf "${red}[security]${no_color} Unattended-upgrades configured (security patches only).\n"
}

# ──────────────────────────────────────────────
# Kernel / sysctl hardening
# ──────────────────────────────────────────────
configure_sysctl_hardening() {
  printf "\n\n${red}[security] =>${no_color} Apply sysctl kernel hardening\n\n"

  $SUDO tee /etc/sysctl.d/99-security.conf > /dev/null <<'EOF'
# Network hardening — managed by dotfiles setup-security.sh

# Disable IP forwarding (unless acting as a router)
net.ipv4.ip_forward = 0

# Disable ICMP redirects (prevent MITM)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Enable SYN flood protection
net.ipv4.tcp_syncookies = 1

# Log Martian packets (spoofed addresses)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP error responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Enable reverse path filtering (anti-spoofing)
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable IPv6 router advertisements
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
EOF

  $SUDO sysctl --system > /dev/null 2>&1

  printf "${red}[security]${no_color} Sysctl hardening applied.\n"
}

# ──────────────────────────────────────────────
# Disable unused services
# ──────────────────────────────────────────────
disable_unused_services() {
  printf "\n\n${red}[security] =>${no_color} Disable unused services\n\n"

  local services=(
    avahi-daemon
    cups
    rpcbind
  )

  for svc in "${services[@]}"; do
    if systemctl is-enabled "$svc" 2>/dev/null | grep -q "enabled"; then
      $SUDO systemctl disable --now "$svc"
      printf "${red}[security]${no_color} Disabled: $svc\n"
    fi
  done
}

# ──────────────────────────────────────────────
# Secure shared memory
# ──────────────────────────────────────────────
secure_shared_memory() {
  printf "\n\n${red}[security] =>${no_color} Secure shared memory\n\n"

  local fstab_entry="tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0"

  if ! grep -q "/run/shm" /etc/fstab; then
    echo "$fstab_entry" | $SUDO tee -a /etc/fstab > /dev/null
    printf "${red}[security]${no_color} Shared memory secured in /etc/fstab.\n"
  else
    printf "${red}[security]${no_color} Shared memory entry already present — skipping.\n"
  fi
}

# ──────────────────────────────────────────────
# Install security audit tools
# ──────────────────────────────────────────────
install_audit_tools() {
  printf "\n\n${red}[security] =>${no_color} Install security audit tools\n\n"

  $SUDO apt-get install -y --no-install-recommends \
    lynis \
    rkhunter \
    chkrootkit \
    auditd
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
install_lite_setup() {
  configure_ssh
  install_configure_ufw
  install_configure_fail2ban
  install_configure_unattended_upgrades
  configure_sysctl_hardening
  disable_unused_services
  secure_shared_memory
}

install_additional_setup() {
  install_configure_crowdsec
  install_audit_tools
}


# Install lite setup
install_lite_setup

# Install full setup
if [ "$FULL_MODE_SETUP" = "true" ]; then
  install_additional_setup
fi
