#!/usr/bin/env bats
# Functional tests for scripts/ai/git-aicommit. curl is stubbed via an exported
# bash function so the child script process inherits it — NO real network call
# is ever made. Runs in a throwaway git repo with an isolated HOME.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/ai/git-aicommit"

  load "$REPO_ROOT/tests/test_helper/bats-support/load"
  load "$REPO_ROOT/tests/test_helper/bats-assert/load"

  # Config lives at $XDG_CONFIG_HOME/ai-tools/config.sh — point it at the repo.
  export XDG_CONFIG_HOME="$REPO_ROOT/config"

  # Isolated HOME so the developer's global gitconfig (signing, hooks) can't
  # interfere with the throwaway repo.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  TEST_REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  git config commit.gpgsign false

  # Stub curl: record that it was hit, return a fixed Ollama-shaped response.
  export CURL_MARKER="$BATS_TEST_TMPDIR/curl_called"
  export AI_RESPONSE='{"response":"feat: ajout X"}'
  curl() { : > "$CURL_MARKER"; printf '%s' "$AI_RESPONSE"; }
  export -f curl
}

@test "git-aicommit fails when nothing is staged" {
  run bash "$SCRIPT" --yes
  assert_failure
  assert_output --partial "no staged changes"
}

@test "git-aicommit --yes commits with the model's message and hits no network" {
  echo "content" > file.txt
  git add file.txt

  run bash "$SCRIPT" --yes
  assert_success

  # The commit exists with the message returned by the stubbed model.
  run git log -1 --pretty=%s
  assert_output "feat: ajout X"

  # The stub intercepted the call — no real curl/network escaped.
  assert [ -f "$CURL_MARKER" ]
}
