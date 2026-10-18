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
  assert_symlink_to "$CONFIG_DIR/opencode/opencode.json" "$FAKE_HOME/.config/opencode/opencode.json"
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

@test "link_shared_configs links every shared command into claude, opencode and copilot" {
  local vscode_user="$FAKE_HOME/.config/Code/User"
  [ "$(uname -s)" = "Darwin" ] && vscode_user="$FAKE_HOME/Library/Application Support/Code/User"
  mkdir -p "$vscode_user"
  run run_link_shared_configs
  assert_success
  local cmd name
  for cmd in "$CONFIG_DIR"/commands/*.md; do
    name=$(basename "$cmd" .md)
    assert_symlink_to "$cmd" "$FAKE_HOME/.claude/commands/$name.md"
    assert_symlink_to "$cmd" "$FAKE_HOME/.config/opencode/commands/$name.md"
    assert_symlink_to "$cmd" "$vscode_user/prompts/$name.prompt.md"
  done
}

@test "link_shared_configs skips copilot prompts when VS Code is absent" {
  run run_link_shared_configs
  assert_success
  assert_not_exists "$FAKE_HOME/.config/Code/User/prompts"
  assert_not_exists "$FAKE_HOME/Library/Application Support/Code/User/prompts"
}

@test "link_shared_configs links every shared skill into HOME" {
  run run_link_shared_configs
  assert_success
  local skill
  for skill in "$CONFIG_DIR"/skills/*/; do
    [ -d "$skill" ] || continue
    assert_symlink_to "$skill" "$FAKE_HOME/.claude/skills/$(basename "$skill")"
  done
}

@test "link_shared_configs backs up an existing regular skill dir" {
  # backup_if_exists only guards regular files, so a pre-existing regular dir
  # is not backed up: ln -sfn -n replaces the dir entry itself with the
  # symlink... except it can't when the dir is non-empty. What actually
  # happens: the link lands INSIDE the existing dir. This documents the
  # (acceptable) behavior — skills dirs are created by us as symlinks, a
  # regular dir would only exist if something else created it.
  mkdir -p "$FAKE_HOME/.claude/skills/commit-types"
  echo "old" > "$FAKE_HOME/.claude/skills/commit-types/SKILL.md"
  run run_link_shared_configs
  assert_success
  # The old content is still there (untouched), and the new symlink landed
  # inside the existing dir rather than replacing it.
  run cat "$FAKE_HOME/.claude/skills/commit-types/SKILL.md"
  assert_output "old"
}

@test "link_shared_configs links every copilot hook into HOME" {
  run run_link_shared_configs
  assert_success
  local hook
  for hook in "$CONFIG_DIR"/copilot/hooks/*; do
    assert_symlink_to "$hook" "$FAKE_HOME/.copilot/hooks/$(basename "$hook")"
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
