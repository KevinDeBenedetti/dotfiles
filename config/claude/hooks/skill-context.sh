#!/usr/bin/env bash
# Claude Code SessionStart hook — at the start of a session (and after /clear
# or a compaction, which drop earlier context) tell Claude when to reach for
# the skills of config/skills/ on its own, tuned to the repository it opens
# in: test-first only where a test suite exists, the infrastructure and CI
# skills only where there is infrastructure or CI, `/next-task` where there is
# a TODO.md. Returned as `additionalContext`, a few lines long.
#
# A session that opens on a shared branch (main, master, dev, develop or the
# remote's default, as in the git-workflow skill) is told to hand the owner
# the branch command before the first commit.
#
#   DOTFILES_SKILL_ROUTER  on (default); off: say nothing (also silences
#                          skill-router.sh).

set -uo pipefail

input=$(cat)

[ "${DOTFILES_SKILL_ROUTER:-on}" = off ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

dir=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$dir" ] || dir=$PWD
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
  "Skill routing (dotfiles SessionStart hook). Load these skills without being asked when the work matches:"
  "- \`diagnosing-bugs\`: before fixing anything reported broken, failing or slow."
)
if has '(^|/)(tests?|spec|__tests__)/|\.bats$|_test\.(go|py|sh)$|\.(test|spec)\.[jt]sx?$|(^|/)test_[^/]*\.py$'; then
  lines+=("- \`tdd\`: for every feature and bug fix here (this repository has a test suite): the failing test first.")
fi
lines+=(
  "- \`codebase-design\`: when a change adds or reshapes a module or its interface."
  "- \`code-review\`: on your own change of more than one file, before proposing the commit; uncommitted, its diff is \`git diff HEAD\`."
  "- \`writing-for-agents\`: when editing a SKILL.md, AGENTS.md or CLAUDE.md."
)
if has '(^|/)GLOSSARY\.md$|(^|/)docs/adr/'; then
  lines+=("- \`domain-modeling\`: when a change names or redefines a concept; keep GLOSSARY.md and docs/adr in step.")
fi
if [ "${#infra[@]}" -gt 0 ]; then
  list=$(printf '%s, ' "${infra[@]}")
  lines+=("- This repository holds infrastructure (${list%, }): an audit or security review of it is the owner's \`/audit\` command; diagnose with \`diagnosing-bugs\` before changing a manifest; kubectl stays read-only.")
fi
has '^\.github/workflows/' && lines+=("- \`debug-action\`: when a GitHub Actions run fails.")
[ -n "$root" ] && [ -f "$root/TODO.md" ] && lines+=("- Tasks live in TODO.md: work them with \`/next-task\`, edit the file under the \`todo-md\` rules.")
[ -n "$branch_line" ] && lines+=("$branch_line")

ctx=$(printf '%s\n' "${lines[@]}")
ctx=${ctx%$'\n'}

jq -n --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
