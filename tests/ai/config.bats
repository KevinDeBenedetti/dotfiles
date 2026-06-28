#!/usr/bin/env bats
# Unit tests for config/ai-tools/config.sh — defaults, env overrides and the
# ai_run helper. curl is stubbed: no real network call is ever made.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/../.." && pwd)"
  CONFIG="$REPO_ROOT/config/ai-tools/config.sh"

  load "$REPO_ROOT/tests/test_helper/bats-support/load"
  load "$REPO_ROOT/tests/test_helper/bats-assert/load"
}

@test "config.sh sets the documented defaults" {
  run bash -c "source '$CONFIG'; printf '%s|%s|%s|%s|%s' \
    \"\$AI_HOST\" \"\$AI_MODEL\" \"\$AI_MODEL_FAST\" \"\$AI_MAX_DIFF\" \"\$AI_TIMEOUT\""
  assert_success
  assert_output "http://localhost:11434|qwen2.5-coder:7b|qwen2.5-coder:1.5b|6000|120"
}

@test "config.sh honours an environment override" {
  run bash -c "AI_MODEL=foo; source '$CONFIG'; printf '%s' \"\$AI_MODEL\""
  assert_success
  assert_output "foo"
}

@test "ai_require_deps passes when curl and jq are present" {
  run bash -c "source '$CONFIG'; ai_require_deps"
  assert_success
}

@test "ai_run builds the request and extracts .response" {
  # Stub curl: ignore args, echo back what Ollama would return. Capturing the
  # JSON payload via a temp file proves ai_run posts {model, prompt, stream}.
  PAYLOAD_FILE="$BATS_TEST_TMPDIR/payload.json"
  run bash -c "
    source '$CONFIG'
    curl() {
      # The JSON body is the argument right after -d.
      while [ \"\$#\" -gt 0 ]; do
        if [ \"\$1\" = '-d' ]; then printf '%s' \"\$2\" > '$PAYLOAD_FILE'; fi
        shift
      done
      printf '%s' '{\"response\":\"hello world\"}'
    }
    ai_run mymodel 'a prompt'
  "
  assert_success
  assert_output "hello world"
  # The payload must carry the model and the prompt we passed.
  run jq -r '.model + "|" + .prompt + "|" + (.stream|tostring)' "$PAYLOAD_FILE"
  assert_output "mymodel|a prompt|false"
}

@test "ai_run surfaces an API error" {
  run bash -c "
    source '$CONFIG'
    curl() { printf '%s' '{\"error\":\"model not found\"}'; }
    ai_run mymodel 'x'
  "
  assert_failure
  assert_output --partial "model not found"
}

@test "ai_run fails on an empty response" {
  run bash -c "
    source '$CONFIG'
    curl() { printf '%s' '{\"response\":\"\"}'; }
    ai_run mymodel 'x'
  "
  assert_failure
  assert_output --partial "empty response"
}
