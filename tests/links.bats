#!/usr/bin/env bats
# Functional tests for os/helpers/links.sh — the shared symlink logic used by
# scripts/symlink.sh and both OS init scripts. Runs against a throwaway HOME.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  CONFIG_DIR="$REPO_ROOT/config"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  FAKE_HOME="$BATS_TEST_TMPDIR/fake-home"
  mkdir -p "$FAKE_HOME"
}

run_link_shared_configs() {
  env HOME="$FAKE_HOME" bash -c \
    "source '$REPO_ROOT/os/helpers/links.sh' && link_shared_configs '$CONFIG_DIR'"
}

@test "link_shared_configs links every shared config into HOME" {
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/git/.gitconfig" "$FAKE_HOME/.gitconfig"
  assert_symlink_to "$CONFIG_DIR/git/ignore" "$FAKE_HOME/.config/git/ignore"
  assert_symlink_to "$CONFIG_DIR/claude/settings.json" "$FAKE_HOME/.claude/settings.json"
  assert_symlink_to "$CONFIG_DIR/proto/.prototools" "$FAKE_HOME/.proto/.prototools"
  assert_symlink_to "$CONFIG_DIR/shell/functions.sh" "$FAKE_HOME/.config/dotfiles/functions.sh"
}

@test "link_shared_configs links every claude global command into HOME" {
  run run_link_shared_configs
  assert_success
  local cmd
  for cmd in "$CONFIG_DIR"/claude/commands/*; do
    assert_symlink_to "$cmd" "$FAKE_HOME/.claude/commands/$(basename "$cmd")"
  done
}

@test "link_shared_configs is idempotent" {
  run run_link_shared_configs
  assert_success
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/git/.gitconfig" "$FAKE_HOME/.gitconfig"
}

@test "link_shared_configs backs up an existing regular file" {
  echo "old content" > "$FAKE_HOME/.gitconfig"
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/git/.gitconfig" "$FAKE_HOME/.gitconfig"
  run bash -c "cat '$FAKE_HOME'/.gitconfig.bak.*"
  assert_output "old content"
}

@test "link_shared_configs skips oh-my-zsh theme when omz is absent" {
  run run_link_shared_configs
  assert_success
  assert_not_exists "$FAKE_HOME/.oh-my-zsh"
}

@test "link_shared_configs links oh-my-zsh theme when omz is present" {
  mkdir -p "$FAKE_HOME/.oh-my-zsh"
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/oh-my-zsh/kevin-de-benedetti.zsh-theme" \
    "$FAKE_HOME/.oh-my-zsh/custom/themes/kevin-de-benedetti.zsh-theme"
}

@test "link_shared_configs links ssh config and creates the local config.d dir" {
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/ssh/config" "$FAKE_HOME/.ssh/config"
  assert_dir_exists "$FAKE_HOME/.ssh/config.d"
}

@test "link_shared_configs leaves local ~/.ssh/config.d files untouched" {
  mkdir -p "$FAKE_HOME/.ssh/config.d"
  printf 'Host k3s\n    HostName 1.2.3.4\n' > "$FAKE_HOME/.ssh/config.d/infra.conf"
  run run_link_shared_configs
  assert_success
  assert_link_not_exists "$FAKE_HOME/.ssh/config.d/infra.conf"
  run cat "$FAKE_HOME/.ssh/config.d/infra.conf"
  assert_line "Host k3s"
}
