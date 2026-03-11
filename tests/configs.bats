#!/usr/bin/env bats

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  CONFIG_DIR="$REPO_ROOT/config"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'
}

# --- Config files ---

@test "config/git/.gitconfig exists" {
  assert_file_exists "$CONFIG_DIR/git/.gitconfig"
}

@test "config/zsh/.zshrc exists" {
  assert_file_exists "$CONFIG_DIR/zsh/.zshrc"
}

@test "config/proto/.prototools exists" {
  assert_file_exists "$CONFIG_DIR/proto/.prototools"
}

@test "config/oh-my-zsh theme exists" {
  assert_file_exists "$CONFIG_DIR/oh-my-zsh/kevin-de-benedetti.zsh-theme"
}

@test "config/shell/env.sh exists" {
  assert_file_exists "$CONFIG_DIR/shell/env.sh"
}

@test "config/shell/functions.sh exists" {
  assert_file_exists "$CONFIG_DIR/shell/functions.sh"
}

@test "config/vscode/settings.json exists" {
  assert_file_exists "$CONFIG_DIR/vscode/settings.json"
}

@test "config/vscode/mcp.json exists" {
  assert_file_exists "$CONFIG_DIR/vscode/mcp.json"
}

@test "config/vscode/extensions.json exists" {
  assert_file_exists "$CONFIG_DIR/vscode/extensions.json"
}

# --- OS scripts ---

@test "os/macos/init.sh exists and is executable" {
  assert_file_exists "$REPO_ROOT/os/macos/init.sh"
}

@test "os/debian/init.sh exists and is executable" {
  assert_file_exists "$REPO_ROOT/os/debian/init.sh"
}

@test "all macOS setup profiles exist" {
  for profile in ai base extras javascript python; do
    assert_file_exists "$REPO_ROOT/os/macos/setup-${profile}.sh"
  done
}

@test "all Debian setup profiles exist" {
  for profile in base kubernetes security; do
    assert_file_exists "$REPO_ROOT/os/debian/setup-${profile}.sh"
  done
}

@test "shared helper scripts exist" {
  for helper in completions proto; do
    assert_file_exists "$REPO_ROOT/os/helpers/${helper}.sh"
  done
}

# --- Directory structure ---

@test "config/ directory exists" {
  assert_dir_exists "$CONFIG_DIR"
}

@test "os/macos/ directory exists" {
  assert_dir_exists "$REPO_ROOT/os/macos"
}

@test "os/debian/ directory exists" {
  assert_dir_exists "$REPO_ROOT/os/debian"
}

@test "scripts/ directory exists" {
  assert_dir_exists "$REPO_ROOT/scripts"
}

# --- Config content sanity checks ---

@test ".gitconfig contains [init] defaultBranch = main" {
  run grep -q 'defaultBranch = main' "$CONFIG_DIR/git/.gitconfig"
  assert_success
}

@test ".zshrc sources oh-my-zsh" {
  run grep -q 'source $ZSH/oh-my-zsh.sh' "$CONFIG_DIR/zsh/.zshrc"
  assert_success
}

@test ".zshrc sources env.sh" {
  run grep -q 'env.sh' "$CONFIG_DIR/zsh/.zshrc"
  assert_success
}

@test ".zshrc sources functions.sh" {
  run grep -q 'functions.sh' "$CONFIG_DIR/zsh/.zshrc"
  assert_success
}

@test "extensions.json contains recommendations array" {
  run grep -q '"recommendations"' "$CONFIG_DIR/vscode/extensions.json"
  assert_success
}

@test "mcp.json contains servers block" {
  run grep -q '"servers"' "$CONFIG_DIR/vscode/mcp.json"
  assert_success
}
