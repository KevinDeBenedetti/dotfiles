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

  # Stub curl: record that it was hit, capture the JSON payload (the `-d` arg, so
  # the prompt can be inspected), and return a fixed Ollama-shaped response.
  # /api/tags is answered separately — profile resolution consults it before any
  # generation, and must find the profile's model listed for the run to proceed.
  export CURL_MARKER="$BATS_TEST_TMPDIR/curl_called"
  export AI_PAYLOAD_FILE="$BATS_TEST_TMPDIR/curl_payload"
  export AI_RESPONSE='{"response":"feat: ajout X"}'
  export AI_TAGS='{"models":[{"name":"test-model:9b","size":6600000000}]}'
  export AI_CAPS='{"capabilities":["completion","thinking"]}'
  curl() {
    : > "$CURL_MARKER"
    local arg prev="" url="" body=""
    for arg in "$@"; do
      [ "$prev" = "-d" ] && body="$arg"
      case "$arg" in http*) url="$arg" ;; esac
      prev="$arg"
    done
    case "$url" in
      */api/tags) printf '%s' "$AI_TAGS" ;;
      */api/show) printf '%s' "$AI_CAPS" ;;
      *)
        # Only the generation body is worth capturing for prompt assertions.
        printf '%s' "$body" > "$AI_PAYLOAD_FILE"
        printf '%s' "$AI_RESPONSE"
        ;;
    esac
  }
  export -f curl

  # Existing tests exercise the Ollama path; the claude backend has its own below.
  export AI_COMMIT_BACKEND=ollama
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

@test "git-aicommit prompt lists the release-please types and forbids refactor" {
  echo "content" > file.txt
  git add file.txt

  run bash "$SCRIPT" --yes
  assert_success
  assert [ -f "$AI_PAYLOAD_FILE" ]

  # Guard the prompt against regressions: the release-relevant Conventional
  # Commits types must be presented to the model, and 'refactor' (not surfaced by
  # the release-please config) must be explicitly forbidden.
  run jq -r '.prompt' "$AI_PAYLOAD_FILE"
  assert_success
  assert_output --partial 'feat'
  assert_output --partial 'fix'
  assert_output --partial 'perf'
  assert_output --partial "NEVER use 'refactor'"
}

@test "git-aicommit claude backend pipes the prompt to a tool-less haiku call" {
  echo "content" > file.txt
  git add file.txt

  export AI_COMMIT_BACKEND=claude
  export CLAUDE_ARGS_FILE="$BATS_TEST_TMPDIR/claude_args"
  claude() { printf '%s\n' "$*" > "$CLAUDE_ARGS_FILE"; cat > /dev/null; printf 'feat: via claude'; }
  export -f claude

  run bash "$SCRIPT" --yes
  assert_success

  run git log -1 --pretty=%s
  assert_output "feat: via claude"

  run cat "$CLAUDE_ARGS_FILE"
  assert_output --partial "--model haiku"
  assert_output --partial "--no-session-persistence"
  # Ollama must not be touched.
  assert [ ! -f "$CURL_MARKER" ]
}

@test "git-aicommit claude backend sees the whole repo diff from a subdirectory" {
  mkdir -p sub
  echo "root" > root.txt
  echo "nested" > sub/nested.txt
  git add root.txt sub/nested.txt

  export AI_COMMIT_BACKEND=claude
  export CLAUDE_PROMPT_FILE="$BATS_TEST_TMPDIR/claude_prompt"
  claude() { cat > "$CLAUDE_PROMPT_FILE"; printf 'feat: via claude'; }
  export -f claude

  cd sub
  run bash "$SCRIPT" --yes
  assert_success

  # The staged diff body (not just --stat) must include the file outside sub/.
  run grep -c '^+root$' "$CLAUDE_PROMPT_FILE"
  assert_output "1"
}

@test "git-aicommit exits non-zero when git commit fails" {
  echo "content" > file.txt
  git add file.txt
  # A rejecting pre-commit hook makes `git commit` fail.
  printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit

  run bash "$SCRIPT" --yes
  assert_failure
  assert_output --partial "Commit failed"
}
