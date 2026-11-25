#!/usr/bin/env bats

# Tests for setup-security.sh. Nothing runs on the host: the SSH, UFW,
# Fail2Ban, sysctl and unattended-upgrades steps are run for real with their
# system commands stubbed and the files they render are read back; the other
# steps are checked in the source.

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

@test "the rendered SSH drop-in hardens sshd on the configured port" {
  mkdir -p "$BATS_TEST_TMPDIR/alice/.ssh"
  echo "ssh-ed25519 AAAA test" > "$BATS_TEST_TMPDIR/alice/.ssh/authorized_keys"
  SSH_PORT=2222
  run render_ssh_dropin
  assert_success
  run cat "$BATS_TEST_TMPDIR/00-hardening.conf"
  assert_line "Port 2222"
  assert_line "PermitRootLogin no"
  assert_line "PasswordAuthentication no"
  assert_line "PermitEmptyPasswords no"
  assert_line "MaxAuthTries 3"
  assert_line "X11Forwarding no"
  assert_line "AllowTcpForwarding no"
  assert_line "ClientAliveInterval 300"
  # Every setting line is a single "Keyword value" pair sshd can parse.
  run grep -Ev '^(#.*|[A-Za-z0-9]+ [^ ].*)?$' "$BATS_TEST_TMPDIR/00-hardening.conf"
  assert_failure
}

@test "the SSH drop-in is written to 00-hardening.conf, private, and sshd restarted" {
  run render_ssh_dropin
  assert_success
  run cat "$BATS_TEST_TMPDIR/calls"
  assert_line "tee /etc/ssh/sshd_config.d/00-hardening.conf"
  assert_line "chmod 600 /etc/ssh/sshd_config.d/00-hardening.conf"
  assert_line "rm -f /etc/ssh/sshd_config.d/99-hardening.conf"
  assert_line "systemctl restart sshd"
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
  # install_apt_key (os/helpers/fetch.sh, tested in fetch.bats) does the check;
  # the repository is written only after it passed.
  run bash -c "sed -n '/^install_configure_crowdsec()/,/^}/p' '$SECURITY_SCRIPT'"
  assert_success
  assert_output --regexp 'install_apt_key https://packagecloud\.io/crowdsec/crowdsec/gpgkey[^|]*"[0-9A-F]{40}" "\$keyring" \|\| return 1'
  local key list
  key=$(grep -n 'install_apt_key https://packagecloud.io' "$SECURITY_SCRIPT" | cut -d: -f1)
  list=$(grep -n 'sources.list.d/crowdsec_crowdsec.list' "$SECURITY_SCRIPT" | cut -d: -f1)
  [ -n "$key" ] && [ -n "$list" ] && [ "$key" -lt "$list" ]
}

# --- SSH port consistency (sshd drop-in / ufw / fail2ban) ---
# A custom SSH_PORT must reach all three places, or the firewall/jail protect
# the wrong port. These guard against re-hardcoding a literal port anywhere.

@test "ufw opens the configured SSH port, after denying incoming by default" {
  SUDO="" SSH_PORT=2222 red="" no_color=""
  load_infra_marker
  eval "$(sed -n '/^install_configure_ufw()/,/^}/p' "$SECURITY_SCRIPT")"
  apt-get() { :; }
  ufw() { echo "ufw $*" >> "$BATS_TEST_TMPDIR/calls"; }
  run install_configure_ufw
  assert_success
  run cat "$BATS_TEST_TMPDIR/calls"
  assert_line "ufw allow 2222/tcp comment SSH"
  assert_line "ufw default deny incoming"
  refute_line --regexp '^ufw allow 22(/tcp)?( |$)'
  local deny allow enable
  deny=$(grep -n 'default deny incoming' "$BATS_TEST_TMPDIR/calls" | cut -d: -f1)
  allow=$(grep -n 'allow 2222/tcp' "$BATS_TEST_TMPDIR/calls" | cut -d: -f1)
  enable=$(grep -n 'force enable' "$BATS_TEST_TMPDIR/calls" | cut -d: -f1)
  [ "$deny" -lt "$allow" ] && [ "$allow" -lt "$enable" ]
}

@test "a re-run keeps the rules of an active UFW: it resets an inactive one only" {
  # Rules added by hand since the first run (a VPN port, an app port) must
  # survive a re-run of the security profile.
  SUDO="" SSH_PORT=22 red="" no_color=""
  load_infra_marker
  eval "$(sed -n '/^install_configure_ufw()/,/^}/p' "$SECURITY_SCRIPT")"
  apt-get() { :; }
  ufw() {
    echo "ufw $*" >> "$BATS_TEST_TMPDIR/calls"
    [ "$1" = status ] && echo "Status: $UFW_STATE"
    return 0
  }
  UFW_STATE=active run install_configure_ufw
  assert_success
  # ufw translates its output: the state is read in the C locale.
  run cat "$BATS_TEST_TMPDIR/calls"
  refute_line --partial "reset"
  rm "$BATS_TEST_TMPDIR/calls"
  ufw() {
    echo "ufw $*" >> "$BATS_TEST_TMPDIR/calls"
    if [ "$1" = status ]; then
      if [ "${LC_ALL:-}" = C ]; then echo "Status: $UFW_STATE"; else echo "État : ${UFW_STATE/active/actif}"; fi
    fi
    return 0
  }
  UFW_STATE=active LC_ALL=fr_FR.UTF-8 run install_configure_ufw
  assert_success
  run cat "$BATS_TEST_TMPDIR/calls"
  refute_line --partial "reset"
  # The configured rules are still applied: `ufw allow` is idempotent.
  assert_line "ufw allow 22/tcp comment SSH"
  rm "$BATS_TEST_TMPDIR/calls"
  UFW_STATE=inactive run install_configure_ufw
  run cat "$BATS_TEST_TMPDIR/calls"
  assert_line "ufw --force reset"
}

@test "UFW is left out on a node managed by the infra repo" {
  SUDO="" SSH_PORT=22 red="" no_color=""
  load_infra_marker
  touch "$INFRA_MARKER"
  eval "$(sed -n '/^install_configure_ufw()/,/^}/p' "$SECURITY_SCRIPT")"
  apt-get() { echo "apt-get $*" >> "$BATS_TEST_TMPDIR/calls"; }
  ufw() { echo "ufw $*" >> "$BATS_TEST_TMPDIR/calls"; }
  run install_configure_ufw
  assert_success
  assert_output --partial "skipping UFW"
  assert_file_not_exists "$BATS_TEST_TMPDIR/calls"
}

# --- Sysctl hardening and unattended-upgrades (behaviour) ---

# render_hardening FUNCTION: runs that function of the script with `tee`
# writing each file under $ETC (named after its path's last part) and every
# other command logged to $CALLS, in place of the real system.
render_hardening() {
  ETC="$BATS_TEST_TMPDIR/etc" CALLS="$BATS_TEST_TMPDIR/calls"
  mkdir -p "$ETC"
  SUDO="" red="" no_color=""
  eval "$(sed -n "/^$1()/,/^}$/p" "$SECURITY_SCRIPT")"
  tee() { echo "tee $*" >> "$CALLS"; cat > "$ETC/${1##*/}"; }
  apt-get() { echo "apt-get $*" >> "$CALLS"; }
  sysctl() { echo "sysctl $*" >> "$CALLS"; }
  rm() { echo "rm $*" >> "$CALLS"; }
  "$1"
}

@test "the rendered sysctl file hardens the network stack, then is loaded" {
  render_hardening configure_sysctl_hardening
  run cat "$ETC/99-security.conf"
  assert_line 'net.ipv4.ip_forward = 0'
  assert_line 'net.ipv4.tcp_syncookies = 1'
  assert_line 'net.ipv4.conf.all.rp_filter = 1'
  assert_line 'net.ipv4.conf.all.accept_redirects = 0'
  assert_line 'kernel.kptr_restrict = 2'
  # Every setting is a `key = value` line sysctl can read.
  run grep -vE '^(#.*)?$|^[a-z0-9_.]+ = [0-9]+$' "$ETC/99-security.conf"
  assert_failure
  run cat "$CALLS"
  assert_line "tee /etc/sysctl.d/99-security.conf"
  assert_line "sysctl --system"
}

@test "IPv6 router advertisements stay accepted unless HARDEN_IPV6_RA=true (issue 126)" {
  # A VPS that gets its IPv6 route by SLAAC loses it with accept_ra = 0.
  HARDEN_IPV6_RA=false render_hardening configure_sysctl_hardening
  run grep -c accept_ra "$ETC/99-security.conf"
  assert_output 0
  assert_file_not_exists "$ETC/99-security-ipv6-ra.conf"
  # A drop-in left by an earlier opt-in run is removed.
  run cat "$CALLS"
  assert_line "rm -f /etc/sysctl.d/99-security-ipv6-ra.conf"
}

@test "HARDEN_IPV6_RA=true disables router advertisements in a drop-in of its own" {
  HARDEN_IPV6_RA=true render_hardening configure_sysctl_hardening
  run grep -c accept_ra "$ETC/99-security.conf"
  assert_output 0
  run grep -v '^#' "$ETC/99-security-ipv6-ra.conf"
  assert_output "net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0"
  # Written before the reload that applies it.
  run cat "$CALLS"
  assert_line "tee /etc/sysctl.d/99-security-ipv6-ra.conf"
  assert_equal "$(tail -n1 "$CALLS")" "sysctl --system"
}

@test "HARDEN_IPV6_RA defaults to false" {
  run grep -c '^HARDEN_IPV6_RA="${HARDEN_IPV6_RA:-false}"$' "$SECURITY_SCRIPT"
  assert_output 1
}

@test "unattended-upgrades checks daily and installs security patches only, never rebooting" {
  render_hardening install_configure_unattended_upgrades
  run cat "$ETC/20auto-upgrades"
  assert_line 'APT::Periodic::Update-Package-Lists "1";'
  assert_line 'APT::Periodic::Unattended-Upgrade "1";'
  run cat "$ETC/52dotfiles-unattended-upgrades"
  assert_line 'Unattended-Upgrade::Automatic-Reboot "false";'
  # Debian's security archive is matched by label: the Ubuntu-style
  # "${distro_id}:${distro_codename}-security" origin matches nothing there.
  assert_output --partial '"origin=Debian,codename=${distro_codename}-security,label=Debian-Security";'
  refute_output --partial '"${distro_id}:${distro_codename}-security"'
  run cat "$CALLS"
  assert_line --partial "apt-get install -y --no-install-recommends unattended-upgrades"
}

@test "unattended-upgrades clears the packaged origins and leaves the conffile alone" {
  render_hardening install_configure_unattended_upgrades
  run cat "$ETC/52dotfiles-unattended-upgrades"
  assert_line '#clear Unattended-Upgrade::Origins-Pattern;'
  assert_line '#clear Unattended-Upgrade::Allowed-Origins;'
  # 50unattended-upgrades is a dpkg conffile: editing it makes every package
  # upgrade prompt about it.
  assert_file_not_exists "$ETC/50unattended-upgrades"
}

@test "the AppArmor boot options are added to GRUB once, however often the profile runs" {
  # Before a reboot, /proc/cmdline does not show them yet: the guard must read
  # the file it edits.
  ROOT="$BATS_TEST_TMPDIR/root" red="" no_color=""
  mkdir -p "$ROOT/etc/default"
  echo 'GRUB_CMDLINE_LINUX="quiet"' > "$ROOT/etc/default/grub"
  # Every command run through $SUDO acts under $ROOT instead of /. GNU sed
  # syntax (`sed -i` with no suffix): gsed where sed is BSD's.
  in_root() {
    local a=() x
    for x in "$@"; do a+=("${x//\/etc\//$ROOT/etc/}"); done
    [ "${a[0]}" = sed ] && command -v gsed >/dev/null && a[0]=gsed
    "${a[@]}"
  }
  apt-get() { :; }; update-grub() { :; }; systemctl() { :; }; aa-status() { :; }
  aa-enforce() { echo "aa-enforce $*" >> "$BATS_TEST_TMPDIR/calls"; }
  # AppArmor is off on this host: the boot options are what turns it on.
  apparmor_active() { return 1; }
  SUDO=in_root
  eval "$(sed -n '/^configure_apparmor()/,/^}$/p' "$SECURITY_SCRIPT")"
  configure_apparmor > /dev/null
  configure_apparmor > /dev/null
  run cat "$ROOT/etc/default/grub"
  assert_output 'GRUB_CMDLINE_LINUX="quiet apparmor=1 security=apparmor"'
}

@test "GRUB is left alone where AppArmor is already active (issue 125)" {
  # Debian enables AppArmor by default since 10: no boot option to add.
  ROOT="$BATS_TEST_TMPDIR/root" red="" no_color=""
  mkdir -p "$ROOT/etc/default"
  echo 'GRUB_CMDLINE_LINUX="quiet"' > "$ROOT/etc/default/grub"
  in_root() {
    local a=() x
    for x in "$@"; do a+=("${x//\/etc\//$ROOT/etc/}"); done
    "${a[@]}"
  }
  apt-get() { :; }; systemctl() { :; }; aa-status() { :; }
  update-grub() { echo "update-grub" >> "$BATS_TEST_TMPDIR/calls"; }
  apparmor_active() { return 0; }
  SUDO=in_root
  eval "$(sed -n '/^configure_apparmor()/,/^}$/p' "$SECURITY_SCRIPT")"
  configure_apparmor > /dev/null
  run cat "$ROOT/etc/default/grub"
  assert_output 'GRUB_CMDLINE_LINUX="quiet"'
  assert_file_not_exists "$BATS_TEST_TMPDIR/calls"
}

@test "AppArmor profiles keep the mode their package ships them in" {
  # aa-enforce on every profile breaks the services whose profile is shipped
  # in complain mode on purpose.
  ROOT="$BATS_TEST_TMPDIR/root" red="" no_color=""
  apt-get() { :; }; systemctl() { :; }; aa-status() { :; }
  aa-enforce() { echo "aa-enforce $*" >> "$BATS_TEST_TMPDIR/calls"; }
  apparmor_active() { return 0; }
  SUDO=""
  eval "$(sed -n '/^configure_apparmor()/,/^}$/p' "$SECURITY_SCRIPT")"
  run configure_apparmor
  assert_success
  assert_file_not_exists "$BATS_TEST_TMPDIR/calls"
  refute_output --partial "enforce"
}

@test "apparmor_active reads the kernel module's enabled flag" {
  eval "$(sed -n '/^apparmor_active()/,/^}$/p' "$SECURITY_SCRIPT")"
  echo Y > "$BATS_TEST_TMPDIR/enabled"
  APPARMOR_ENABLED_FILE="$BATS_TEST_TMPDIR/enabled" run apparmor_active
  assert_success
  echo N > "$BATS_TEST_TMPDIR/enabled"
  APPARMOR_ENABLED_FILE="$BATS_TEST_TMPDIR/enabled" run apparmor_active
  assert_failure
  APPARMOR_ENABLED_FILE="$BATS_TEST_TMPDIR/missing" run apparmor_active
  assert_failure
}

# --- SSH lockout safeguards ---

# Defines is_infra_managed (os/helpers/infra.sh) with its marker moved into
# the test's temp dir: absent unless a test touches "$INFRA_MARKER".
load_infra_marker() {
  INFRA_MARKER="$BATS_TEST_TMPDIR/00-infra-hardening.conf"
  source "$REPO_ROOT/os/helpers/infra.sh"
}

# Defines has_admin_ssh_login and can_escalate from the script (without
# running the script) with getent, passwd and sudo stubbed: root and alice are
# in group sudo, alice's authorized_keys is under $BATS_TEST_TMPDIR/alice.
# alice's password status is $ALICE_PASSWD (`passwd -S`: P usable, L locked,
# NP none; P by default) and `sudo -l -U alice` prints $ALICE_SUDO_L.
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
  passwd() { [ "$1 $2" = "-S alice" ] && echo "alice ${ALICE_PASSWD:-P} 01/01/2026 0 99999 7 -1"; }
  sudo() { [ "$*" = "-l -U alice" ] && printf '%s\n' "${ALICE_SUDO_L:-    (ALL : ALL) ALL}"; }
  eval "$(sed -n '/^can_escalate()/,/^}/p;/^has_admin_ssh_login()/,/^}/p' "$SECURITY_SCRIPT")"
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

@test "has_admin_ssh_login ignores a sudo user who cannot escalate" {
  # init.sh -u creates the user with --disabled-password: without a NOPASSWD
  # rule, sudo asks for a password the account does not have.
  mkdir -p "$BATS_TEST_TMPDIR/alice/.ssh"
  echo "ssh-ed25519 AAAA test" > "$BATS_TEST_TMPDIR/alice/.ssh/authorized_keys"
  load_admin_check
  local status
  for status in L NP; do
    ALICE_PASSWD=$status run has_admin_ssh_login
    assert_failure
  done
  # A NOPASSWD rule is a way up without a password; one limited to a few
  # commands is not a way to root.
  ALICE_PASSWD=L ALICE_SUDO_L="    (ALL) NOPASSWD: ALL" run has_admin_ssh_login
  assert_success
  ALICE_PASSWD=L ALICE_SUDO_L="    (ALL) NOPASSWD: /usr/bin/systemctl" run has_admin_ssh_login
  assert_failure
}

@test "root login stays key-only while the only sudo user cannot escalate" {
  mkdir -p "$BATS_TEST_TMPDIR/alice/.ssh"
  echo "ssh-ed25519 AAAA test" > "$BATS_TEST_TMPDIR/alice/.ssh/authorized_keys"
  ALICE_PASSWD=L render_ssh_dropin
  run cat "$DROPIN"
  assert_line "PermitRootLogin prohibit-password"
}

@test "has_admin_ssh_login ignores a sudo user left out of SSH_ALLOWED_USERS" {
  mkdir -p "$BATS_TEST_TMPDIR/alice/.ssh"
  echo "ssh-ed25519 AAAA test" > "$BATS_TEST_TMPDIR/alice/.ssh/authorized_keys"
  SSH_ALLOWED_USERS="deploy"
  load_admin_check
  run has_admin_ssh_login
  assert_failure
}

# Runs the real configure_ssh with the system commands stubbed: the drop-in it
# renders lands in $DROPIN instead of /etc/ssh/sshd_config.d/ and each stubbed
# call is logged in $CALLS. The drop-in of the previous run set the port
# $PREVIOUS_PORT (none by default), and `systemctl` fails when $RESTART is not
# "ok". `sshd -t` answers $SSHD_T, one word per call
# ("ok" or "bad", the last one repeating): "ok bad" is a config the drop-in
# broke. The infra marker is $INFRA_MARKER, a path in the test's temp dir.
render_ssh_dropin() {
  load_admin_check
  load_infra_marker
  eval "$(sed -n '/^configure_ssh()/,/^}/p' "$SECURITY_SCRIPT")"
  DROPIN="$BATS_TEST_TMPDIR/00-hardening.conf"
  CALLS="$BATS_TEST_TMPDIR/calls"
  SSH_PORT="${SSH_PORT:-22}" red="" no_color=""
  # Unquoted on purpose: SSHD_T is split into one answer per word.
  # shellcheck disable=SC2206
  local sshd_t=(${SSHD_T:-ok}) sshd_t_calls=0
  tee() { echo "tee $*" >> "$CALLS"; cat > "$DROPIN"; }
  rm() { echo "rm $*" >> "$CALLS"; }
  mv() { echo "mv $*" >> "$CALLS"; }
  chmod() { echo "chmod $*" >> "$CALLS"; }
  systemctl() { echo "systemctl $*" >> "$CALLS"; [ "${RESTART:-ok}" = ok ]; }
  ufw() { echo "ufw $*" >> "$CALLS"; }
  ssh_dropin_port() { echo "${PREVIOUS_PORT:-}"; }
  sshd() {
    [ "$1" = -t ] || return 1
    local answer="${sshd_t[$sshd_t_calls]:-${sshd_t[${#sshd_t[@]}-1]}}"
    sshd_t_calls=$((sshd_t_calls + 1))
    [ "$answer" = ok ]
  }
  configure_ssh
}

@test "AllowUsers keeps root while root is the only way in" {
  # alice is in sudo but has no key and is not listed: root login is kept, so
  # AllowUsers must not shut root out (issue 50).
  SSH_ALLOWED_USERS="deploy"
  run render_ssh_dropin
  assert_success
  run cat "$BATS_TEST_TMPDIR/00-hardening.conf"
  assert_line "PermitRootLogin prohibit-password"
  assert_line "AllowUsers deploy root"
}

@test "AllowUsers lists root once when the owner already named it" {
  SSH_ALLOWED_USERS="root deploy"
  run render_ssh_dropin
  run cat "$BATS_TEST_TMPDIR/00-hardening.conf"
  assert_line "AllowUsers root deploy"
}

@test "AllowUsers leaves root out once a listed admin can log in" {
  mkdir -p "$BATS_TEST_TMPDIR/alice/.ssh"
  echo "ssh-ed25519 AAAA test" > "$BATS_TEST_TMPDIR/alice/.ssh/authorized_keys"
  SSH_ALLOWED_USERS="alice"
  run render_ssh_dropin
  run cat "$BATS_TEST_TMPDIR/00-hardening.conf"
  assert_line "PermitRootLogin no"
  assert_line "AllowUsers alice"
}

@test "no AllowUsers line is written when SSH_ALLOWED_USERS is empty" {
  SSH_ALLOWED_USERS=""
  run render_ssh_dropin
  run cat "$BATS_TEST_TMPDIR/00-hardening.conf"
  refute_line --partial "AllowUsers"
}

@test "an sshd drop-in that breaks a valid config is moved aside" {
  SSHD_T="ok bad"
  run render_ssh_dropin
  assert_failure
  assert_output --partial "moved to /etc/ssh/sshd_config.d/00-hardening.conf.rejected"
  run cat "$BATS_TEST_TMPDIR/calls"
  assert_line "mv /etc/ssh/sshd_config.d/00-hardening.conf /etc/ssh/sshd_config.d/00-hardening.conf.rejected"
  refute_line "systemctl restart sshd"
}

@test "the drop-in is kept, and sshd not restarted, where sshd -t fails either way" {
  # A container has no host keys: sshd -t fails before the write too, which
  # says nothing about the drop-in.
  SSHD_T="bad"
  run render_ssh_dropin
  assert_success
  assert_output --partial "sshd -t fails on this host, before and after"
  run cat "$BATS_TEST_TMPDIR/calls"
  refute_line --partial "mv "
  refute_line "systemctl restart sshd"
}

# --- SSH port change (issue 124) ---

@test "the firewall opens the SSH port before sshd is restarted on it" {
  # On a re-run with a new SSH_PORT, an active UFW must allow the port first:
  # a failure between the two steps would leave sshd on a closed port.
  local body ufw_line ssh_line
  body=$(sed -n '/^install_lite_setup()/,/^}/p' "$SECURITY_SCRIPT")
  ufw_line=$(grep -n '^  install_configure_ufw$' <<<"$body" | cut -d: -f1)
  ssh_line=$(grep -n '^  configure_ssh$' <<<"$body" | cut -d: -f1)
  [ -n "$ufw_line" ] && [ -n "$ssh_line" ] || fail "install_lite_setup lacks one of the two steps"
  [ "$ufw_line" -lt "$ssh_line" ] || fail "configure_ssh (line $ssh_line) runs before install_configure_ufw (line $ufw_line)"
}

@test "a changed SSH port is closed in UFW once sshd restarted on the new one" {
  PREVIOUS_PORT=22 SSH_PORT=2222 run render_ssh_dropin
  assert_success
  assert_output --partial "port 22 closed in UFW"
  run cat "$BATS_TEST_TMPDIR/calls"
  assert_line "ufw delete allow 22/tcp"
  local restart delete
  restart=$(grep -n '^systemctl restart sshd$' "$BATS_TEST_TMPDIR/calls" | cut -d: -f1)
  delete=$(grep -n '^ufw delete allow 22/tcp$' "$BATS_TEST_TMPDIR/calls" | cut -d: -f1)
  [ "$restart" -lt "$delete" ] || fail "the old port was closed before the restart"
}

@test "the previous SSH port stays open, with a warning, when sshd did not restart" {
  PREVIOUS_PORT=22 SSH_PORT=2222 RESTART=failed run render_ssh_dropin
  assert_success
  assert_output --partial "port 22 is still open in UFW"
  run cat "$BATS_TEST_TMPDIR/calls"
  refute_line --partial "ufw delete"
  PREVIOUS_PORT=22 SSH_PORT=2222 SSHD_T=bad run render_ssh_dropin
  run cat "$BATS_TEST_TMPDIR/calls"
  refute_line --partial "ufw delete"
}

@test "an unchanged SSH port, or a first run, closes nothing in UFW" {
  PREVIOUS_PORT=2222 SSH_PORT=2222 run render_ssh_dropin
  assert_success
  SSH_PORT=2222 run render_ssh_dropin
  assert_success
  run cat "$BATS_TEST_TMPDIR/calls"
  refute_line --partial "ufw delete"
}

@test "ssh_dropin_port reads the port a drop-in sets, and nothing from a missing one" {
  eval "$(sed -n '/^ssh_dropin_port()/,/^}/p' "$SECURITY_SCRIPT")"
  SUDO=""
  printf '%s\n' '# SSH Hardening' 'Port 2222' 'PermitRootLogin no' > "$BATS_TEST_TMPDIR/dropin.conf"
  run ssh_dropin_port "$BATS_TEST_TMPDIR/dropin.conf"
  assert_output "2222"
  run ssh_dropin_port "$BATS_TEST_TMPDIR/missing.conf"
  assert_output ""
}

@test "ssh_dropin_port does not abort the script on a first run, with no drop-in yet" {
  # setup-security.sh runs under set -euo pipefail: a failing read there ended
  # the whole profile right after "Harden SSH configuration" (Docker targets).
  printf '%s\n' 'Port 2222' 'Port 3333' > "$BATS_TEST_TMPDIR/two.conf"
  run bash -c "set -euo pipefail; SUDO=''; $(sed -n '/^ssh_dropin_port()/,/^}/p' "$SECURITY_SCRIPT")
    p=\$(ssh_dropin_port '$BATS_TEST_TMPDIR/missing.conf'); echo \"missing:[\$p]\"
    p=\$(ssh_dropin_port '$BATS_TEST_TMPDIR/two.conf'); echo \"two:[\$p]\""
  assert_success
  assert_line "missing:[]"
  assert_line "two:[2222]"
}

# --- Nodes managed by the infra repo ---

# Runs the real install_configure_fail2ban with the system commands stubbed:
# the jail it renders lands in $JAIL and each stubbed call is logged in $CALLS.
# The infra marker is $INFRA_MARKER, a path in the test's temp dir.
render_fail2ban_jail() {
  SUDO="" SSH_PORT=2222 red="" no_color=""
  JAIL="$BATS_TEST_TMPDIR/jail.local"
  CALLS="$BATS_TEST_TMPDIR/calls"
  load_infra_marker
  eval "$(sed -n '/^install_configure_fail2ban()/,/^}/p' "$SECURITY_SCRIPT")"
  tee() { cat > "$JAIL"; }
  apt-get() { echo "apt-get $*" >> "$CALLS"; }
  systemctl() { echo "systemctl $*" >> "$CALLS"; }
  fail2ban-client() { :; }
  install_configure_fail2ban
}

@test "is_infra_managed follows the infra sshd drop-in marker" {
  load_infra_marker
  run is_infra_managed
  assert_failure
  load_infra_marker
  touch "$INFRA_MARKER"
  run is_infra_managed
  assert_success
}

@test "the infra marker defaults to the sshd drop-in the infra repo writes" {
  run bash -c "unset INFRA_MARKER; source '$REPO_ROOT/os/helpers/infra.sh'; echo \"\$INFRA_MARKER\""
  assert_output "/etc/ssh/sshd_config.d/00-infra-hardening.conf"
}

@test "the marker path is written once, in the shared helper" {
  run grep -rlF '00-infra-hardening.conf' "$REPO_ROOT/os"
  assert_output "$REPO_ROOT/os/helpers/infra.sh"
}

@test "SSH hardening is left out on a node managed by the infra repo" {
  # Its own drop-ins are dropped too: they sort before the infra one and would
  # win at the next sshd restart.
  load_infra_marker
  touch "$INFRA_MARKER"
  run render_ssh_dropin
  assert_success
  assert_output --partial "skipping SSH hardening"
  assert_file_not_exists "$BATS_TEST_TMPDIR/00-hardening.conf"
  run cat "$BATS_TEST_TMPDIR/calls"
  assert_output "rm -f /etc/ssh/sshd_config.d/00-hardening.conf /etc/ssh/sshd_config.d/99-hardening.conf"
}

@test "Fail2Ban renders a ufw jail on the configured port on a standalone host" {
  run render_fail2ban_jail
  assert_success
  run cat "$BATS_TEST_TMPDIR/jail.local"
  assert_line "banaction = ufw"
  assert_line "port     = 2222"
  assert_line "backend  = systemd"
  assert_line "enabled  = true"
  # One port line, the configured one: no leftover literal or "ssh".
  run grep -c '^port ' "$BATS_TEST_TMPDIR/jail.local"
  assert_output "1"
  run cat "$BATS_TEST_TMPDIR/calls"
  # python3-systemd: the systemd backend cannot start without it.
  assert_line --regexp '^apt-get install .*fail2ban python3-systemd$'
  assert_line "systemctl restart fail2ban"
}

@test "Fail2Ban is left out on a node managed by the infra repo (issue 54)" {
  # UFW is skipped there, so a jail with banaction = ufw could not ban anyone,
  # and it would watch \$SSH_PORT, not the port the infra drop-in sets.
  load_infra_marker
  touch "$INFRA_MARKER"
  run render_fail2ban_jail
  assert_success
  assert_output --partial "skipping Fail2Ban"
  assert_file_not_exists "$BATS_TEST_TMPDIR/jail.local"
  assert_file_not_exists "$BATS_TEST_TMPDIR/calls"
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
