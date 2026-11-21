#!/usr/bin/env bats
# Behavior tests for scripts/install-managed-settings.sh: the script that copies
# the Claude Code managed policy to its root-owned system path.
#
# The script runs from a copy of the repository layout in the test's temp dir,
# with `uname` and `sudo` stubbed and its Linux destination moved under that
# temp dir, so nothing is read from or written to the real system path.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  SANDBOX="$BATS_TEST_TMPDIR/repo"
  SRC="$SANDBOX/config/claude/managed-settings.json"
  DEST="$BATS_TEST_TMPDIR/etc/claude-code/managed-settings.json"
  SUDO_LOG="$BATS_TEST_TMPDIR/sudo.log"
  mkdir -p "$SANDBOX/scripts" "$SANDBOX/config/claude" "$BATS_TEST_TMPDIR/bin"
  cp "$REPO_ROOT/config/claude/managed-settings.json" "$SRC"
  # Only the destination's prefix changes; the test fails if it is not there.
  grep -qF 'DEST="/etc/claude-code/managed-settings.json"' "$REPO_ROOT/scripts/install-managed-settings.sh"
  sed "s#DEST=\"/etc/claude-code/#DEST=\"$BATS_TEST_TMPDIR/etc/claude-code/#" \
    "$REPO_ROOT/scripts/install-managed-settings.sh" > "$SANDBOX/scripts/install-managed-settings.sh"

  printf '#!/bin/sh\necho Linux\n' > "$BATS_TEST_TMPDIR/bin/uname"
  # sudo only records what it was asked to run.
  printf '#!/bin/sh\necho "$*" >> "%s"\n' "$SUDO_LOG" > "$BATS_TEST_TMPDIR/bin/sudo"
  chmod +x "$BATS_TEST_TMPDIR/bin/uname" "$BATS_TEST_TMPDIR/bin/sudo"
}

# $1 = what the owner types at the prompt.
run_install() {
  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c \
    "printf '%s\n' '${1:-}' | bash '$SANDBOX/scripts/install-managed-settings.sh'"
}

install_dest() {
  mkdir -p "$(dirname "$DEST")"
  printf '%s\n' "$1" > "$DEST"
}

@test "a first install copies the policy as a root-owned file, without a prompt" {
  run_install
  assert_success
  refute_output --partial "Apply this policy?"
  run cat "$SUDO_LOG"
  assert_line "mkdir -p $(dirname "$DEST")"
  assert_line "install -m 0644 -o root $SRC $DEST"
  # A copy, never a link: a link would leave the policy user-writable.
  refute_output --partial "ln "
}

@test "an up-to-date policy is left alone" {
  mkdir -p "$(dirname "$DEST")"
  cp "$SRC" "$DEST"
  run_install
  assert_success
  assert_output --partial "already up to date"
  assert_not_exists "$SUDO_LOG"
}

@test "a policy that differs is shown and kept when the owner declines" {
  install_dest '{"old": true}'
  run_install n
  assert_failure
  assert_output --partial "Current policy differs from repo version:"
  assert_output --partial '-{"old": true}'
  assert_output --partial "Aborted."
  assert_not_exists "$SUDO_LOG"
  run cat "$DEST"
  assert_output '{"old": true}'
}

@test "an empty answer declines: the prompt defaults to no" {
  install_dest '{"old": true}'
  run_install ""
  assert_failure
  assert_output --partial "Aborted."
  assert_not_exists "$SUDO_LOG"
}

@test "a policy that differs is replaced once the owner accepts" {
  install_dest '{"old": true}'
  run_install y
  assert_success
  run cat "$SUDO_LOG"
  assert_line "install -m 0644 -o root $SRC $DEST"
}

@test "invalid JSON aborts before anything is compared or installed" {
  echo '{"permissions": ' > "$SRC"
  install_dest '{"old": true}'
  run_install y
  assert_failure
  assert_output --partial "is not valid JSON, aborting"
  refute_output --partial "Apply this policy?"
  assert_not_exists "$SUDO_LOG"
}

@test "an unsupported OS is refused" {
  printf '#!/bin/sh\necho Plan9\n' > "$BATS_TEST_TMPDIR/bin/uname"
  run_install
  assert_failure
  assert_output --partial "Unsupported OS: Plan9"
  assert_not_exists "$SUDO_LOG"
}
