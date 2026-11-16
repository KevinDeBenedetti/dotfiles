#!/usr/bin/env bats

# Tests for os/helpers/oh-my-zsh.sh: the oh-my-zsh installer runs only when it
# is the script pinned by commit and SHA-256. The functions run for real, with
# curl stubbed to "download" a fake installer.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  export TMPDIR="$BATS_TEST_TMPDIR"
  export RAN="$BATS_TEST_TMPDIR/installer-ran"
  # A fake installer that records that it ran, and with which settings.
  FAKE_INSTALLER="$BATS_TEST_TMPDIR/install.sh"
  printf 'echo "RUNZSH=$RUNZSH CHSH=$CHSH KEEP_ZSHRC=$KEEP_ZSHRC" > "$RAN"\n' > "$FAKE_INSTALLER"

  curl() {
    local out="" prev="" arg
    for arg in "$@"; do [ "$prev" = "-o" ] && out="$arg"; prev="$arg"; done
    echo "$*" >> "$BATS_TEST_TMPDIR/curl.log"
    cp "$FAKE_INSTALLER" "$out"
  }
  source "$REPO_ROOT/os/helpers/oh-my-zsh.sh"
}

sha256_of() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

@test "run_oh_my_zsh_installer runs a matching installer unattended, keeping .zshrc" {
  run run_oh_my_zsh_installer https://example.invalid/install.sh "$(sha256_of "$FAKE_INSTALLER")"
  assert_success
  run cat "$RAN"
  assert_output "RUNZSH=no CHSH=no KEEP_ZSHRC=yes"
}

@test "run_oh_my_zsh_installer never runs an installer that does not match" {
  run run_oh_my_zsh_installer https://example.invalid/install.sh \
    0000000000000000000000000000000000000000000000000000000000000000
  assert_failure
  assert_output --partial "pinned SHA-256"
  assert_file_not_exists "$RAN"
}

@test "run_oh_my_zsh_installer reports a failing installer and leaves no temp files" {
  printf 'exit 7\n' > "$FAKE_INSTALLER"
  run run_oh_my_zsh_installer https://example.invalid/install.sh "$(sha256_of "$FAKE_INSTALLER")"
  assert_failure 7
  run find "$BATS_TEST_TMPDIR" -maxdepth 1 -name 'oh-my-zsh.*'
  assert_output ""
}

@test "install_oh_my_zsh fetches the installer at a pinned commit and rejects other bytes" {
  run install_oh_my_zsh
  assert_failure
  assert_output --partial "pinned SHA-256"
  assert_file_not_exists "$RAN"
  run cat "$BATS_TEST_TMPDIR/curl.log"
  assert_output --regexp 'https://raw\.githubusercontent\.com/ohmyzsh/ohmyzsh/[0-9a-f]{40}/tools/install\.sh$'
}

@test "no init script fetches the oh-my-zsh installer from a branch" {
  run grep -rnE 'ohmyzsh/ohmyzsh/(master|main)/' "$REPO_ROOT/os"
  assert_failure
}
