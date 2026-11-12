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
  assert_output --partial 'git-ecosystem/git-credential-manager'
}

@test "the Debian GCM .deb is checked against GitHub's SHA-256 digest before install" {
  run lite_body "$DEBIAN_BASE"
  assert_output --partial '.digest'
  assert_output --partial 'sha256sum -c'
  # Never piped from curl into a shell or dpkg.
  run grep -E 'curl[^|]*git-credential-manager[^|]*\|[[:space:]]*(ba)?sh' "$DEBIAN_BASE"
  assert_failure
}

@test "the Debian base script trusts an apt key only after its fingerprint check" {
  # No key goes from curl straight into the keyring any more (2026-11-12).
  # (The old form put the pipe on a continuation line: match the pipe itself.)
  run grep -E '\|[[:space:]]*\$SUDO gpg --dearmor' "$DEBIAN_BASE"
  assert_failure
  run bash -c "sed -n '/^install_apt_key()/,/^}/p' '$DEBIAN_BASE'"
  assert_success
  assert_output --partial 'grep -qx "$key_fpr"'
  # The file holds that one key only: an appended key would be trusted too.
  assert_output --partial 'END { if (n == 1) print fpr }'
  assert_output --partial 'return 1'
  # The check comes before the key is written into the apt keyring.
  local check dearmor
  check=$(grep -n 'grep -qx "$key_fpr"' "$DEBIAN_BASE" | cut -d: -f1)
  dearmor=$(grep -n 'gpg --dearmor < "$key_tmp"' "$DEBIAN_BASE" | cut -d: -f1)
  [ -n "$check" ] && [ -n "$dearmor" ] && [ "$check" -lt "$dearmor" ]
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
