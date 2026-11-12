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
# Opt-in: remount /tmp as a size-capped noexec tmpfs. Off by default because
# `noexec /tmp` breaks apt/dpkg postinst scripts and build tooling, and the
# 1G cap is wrong for small VPSes. Set HARDEN_TMP=true to enable.
HARDEN_TMP="${HARDEN_TMP:-false}"

# ──────────────────────────────────────────────
# SSH Hardening
# ──────────────────────────────────────────────

# Succeeds when a non-root member of the sudo group has a non-empty
# authorized_keys and, when SSH_ALLOWED_USERS is set, is listed in it.
has_admin_ssh_login() {
  local members user home
  members=$(getent group sudo 2>/dev/null | cut -d: -f4 | tr ',' ' ')
  for user in $members; do
    [[ "$user" = root ]] && continue
    if [[ -n "$SSH_ALLOWED_USERS" && " $SSH_ALLOWED_USERS " != *" $user "* ]]; then
      continue
    fi
    home=$(getent passwd "$user" | cut -d: -f6)
    [[ -n "$home" ]] || continue
    $SUDO test -s "$home/.ssh/authorized_keys" && return 0
  done
  return 1
}

configure_ssh() {
  # A node managed by the infra repo (Ansible role `common`) owns sshd: it
  # writes /etc/ssh/sshd_config.d/00-infra-hardening.conf with the port the
  # Hetzner firewall and UFW open. 00-hardening.conf sorts BEFORE it, and sshd
  # keeps the FIRST value it reads for each keyword, so on an `init.sh` re-run
  # this step would move sshd to $SSH_PORT — off the only reachable port. Leave
  # sshd to Ansible there, and drop this script's own drop-ins so they stop
  # shadowing the infra one at the next sshd restart (the `common` role removes
  # them too, common_sshd_foreign_dropins, but only while it can still log in).
  local infra_conf="/etc/ssh/sshd_config.d/00-infra-hardening.conf"
  if [[ -f "$infra_conf" ]]; then
    printf '%b' "\n\n${red}[security] =>${no_color} sshd is managed by the infra repo ($infra_conf): skipping SSH hardening.\n\n"
    $SUDO rm -f /etc/ssh/sshd_config.d/00-hardening.conf /etc/ssh/sshd_config.d/99-hardening.conf
    return 0
  fi

  printf '%b' "\n\n${red}[security] =>${no_color} Harden SSH configuration (port: $SSH_PORT)\n\n"

  # sshd keeps the FIRST value it reads for each keyword and includes the
  # drop-ins in lexical order, so a late 99-* file loses to any earlier one
  # (e.g. cloud-init's 50-cloud-init.conf with "PasswordAuthentication yes").
  # 00- makes these settings win.
  local hardening_conf="/etc/ssh/sshd_config.d/00-hardening.conf"
  # Drop the file written under the old name by previous runs.
  $SUDO rm -f /etc/ssh/sshd_config.d/99-hardening.conf

  # Build AllowUsers directive if env var is set
  local allow_users_line=""
  if [[ -n "$SSH_ALLOWED_USERS" ]]; then
    allow_users_line="AllowUsers $SSH_ALLOWED_USERS"
  fi

  # Root login is only turned off when another way in exists: a member of the
  # sudo group with a non-empty authorized_keys, allowed by AllowUsers when it
  # is set. Otherwise root keeps key-only login (passwords stay off), so a VPS
  # provisioned with root's key alone is not locked out.
  local permit_root="no"
  if ! has_admin_ssh_login; then
    permit_root="prohibit-password"
    printf '%b' "${red}[warning]${no_color} No sudo user with SSH keys found — keeping root login (key only).\n"
    printf '%b' "${red}[warning]${no_color} Create one with init.sh -u <user>, then re-run to disable root login.\n"
  fi

  # Baseline before writing: if sshd -t already fails (no host keys or
  # privilege-separation dir, e.g. in a container), a failure after the write
  # says nothing about the drop-in, which is then kept.
  local sshd_ok_before=false
  $SUDO sshd -t 2>/dev/null && sshd_ok_before=true

  # Create a drop-in config for hardening (overrides defaults)
  $SUDO tee "$hardening_conf" > /dev/null <<EOF
# SSH Hardening — managed by dotfiles setup-security.sh

# Non-standard port (reduce automated scan noise)
Port $SSH_PORT

# Disable root login (prohibit-password when no other admin can log in)
PermitRootLogin ${permit_root}

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

  # Validate before restarting. If the config was valid before the write and
  # is not after it, the drop-in broke it: move it aside, or sshd would fail
  # at its next restart or reboot and take SSH access down with it. The
  # restart itself stays best-effort (no systemd in a container).
  if $SUDO sshd -t 2>/dev/null; then
    $SUDO systemctl restart sshd || true
    printf '%b' "${red}[security]${no_color} SSH hardening applied and service restarted.\n"
  elif [[ "$sshd_ok_before" = true ]]; then
    $SUDO mv "$hardening_conf" "${hardening_conf}.rejected"
    printf '%b' "${red}[error]${no_color} The SSH hardening drop-in made the sshd config invalid — moved to ${hardening_conf}.rejected, sshd left as it was.\n"
    printf '%b' "${red}[error]${no_color} Check it with: sudo sshd -t -f /etc/ssh/sshd_config\n"
    return 1
  else
    printf '%b' "${red}[error]${no_color} sshd -t fails on this host, before and after the hardening drop-in — not restarting sshd.\n"
    printf '%b' "${red}[error]${no_color} Review $hardening_conf and run: sudo sshd -t\n"
  fi

  # Check the effective configuration, not just the file written above: another
  # drop-in can still override it. Best-effort (sshd -T needs host keys).
  # sshd -T spells prohibit-password by its old name, without-password.
  local effective directive expected_root="$permit_root"
  [[ "$expected_root" = prohibit-password ]] && expected_root="without-password"
  if effective=$($SUDO sshd -T 2>/dev/null); then
    for directive in "permitrootlogin $expected_root" "passwordauthentication no"; do
      if ! grep -qx "$directive" <<<"$effective"; then
        printf '%b' "${red}[warning]${no_color} Effective sshd config lacks '$directive' — another file in /etc/ssh/sshd_config.d/ overrides it.\n"
      fi
    done
  fi
}

# ──────────────────────────────────────────────
# UFW (Uncomplicated Firewall)
# ──────────────────────────────────────────────
install_configure_ufw() {
  # A node managed by the infra repo has no UFW any more (removed there on
  # 2026-08-17: it rewrites the netfilter tables k3s owns) and its ports come
  # from the Hetzner firewall or the `host_firewall` role. This step would
  # `ufw --force reset` and re-enable UFW with 22/80/443 only: the WireGuard
  # port, 6443, 8472 and infra's SSH port gone, kubectl and SSH over the VPN
  # with them, until an Ansible run that could no longer connect. Same marker
  # as configure_ssh: the infra sshd drop-in means the node is theirs.
  local infra_conf="/etc/ssh/sshd_config.d/00-infra-hardening.conf"
  if [[ -f "$infra_conf" ]]; then
    printf '%b' "\n\n${red}[security] =>${no_color} firewall managed by the infra repo ($infra_conf): skipping UFW.\n\n"
    return 0
  fi

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

  # python3-systemd is only a Recommends of fail2ban, but `backend = systemd`
  # below cannot start without it: fail2ban would exit at once, hidden by the
  # `|| true` on its restart.
  $SUDO apt-get install -y --no-install-recommends fail2ban python3-systemd

  # Create local jail config (never edit jail.conf directly).
  # Unquoted heredoc so $SSH_PORT expands — the jail must watch the same port
  # the sshd drop-in listens on (see configure_ssh), not the default 22.
  $SUDO tee /etc/fail2ban/jail.local > /dev/null <<EOF
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
port     = $SSH_PORT
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
    # CrowdSec's apt repository, set up inline instead of running the
    # https://install.crowdsec.net script as root: that script only adds this
    # packagecloud repo (same keyring and list paths, so hosts it set up are
    # overwritten, not duplicated). The key must match the pinned fingerprint
    # (recorded 2026-11-12 from packagecloud.io) before apt trusts it; a
    # rotated or swapped key aborts the run instead of being trusted silently.
    # The file must hold that one key only: an extra key appended to it would
    # land in the keyring too.
    local key_fpr="6A89E3C2303A901A889971D3376ED5326E93CD0C"
    local keyring="/etc/apt/keyrings/crowdsec_crowdsec-archive-keyring.gpg"
    local key_tmp gnupg_tmp
    key_tmp=$(mktemp)
    gnupg_tmp=$(mktemp -d)
    $SUDO apt-get install -y --no-install-recommends ca-certificates gnupg
    curl -fsSL -o "$key_tmp" https://packagecloud.io/crowdsec/crowdsec/gpgkey
    if ! GNUPGHOME="$gnupg_tmp" gpg --show-keys --with-colons "$key_tmp" 2>/dev/null \
        | awk -F: '$1 == "pub" { n++ } $1 == "fpr" && !fpr { fpr = $10 } END { if (n == 1) print fpr }' \
        | grep -qx "$key_fpr"; then
      rm -rf "$key_tmp" "$gnupg_tmp"
      printf '%b' "${red}[error]${no_color} CrowdSec apt key does not match fingerprint $key_fpr — not installing CrowdSec.\n"
      return 1
    fi
    $SUDO install -m 0755 -d /etc/apt/keyrings
    GNUPGHOME="$gnupg_tmp" gpg --dearmor < "$key_tmp" | $SUDO tee "$keyring" > /dev/null
    rm -rf "$key_tmp" "$gnupg_tmp"
    $SUDO chmod 644 "$keyring"
    echo "deb [signed-by=$keyring] https://packagecloud.io/crowdsec/crowdsec/any/ any main" \
      | $SUDO tee /etc/apt/sources.list.d/crowdsec_crowdsec.list > /dev/null
    $SUDO apt-get update -qq
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

  # Restrict unattended-upgrades to security patches. Written to its own file
  # instead of 50unattended-upgrades: that one is a dpkg conffile, and editing
  # it makes every package upgrade prompt about it. `#clear` drops the origins
  # the packaged file lists (all stable point updates on Debian); apt reads the
  # files in order, so 52-… comes after 50-… and wins.
  # Debian's security archive is matched by label, not by the Ubuntu-style
  # "${distro_id}:${distro_codename}-security" origin, which matches nothing on
  # Debian (Debian ships the codename-security suite under origin
  # "Debian", label "Debian-Security").
  $SUDO tee /etc/apt/apt.conf.d/52dotfiles-unattended-upgrades > /dev/null <<'EOF'
// Security patches only — managed by dotfiles setup-security.sh
#clear Unattended-Upgrade::Allowed-Origins;
#clear Unattended-Upgrade::Origins-Pattern;
Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
    "origin=Ubuntu,archive=${distro_codename}-security,label=Ubuntu";
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

  # Harden /dev/shm — the canonical shared-memory tmpfs on modern Debian.
  # (/run/shm is only a legacy symlink to it, so mounting there hardens nothing.)
  local shm_entry="tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0"
  local tmp_entry="tmpfs /tmp tmpfs defaults,noexec,nosuid,nodev,size=1G 0 0"

  if ! grep -qE '[[:space:]]/dev/shm[[:space:]]' /etc/fstab; then
    echo "$shm_entry" | $SUDO tee -a /etc/fstab > /dev/null
    printf '%b' "${red}[security]${no_color} Shared memory (/dev/shm) secured in /etc/fstab.\n"
  else
    printf '%b' "${red}[security]${no_color} Shared memory entry already present — skipping.\n"
  fi

  if [ "$HARDEN_TMP" = "true" ]; then
    if ! grep -q "^tmpfs /tmp" /etc/fstab; then
      echo "$tmp_entry" | $SUDO tee -a /etc/fstab > /dev/null
      printf '%b' "${red}[security]${no_color} /tmp secured (noexec,nosuid,nodev,size=1G) in /etc/fstab.\n"
    else
      printf '%b' "${red}[security]${no_color} /tmp entry already present — skipping.\n"
    fi
  else
    printf '%b' "${red}[security]${no_color} /tmp tmpfs hardening skipped (set HARDEN_TMP=true to enable; noexec/size=1G can break apt/dpkg/builds).\n"
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
# Docker published ports vs UFW
# ──────────────────────────────────────────────
# Docker inserts its own iptables rules ahead of UFW's, so `-p 5432:5432` would
# be reachable from the Internet despite `ufw default deny incoming`. Make
# published ports bind to loopback unless an address is given explicitly
# (`-p 0.0.0.0:80:80` for a service meant to be public).
configure_docker_default_bind() {
  command -v dockerd &>/dev/null || return 0
  printf '%b' "\n\n${red}[security] =>${no_color} Bind Docker published ports to 127.0.0.1 by default\n\n"

  local conf=/etc/docker/daemon.json current='{}' updated
  [ -f "$conf" ] && current=$($SUDO cat "$conf")
  updated=$(jq '.ip = "127.0.0.1"' <<<"$current")
  if [ "$updated" != "$current" ]; then
    $SUDO mkdir -p /etc/docker
    printf '%s\n' "$updated" | $SUDO tee "$conf" > /dev/null
    # Best-effort: systemd may be unavailable (e.g. containers).
    $SUDO systemctl restart docker || true
  fi
  printf '%b' "${red}[security]${no_color} Docker ports publish on 127.0.0.1 unless an address is given.\n"
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
install_lite_setup() {
  configure_ssh
  install_configure_ufw
  configure_docker_default_bind
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
