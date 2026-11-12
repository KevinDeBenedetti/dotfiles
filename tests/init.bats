#!/usr/bin/env bats

# Tests for init.sh flag parsing and early-exit behavior.
# These tests only validate the argument handling logic — they do NOT
# run any actual install steps (brew, apt, proto, etc.).

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
}

# --- macOS init.sh ---

@test "macos init.sh -h prints help and exits 0" {
  run bash "$REPO_ROOT/os/macos/init.sh" -h
  assert_success
  assert_output --partial "This script aims to install"
}

@test "macos init.sh with no flags exits 1 with warning" {
  run bash "$REPO_ROOT/os/macos/init.sh"
  assert_failure 1
  assert_output --partial "No profile or action flag provided"
}

@test "macos init.sh -h output contains all documented flags" {
  run bash "$REPO_ROOT/os/macos/init.sh" -h
  assert_success
  assert_output --partial "-a"
  assert_output --partial "-c"
  assert_output --partial "-d"
  assert_output --partial "-l"
  assert_output --partial "-p"
  assert_output --partial "-r"
  assert_output --partial "-h"
}

@test "macos init.sh -h output lists all profiles" {
  run bash "$REPO_ROOT/os/macos/init.sh" -h
  assert_success
  assert_output --partial "ai"
  assert_output --partial "base"
  assert_output --partial "extras"
  assert_output --partial "javascript"
  assert_output --partial "python"
}

# --- Debian init.sh ---

@test "debian init.sh -h prints help and exits 0" {
  run bash "$REPO_ROOT/os/debian/init.sh" -h
  assert_success
  assert_output --partial "This script aims to install"
}

@test "debian init.sh with no flags exits 1 with warning" {
  run bash "$REPO_ROOT/os/debian/init.sh"
  assert_failure 1
  assert_output --partial "No profile or action flag provided"
}

@test "debian init.sh -h output contains all documented flags" {
  run bash "$REPO_ROOT/os/debian/init.sh" -h
  assert_success
  assert_output --partial "-a"
  assert_output --partial "-c"
  assert_output --partial "-d"
  assert_output --partial "-l"
  assert_output --partial "-p"
  assert_output --partial "-r"
  assert_output --partial "-h"
}

@test "debian init.sh -h output lists all profiles" {
  run bash "$REPO_ROOT/os/debian/init.sh" -h
  assert_success
  assert_output --partial "base"
  assert_output --partial "kubernetes"
  assert_output --partial "security"
}

# --- Debian setup-user.sh ---

@test "setup-user.sh rejects a user name with a dot before touching the system" {
  # sudo skips /etc/sudoers.d files whose name contains a dot.
  # SUDO=false: any privileged call that slipped past the check would fail.
  CREATE_USER="first.last" SUDO=false run bash "$REPO_ROOT/os/debian/setup-user.sh"
  assert_failure 1
  assert_output --partial "Invalid user name 'first.last'"
  refute_output --partial "already exists"
}

@test "setup-user.sh rejects a user name with uppercase or a leading digit" {
  for name in Deploy 1deploy "de ploy"; do
    CREATE_USER="$name" SUDO=false run bash "$REPO_ROOT/os/debian/setup-user.sh"
    assert_failure 1
    assert_output --partial "Invalid user name"
  done
}

@test "setup-user.sh validates the NOPASSWD sudoers rule with visudo before installing it" {
  run grep -F 'visudo -cqf "$sudoers_tmp"' "$REPO_ROOT/os/debian/setup-user.sh"
  assert_success
  run grep -F 'tee "/etc/sudoers.d/' "$REPO_ROOT/os/debian/setup-user.sh"
  assert_failure
}
