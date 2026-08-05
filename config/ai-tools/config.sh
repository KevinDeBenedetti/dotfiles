# shellcheck shell=bash
# config.sh — centralized configuration + helpers for the local AI tooling
# (scripts/ai/*). Sourced, never executed.
#
#   source "${XDG_CONFIG_HOME:-$HOME/.config}/ai-tools/config.sh"
#
# Talks to Ollama over its HTTP API (no `ollama` binary dependency) so the
# tooling stays agnostic of OS and runtime. Only `curl` and `jq` are required.

# ── What the environment provided ────────────────────────────────────────────
# Snapshot BEFORE any default lands, so profile selection below can tell an
# explicit choice from an absent one. `${VAR+set}` is true for a variable that
# exists even when empty — which is exactly how AI_THINK= disables the field.
_AI_ENV_MODEL="${AI_MODEL+set}"
_AI_ENV_MODEL_FAST="${AI_MODEL_FAST+set}"
_AI_ENV_THINK="${AI_THINK+set}"

# ── Defaults (override any of these via the environment) ─────────────────────
: "${AI_HOST:=http://localhost:11434}"   # Ollama HTTP endpoint
: "${AI_MAX_DIFF:=6000}"                  # max diff bytes sent to the model
: "${AI_TIMEOUT:=120}"                    # curl --max-time, in seconds

# AI_NUM_CTX — Ollama caps the context at 4096 regardless of what the model
# supports unless options.num_ctx is sent, which silently clips the tail of a
# large staged diff. 16384 costs ~6.1 GB resident for a 9b at Q4_K_M — measured
# 100% GPU on 16 GB of unified memory, with headroom. Drop it back to 8192 if
# `ollama ps` ever reports a CPU share.
: "${AI_NUM_CTX:=16384}"

# AI_TEMPERATURE — sampling temperature. Sent explicitly rather than left to the
# model's own default, which is tuned for chat and runs hot: qwen3.5 ships
# temperature=1, and at that setting it drifts off the format the prompts pin
# down (over-long headers, invented bullet markers). These tools want a
# structured artifact, so bias hard towards obedience. Raise it for prose.
: "${AI_TEMPERATURE:=0.3}"

# AI_PRESENCE_PENALTY — penalty on tokens already seen. Pinned to 0 because the
# model's own value fights these prompts head-on: qwen3.5 ships 1.5, and a commit
# body is *meant* to repeat itself — every bullet opens with the same '- ' prefix.
# Penalised that hard, the model abandons the list format and writes paragraphs.
# Independent of AI_TEMPERATURE: lowering that alone does not bring bullets back.
: "${AI_PRESENCE_PENALTY:=0}"

# ── Model selection ──────────────────────────────────────────────────────────
# No model name is hardcoded anywhere below. Ollama already knows which models
# exist (/api/tags, with sizes) and what each one can do (/api/show, which
# reports `thinking` among its capabilities) — so the two things a hand-written
# profile used to encode are both discoverable at runtime.
#
# AI_MODELS is an ordered preference list of model names. It is empty here on
# purpose: this file is tracked and shared, and a model list is a per-user, even
# per-machine choice. Set it in the untracked ~/.config/dotfiles/env.local.sh:
#
#   export AI_MODELS="qwen3.5:9b qwen2.5-coder:7b"
#
# Left empty, selection falls back to a policy rather than a name: the largest
# installed model that can do completion and fits AI_MAX_MODEL_GB.
: "${AI_MODELS=}"
: "${AI_MODELS_FAST=}"

# AI_MAX_MODEL_GB — ceiling for automatic selection, in decimal GB of on-disk
# size (what /api/tags reports). Machine-specific, hence overridable per host:
# 8 suits 16 GB of unified memory, where roughly 10.6 GB is usable as VRAM and
# the KV cache still has to fit alongside the weights. Ignored when AI_MODELS or
# AI_MODEL names something explicitly — an explicit choice is not second-guessed.
: "${AI_MAX_MODEL_GB:=8}"

# _ai_model_list — "<size-in-bytes><TAB><name>" per installed model, largest
# first. /api/tags is metadata only: it lists what is on disk and loads nothing.
_ai_model_list() {
  curl -sS --max-time 5 "$AI_HOST/api/tags" 2>/dev/null \
    | jq -r '.models[]? | "\(.size)\t\(.name)"' 2>/dev/null \
    | sort -rn
}

# _ai_capabilities <model> — one capability per line ("completion", "thinking",
# "tools", "vision", …). Also metadata: measured ~10 ms, and `ollama ps` confirms
# it loads nothing.
_ai_capabilities() {
  curl -sS --max-time 5 "$AI_HOST/api/show" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg m "$1" '{model: $m}')" 2>/dev/null \
    | jq -r '.capabilities[]? // empty' 2>/dev/null
}

# _ai_pick_generative <list> [max_bytes] — first model in <list> that can
# actually generate text. Embedding models are installed like any other and lack
# the "completion" capability; picking one would fail at generation time with a
# baffling error. Stops at the first match, so this is normally one extra call.
_ai_pick_generative() {
  local list="$1" max="${2:-0}" size name
  while IFS="$(printf '\t')" read -r size name; do
    [ -n "$name" ] || continue
    # A missing or non-numeric size must not abort the scan; treat it as unknown
    # and let the model through rather than excluding it on a parsing accident.
    case "$size" in ''|*[!0-9]*) size=0 ;; esac
    [ "$max" -gt 0 ] && [ "$size" -gt 0 ] && [ "$size" -gt "$max" ] && continue
    if _ai_capabilities "$name" | grep -qx completion; then
      printf '%s' "$name"
      return 0
    fi
  done <<EOF
$list
EOF
  return 1
}

# _ai_first_installed <preferences> <list> — first preferred name present in
# <list>, preserving the caller's order.
_ai_first_installed() {
  local want installed="$2" name
  for want in $1; do
    while IFS="$(printf '\t')" read -r _ name; do
      [ "$name" = "$want" ] && { printf '%s' "$want"; return 0; }
    done <<EOF
$installed
EOF
  done
  return 1
}

# _ai_resolve — settle AI_MODEL / AI_MODEL_FAST / AI_THINK.
# Lazy and memoised: config.sh is sourced by every script (including `ai help`),
# and resolving at source time would make all of them depend on a running Ollama.
_ai_resolve() {
  [ -n "${AI_SELECTED_BY:-}" ] && return 0

  local list max_bytes
  max_bytes=$(( AI_MAX_MODEL_GB * 1000000000 ))

  if [ -n "$_AI_ENV_MODEL" ]; then
    # An explicit pin is taken at face value — not checked against what is
    # installed, so a model can be pulled on demand by the generation call.
    AI_SELECTED_BY='AI_MODEL'
  else
    list="$(_ai_model_list)"
    if [ -z "$list" ]; then
      printf 'error: no model list from Ollama (%s). Is it running?\n' "$AI_HOST" >&2
      return 1
    fi

    if [ -n "$AI_MODELS" ]; then
      AI_MODEL="$(_ai_first_installed "$AI_MODELS" "$list")" || {
        printf 'error: none of AI_MODELS is installed (%s).\n' "$AI_MODELS" >&2
        printf 'Install one with:  ollama pull %s\n' "${AI_MODELS%% *}" >&2
        return 1
      }
      AI_SELECTED_BY='AI_MODELS'
    else
      AI_MODEL="$(_ai_pick_generative "$list" "$max_bytes")" || {
        printf 'error: no installed model can generate text under %s GB.\n' \
          "$AI_MAX_MODEL_GB" >&2
        printf 'Pull one, or raise AI_MAX_MODEL_GB.\n' >&2
        return 1
      }
      AI_SELECTED_BY='auto'
    fi
  fi

  # Fast model: preference list, else the smallest generative model that fits,
  # else the main one. Never fatal — nothing depends on it for correctness.
  if [ -z "$_AI_ENV_MODEL_FAST" ]; then
    AI_MODEL_FAST=""
    if [ -n "${list:-}" ]; then
      if [ -n "$AI_MODELS_FAST" ]; then
        AI_MODEL_FAST="$(_ai_first_installed "$AI_MODELS_FAST" "$list")" || AI_MODEL_FAST=""
      else
        local ascending
        ascending="$(printf '%s\n' "$list" | sort -n)"
        AI_MODEL_FAST="$(_ai_pick_generative "$ascending" "$max_bytes")" || AI_MODEL_FAST=""
      fi
    fi
    [ -n "$AI_MODEL_FAST" ] || AI_MODEL_FAST="$AI_MODEL"
  fi

  # AI_THINK from the model's own capabilities rather than a maintained table:
  # false when it can think (suppress the monologue), empty otherwise so the
  # field is dropped — Ollama rejects it outright on models without it.
  if [ -z "$_AI_ENV_THINK" ]; then
    if _ai_capabilities "$AI_MODEL" | grep -qx thinking; then
      AI_THINK=false
    else
      AI_THINK=
    fi
  fi

  return 0
}

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

# ai_strip_thinking — drop a leading <think>…</think> reasoning block from stdin.
# Thinking-capable models (qwen3.x, gemma, deepseek-r1, …) may inline their
# reasoning in `.response` rather than in the separate `.thinking` field, and it
# would otherwise land verbatim in a commit message.
#
# Deliberately narrow: only a block that OPENS the response and is properly
# CLOSED is removed. Reasoning is always emitted first, never mid-answer, so
# anything further in is prose — a commit message describing this very function
# says "remove <think> blocks", and a looser matcher swallowed the rest of the
# message. An unclosed leading tag is left alone too: that response is degenerate
# either way, and returning it visibly beats silently returning nothing.
ai_strip_thinking() {
  local text
  text="$(cat)"

  local trimmed="${text#"${text%%[![:space:]]*}"}"
  if [ "${trimmed#<think>}" != "$trimmed" ] && [ "${trimmed#*</think>}" != "$trimmed" ]; then
    text="${trimmed#*</think>}"
    text="${text#"${text%%[![:space:]]*}"}"
  fi

  printf '%s\n' "$text"
}

# ai_run [model] <prompt> — send <prompt> to Ollama and print the response text.
#   - With 2+ args, the first is the model and the rest is the prompt.
#   - With a single arg, the model comes from the resolved profile ($AI_MODEL).
# Prefer the single-arg form: it lets profile selection pick the model, and the
# call sites have no business pinning one.
# Returns 1 (with a message on stderr) on dependency, network, API or empty-reply
# errors.
ai_run() {
  ai_require_deps || return 1
  _ai_resolve || return 1

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
  payload="$(jq -n \
    --arg model "$model" \
    --arg prompt "$prompt" \
    --argjson num_ctx "$AI_NUM_CTX" \
    --argjson temperature "$AI_TEMPERATURE" \
    --argjson presence_penalty "$AI_PRESENCE_PENALTY" \
    --arg think "$AI_THINK" \
    '{model: $model, prompt: $prompt, stream: false,
      options: {num_ctx: $num_ctx,
                temperature: $temperature,
                presence_penalty: $presence_penalty}}
     + (if $think == "" then {} else {think: ($think == "true")} end)')"

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
  text="$(printf '%s' "$response" | jq -r '.response // empty' | ai_strip_thinking)"
  if [ -z "$text" ]; then
    printf 'error: empty response from Ollama (model: %s)\n' "$model" >&2
    return 1
  fi

  printf '%s\n' "$text"
}
