#!/usr/bin/env bats
# Functional tests for scripts/ai/ai-test-api. curl is stubbed via an exported
# bash function so the child script process inherits it — NO real network call
# is ever made.
#
# The env files used here are named `creds`, not `.env`: agent sandboxes (and
# some CI setups) deny access to *.env paths, and the script's --file flag
# makes the name irrelevant to what is being tested.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/ai/ai-test-api"

  load "$REPO_ROOT/tests/test_helper/bats-support/load"
  load "$REPO_ROOT/tests/test_helper/bats-assert/load"

  # Config lives at $XDG_CONFIG_HOME/ai-tools/config.sh — point it at the repo.
  export XDG_CONFIG_HOME="$REPO_ROOT/config"

  cd "$BATS_TEST_TMPDIR"

  # Stub curl: record every argv (so headers/payloads can be inspected) and
  # answer per endpoint, emulating `-w '\n%{http_code}'`.
  export AI_ARGS_FILE="$BATS_TEST_TMPDIR/curl_args"
  export MODELS_CODE=200
  export MODELS_BODY='{"data":[{"id":"gpt-test-1"},{"id":"gpt-test-2"}]}'
  export CHAT_CODE=200
  export CHAT_BODY='{"choices":[{"message":{"content":"pong"}}],"usage":{"total_tokens":12}}'
  curl() {
    printf '%s\n' "$@" >> "$AI_ARGS_FILE"
    local url="${*: -1}"
    case "$url" in
      */models)           printf '%s\n%s' "$MODELS_BODY" "$MODELS_CODE" ;;
      */chat/completions) printf '%s\n%s' "$CHAT_BODY" "$CHAT_CODE" ;;
      *)                  return 1 ;;
    esac
  }
  export -f curl
}

@test "ai-test-api --help prints usage" {
  run bash "$SCRIPT" --help
  assert_success
  assert_output --partial "Usage: ai-test-api"
}

@test "ai-test-api fails clearly when OPENAI_API_KEY is nowhere to be found" {
  run bash "$SCRIPT"
  assert_failure
  assert_output --partial "OPENAI_API_KEY not found"
}

@test "ai-test-api reads the env file, checks /models and runs a completion" {
  printf 'OPENAI_API_KEY=sk-secret-value-1234\nOPENAI_MODEL=my-model\n' > creds

  run bash "$SCRIPT" --file creds
  assert_success
  assert_output --partial "GET /models → 200 (2 models available)"
  assert_output --partial 'POST /chat/completions (my-model) → 200 — reply: "pong" (12 tokens)'

  # The full key must never be printed — only its masked form.
  refute_output --partial "sk-secret-value-1234"
  assert_output --partial "sk-s…1234"

  # The key was sent as a Bearer header to the stubbed curl.
  run grep -c "Bearer sk-secret-value-1234" "$AI_ARGS_FILE"
  assert_output "2"
}

@test "ai-test-api --models-only skips the completion call" {
  printf 'OPENAI_API_KEY=sk-secret-value-1234\n' > creds

  run bash "$SCRIPT" --file creds --models-only
  assert_success
  assert_output --partial "models-only"
  run grep -c "chat/completions" "$AI_ARGS_FILE"
  assert_failure   # grep finds nothing → exit 1
}

@test "ai-test-api parses quotes/export and defaults the model to the first of /models" {
  # Deliberately fake credential, built with printf (not a heredoc) so the
  # gitleaks:allow marker stays a shell comment instead of ending up in `creds`.
  printf 'export OPENAI_API_KEY="sk-quoted-key-5678"\n' > creds  # gitleaks:allow
  printf "OPENAI_BASE_URL='http://localhost:11434/v1'\n" >> creds

  run bash "$SCRIPT" --file creds
  assert_success
  assert_output --partial "base URL: http://localhost:11434/v1"
  # No OPENAI_MODEL anywhere → first entry of the /models response is used.
  assert_output --partial "POST /chat/completions (gpt-test-1)"
  # Quotes were stripped before building the Authorization header.
  run grep -c 'Bearer sk-quoted-key-5678' "$AI_ARGS_FILE"
  assert_output "2"
}

@test "ai-test-api lets the real environment win over the env file" {
  printf 'OPENAI_API_KEY=sk-from-file-0000\n' > creds

  OPENAI_API_KEY="sk-from-env-9999" run bash "$SCRIPT" --file creds --models-only
  assert_success
  run grep -c "Bearer sk-from-env-9999" "$AI_ARGS_FILE"
  assert_output "1"
}

@test "ai-test-api surfaces the API error on a non-200 /models" {
  printf 'OPENAI_API_KEY=sk-bad-key-1234\n' > creds
  export MODELS_CODE=401
  export MODELS_BODY='{"error":{"message":"Incorrect API key provided"}}'

  run bash "$SCRIPT" --file creds
  assert_failure
  assert_output --partial "HTTP 401"
  assert_output --partial "Incorrect API key provided"
}
