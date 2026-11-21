#!/usr/bin/env bats
# Behavior tests for os/helpers/dotfiles.sh — the post-link steps shared by
# both OS init scripts — and for write_completion (os/helpers/completions.sh).
# Each one runs the real function against a throwaway HOME and reads the files
# it rendered.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  CONFIG_DIR="$REPO_ROOT/config"
  HELPER="$REPO_ROOT/os/helpers/dotfiles.sh"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  FAKE_HOME="$BATS_TEST_TMPDIR/fake-home"
  mkdir -p "$FAKE_HOME"
  # The owner's global git config must not leak into the tests.
  GITCONFIG="$BATS_TEST_TMPDIR/gitconfig"
  : > "$GITCONFIG"
}

# Runs one helper function in a fresh shell with the fake HOME and git config.
run_helper() {
  run env HOME="$FAKE_HOME" GIT_CONFIG_GLOBAL="$GITCONFIG" GIT_CONFIG_NOSYSTEM=1 \
    bash -c "source '$HELPER' && $*"
}

# Octal permission bits of a file, on GNU and BSD stat alike.
mode_of() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

# --- create_allowed_signers ---

@test "create_allowed_signers pairs the git email with the public key, on one line" {
  mkdir -p "$FAKE_HOME/.ssh"
  # CRLF line ending, as a key pasted from Windows would have.
  printf 'ssh-rsa AAAAtest owner@host\r\n' > "$FAKE_HOME/.ssh/id_rsa.pub"
  git config --file "$GITCONFIG" user.email "dev@example.com"
  run_helper create_allowed_signers
  assert_success
  run cat "$FAKE_HOME/.ssh/allowed_signers"
  assert_output "dev@example.com ssh-rsa AAAAtest owner@host"
  run mode_of "$FAKE_HOME/.ssh/allowed_signers"
  assert_output "600"
}

@test "create_allowed_signers falls back to the default email when git has none" {
  mkdir -p "$FAKE_HOME/.ssh"
  echo 'ssh-rsa AAAAtest' > "$FAKE_HOME/.ssh/id_rsa.pub"
  run_helper create_allowed_signers
  assert_success
  run cat "$FAKE_HOME/.ssh/allowed_signers"
  assert_output "contact@kevindb.dev ssh-rsa AAAAtest"
}

@test "create_allowed_signers writes nothing without a public key" {
  run_helper create_allowed_signers
  assert_success
  assert_output --partial "No SSH public key found"
  assert_not_exists "$FAKE_HOME/.ssh/allowed_signers"
}

# --- create_local_stubs ---

@test "create_local_stubs creates the three per-machine override files" {
  run_helper create_local_stubs
  assert_success
  assert_file_exists "$FAKE_HOME/.zshrc.local"
  assert_file_exists "$FAKE_HOME/.gitconfig.local"
  assert_file_exists "$FAKE_HOME/.config/dotfiles/env.local.sh"
}

@test "the stubs hold comments only: sourcing or including them changes nothing" {
  run_helper create_local_stubs
  local stub
  for stub in .zshrc.local .gitconfig.local .config/dotfiles/env.local.sh; do
    run grep -Ev '^(#.*)?$' "$FAKE_HOME/$stub"
    assert_failure
  done
  # git reads the stub as an (empty) config file.
  run git config --file "$FAKE_HOME/.gitconfig.local" --list
  assert_success
  assert_output ""
}

@test "create_local_stubs leaves existing override files untouched" {
  mkdir -p "$FAKE_HOME/.config/dotfiles"
  echo "alias mine=1" > "$FAKE_HOME/.zshrc.local"
  echo "[user]" > "$FAKE_HOME/.gitconfig.local"
  echo "export MINE=1" > "$FAKE_HOME/.config/dotfiles/env.local.sh"
  run_helper create_local_stubs
  assert_success
  assert_output ""
  run cat "$FAKE_HOME/.zshrc.local"
  assert_output "alias mine=1"
  run cat "$FAKE_HOME/.gitconfig.local"
  assert_output "[user]"
  run cat "$FAKE_HOME/.config/dotfiles/env.local.sh"
  assert_output "export MINE=1"
}

# --- install_vscode_config ---

# A `code` stand-in: lists $INSTALLED (one extension per line) and logs every
# other call in $CODE_LOG.
stub_code() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  CODE_LOG="$BATS_TEST_TMPDIR/code.log"
  cat > "$BATS_TEST_TMPDIR/bin/code" <<EOF
#!/bin/bash
if [ "\$1" = --list-extensions ]; then printf '%s\n' "\$INSTALLED"; else echo "\$*" >> "$CODE_LOG"; fi
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/code"
}

run_install_vscode_config() {
  run env HOME="$FAKE_HOME" INSTALLED="${INSTALLED:-}" PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c \
    "source '$REPO_ROOT/os/helpers/links.sh' && source '$HELPER' && install_vscode_config '$CONFIG_DIR' '$FAKE_HOME/vscode-user'"
}

@test "install_vscode_config installs every recommended extension that is missing" {
  stub_code
  run_install_vscode_config
  assert_success
  local expected
  expected=$(grep -v '//' "$CONFIG_DIR/vscode/extensions.json" | jq -r '.recommendations[] | "--install-extension \(.)"')
  run cat "$CODE_LOG"
  assert_output "$expected"
}

@test "install_vscode_config skips an installed extension, whatever its case" {
  stub_code
  # VS Code lists ids in lower case; extensions.json spells this one with capitals.
  INSTALLED="github.vscode-pull-request-github"
  run_install_vscode_config
  assert_success
  assert_output --partial "GitHub.vscode-pull-request-github already installed"
  run grep -ci 'github.vscode-pull-request-github' "$CODE_LOG"
  assert_output "0"
}

@test "install_vscode_config does nothing on a machine without VS Code" {
  # A PATH holding the base tools only: no `code`.
  run env HOME="$FAKE_HOME" PATH="/usr/bin:/bin" bash -c \
    "source '$REPO_ROOT/os/helpers/links.sh' && source '$HELPER' && install_vscode_config '$CONFIG_DIR' '$FAKE_HOME/vscode-user'"
  assert_success
  assert_output ""
  assert_not_exists "$FAKE_HOME/vscode-user"
}

# --- write_completion (os/helpers/completions.sh) ---

# completions.sh generates completions as it is sourced, so only the function
# is taken from it.
load_write_completion() {
  eval "$(sed -n '/^write_completion()/,/^}/p' "$REPO_ROOT/os/helpers/completions.sh")"
}

@test "write_completion writes the content to its destination" {
  load_write_completion
  SUDO=""
  run write_completion $'#compdef gh\n_gh() { :; }' "$BATS_TEST_TMPDIR/_gh"
  assert_success
  assert_output ""
  run cat "$BATS_TEST_TMPDIR/_gh"
  assert_output $'#compdef gh\n_gh() { :; }'
}

@test "write_completion writes through \$SUDO when one is set" {
  load_write_completion
  # Stands in for sudo: logs the command it was given, then runs it.
  as_root() { echo "$*" >> "$BATS_TEST_TMPDIR/sudo.log"; "$@"; }
  SUDO="as_root"
  run write_completion "#compdef uv" "$BATS_TEST_TMPDIR/_uv"
  assert_success
  assert_output ""
  run cat "$BATS_TEST_TMPDIR/_uv"
  assert_output "#compdef uv"
  run cat "$BATS_TEST_TMPDIR/sudo.log"
  assert_output "tee $BATS_TEST_TMPDIR/_uv"
}
