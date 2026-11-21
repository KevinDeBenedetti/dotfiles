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

# --- load_homebrew_env: brew is found where the installer puts it ---

# A brew stand-in under <prefix>/bin whose `shellenv` puts that bin on PATH,
# as the real one does.
fake_brew_prefix() {
  mkdir -p "$1/bin"
  printf '#!/bin/bash\n[ "$1" = shellenv ] && echo "export PATH=\\"%s/bin:\\$PATH\\""\n' "$1" > "$1/bin/brew"
  chmod +x "$1/bin/brew"
}

@test "load_homebrew_env puts a brew that is installed but not on PATH back on it" {
  # Apple Silicon: the installer writes /opt/homebrew/bin, which the default
  # macOS PATH does not hold, so the script that just installed brew cannot
  # call it.
  fake_brew_prefix "$BATS_TEST_TMPDIR/opt"
  PATH="/usr/bin:/bin"
  run command -v brew
  assert_failure
  load_homebrew_env "$BATS_TEST_TMPDIR/missing" "$BATS_TEST_TMPDIR/opt"
  run command -v brew
  assert_output "$BATS_TEST_TMPDIR/opt/bin/brew"
}

@test "load_homebrew_env leaves PATH alone when brew is already on it, or installed nowhere" {
  fake_brew_prefix "$BATS_TEST_TMPDIR/first"
  fake_brew_prefix "$BATS_TEST_TMPDIR/second"
  PATH="$BATS_TEST_TMPDIR/first/bin:/usr/bin:/bin"
  load_homebrew_env "$BATS_TEST_TMPDIR/second"
  assert_equal "$PATH" "$BATS_TEST_TMPDIR/first/bin:/usr/bin:/bin"
  PATH="/usr/bin:/bin"
  run load_homebrew_env "$BATS_TEST_TMPDIR/missing"
  assert_success
}

@test "macOS init.sh looks for an installed brew before offering to install it, and again after" {
  # Before: a brew off PATH is not installed a second time. After: the fresh
  # install is usable by the rest of the script.
  run bash -c "sed -n '/^install_homebrew_and_report()/,/^}/p' '$REPO_ROOT/os/macos/init.sh' | grep -A1 'NONINTERACTIVE=1 install_homebrew\$' | tail -1"
  assert_output --partial "load_homebrew_env"
  run bash -c "grep -B3 '^if ! command -v brew' '$REPO_ROOT/os/macos/init.sh' | grep -c '^load_homebrew_env\$'"
  assert_output "1"
}
