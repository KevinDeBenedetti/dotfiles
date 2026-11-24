#!/usr/bin/env bats
# Tests for scripts/bats-affected.sh, the pre-commit hook's fast path: it runs
# the Bats files that cover the staged files, and the whole suite when it
# cannot tell (prek.toml).

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/bats-affected.sh"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
}

select_for() {
  run bash "$SCRIPT" --list "$@"
}

@test "a changed script selects the test files that name it, and only those" {
  select_for os/debian/setup-security.sh
  assert_success
  assert_line tests/security.bats
  refute_line tests/functions.bats
  refute_line ALL
}

@test "a changed test file selects itself, and a test helper the file using it" {
  select_for tests/kubernetes.bats tests/project-board-harness.mjs
  assert_success
  assert_line tests/kubernetes.bats
  assert_line tests/project-board.bats
  refute_line ALL
}

@test "a file no test names by path is covered through the directory a test names" {
  # .github/project-board/board.mjs: project-board.bats names the directory.
  select_for .github/project-board/board.mjs docs/setup/debian.md
  assert_success
  assert_line tests/project-board.bats
  assert_line tests/init.bats
  refute_line ALL
}

@test "an incidental mention does not hide the tests of the file's directory" {
  # configs.bats names plan.mjs once; project-board.bats tests it through its
  # directory.
  select_for .github/project-board/plan.mjs
  assert_line tests/project-board.bats
  # fetch.sh is sourced by the other helpers: their tests run too.
  select_for os/helpers/fetch.sh
  assert_line tests/fetch.bats
  assert_line tests/proto.bats
  assert_line tests/homebrew.bats
}

@test "a change to this selector runs its own tests" {
  select_for scripts/bats-affected.sh
  assert_line tests/bats-affected.bats
  refute_line ALL
}

@test "a file no test covers runs the whole suite" {
  select_for os/debian/setup-security.sh CHANGELOG.md
  assert_success
  assert_output ALL
}

@test "every test file is selected when it changes" {
  local f
  for f in "$REPO_ROOT"/tests/*.bats "$REPO_ROOT"/tests/*/*.bats; do
    case "$f" in */test_helper/*) continue ;; esac
    select_for "${f#"$REPO_ROOT"/}"
    assert_line "${f#"$REPO_ROOT"/}"
  done
}

@test "nothing staged runs nothing" {
  select_for
  assert_success
  assert_output ""
}

@test "the test files run without the git environment of the hook" {
  # git exports GIT_DIR (and GIT_INDEX_FILE, …) to its hooks: the fixtures'
  # `git init` / `git config` would act on this repository with them.
  local unset_line exec_line
  unset_line=$(grep -n 'unset $(git rev-parse --local-env-vars)' "$SCRIPT" | head -n1 | cut -d: -f1)
  exec_line=$(grep -n '^exec bash scripts/bats-run.sh' "$SCRIPT" | head -n1 | cut -d: -f1)
  [ -n "$unset_line" ] && [ -n "$exec_line" ] && [ "$unset_line" -lt "$exec_line" ]
}

@test "the pre-commit hook runs the covering tests, the push the whole suite" {
  local prek="$REPO_ROOT/prek.toml"
  run sed -n '/^id = "bats-affected"$/,/^stages/p' "$prek"
  assert_output --partial 'entry = "bash scripts/bats-affected.sh"'
  assert_output --partial 'pass_filenames = true'
  assert_output --partial 'require_serial = true'
  assert_line 'stages = ["pre-commit"]'
  run sed -n '/^id = "bats"$/,/^stages/p' "$prek"
  assert_line 'stages = ["pre-push"]'
}
