#!/usr/bin/env bats
# Tests for scripts/bats-run.sh, the parallel Bats runner of the git hooks
# (prek.toml): same verdict as a plain `bats` run, in a fraction of the time.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/bats-run.sh"
  T="$BATS_TEST_TMPDIR/t"
  mkdir -p "$T/sub"
  # A `parallel` that is not GNU parallel (moreutils ships one): the runner
  # then runs the files side by side itself, whatever the machine has.
  NO_GNU="$BATS_TEST_TMPDIR/no-gnu"
  mkdir -p "$NO_GNU"
  printf '%s\n' '#!/bin/sh' 'echo "parallel (moreutils)"' > "$NO_GNU/parallel"
  chmod +x "$NO_GNU/parallel"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
}

# fixture FILE BODY: a one-test Bats file running BODY.
fixture() {
  printf '@test "%s" {\n  %s\n}\n' "${1##*/}" "$2" > "$1"
}

@test "every file of the given directories and files runs, and all passing passes" {
  fixture "$T/a.bats" 'true'
  fixture "$T/b.bats" 'true'
  fixture "$T/sub/c.bats" 'true'
  PATH="$NO_GNU:$PATH" run bash "$SCRIPT" "$T/" "$T/sub/c.bats"
  assert_success
  assert_output --partial 'ok 1 a.bats'
  assert_output --partial 'ok 1 b.bats'
  assert_output --partial 'ok 1 c.bats'
}

@test "one failing file fails the run and shows which test failed" {
  fixture "$T/a.bats" 'true'
  fixture "$T/b.bats" 'false'
  PATH="$NO_GNU:$PATH" run bash "$SCRIPT" "$T/"
  assert_failure
  assert_output --partial 'not ok 1 b.bats'
  assert_output --partial "$T/b.bats"
}

@test "the files run at the same time" {
  # Each test waits for the other's marker: run one after the other, the first
  # times out.
  fixture "$T/a.bats" "touch '$T/a.up'; for _ in \$(seq 50); do [ -e '$T/b.up' ] && return 0; sleep 0.1; done; false"
  fixture "$T/b.bats" "touch '$T/b.up'; for _ in \$(seq 50); do [ -e '$T/a.up' ] && return 0; sleep 0.1; done; false"
  BATS_RUN_JOBS=2 PATH="$NO_GNU:$PATH" run bash "$SCRIPT" "$T/"
  assert_success
}

@test "the tests run without the git environment of the hook" {
  # git exports GIT_DIR (and GIT_INDEX_FILE, …) to its hooks: the fixtures'
  # `git init` / `git config` would act on this repository with them.
  fixture "$T/a.bats" '[ -z "${GIT_DIR+x}${GIT_INDEX_FILE+x}${GIT_WORK_TREE+x}" ]'
  fixture "$T/b.bats" '[ -z "${GIT_DIR+x}${GIT_INDEX_FILE+x}${GIT_WORK_TREE+x}" ]'
  run env PATH="$NO_GNU:$PATH" GIT_DIR=/nonexistent/.git GIT_INDEX_FILE=/nonexistent/index \
    GIT_WORK_TREE=/nonexistent bash "$SCRIPT" "$T/"
  assert_success
}

@test "with GNU parallel installed, bats parallelizes within the files too" {
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  printf '%s\n' '#!/bin/sh' 'echo "GNU parallel 20261022"' > "$bin/parallel"
  printf '%s\n' '#!/bin/sh' 'echo "bats $*"' > "$bin/bats"
  chmod +x "$bin/parallel" "$bin/bats"
  BATS_RUN_JOBS=3 run env PATH="$bin:$PATH" bash "$SCRIPT" "$T/"
  assert_success
  assert_output "bats --jobs 3 $T/"
}

@test "with GNU parallel, a failing test still fails the run" {
  # Real bats --jobs (CI's runner image has GNU parallel); tests are numbered
  # across the files there.
  parallel --version 2>/dev/null | grep -q '^GNU parallel' || skip "GNU parallel not installed"
  fixture "$T/a.bats" 'true'
  fixture "$T/b.bats" 'false'
  run bash "$SCRIPT" "$T/"
  assert_failure
  assert_line --regexp '^ok [0-9]+ a\.bats$'
  assert_line --regexp '^not ok [0-9]+ b\.bats$'
}

@test "the git hooks run the suite through the parallel runner" {
  local prek="$REPO_ROOT/prek.toml"
  run sed -n '/^id = "bats"$/,/^stages/p' "$prek"
  assert_output --partial 'entry = "bash scripts/bats-run.sh tests/ tests/ai/ tests/ollama/"'
  run grep -c 'exec bash scripts/bats-run.sh' "$REPO_ROOT/scripts/bats-affected.sh"
  assert_output 2
}
