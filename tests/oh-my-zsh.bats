#!/usr/bin/env bats

# Tests for clone_at_commit (os/helpers/fetch.sh) and os/helpers/oh-my-zsh.sh:
# a repository is cloned at one pinned commit, whose hash git itself verifies;
# no installer script is fetched or run. The clone runs for real against a
# local fixture repository.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  export TMPDIR="$BATS_TEST_TMPDIR"
  # Keep the owner's git config (signing, url rewrites) out of the fixture.
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

  # An "upstream" whose master has moved on since the commit we pin.
  UPSTREAM="$BATS_TEST_TMPDIR/upstream"
  git init -q -b master "$UPSTREAM"
  PINNED=$(fixture_commit "pinned")
  fixture_commit "newer, unreviewed" > /dev/null
  # GitHub serves any reachable commit by hash; a local repo must opt in.
  git -C "$UPSTREAM" config uploadpack.allowAnySHA1InWant true

  DEST="$BATS_TEST_TMPDIR/home/.oh-my-zsh"
  source "$REPO_ROOT/os/helpers/oh-my-zsh.sh"
}

# Record a new state of the fixture's oh-my-zsh.sh on its master and print the
# new commit's hash.
fixture_commit() {
  echo "$1" > "$UPSTREAM/oh-my-zsh.sh"
  git -C "$UPSTREAM" add oh-my-zsh.sh
  git -C "$UPSTREAM" commit -q -m "$1"
  git -C "$UPSTREAM" rev-parse HEAD
}

@test "clone_at_commit checks out the pinned commit, not the branch tip" {
  run clone_at_commit oh-my-zsh "file://$UPSTREAM" "$PINNED" "$DEST"
  assert_success
  run git -C "$DEST" rev-parse HEAD
  assert_output "$PINNED"
  run cat "$DEST/oh-my-zsh.sh"
  assert_output "pinned"
}

@test "clone_at_commit leaves a checkout that oh-my-zsh can update from master" {
  clone_at_commit oh-my-zsh "file://$UPSTREAM" "$PINNED" "$DEST"
  # A bare `git pull` only works through the branch's tracking config.
  run git -C "$DEST" pull -q --rebase
  assert_success
  run cat "$DEST/oh-my-zsh.sh"
  assert_output "newer, unreviewed"
}

@test "clone_at_commit refuses an existing destination and leaves it untouched" {
  mkdir -p "$DEST"
  echo "mine" > "$DEST/keep"
  run clone_at_commit oh-my-zsh "file://$UPSTREAM" "$PINNED" "$DEST"
  assert_failure
  assert_output --partial "already exists"
  run cat "$DEST/keep"
  assert_output "mine"
}

@test "clone_at_commit leaves no group- or world-writable files, whatever the umask" {
  umask 000
  clone_at_commit oh-my-zsh "file://$UPSTREAM" "$PINNED" "$DEST"
  run find "$DEST" -perm -020 -o -perm -002
  assert_output ""
}

@test "clone_at_commit leaves no partial clone next to the destination on failure" {
  run clone_at_commit oh-my-zsh "file://$UPSTREAM" 0123456789abcdef0123456789abcdef01234567 "$DEST"
  assert_failure
  run find "$BATS_TEST_TMPDIR/home" -mindepth 1
  assert_output ""
}

@test "clone_at_commit fails on a commit the remote does not have, and leaves nothing" {
  run clone_at_commit oh-my-zsh "file://$UPSTREAM" 0123456789abcdef0123456789abcdef01234567 "$DEST"
  assert_failure
  assert_output --partial "oh-my-zsh not installed"
  assert_dir_not_exists "$DEST"
}

@test "clone_at_commit refuses anything but a full commit hash" {
  local ref
  for ref in master "" "${PINNED:0:12}"; do
    run clone_at_commit oh-my-zsh "file://$UPSTREAM" "$ref" "$DEST"
    assert_failure
    assert_dir_not_exists "$DEST"
  done
}

@test "install_oh_my_zsh clones the official repository at one pinned commit" {
  clone_at_commit() { echo "$*"; }
  HOME="$BATS_TEST_TMPDIR/home" run install_oh_my_zsh
  assert_success
  # oh-my-zsh.remote and oh-my-zsh.branch are what its updater (tools/upgrade.sh) reads.
  assert_output --regexp "^oh-my-zsh https://github\.com/ohmyzsh/ohmyzsh\.git [0-9a-f]{40} $BATS_TEST_TMPDIR/home/\.oh-my-zsh oh-my-zsh\.remote=origin oh-my-zsh\.branch=master$"
}

@test "no oh-my-zsh installer script is fetched by the setup scripts" {
  run grep -rn 'tools/install.sh' "$REPO_ROOT/os"
  assert_failure
}

@test "clone_at_commit sets extra git config in the clone before it is in place" {
  clone_at_commit oh-my-zsh "file://$UPSTREAM" "$PINNED" "$DEST" oh-my-zsh.remote=origin oh-my-zsh.branch=master
  run git -C "$DEST" config oh-my-zsh.remote
  assert_output "origin"
  run git -C "$DEST" config oh-my-zsh.branch
  assert_output "master"
}

@test "clone_at_commit leaves no destination when an extra git config fails" {
  run clone_at_commit oh-my-zsh "file://$UPSTREAM" "$PINNED" "$DEST" "not a valid key=x"
  assert_failure
  assert_dir_not_exists "$DEST"
  run find "$BATS_TEST_TMPDIR/home" -mindepth 1
  assert_output ""
}

@test "install_zsh_completions clones zsh-completions at one pinned commit into the given dir" {
  clone_at_commit() { echo "$*"; }
  run install_zsh_completions "$BATS_TEST_TMPDIR/plugins/zsh-completions"
  assert_success
  assert_output --regexp "^zsh-completions https://github\.com/zsh-users/zsh-completions\.git [0-9a-f]{40} $BATS_TEST_TMPDIR/plugins/zsh-completions$"
}

@test "no init script clones zsh-completions from its default branch" {
  run grep -n 'git clone .*zsh-completions' "$REPO_ROOT/os/debian/init.sh" "$REPO_ROOT/os/macos/init.sh"
  assert_failure 1
  run grep -c 'install_zsh_completions "$ZSH_COMP_PLUGIN"' "$REPO_ROOT/os/debian/init.sh" "$REPO_ROOT/os/macos/init.sh"
  assert_line --regexp 'debian/init\.sh:1$'
  assert_line --regexp 'macos/init\.sh:1$'
}

@test "the macOS completions step resolves the oh-my-zsh dir from \$HOME, not a literal ~" {
  # Inside double quotes "~" is not expanded: the plugin landed in ./~/.oh-my-zsh.
  run grep -n 'ZSH_COMP_PLUGIN=.*ZSH:-~' "$REPO_ROOT/os/macos/init.sh" "$REPO_ROOT/os/debian/init.sh"
  assert_failure 1
}
