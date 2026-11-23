#!/usr/bin/env bash
# Claude Code SessionStart hook — at the start of a session (and after /clear
# or a compaction, which drop earlier context) tell Claude when to reach for
# the mattpocock-skills skills on its own, tuned to the repository it opens
# in: test-first only where a test suite exists, the infrastructure and CI
# skills only where there is infrastructure or CI, `/next-task` where there is
# a TODO.md. Returned as `additionalContext`, a few lines long.
#
# It also tells the owner (a `systemMessage`, not sent to Claude) when a repo
# that is set up for agents (AGENTS.md or CLAUDE.md) has not run the plugin's
# per-repository setup, which its workflow skills read. Only at startup.
#
# A session that opens on a shared branch (main, master, dev, develop or the
# remote's default, as in the git-workflow skill) is told to hand the owner
# the branch command before the first commit: that line comes plugin or not.
#
#   DOTFILES_SKILL_ROUTER  on (default); off: say nothing (also silences
#                          skill-router.sh).

set -uo pipefail

input=$(cat)

[ "${DOTFILES_SKILL_ROUTER:-on}" = off ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

dir=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$dir" ] || dir=$PWD
source=$(printf '%s' "$input" | jq -r '.source // "startup"' 2>/dev/null)
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root=""

branch_line=""
if [ -n "$root" ]; then
  # Shared branches: the same rule as next-steps.sh and the git-workflow skill.
  branch=$(git -C "$root" symbolic-ref --short -q HEAD 2>/dev/null)
  remote=$(git -C "$root" remote 2>/dev/null | sed -n '/^origin$/{p;q;}')
  [ -n "$remote" ] || remote=$(git -C "$root" remote 2>/dev/null | head -n 1)
  default=$(git -C "$root" symbolic-ref --short -q "refs/remotes/$remote/HEAD" 2>/dev/null)
  case $branch in
    "") ;;
    main | master | dev | develop | "${default#"$remote"/}")
      branch_line="- This session is on \`$branch\`, a shared branch: before the first change that ends in a commit, hand the owner the \`git checkout -b <type>/<slug>\` command named after the work (\`git-workflow\` skill)." ;;
  esac
fi

plugin=mattpocock-skills@claude-plugins-official
enabled=$(jq -r --arg p "$plugin" '.enabledPlugins[$p] // false' "$HOME/.claude/settings.json" 2>/dev/null)
if [ "$enabled" != true ]; then
  [ -n "$branch_line" ] || exit 0
  jq -n --arg c "Git workflow (dotfiles SessionStart hook):"$'\n'"$branch_line" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
  exit 0
fi

files=""
[ -n "$root" ] && files=$(git -C "$root" ls-files 2>/dev/null)
has() { grep -qE "$1" <<<"$files"; }

# What the repository holds, as names for the context line.
infra=()
has '\.tf$' && infra+=(Terraform)
has '(^|/)(ansible\.cfg|playbooks?/|roles/[^/]+/tasks/)' && infra+=(Ansible)
has '(^|/)Chart\.yaml$' && infra+=(Helm)
has '(^|/)kustomization\.ya?ml$' && infra+=(Kustomize)
has '(^|/)(k8s|kubernetes|manifests)/.*\.ya?ml$' && infra+=(Kubernetes)
has '(^|/)(Dockerfile[^/]*|(docker-)?compose[^/]*\.ya?ml)$' && infra+=(Docker)

lines=(
  "Skill routing (dotfiles SessionStart hook). Use these mattpocock-skills skills without being asked, through the Skill tool, when the work matches:"
  "- \`mattpocock-skills:diagnosing-bugs\`: before fixing anything reported broken, failing or slow."
)
if has '(^|/)(tests?|spec|__tests__)/|\.bats$|_test\.(go|py|sh)$|\.(test|spec)\.[jt]sx?$|(^|/)test_[^/]*\.py$'; then
  lines+=("- \`mattpocock-skills:tdd\`: for every feature and bug fix here (this repository has a test suite): the failing test first.")
fi
lines+=(
  "- \`mattpocock-skills:codebase-design\`: when a change adds or reshapes a module or its interface."
  "- \`mattpocock-skills:code-review\`: on your own change of more than one file, before proposing the commit; uncommitted, its diff is \`git diff HEAD\`."
  "- \`mattpocock-skills:writing-for-agents\`: when editing a SKILL.md, AGENTS.md or CLAUDE.md."
  "- \`mattpocock-skills:pr\`: whenever you write a pull request body."
)
if has '(^|/)GLOSSARY\.md$|(^|/)docs/adr/'; then
  lines+=("- \`mattpocock-skills:domain-modeling\`: when a change names or redefines a concept; keep GLOSSARY.md and docs/adr in step.")
fi
if [ "${#infra[@]}" -gt 0 ]; then
  list=$(printf '%s, ' "${infra[@]}")
  lines+=("- This repository holds infrastructure (${list%, }): \`audit\` for an audit or security review of it; diagnose with \`mattpocock-skills:diagnosing-bugs\` before changing a manifest; kubectl stays read-only.")
fi
has '^\.github/workflows/' && lines+=("- \`debug-action\`: when a GitHub Actions run fails.")
[ -n "$root" ] && [ -f "$root/TODO.md" ] && lines+=("- Tasks live in TODO.md: work them with \`/next-task\`, edit the file under the \`todo-md\` rules.")
[ -n "$branch_line" ] && lines+=("$branch_line")
lines+=("Never use \`implement\` or \`implement-spec\`: they commit, and only the owner commits.")

ctx=$(printf '%s\n' "${lines[@]}")
ctx=${ctx%$'\n'}

msg=""
if [ "$source" = startup ] && [ -n "$root" ] \
  && { [ -f "$root/AGENTS.md" ] || [ -f "$root/CLAUDE.md" ]; } \
  && [ ! -f "$root/docs/agents/issue-tracker.md" ]; then
  msg="mattpocock-skills is not set up in $(basename "$root"): run /mattpocock-skills:setup-matt-pocock-skills once for triage, to-spec, to-tickets and wayfinder."
fi

jq -n --arg c "$ctx" --arg m "$msg" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}} + (if $m == "" then {} else {systemMessage: $m} end)'
