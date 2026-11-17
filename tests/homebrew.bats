#!/usr/bin/env bats

# Tests for os/helpers/homebrew.sh: the Homebrew installer runs only when it is
# the script pinned by commit and SHA-256. The functions run for real, with
# curl stubbed to "download" a fake installer.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  export TMPDIR="$BATS_TEST_TMPDIR"
  export RAN="$BATS_TEST_TMPDIR/installer-ran"
  FAKE_INSTALLER="$BATS_TEST_TMPDIR/install.sh"
  printf 'echo "NONINTERACTIVE=${NONINTERACTIVE:-}" > "$RAN"\n' > "$FAKE_INSTALLER"
  unset NONINTERACTIVE

  curl() {
    local out="" prev="" arg
    for arg in "$@"; do [ "$prev" = "-o" ] && out="$arg"; prev="$arg"; done
    echo "$*" >> "$BATS_TEST_TMPDIR/curl.log"
    cp "$FAKE_INSTALLER" "$out"
  }
  source "$REPO_ROOT/os/helpers/homebrew.sh"
}

sha256_of() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -d' ' -f1; }

@test "run_homebrew_installer runs a matching installer, leaving NONINTERACTIVE to the caller" {
  run run_homebrew_installer https://example.invalid/install.sh "$(sha256_of "$FAKE_INSTALLER")"
  assert_success
  run cat "$RAN"
  assert_output "NONINTERACTIVE="
  NONINTERACTIVE=1 run run_homebrew_installer https://example.invalid/install.sh "$(sha256_of "$FAKE_INSTALLER")"
  assert_success
  run cat "$RAN"
  assert_output "NONINTERACTIVE=1"
}

@test "macOS init.sh keeps running the Homebrew installer non-interactively" {
  run grep -c 'NONINTERACTIVE=1 install_homebrew$' "$REPO_ROOT/os/macos/init.sh"
  assert_output "1"
}

@test "run_homebrew_installer never runs an installer that does not match" {
  run run_homebrew_installer https://example.invalid/install.sh \
    0000000000000000000000000000000000000000000000000000000000000000
  assert_failure 1
  assert_output --partial "pinned SHA-256"
  assert_file_not_exists "$RAN"
}

@test "run_homebrew_installer reports a failing installer and leaves no temp files" {
  printf 'exit 7\n' > "$FAKE_INSTALLER"
  run run_homebrew_installer https://example.invalid/install.sh "$(sha256_of "$FAKE_INSTALLER")"
  assert_failure 7
  run find "$BATS_TEST_TMPDIR" -maxdepth 1 -name 'homebrew.*'
  assert_output ""
}

@test "install_homebrew fetches the installer at a pinned commit and rejects other bytes" {
  run install_homebrew
  assert_failure 1
  assert_output --partial "pinned SHA-256"
  assert_file_not_exists "$RAN"
  run cat "$BATS_TEST_TMPDIR/curl.log"
  assert_output --regexp 'https://raw\.githubusercontent\.com/Homebrew/install/[0-9a-f]{40}/install\.sh$'
}

@test "no script runs the Homebrew installer from a branch" {
  run grep -rnE 'Homebrew/install/(HEAD|master|main)/' "$REPO_ROOT/os" "$REPO_ROOT/scripts"
  assert_failure 1
}
