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

@test "GCM gets its Linux credential store system-wide, never via the linked ~/.gitconfig" {
  run grep -qF 'git config --system credential.credentialStore cache' "$DEBIAN_BASE"
  assert_success
  # `configure` and --global would write into the tracked, symlinked ~/.gitconfig
  # (comment lines may mention them; executable lines must not).
  run bash -c "grep -hvE '^[[:space:]]*#' '$MACOS_BASE' '$DEBIAN_BASE' | grep -E 'git-credential-manager configure|git config --global'"
  assert_failure
}
