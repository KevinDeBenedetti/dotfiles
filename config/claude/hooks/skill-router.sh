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
# A command the owner ran from the chat arrives as a <bash-input> prompt. Its
# output is no request, so it gets no skill hint, with one exception, plugin
# or not: a commit or push that went through gets the next step of the
# git-workflow skill (push, then the pull request's title and description).
#
# A session the Claude desktop app opened in a worktree sits on a generated
# branch, `<prefix>/<words>-<6 hex>`. While it has that name and no upstream,
# every prompt also asks Claude to rename it after the work, `<type>/<slug>`
# (git-workflow skill, "Session branch"), plugin or not.
#
#   DOTFILES_SKILL_ROUTER          on (default); off: never hint.
#   DOTFILES_SESSION_BRANCH_PREFIX the app's branch prefix setting (default
#                                  claude).

set -uo pipefail

# Read the payload before any exit (see next-steps.sh: EPIPE otherwise).
input=$(cat)

[ "${DOTFILES_SKILL_ROUTER:-on}" = off ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
dir=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$dir" ] || dir=$PWD
trimmed=${prompt#"${prompt%%[![:space:]]*}"}

# git_step — a <bash-input> commit or push that went through: name the next
# step, and the branch it landed on. A failed one (a hook's "....Failed", a
# rejected push, a line starting with error: or fatal:) or any other command
# (git stash push, git log --grep push, …): nothing.
git_step() {
  local run=${trimmed#<bash-input>} out step branch next
  run=${run%%</bash-input>*}
  out=${trimmed#*</bash-input>}
  # git_cmd <subcommand> — git runs it: at the start of a command (or after
  # ; & | or rtk), with only global options in between, as in the guard of
  # config/claude/settings.json.
  git_cmd() {
    grep -qE "(^|[;&|(])[[:space:]]*(rtk[[:space:]]+)?git([[:space:]]+(-[Cc]|--git-dir|--work-tree|--namespace|--exec-path|--config-env)[[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+$1([[:space:]]|\$)" <<<"$run"
  }
  if git_cmd push; then step=push
  elif git_cmd commit; then step=commit
  else return 0
  fi
  grep -qE '\.Failed([[:space:]<]|$)|\[(remote )?rejected\]|(^|>)(error|fatal):|nothing (added )?to commit|no changes added to commit' <<<"$out" && return 0
  branch=$(git -C "$dir" branch --show-current 2>/dev/null)
  if [ "$step" = push ]; then
    next="the owner pushed${branch:+ \`$branch\`} from the chat and it went through: bring its pull request up to date (title and description), or hand the \`gh pr create\` command when it has none. A shared branch (main, dev, …) has none."
  else
    next="the owner committed${branch:+ on \`$branch\`} from the chat: on a shared branch (main, dev, …), hand the branch command that moves the commit off it; otherwise the push command, then the pull request step."
  fi
  jq -n --arg c "Git step (dotfiles hook): $next Follow the \`git-workflow\` skill (Skill tool), in your next reply." \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
}
case $trimmed in '<bash-input>'*) git_step; exit 0 ;; esac

# Reports from subagents and events from the app arrive as prompts too. Their
# words ("refactor", "fails", "PR") describe work already done: no hint.
case $trimmed in
  'Another Claude session sent a message'* | '<agent-message'* | '<task-notification'* \
    | '<side-sessions-event'* | '<ci-monitor-event'*) exit 0 ;;
esac

# The app's generated session branch, not pushed yet: rename it after the work.
session_note=""
branch=$(git -C "$dir" branch --show-current 2>/dev/null)
prefix=${DOTFILES_SESSION_BRANCH_PREFIX:-claude}
if grep -qxE "${prefix//./\\.}/[a-z0-9]+(-[a-z0-9]+)*-[0-9a-f]{6}" <<<"$branch" \
  && [ -z "$(git -C "$dir" config "branch.$branch.merge" 2>/dev/null)" ]; then
  session_note="Session branch (dotfiles hook): \`$branch\` is the name the app generated for this session. As soon as you know what the work is, rename it after the work yourself — \`git branch -m <type>/<slug>\` (\`git-workflow\` skill, \"Session branch\")."
fi

# finish [context] — print the session note and the context, if any, and stop.
finish() {
  local c=$session_note
  [ -n "${1:-}" ] && c=${c:+$c$'\n'}$1
  [ -n "$c" ] && jq -n --arg c "$c" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
  exit 0
}

plugin=mattpocock-skills@claude-plugins-official
enabled=$(jq -r --arg p "$plugin" '.enabledPlugins[$p] // false' "$HOME/.claude/settings.json" 2>/dev/null)
[ "$enabled" = true ] || finish

[ "${#trimmed}" -ge 12 ] || finish
case $trimmed in /*) finish ;; esac
grep -qiE 'mattpocock-skills:|Skill tool' <<<"$prompt" && finish

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

[ "${#hints[@]}" -gt 0 ] || finish

ctx="Skill routing (dotfiles hook): this prompt matches the skills below. Invoke each with the Skill tool before starting that part of the work, unless it clearly does not fit; say in one line which ones you skip and why."
for h in "${hints[@]}"; do ctx+=$'\n'"$h"; done

finish "$ctx"
