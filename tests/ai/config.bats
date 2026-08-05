#!/usr/bin/env bats
# Unit tests for config/ai-tools/config.sh — defaults, model selection and the
# ai_run helper. curl is stubbed: no real network call is ever made, and no model
# is ever loaded.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/../.." && pwd)"
  CONFIG="$REPO_ROOT/config/ai-tools/config.sh"

  load "$REPO_ROOT/tests/test_helper/bats-support/load"
  load "$REPO_ROOT/tests/test_helper/bats-assert/load"

  export PAYLOAD_FILE="$BATS_TEST_TMPDIR/payload.json"
  export TAGS_MARKER="$BATS_TEST_TMPDIR/tags_called"

  # Two models: a big thinking-capable one and a smaller plain one. Sizes are in
  # decimal bytes, as /api/tags reports them.
  export TAGS_JSON='{"models":[
    {"name":"big:9b","size":6600000000},
    {"name":"small:4b","size":3400000000}]}'
  export THINKING_MODELS="big:9b"   # answer /api/show with the thinking capability
  export NOGEN_MODELS=""            # answer without "completion" (embedding models)
  export GEN_JSON='{"response":"hello world"}'

  # The stub lives in a real file rather than inside a bash -c string: the
  # escaping needed for a multi-line function in nested quotes is what broke two
  # earlier revisions of these tests.
  STUB="$BATS_TEST_TMPDIR/stub.sh"
  cat > "$STUB" <<'STUB_EOF'
# curl replacement covering the three endpoints config.sh talks to.
curl() {
  local arg url="" body="" want_body=0 model caps
  for arg in "$@"; do
    if [ "$want_body" = 1 ]; then body="$arg"; want_body=0; continue; fi
    case "$arg" in
      -d)    want_body=1 ;;
      http*) url="$arg" ;;
    esac
  done

  case "$url" in
    */api/tags)
      : > "$TAGS_MARKER"
      printf '%s' "$TAGS_JSON"
      ;;
    */api/show)
      model="$(printf '%s' "$body" | jq -r '.model')"
      case " $NOGEN_MODELS " in
        *" $model "*) caps='["embedding"]' ;;
        *)
          case " $THINKING_MODELS " in
            *" $model "*) caps='["completion","thinking"]' ;;
            *)            caps='["completion"]' ;;
          esac
          ;;
      esac
      printf '{"capabilities":%s}' "$caps"
      ;;
    *)
      printf '%s' "$body" > "$PAYLOAD_FILE"
      printf '%s' "$GEN_JSON"
      ;;
  esac
}
STUB_EOF
  export STUB
}

# report — model|fast|think|chosen-by, the whole outcome of selection.
REPORT='printf "%s|%s|[%s]|%s" "$AI_MODEL" "$AI_MODEL_FAST" "$AI_THINK" "$AI_SELECTED_BY"'

# ── Defaults ─────────────────────────────────────────────────────────────────

@test "config.sh sets the documented defaults" {
  run bash -c "source '$CONFIG'; printf '%s|%s|%s|%s|%s|%s|[%s]' \
    \"\$AI_HOST\" \"\$AI_MAX_DIFF\" \"\$AI_TIMEOUT\" \"\$AI_NUM_CTX\" \
    \"\$AI_TEMPERATURE\" \"\$AI_PRESENCE_PENALTY\" \"\$AI_MODELS\""
  assert_success
  assert_output "http://localhost:11434|6000|120|16384|0.3|0|[]"
}

@test "config.sh hardcodes no model tag in code" {
  # The point of the whole design: this file is tracked and shared, so a model
  # list belongs in the user's untracked env, not here.
  #
  # Match the *shape* of an Ollama tag (name:9b, name:1.5b, name:270m) rather
  # than a list of families, so a future model nobody thought of is caught too.
  # Comments may still name models as examples, hence stripping them first.
  run bash -c "sed 's/#.*//' '$CONFIG' \
    | grep -nE '[a-zA-Z][a-zA-Z0-9._-]*:[0-9]+(\.[0-9]+)?[bBmM]([^a-zA-Z]|\$)'"
  assert_failure
}

@test "config.sh resolves no model at source time" {
  # config.sh is sourced by every script, `ai help` included; resolving here
  # would make all of them require a running Ollama.
  run bash -c "source '$CONFIG'; printf '%s' \"\${AI_MODEL-<unset>}\""
  assert_success
  assert_output "<unset>"
}

@test "ai_require_deps passes when curl and jq are present" {
  run bash -c "source '$CONFIG'; ai_require_deps"
  assert_success
}

# ── Automatic selection ──────────────────────────────────────────────────────

@test "auto-selection takes the largest model that fits, smallest as fast" {
  run bash -c "source '$CONFIG'; source '$STUB'; _ai_resolve; $REPORT"
  assert_success
  assert_output "big:9b|small:4b|[false]|auto"
}

@test "auto-selection honours AI_MAX_MODEL_GB" {
  run bash -c "AI_MAX_MODEL_GB=5
source '$CONFIG'; source '$STUB'; _ai_resolve; $REPORT"
  assert_success
  assert_output "small:4b|small:4b|[]|auto"
}

@test "auto-selection skips models that cannot generate" {
  # Embedding models install like any other and lack the completion capability;
  # picking one would fail at generation time with a baffling error.
  export NOGEN_MODELS="big:9b"
  run bash -c "source '$CONFIG'; source '$STUB'; _ai_resolve; $REPORT"
  assert_success
  assert_output "small:4b|small:4b|[]|auto"
}

@test "auto-selection fails clearly when nothing fits" {
  run bash -c "AI_MAX_MODEL_GB=1
source '$CONFIG'; source '$STUB'; _ai_resolve"
  assert_failure
  assert_output --partial "raise AI_MAX_MODEL_GB"
}

# ── AI_THINK is detected, not declared ───────────────────────────────────────

@test "AI_THINK is false for a thinking-capable model" {
  run bash -c "source '$CONFIG'; source '$STUB'; _ai_resolve; printf '[%s]' \"\$AI_THINK\""
  assert_success
  assert_output "[false]"
}

@test "AI_THINK is empty for a model without the capability" {
  # Ollama rejects the field outright there, so it must be dropped entirely.
  export THINKING_MODELS=""
  run bash -c "source '$CONFIG'; source '$STUB'; _ai_resolve; printf '[%s]' \"\$AI_THINK\""
  assert_success
  assert_output "[]"
}

@test "an explicit AI_THINK survives selection" {
  run bash -c "AI_THINK=true
source '$CONFIG'; source '$STUB'; _ai_resolve; printf '%s' \"\$AI_THINK\""
  assert_success
  assert_output "true"
}

# ── Preference list ──────────────────────────────────────────────────────────

@test "AI_MODELS wins over automatic selection, in order" {
  run bash -c "AI_MODELS='small:4b big:9b'
source '$CONFIG'; source '$STUB'; _ai_resolve; $REPORT"
  assert_success
  assert_output "small:4b|small:4b|[]|AI_MODELS"
}

@test "AI_MODELS skips entries that are not installed" {
  # The failure that started this: a deleted model must degrade to the next
  # candidate rather than leave a dangling default.
  run bash -c "AI_MODELS='deleted:70b big:9b'
source '$CONFIG'; source '$STUB'; _ai_resolve; printf '%s' \"\$AI_MODEL\""
  assert_success
  assert_output "big:9b"
}

@test "AI_MODELS ignores AI_MAX_MODEL_GB" {
  # An explicit choice is not second-guessed.
  run bash -c "AI_MODELS='big:9b'
AI_MAX_MODEL_GB=1
source '$CONFIG'; source '$STUB'; _ai_resolve; printf '%s' \"\$AI_MODEL\""
  assert_success
  assert_output "big:9b"
}

@test "AI_MODELS naming nothing installed fails with the pull command" {
  run bash -c "AI_MODELS='absent:70b'
source '$CONFIG'; source '$STUB'; _ai_resolve"
  assert_failure
  assert_output --partial "ollama pull absent:70b"
}

@test "AI_MODELS_FAST selects the fast model independently" {
  run bash -c "AI_MODELS_FAST='big:9b'
source '$CONFIG'; source '$STUB'; _ai_resolve; printf '%s' \"\$AI_MODEL_FAST\""
  assert_success
  assert_output "big:9b"
}

# ── Explicit pin and failure modes ───────────────────────────────────────────

@test "an explicit AI_MODEL bypasses selection without listing models" {
  run bash -c "AI_MODEL=pinned:1b
source '$CONFIG'; source '$STUB'; _ai_resolve
printf '%s|%s|%s' \"\$AI_MODEL\" \"\$AI_MODEL_FAST\" \"\$AI_SELECTED_BY\""
  assert_success
  # No fast counterpart given, so it serves as its own.
  assert_output "pinned:1b|pinned:1b|AI_MODEL"
  [ ! -f "$TAGS_MARKER" ]
}

@test "an unreachable Ollama is reported distinctly" {
  export TAGS_JSON=''
  run bash -c "source '$CONFIG'; source '$STUB'; _ai_resolve"
  assert_failure
  assert_output --partial "Is it running?"
}

# ── ai_run ───────────────────────────────────────────────────────────────────

@test "ai_run builds the request and extracts .response" {
  run bash -c "source '$CONFIG'; source '$STUB'; ai_run mymodel 'a prompt'"
  assert_success
  assert_output "hello world"

  run jq -r '.model + "|" + .prompt + "|" + (.stream|tostring)' "$PAYLOAD_FILE"
  assert_output "mymodel|a prompt|false"
  # num_ctx must be sent, otherwise Ollama silently caps the context at 4096 and
  # truncates the tail of a large staged diff.
  run jq -r '.options.num_ctx|tostring' "$PAYLOAD_FILE"
  assert_output "16384"
  run jq -r '.options.temperature|tostring' "$PAYLOAD_FILE"
  assert_output "0.3"
  # Must be sent even at 0: a model shipping presence_penalty=1.5 otherwise
  # suppresses the repeated '- ' bullet prefix a commit body is built on.
  run jq -r '.options.presence_penalty|tostring' "$PAYLOAD_FILE"
  assert_output "0"
}

@test "ai_run with no model argument uses the selected model" {
  run bash -c "source '$CONFIG'; source '$STUB'; ai_run 'a prompt'"
  assert_success
  run jq -r '.model' "$PAYLOAD_FILE"
  assert_output "big:9b"
}

@test "ai_run sends 'think' when detected and omits it otherwise" {
  run bash -c "source '$CONFIG'; source '$STUB'; ai_run 'x'"
  assert_success
  run jq -r '.think|tostring' "$PAYLOAD_FILE"
  assert_output "false"

  export THINKING_MODELS=""
  run bash -c "source '$CONFIG'; source '$STUB'; ai_run 'x'"
  assert_success
  run jq -r 'has("think")|tostring' "$PAYLOAD_FILE"
  assert_output "false"
}

@test "ai_run strips a leading <think> reasoning block from the response" {
  export GEN_JSON='{"response":"<think>\nWeighing the options.\n</think>\nfeat(api): add endpoint"}'
  run bash -c "source '$CONFIG'; source '$STUB'; ai_run 'x'"
  assert_success
  assert_output "feat(api): add endpoint"
}

@test "ai_run keeps prose that merely mentions <think>" {
  # Regression: a message describing ai_strip_thinking itself legitimately
  # contains the literal tag. An earlier matcher treated it as a real reasoning
  # block and swallowed everything after it, truncating the message mid-sentence.
  export GEN_JSON='{"response":"feat(ai): strip reasoning\n\n- remove <think> blocks from replies\n- add tests"}'
  run bash -c "source '$CONFIG'; source '$STUB'; ai_run 'x'"
  assert_success
  assert_output --partial "- remove <think> blocks from replies"
  assert_output --partial "- add tests"
}

@test "ai_run keeps a response whose leading <think> is never closed" {
  # Degenerate output, but returning it visibly beats silently returning nothing.
  export GEN_JSON='{"response":"<think>\nrambling with no closing tag"}'
  run bash -c "source '$CONFIG'; source '$STUB'; ai_run 'x'"
  assert_success
  assert_line --index 0 "<think>"
}

@test "ai_run surfaces an API error" {
  export GEN_JSON='{"error":"model not found"}'
  run bash -c "source '$CONFIG'; source '$STUB'; ai_run 'x'"
  assert_failure
  assert_output --partial "model not found"
}

@test "ai_run fails on an empty response" {
  export GEN_JSON='{"response":""}'
  run bash -c "source '$CONFIG'; source '$STUB'; ai_run 'x'"
  assert_failure
  assert_output --partial "empty response"
}
