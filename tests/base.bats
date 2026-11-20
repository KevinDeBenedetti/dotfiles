#!/usr/bin/env bats

# Static tests for the base profiles (os/macos/setup-base.sh,
# os/debian/setup-base.sh): syntax and the Git Credential Manager install that
# config/git/.gitconfig (`credential.helper = manager`) depends on. Like
# security.bats, they read the scripts without running any install.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  MACOS_BASE="$REPO_ROOT/os/macos/setup-base.sh"
  DEBIAN_BASE="$REPO_ROOT/os/debian/setup-base.sh"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
}

lite_body() { sed -n '/^install_lite_setup()/,/^}/p' "$1"; }

@test "both base scripts have valid bash syntax" {
  run bash -n "$MACOS_BASE"
  assert_success
  run bash -n "$DEBIAN_BASE"
  assert_success
}

@test "the Debian lite profile leaves Docker off a node managed by the infra repo" {
  # Same marker as configure_ssh and the UFW step of setup-security.sh: the
  # infra `common` role removes Docker on every run, a re-run must not put it back.
  run lite_body "$DEBIAN_BASE"
  assert_output --partial 'infra_conf="/etc/ssh/sshd_config.d/00-infra-hardening.conf"'
  assert_output --partial 'if [[ -f "$infra_conf" ]]; then'
  # The marker is tested before the Docker apt source is written, and the
  # install sits in the branch after it.
  marker=$(lite_body "$DEBIAN_BASE" | grep -n 'if \[\[ -f "$infra_conf" \]\]' | head -n1 | cut -d: -f1)
  docker_source=$(lite_body "$DEBIAN_BASE" | grep -n 'sources.list.d/docker.list' | head -n1 | cut -d: -f1)
  [ -n "$marker" ] && [ -n "$docker_source" ] && [ "$marker" -lt "$docker_source" ]
  run bash -c "sed -n '/^install_lite_setup()/,/^}/p' '$DEBIAN_BASE' | sed -n '/if \[\[ -f \"\$infra_conf\" \]\]; then/,/^  elif/p' | grep -E 'apt-get|docker.list|usermod'"
  assert_failure
}

@test "both base profiles install Git Credential Manager in lite mode" {
  run lite_body "$MACOS_BASE"
  assert_output --partial 'install_cask git-credential-manager'
  run lite_body "$DEBIAN_BASE"
  assert_output --partial 'install_gcm'
}

@test "install_gcm installs one pinned Git Credential Manager .deb, checked against its pinned SHA-256" {
  SUDO="" red="" no_color=""
  dpkg() { echo "${FAKE_ARCH:-amd64}"; }
  install_deb_verified() { echo "$*"; }
  eval "$(sed -n '/^install_gcm()/,/^}/p' "$DEBIAN_BASE")"
  declare -F install_gcm >/dev/null || fail "install_gcm not found"
  run install_gcm
  assert_success
  assert_output --regexp '^git-credential-manager https://github\.com/git-ecosystem/git-credential-manager/releases/download/v[0-9.]+/gcm-linux-x64-[0-9.]+\.deb [0-9a-f]{64}$'
  # The asset name repeats the version, without its leading v.
  local v
  v=$(sed -n 's|.*/download/v\([0-9.]*\)/.*|\1|p' <<<"$output")
  assert_output --partial "gcm-linux-x64-$v.deb"
  FAKE_ARCH=arm64 run install_gcm
  assert_output --regexp 'gcm-linux-arm64-[0-9.]+\.deb'
  FAKE_ARCH=armhf run install_gcm
  assert_failure
  assert_output --partial "armhf"
}

@test "Git Credential Manager no longer follows the latest release" {
  run grep -c 'git-credential-manager/releases/latest' "$DEBIAN_BASE"
  assert_output "0"
}

@test "the Debian base script trusts an apt key only through install_apt_key" {
  # No key goes from curl straight into the keyring (2026-11-12): every key
  # passes the fingerprint check of install_apt_key (os/helpers/fetch.sh,
  # tested in fetch.bats).
  run grep -E 'gpg --dearmor' "$DEBIAN_BASE"
  assert_failure
}

@test "Docker's and HashiCorp's apt keys are installed with a pinned fingerprint" {
  run bash -c "grep -A1 'install_apt_key \"https://download.docker.com' '$DEBIAN_BASE'"
  assert_success
  assert_output --regexp '"[0-9A-F]{40}" /etc/apt/keyrings/docker\.gpg'
  run bash -c "grep -A1 'install_apt_key https://apt.releases.hashicorp.com/gpg' '$DEBIAN_BASE'"
  assert_success
  assert_output --regexp '"[0-9A-F]{40}" /etc/apt/keyrings/hashicorp\.gpg'
}

@test "GCM gets its Linux credential store system-wide, never via the linked ~/.gitconfig" {
  run grep -qF 'git config --system credential.credentialStore cache' "$DEBIAN_BASE"
  assert_success
  # `configure` and --global would write into the tracked, symlinked ~/.gitconfig
  # (comment lines may mention them; executable lines must not).
  run bash -c "grep -hvE '^[[:space:]]*#' '$MACOS_BASE' '$DEBIAN_BASE' | grep -E 'git-credential-manager configure|git config --global'"
  assert_failure
}
