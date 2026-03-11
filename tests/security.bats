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
  run grep 'PermitRootLogin no' "$SECURITY_SCRIPT"
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
