#!/usr/bin/env bash
# VS Code Copilot PreToolUse guard — mirrors the hard rules of
# config/claude/settings.json (the reference config):
#   - git commit / git push / gh repo delete      → deny
#   - gh auth token / git credential              → deny (print stored tokens)
#   - mutating kubectl verbs (kubectl is read-only) → deny
#   - kubectl get secret(s)                       → deny (dumps Secret values)
#   - terraform apply|destroy, gh pr merge,
#     gh api, kubectl config view                 → ask
#   - reading/writing secrets (.env*, keys, …)    → deny (.env.example allowed)
#
# Copilot has no OS sandbox and its tool names differ from Claude Code's, so
# this guard is tool-agnostic: it inspects `tool_input.command` and every
# path-like argument (keys containing path/file/uri), plus each token of the
# command line, whatever the tool is called.

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "agent-guard: jq is required — blocking tool call (fail closed)" >&2
  exit 2
fi

input=$(cat)

decide() {
  jq -n --arg d "$1" --arg r "$2" '{hookSpecificOutput: {
    hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

# Stricter than config/claude/settings.json: every .env.* except .env.example is
# denied, since Copilot has no sandbox behind this guard.
is_sensitive_path() {
  local p="$1" base
  p="${p#file://}"
  base="${p##*/}"
  case "$base" in
    .env.example) return 1 ;;
    .env | .env.* | *.env | *.pem | *.key | .netrc | .npmrc) return 0 ;;
  esac
  case "$p" in
    # Everything under ~/.ssh is private (keys are not all named id_*), except
    # public keys and the client config.
    *.ssh/*.pub | *.ssh/config | *.ssh/config.d/* | *.ssh/known_hosts) return 1 ;;
    *.ssh/* | *.aws/* | *.aws | *.gnupg/* | *.gnupg | *.claude/.credentials.json) return 0 ;;
    *.kube/config | *.config/dotfiles/env.local.sh | *.config/opencode/llm-api-key) return 0 ;;
  esac
  return 1
}

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.cmd // empty' 2>/dev/null)

if [ -n "$cmd" ]; then
  # The prefix accepts any non-word char (quotes, backticks, $(, /usr/bin/) so
  # `bash -c "git push"` is caught; value-taking global options (-c, -C,
  # --git-dir, …) are skipped with their argument.
  if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_.-])git([[:space:]]+(-[Cc]|--git-dir|--work-tree|--namespace|--exec-path|--config-env)[[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+(commit|push)([^[:alnum:]_-]|$)'; then
    decide deny "git commit/push are done manually — blocked by agent-guard"
  fi
  if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])gh[[:space:]]+repo[[:space:]]+delete'; then
    decide deny "gh repo delete is blocked by agent-guard"
  fi
  if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_.-])(gh[[:space:]]+auth[[:space:]]+token|git[[:space:]]+credential)([^[:alnum:]_-]|$)'; then
    decide deny "printing stored credentials is blocked by agent-guard"
  fi
  if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_.-])kubectl[[:space:]]([^;&|]*[[:space:]])?get[[:space:]]([^;&|]*[[:space:],])?secrets?([[:space:]/,]|$)'; then
    decide deny "reading Kubernetes Secrets is blocked by agent-guard"
  fi
  if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_.-])kubectl[[:space:]]([^;&|]*[[:space:]])?(apply|delete|patch|rollout|create|annotate|edit|scale|exec|debug|run|replace|set|label|taint|cordon|uncordon|drain|cp|expose|autoscale)([^[:alnum:]_-]|$)'; then
    decide deny "kubectl is read-only for the agent — mutating verbs are blocked by agent-guard"
  fi
  # Secrets referenced on the command line (cat .env, source .env.production, …)
  set -f
  for tok in $(printf '%s' "$cmd" | tr "\"'=<>|;&()" '          '); do
    if is_sensitive_path "$tok"; then
      decide deny "access to secret file '$tok' is blocked by agent-guard"
    fi
  done
  set +f
  if printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])(terraform[[:space:]]+(apply|destroy)|gh[[:space:]]+pr[[:space:]]+merge|gh[[:space:]]+api|kubectl[[:space:]]+config[[:space:]]+view)'; then
    decide ask "terraform apply/destroy, gh pr merge, gh api and kubectl config view require confirmation"
  fi
fi

# Path-like arguments of read/edit/create tools, whatever their name.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if is_sensitive_path "$p"; then
    decide deny "access to secret file '$p' is blocked by agent-guard"
  fi
done < <(printf '%s' "$input" | jq -r '
  [.tool_input? // {} | .. | objects | to_entries[]
   | select(.key | test("path|file|uri"; "i")) | .value
   | if type == "array" then .[] else . end | strings] | .[]' 2>/dev/null)

exit 0
