# shellcheck shell=bash
# config.sh — centralized configuration + helpers for the local AI tooling
# (scripts/ai/*). Sourced, never executed.
#
#   source "${XDG_CONFIG_HOME:-$HOME/.config}/ai-tools/config.sh"
#
# Talks to Ollama over its HTTP API (no `ollama` binary dependency) so the
# tooling stays agnostic of OS and runtime. Only `curl` and `jq` are required.

# ── Defaults (override any of these via the environment) ─────────────────────
: "${AI_HOST:=http://localhost:11434}"   # Ollama HTTP endpoint
: "${AI_MODEL:=qwen2.5-coder:7b}"         # default model
: "${AI_MODEL_FAST:=qwen2.5-coder:1.5b}"  # lighter / faster model
: "${AI_MAX_DIFF:=6000}"                  # max diff bytes sent to the model
: "${AI_TIMEOUT:=120}"                    # curl --max-time, in seconds

# ai_require_deps — ensure curl and jq are available, otherwise fail clearly.
ai_require_deps() {
  local missing=0 dep
  for dep in curl jq; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      printf 'error: required dependency not found: %s\n' "$dep" >&2
      missing=1
    fi
  done
  return "$missing"
}

# ai_run [model] <prompt> — send <prompt> to Ollama and print the response text.
#   - With 2+ args, the first is the model and the rest is the prompt.
#   - With a single arg, the model defaults to $AI_MODEL.
# Returns 1 (with a message on stderr) on dependency, network, API or empty-reply
# errors.
ai_run() {
  ai_require_deps || return 1

  local model prompt
  if [ "$#" -ge 2 ]; then
    model="$1"; shift
    prompt="$*"
  else
    model="$AI_MODEL"
    prompt="${1:-}"
  fi

  if [ -z "$prompt" ]; then
    printf 'error: ai_run called with an empty prompt\n' >&2
    return 1
  fi

  local payload response
  payload="$(jq -n --arg model "$model" --arg prompt "$prompt" \
    '{model: $model, prompt: $prompt, stream: false}')"

  # No `-f`: we want the body even on a 4xx so the API's own .error can surface.
  if ! response="$(curl -sS --max-time "$AI_TIMEOUT" \
      -H 'Content-Type: application/json' \
      -d "$payload" \
      "$AI_HOST/api/generate")"; then
    printf 'error: request to Ollama failed (%s). Is it running?\n' "$AI_HOST" >&2
    return 1
  fi

  local api_err
  api_err="$(printf '%s' "$response" | jq -r '.error // empty')"
  if [ -n "$api_err" ]; then
    printf 'error: Ollama API: %s\n' "$api_err" >&2
    return 1
  fi

  local text
  text="$(printf '%s' "$response" | jq -r '.response // empty')"
  if [ -z "$text" ]; then
    printf 'error: empty response from Ollama (model: %s)\n' "$model" >&2
    return 1
  fi

  printf '%s\n' "$text"
}
