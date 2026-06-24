#!/bin/bash

# Strict mode: abort on real errors (failed apt/curl|gpg installs, unset vars,
# broken pipes) instead of swallowing them. Environment-dependent service
# actions (systemctl/ufw/sshd/sysctl/modprobe/apparmor) are individually guarded
# with `|| true` below, since they legitimately fail in containers / non-systemd
# hosts and must not abort the hardening run.
set -euo pipefail

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

SUDO="${SUDO:-}"
# Default so `set -u` doesn't trip when run standalone (init.sh exports it)
FULL_MODE_SETUP="${FULL_MODE_SETUP:-false}"

# Configurable via env vars (set before sourcing or in init.sh)
SSH_PORT="${SSH_PORT:-22}"
SSH_ALLOWED_USERS="${SSH_ALLOWED_USERS:-}"

# ──────────────────────────────────────────────
# SSH Hardening
# ──────────────────────────────────────────────
configure_ssh() {
  printf '%b' "\n\n${red}[security] =>${no_color} Harden SSH configuration (port: $SSH_PORT)\n\n"

  local hardening_conf="/etc/ssh/sshd_config.d/99-hardening.conf"

  # Build AllowUsers directive if env var is set
  local allow_users_line=""
  if [[ -n "$SSH_ALLOWED_USERS" ]]; then
    allow_users_line="AllowUsers $SSH_ALLOWED_USERS"
  fi

  # Create a drop-in config for hardening (overrides defaults)
  $SUDO tee "$hardening_conf" > /dev/null <<EOF
# SSH Hardening — managed by dotfiles setup-security.sh

# Non-standard port (reduce automated scan noise)
Port $SSH_PORT

# Disable root login
PermitRootLogin no

# Disable password authentication (key-only)
PasswordAuthentication no

# Disable empty passwords
PermitEmptyPasswords no

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
UsePAM yes
${allow_users_line}
EOF

  $SUDO chmod 600 "$hardening_conf"

  # Validate sshd configuration before restarting. Both the check and the restart
  # are best-effort: sshd may be absent / unable to start in a container, which
  # must not abort the rest of the hardening run (the config file is already
  # written above).
  if $SUDO sshd -t 2>/dev/null; then
    $SUDO systemctl restart sshd || true
    printf '%b' "${red}[security]${no_color} SSH hardening applied and service restarted.\n"
  else
    printf '%b' "${red}[error]${no_color} SSH config validation failed — not restarting sshd.\n"
    printf '%b' "${red}[error]${no_color} Review $hardening_conf and fix errors.\n"
  fi
}

# ──────────────────────────────────────────────
# UFW (Uncomplicated Firewall)
# ──────────────────────────────────────────────
install_configure_ufw() {
  printf '%b' "\n\n${red}[security] =>${no_color} Install and configure UFW\n\n"

  $SUDO apt-get install -y --no-install-recommends ufw

  # ufw needs a real netfilter backend (NET_ADMIN); these are best-effort so the
  # run still completes in containers / unprivileged environments.
  # Reset rules (non-interactive)
  $SUDO ufw --force reset || true

  # Default policies: deny incoming, allow outgoing
  $SUDO ufw default deny incoming || true
  $SUDO ufw default allow outgoing || true

  # Allow SSH on configured port
  $SUDO ufw allow "$SSH_PORT/tcp" comment 'SSH' || true

  # Allow HTTP/HTTPS for web servers
  $SUDO ufw allow http || true
  $SUDO ufw allow https || true

  # Enable UFW (non-interactive)
  $SUDO ufw --force enable || true

  printf '%b' "${red}[security]${no_color} UFW configured and enabled.\n"
  $SUDO ufw status verbose || true
}

# ──────────────────────────────────────────────
# Fail2Ban
# ──────────────────────────────────────────────
install_configure_fail2ban() {
  printf '%b' "\n\n${red}[security] =>${no_color} Install and configure Fail2Ban\n\n"

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

  # Best-effort: systemd may be unavailable (e.g. containers).
  $SUDO systemctl enable fail2ban || true
  $SUDO systemctl restart fail2ban || true

  printf '%b' "${red}[security]${no_color} Fail2Ban configured and started.\n"
  $SUDO fail2ban-client status || true
}

# ──────────────────────────────────────────────
# CrowdSec (collaborative IDS/IPS)
# ──────────────────────────────────────────────
install_configure_crowdsec() {
  printf '%b' "\n\n${red}[security] =>${no_color} Install and configure CrowdSec\n\n"

  if ! command -v cscli &>/dev/null; then
    # Install CrowdSec repository and package
    curl -s https://install.crowdsec.net | $SUDO bash
    $SUDO apt-get install -y --no-install-recommends crowdsec

    # Install the firewall bouncer (works with iptables/nftables)
    $SUDO apt-get install -y --no-install-recommends crowdsec-firewall-bouncer-iptables
  else
    printf '%b' "${red}[security]${no_color} CrowdSec already installed — skipping.\n"
  fi

  # Install recommended collections
  $SUDO cscli collections install crowdsecurity/linux 2>/dev/null || true
  $SUDO cscli collections install crowdsecurity/sshd 2>/dev/null || true

  $SUDO systemctl enable crowdsec || true
  $SUDO systemctl restart crowdsec || true

  printf '%b' "${red}[security]${no_color} CrowdSec configured and started.\n"
  $SUDO cscli metrics 2>/dev/null || true
}

# ──────────────────────────────────────────────
# Unattended Upgrades (automatic security patches)
# ──────────────────────────────────────────────
install_configure_unattended_upgrades() {
  printf '%b' "\n\n${red}[security] =>${no_color} Install and configure unattended-upgrades\n\n"

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

  printf '%b' "${red}[security]${no_color} Unattended-upgrades configured (security patches only).\n"
}

# ──────────────────────────────────────────────
# Kernel / sysctl hardening
# ──────────────────────────────────────────────
configure_sysctl_hardening() {
  printf '%b' "\n\n${red}[security] =>${no_color} Apply sysctl kernel hardening\n\n"

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

# TIME_WAIT assassination protection (RFC 1337)
net.ipv4.tcp_rfc1337 = 1

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

# Kernel hardening
# Restrict kernel pointer exposure in /proc
kernel.kptr_restrict = 2
# Restrict access to kernel logs
kernel.dmesg_restrict = 1
# Full ASLR (Address Space Layout Randomization)
kernel.randomize_va_space = 2
# Restrict ptrace to parent processes only
kernel.yama.ptrace_scope = 1
# Harden BPF JIT compiler
net.core.bpf_jit_harden = 2
# Prevent null pointer dereference exploits
vm.mmap_min_addr = 65536

# Filesystem hardening
# No core dumps for setuid binaries
fs.suid_dumpable = 0
# Protect symlinks in world-writable sticky directories
fs.protected_symlinks = 1
# Protect hardlinks — only owner can follow
fs.protected_hardlinks = 1
# Restrict FIFO creation in sticky directories
fs.protected_fifos = 2
# Restrict regular file creation in sticky directories
fs.protected_regular = 2
EOF

  # Best-effort: reloading sysctl can fail on read-only / container kernels.
  $SUDO sysctl --system > /dev/null 2>&1 || true

  printf '%b' "${red}[security]${no_color} Sysctl hardening applied.\n"
}

# ──────────────────────────────────────────────
# Disable unused services
# ──────────────────────────────────────────────
disable_unused_services() {
  printf '%b' "\n\n${red}[security] =>${no_color} Disable unused services\n\n"

  local services=(
    avahi-daemon
    cups
    rpcbind
  )

  for svc in "${services[@]}"; do
    if systemctl is-enabled "$svc" 2>/dev/null | grep -q "enabled"; then
      $SUDO systemctl disable --now "$svc" || true
      printf '%b' "${red}[security]${no_color} Disabled: $svc\n"
    fi
  done
}

# ──────────────────────────────────────────────
# Secure shared memory and /tmp
# ──────────────────────────────────────────────
secure_shared_memory() {
  printf '%b' "\n\n${red}[security] =>${no_color} Secure shared memory and /tmp\n\n"

  local shm_entry="tmpfs /run/shm tmpfs defaults,noexec,nosuid 0 0"
  local tmp_entry="tmpfs /tmp tmpfs defaults,noexec,nosuid,nodev,size=1G 0 0"

  if ! grep -q "/run/shm" /etc/fstab; then
    echo "$shm_entry" | $SUDO tee -a /etc/fstab > /dev/null
    printf '%b' "${red}[security]${no_color} Shared memory secured in /etc/fstab.\n"
  else
    printf '%b' "${red}[security]${no_color} Shared memory entry already present — skipping.\n"
  fi

  if ! grep -q "^tmpfs /tmp" /etc/fstab; then
    echo "$tmp_entry" | $SUDO tee -a /etc/fstab > /dev/null
    printf '%b' "${red}[security]${no_color} /tmp secured (noexec,nosuid,nodev) in /etc/fstab.\n"
  else
    printf '%b' "${red}[security]${no_color} /tmp entry already present — skipping.\n"
  fi
}

# ──────────────────────────────────────────────
# AppArmor
# ──────────────────────────────────────────────
configure_apparmor() {
  printf '%b' "\n\n${red}[security] =>${no_color} Ensure AppArmor is enabled and enforcing\n\n"

  $SUDO apt-get install -y --no-install-recommends apparmor apparmor-utils

  # Enable AppArmor on boot
  if ! grep -q "apparmor=1" /proc/cmdline 2>/dev/null; then
    if [ -f /etc/default/grub ]; then
      $SUDO sed -i 's|GRUB_CMDLINE_LINUX="\(.*\)"|GRUB_CMDLINE_LINUX="\1 apparmor=1 security=apparmor"|' /etc/default/grub
      $SUDO update-grub 2>/dev/null || true
      printf '%b' "${red}[security]${no_color} AppArmor boot parameters added to GRUB.\n"
    fi
  fi

  $SUDO systemctl enable apparmor || true
  $SUDO systemctl start apparmor || true

  # Set all loaded profiles to enforce mode
  $SUDO aa-enforce /etc/apparmor.d/* 2>/dev/null || true

  printf '%b' "${red}[security]${no_color} AppArmor enabled and profiles set to enforce.\n"
  $SUDO aa-status --verbose 2>/dev/null | head -20 || true
}

# ──────────────────────────────────────────────
# Install security audit tools
# ──────────────────────────────────────────────
install_audit_tools() {
  printf '%b' "\n\n${red}[security] =>${no_color} Install security audit tools\n\n"

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
  # AppArmor setup is kernel/grub/systemd-dependent (and pulls packages that may
  # be unavailable in minimal/container images) — treat the whole step as
  # best-effort so it never aborts the rest of the hardening run.
  configure_apparmor || true
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
