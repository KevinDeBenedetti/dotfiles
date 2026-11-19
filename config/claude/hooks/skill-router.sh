#!/usr/bin/env bash
# Claude Code UserPromptSubmit hook — read each prompt, and when it matches the
# kind of work a mattpocock-skills skill (or one of this repo's skills) is
# built for, hand Claude a short hint naming that skill. A hook cannot invoke a
# skill itself: the hint is `additionalContext`, which Claude reads with the
# prompt and acts on. It never blocks the prompt.
#
# Stays silent when the prompt is a slash command (a skill was already picked),
# already names a skill, is too short to say what it is about ("yes", "ok"),
# or when the plugin is not enabled. At most two hints per prompt.
#
#   DOTFILES_SKILL_ROUTER  on (default); off: never hint.

set -uo pipefail

# Read the payload before any exit (see next-steps.sh: EPIPE otherwise).
input=$(cat)

[ "${DOTFILES_SKILL_ROUTER:-on}" = off ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

plugin=mattpocock-skills@claude-plugins-official
enabled=$(jq -r --arg p "$plugin" '.enabledPlugins[$p] // false' "$HOME/.claude/settings.json" 2>/dev/null)
[ "$enabled" = true ] || exit 0

prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
dir=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$dir" ] || dir=$PWD

trimmed=${prompt#"${prompt%%[![:space:]]*}"}
[ "${#trimmed}" -ge 12 ] || exit 0
case $trimmed in /*) exit 0 ;; esac
# Reports from subagents and events from the app arrive as prompts too. Their
# words ("refactor", "fails", "PR") describe work already done: no hint.
case $trimmed in
  'Another Claude session sent a message'* | '<agent-message'* | '<task-notification'* \
    | '<side-sessions-event'* | '<ci-monitor-event'*) exit 0 ;;
esac
grep -qiE 'mattpocock-skills:|Skill tool' <<<"$prompt" && exit 0

# matches <ERE> — the prompt holds one of the alternatives as a whole word.
# C locale: accented letters are bytes outside [[:alnum:]], so they still
# match literally and count as word boundaries.
matches() { LC_ALL=C grep -qiE "(^|[^[:alnum:]_])($1)($|[^[:alnum:]_])" <<<"$prompt"; }

root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root=""
# has_tests — the repository has a test suite tdd can drive.
has_tests() {
  [ -n "$root" ] || return 1
  git -C "$root" ls-files 2>/dev/null \
    | grep -qE '(^|/)(tests?|spec|__tests__)/|\.bats$|_test\.(go|py|sh)$|\.(test|spec)\.[jt]sx?$|(^|/)test_[^/]*\.py$'
}

hints=()
hint() { [ "${#hints[@]}" -lt 2 ] && hints+=("- \`$1\`: $2"); return 0; }

infra='terraform|tofu|ansible|helm|kubernetes|k8s|kubectl|kustomize|argo ?cd|flux|docker|compose|infra(structure)?|cluster|manifests?|playbooks?'
failure="bugs?|broken|crash(es|ed|ing)?|fail(s|ed|ing|ure)?|errors?|exceptions?|regressions?|slow(er|ness)?|hangs?|hanging|debug|not working|doesn'?t work|ne (marche|fonctionne) (pas|plus)|erreurs?|plante|bloqu[ée]"
ci='ci|github actions?|workflow run|actions run|pipeline'

if matches "$failure"; then
  if matches "$ci" && ! matches "$infra"; then
    hint debug-action "a CI run fails: read its log and find the cause before changing anything"
  else
    hint mattpocock-skills:diagnosing-bugs "something is reported broken, failing or slow: reproduce and find the cause before fixing"
  fi
fi

if matches "audit|security review|harden(ing)?|s[ée]curit[ée]" && matches "$infra"; then
  hint audit "an infrastructure audit: report only actionable findings"
fi

if matches "review|relis|relire|revue|before (i|we) (merge|commit)"; then
  matches "repo(sitory)?|codebase" || hint mattpocock-skills:code-review "review the changes against the repo's standards and the task's spec"
fi

if matches "grill|stress[- ]test|poke holes|challenge (my|this|the) (plan|idea|design)"; then
  hint mattpocock-skills:grilling "stress-test the plan with the owner, one question at a time"
fi

if matches "refactor(ing)?|architecture|deep modules?|seams?|decouple|restructure|interface|module boundar(y|ies)"; then
  hint mattpocock-skills:codebase-design "shape the module and its interface before writing the code"
fi

if matches "glossary|adrs?|terminology|domain model(ing)?|ubiquitous language"; then
  hint mattpocock-skills:domain-modeling "name the concepts; keep GLOSSARY.md / docs/adr in step"
fi

if matches "prototype|spike|poc|proof of concept|throwaway"; then
  hint mattpocock-skills:prototype "answer the design question with a throwaway prototype first"
fi

if matches "research|investigate|compare (the )?(options|librar(y|ies)|tools|approaches)|which (library|tool|approach) should"; then
  hint mattpocock-skills:research "check primary sources before deciding"
fi

if matches "pull request|pr (body|description)|open (a|the) pr|write (a|the) pr"; then
  hint mattpocock-skills:pr "write the PR body"
fi

if matches "SKILL\.md|AGENTS\.md|CLAUDE\.md|(new|a|the|this) skill"; then
  hint mattpocock-skills:writing-for-agents "the text is written for agents"
fi

if matches "implement|add (a |an |the )?(feature|option|flag|command|target|check|test)|new feature|fix|ajoute[rz]?|impl[ée]mente[rz]?|corrige[rz]?" && has_tests; then
  hint mattpocock-skills:tdd "this repository has a test suite: write the failing test first"
fi

[ "${#hints[@]}" -gt 0 ] || exit 0

ctx="Skill routing (dotfiles hook): this prompt matches the skills below. Invoke each with the Skill tool before starting that part of the work, unless it clearly does not fit; say in one line which ones you skip and why."
for h in "${hints[@]}"; do ctx+=$'\n'"$h"; done

jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
