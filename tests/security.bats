#!/usr/bin/env bats

# Tests for setup-security.sh script structure and function definitions.
# These tests validate the script without running it on the host —
# they check syntax, function presence, and generated config content.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  SECURITY_SCRIPT="$REPO_ROOT/os/debian/setup-security.sh"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'
}

# --- Script existence & syntax ---

@test "setup-security.sh exists" {
  assert_file_exists "$SECURITY_SCRIPT"
}

@test "setup-security.sh has valid bash syntax" {
  run bash -n "$SECURITY_SCRIPT"
  assert_success
}

@test "setup-security.sh starts with shebang" {
  run head -1 "$SECURITY_SCRIPT"
  assert_output "#!/bin/bash"
}

# --- Function definitions ---

@test "setup-security.sh defines configure_ssh" {
  run grep -c 'configure_ssh()' "$SECURITY_SCRIPT"
  assert_success
  assert_output "1"
}

@test "setup-security.sh defines install_configure_ufw" {
  run grep -c 'install_configure_ufw()' "$SECURITY_SCRIPT"
  assert_success
  assert_output "1"
}

@test "setup-security.sh defines install_configure_fail2ban" {
  run grep -c 'install_configure_fail2ban()' "$SECURITY_SCRIPT"
  assert_success
  assert_output "1"
}

@test "setup-security.sh defines install_configure_crowdsec" {
  run grep -c 'install_configure_crowdsec()' "$SECURITY_SCRIPT"
  assert_success
  assert_output "1"
}

@test "setup-security.sh defines install_configure_unattended_upgrades" {
  run grep -c 'install_configure_unattended_upgrades()' "$SECURITY_SCRIPT"
  assert_success
  assert_output "1"
}

@test "setup-security.sh defines configure_sysctl_hardening" {
  run grep -c 'configure_sysctl_hardening()' "$SECURITY_SCRIPT"
  assert_success
  assert_output "1"
}

@test "setup-security.sh defines disable_unused_services" {
  run grep -c 'disable_unused_services()' "$SECURITY_SCRIPT"
  assert_success
  assert_output "1"
}

@test "setup-security.sh defines secure_shared_memory" {
  run grep -c 'secure_shared_memory()' "$SECURITY_SCRIPT"
  assert_success
  assert_output "1"
}

@test "setup-security.sh defines install_audit_tools" {
  run grep -c 'install_audit_tools()' "$SECURITY_SCRIPT"
  assert_success
  assert_output "1"
}

@test "setup-security.sh defines install_lite_setup" {
  run grep -c 'install_lite_setup()' "$SECURITY_SCRIPT"
  assert_success
  assert_output "1"
}

@test "setup-security.sh defines install_additional_setup" {
  run grep -c 'install_additional_setup()' "$SECURITY_SCRIPT"
  assert_success
  assert_output "1"
}

# --- SSH hardening config content ---

@test "SSH config disables root login" {
  # Off by default; key-only root is the fallback when no other admin exists.
  run grep -F 'local permit_root="no"' "$SECURITY_SCRIPT"
  assert_success
}

@test "SSH config disables password auth" {
  run grep 'PasswordAuthentication no' "$SECURITY_SCRIPT"
  assert_success
}

@test "SSH config limits auth tries to 3" {
  run grep 'MaxAuthTries 3' "$SECURITY_SCRIPT"
  assert_success
}

@test "SSH config disables X11 forwarding" {
  run grep 'X11Forwarding no' "$SECURITY_SCRIPT"
  assert_success
}

@test "SSH config sets idle timeout" {
  run grep 'ClientAliveInterval 300' "$SECURITY_SCRIPT"
  assert_success
}

@test "SSH drop-in sorts first so earlier drop-ins cannot override it" {
  # sshd keeps the first value read; a 99-* file loses to 50-cloud-init.conf.
  run grep -F 'sshd_config.d/00-hardening.conf' "$SECURITY_SCRIPT"
  assert_success
  run grep -E 'hardening_conf=.*99-hardening' "$SECURITY_SCRIPT"
  assert_failure
}

@test "SSH hardening checks the effective config with sshd -T" {
  run grep -F 'sshd -T' "$SECURITY_SCRIPT"
  assert_success
}

# --- Docker vs UFW ---

@test "Docker published ports default to loopback (UFW does not filter them)" {
  run grep -F '.ip = "127.0.0.1"' "$SECURITY_SCRIPT"
  assert_success
  run bash -c "sed -n '/^install_lite_setup()/,/^}/p' '$SECURITY_SCRIPT'"
  assert_output --partial "configure_docker_default_bind"
}

# --- Remote installers ---

@test "CrowdSec is installed from its signed apt repo, never a remote script" {
  run bash -c "sed -n '/^install_configure_crowdsec()/,/^}/p' '$SECURITY_SCRIPT' | grep -v '^ *#'"
  assert_success
  refute_output --partial 'install.crowdsec.net'
  refute_output --regexp '(\| *|\$SUDO +)(ba)?sh[[:space:]]'
  assert_output --partial 'signed-by=$keyring] https://packagecloud.io/crowdsec/crowdsec/any/ any main'
}

@test "CrowdSec apt key is checked against a pinned fingerprint before it is trusted" {
  run bash -c "sed -n '/^install_configure_crowdsec()/,/^}/p' '$SECURITY_SCRIPT'"
  assert_success
  assert_output --regexp 'key_fpr="[0-9A-F]{40}"'
  assert_output --partial 'grep -qx "$key_fpr"'
  # The file holds that one key only: an appended key would be trusted too.
  assert_output --partial 'END { if (n == 1) print fpr }'
  # The check comes before the key is written into the apt keyring.
  local check dearmor
  check=$(grep -n 'grep -qx "$key_fpr"' "$SECURITY_SCRIPT" | cut -d: -f1)
  dearmor=$(grep -n 'gpg --dearmor < "$key_tmp"' "$SECURITY_SCRIPT" | cut -d: -f1)
  [ -n "$check" ] && [ -n "$dearmor" ] && [ "$check" -lt "$dearmor" ]
}

# --- Fail2Ban config content ---

@test "Fail2Ban config uses systemd backend" {
  run grep 'backend  = systemd' "$SECURITY_SCRIPT"
  assert_success
}

@test "Fail2Ban config uses ufw banaction" {
  run grep 'banaction = ufw' "$SECURITY_SCRIPT"
  assert_success
}

@test "Fail2Ban config enables sshd jail" {
  run grep 'enabled  = true' "$SECURITY_SCRIPT"
  assert_success
}

# --- SSH port consistency (sshd drop-in / ufw / fail2ban) ---
# A custom SSH_PORT must reach all three places, or the firewall/jail protect
# the wrong port. These guard against re-hardcoding a literal port anywhere.

@test "SSH port is parameterized via \$SSH_PORT in the sshd drop-in" {
  run grep -F 'Port $SSH_PORT' "$SECURITY_SCRIPT"
  assert_success
}

@test "ufw allows the configured \$SSH_PORT" {
  run grep -F 'ufw allow "$SSH_PORT/tcp"' "$SECURITY_SCRIPT"
  assert_success
}

@test "fail2ban sshd jail watches the configured \$SSH_PORT" {
  run grep -F 'port     = $SSH_PORT' "$SECURITY_SCRIPT"
  assert_success
}

@test "fail2ban sshd jail does not hardcode the SSH port" {
  # Regression guard for the original bug: port = ssh (or a literal number)
  # ignored a custom SSH_PORT.
  run grep -E '^port[[:space:]]+=[[:space:]]+(ssh|[0-9]+)[[:space:]]*$' "$SECURITY_SCRIPT"
  assert_failure
}

# --- Sysctl hardening content ---

@test "sysctl disables IP forwarding" {
  run grep 'net.ipv4.ip_forward = 0' "$SECURITY_SCRIPT"
  assert_success
}

@test "sysctl enables SYN cookies" {
  run grep 'net.ipv4.tcp_syncookies = 1' "$SECURITY_SCRIPT"
  assert_success
}

@test "sysctl enables reverse path filtering" {
  run grep 'net.ipv4.conf.all.rp_filter = 1' "$SECURITY_SCRIPT"
  assert_success
}

@test "sysctl disables ICMP redirects" {
  run grep 'net.ipv4.conf.all.accept_redirects = 0' "$SECURITY_SCRIPT"
  assert_success
}

# --- Unattended upgrades content ---

@test "unattended-upgrades disables automatic reboot" {
  run grep 'Automatic-Reboot "false"' "$SECURITY_SCRIPT"
  assert_success
}

@test "unattended-upgrades enables daily update check" {
  run grep 'Update-Package-Lists "1"' "$SECURITY_SCRIPT"
  assert_success
}

@test "unattended-upgrades matches Debian's security archive by label" {
  # The Ubuntu-style "${distro_id}:${distro_codename}-security" origin matches
  # nothing on Debian.
  run grep -F 'codename=${distro_codename}-security,label=Debian-Security' "$SECURITY_SCRIPT"
  assert_success
  run bash -c "grep -v '^ *#' '$SECURITY_SCRIPT' | grep -F '\"\${distro_id}:\${distro_codename}-security\"'"
  assert_failure
}

@test "unattended-upgrades clears the packaged origins and leaves the conffile alone" {
  run grep -F '#clear Unattended-Upgrade::Origins-Pattern;' "$SECURITY_SCRIPT"
  assert_success
  run grep -F 'tee /etc/apt/apt.conf.d/50unattended-upgrades' "$SECURITY_SCRIPT"
  assert_failure
}

# --- Fail2Ban dependencies ---

@test "fail2ban is installed with python3-systemd for its systemd backend" {
  run grep -E 'apt-get install .*fail2ban python3-systemd' "$SECURITY_SCRIPT"
  assert_success
}

# --- SSH lockout safeguards ---

# Defines has_admin_ssh_login from the script (without running the script)
# with getent and the sudo prefix stubbed: root and alice are in group sudo,
# alice's authorized_keys is $ALICE_KEYS.
load_admin_check() {
  SUDO=""
  SSH_ALLOWED_USERS="${SSH_ALLOWED_USERS:-}"
  getent() {
    case "$1 $2" in
      "group sudo") echo "sudo:x:27:root,alice" ;;
      "passwd alice") echo "alice:x:1000:1000::$BATS_TEST_TMPDIR/alice:/bin/bash" ;;
      "passwd root") echo "root:x:0:0::/root:/bin/bash" ;;
    esac
  }
  eval "$(sed -n '/^has_admin_ssh_login()/,/^}/p' "$SECURITY_SCRIPT")"
}

@test "root login is disabled only when a sudo user can log in with a key" {
  run grep -F 'PermitRootLogin ${permit_root}' "$SECURITY_SCRIPT"
  assert_success
  run grep -F 'permit_root="prohibit-password"' "$SECURITY_SCRIPT"
  assert_success
}

@test "has_admin_ssh_login fails when only root has keys" {
  load_admin_check
  run has_admin_ssh_login
  assert_failure
}

@test "has_admin_ssh_login succeeds for a sudo user with authorized_keys" {
  mkdir -p "$BATS_TEST_TMPDIR/alice/.ssh"
  echo "ssh-ed25519 AAAA test" > "$BATS_TEST_TMPDIR/alice/.ssh/authorized_keys"
  load_admin_check
  run has_admin_ssh_login
  assert_success
}

@test "has_admin_ssh_login ignores an empty authorized_keys" {
  mkdir -p "$BATS_TEST_TMPDIR/alice/.ssh"
  : > "$BATS_TEST_TMPDIR/alice/.ssh/authorized_keys"
  load_admin_check
  run has_admin_ssh_login
  assert_failure
}

@test "has_admin_ssh_login ignores a sudo user left out of SSH_ALLOWED_USERS" {
  mkdir -p "$BATS_TEST_TMPDIR/alice/.ssh"
  echo "ssh-ed25519 AAAA test" > "$BATS_TEST_TMPDIR/alice/.ssh/authorized_keys"
  SSH_ALLOWED_USERS="deploy"
  load_admin_check
  run has_admin_ssh_login
  assert_failure
}

@test "an sshd drop-in that breaks a valid config is moved aside" {
  run grep -F 'mv "$hardening_conf" "${hardening_conf}.rejected"' "$SECURITY_SCRIPT"
  assert_success
  # Only when sshd -t passed before the write (a container fails it either way).
  run grep -F 'sshd_ok_before=true' "$SECURITY_SCRIPT"
  assert_success
}

# --- Lite vs full mode ---

@test "lite setup calls core security functions" {
  # Extract the install_lite_setup function body
  run bash -c "sed -n '/^install_lite_setup()/,/^}/p' '$SECURITY_SCRIPT'"
  assert_success
  assert_output --partial "configure_ssh"
  assert_output --partial "install_configure_ufw"
  assert_output --partial "install_configure_fail2ban"
  assert_output --partial "install_configure_unattended_upgrades"
  assert_output --partial "configure_sysctl_hardening"
  assert_output --partial "disable_unused_services"
  assert_output --partial "secure_shared_memory"
}

@test "additional setup includes crowdsec and audit tools" {
  run bash -c "sed -n '/^install_additional_setup()/,/^}/p' '$SECURITY_SCRIPT'"
  assert_success
  assert_output --partial "install_configure_crowdsec"
  assert_output --partial "install_audit_tools"
}

@test "full mode is gated on FULL_MODE_SETUP variable" {
  run grep 'FULL_MODE_SETUP' "$SECURITY_SCRIPT"
  assert_success
  assert_output --partial '"true"'
}
