#!/usr/bin/env bash
# Claude Code Stop hook — before Claude ends its turn, check whether code
# changed in the current git repository without the docs following. If so,
# block the stop once and ask Claude to run the `docs-hub` (docs/) and
# `readme` (README.md) skills. A hook cannot invoke a skill itself; it can only
# hand Claude the instruction.
#
# Fires only when:
#   - the working tree has uncommitted changes to non-Markdown files, and
#   - the repo has a docs/ folder or a README.md, and
#   - neither docs/ nor README.md is already part of the changes.
# `stop_hook_active` is true when Claude is already continuing because of a
# Stop hook: then it always lets the stop through, so it can never loop.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)

[ "$(printf '%s' "$input" | jq -r '.stop_hook_active // false')" = "true" ] && exit 0

dir=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -n "$dir" ] || dir=$PWD
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || exit 0

[ -d "$root/docs" ] || [ -f "$root/README.md" ] || exit 0

# Paths of every staged, unstaged or untracked change (rename → new path).
changed=$(git -C "$root" status --porcelain --untracked-files=all 2>/dev/null \
  | sed -E 's/^.{3}//; s/.* -> //')
[ -n "$changed" ] || exit 0

grep -qE '^(docs/|README\.md$)' <<<"$changed" && exit 0

code=$(grep -vE '\.md$' <<<"$changed" | head -n 10)
[ -n "$code" ] || exit 0

targets=()
[ -d "$root/docs" ] && targets+=("the \`docs-hub\` skill for docs/")
[ -f "$root/README.md" ] && targets+=("the \`readme\` skill for README.md")
list=$(printf '%s and ' "${targets[@]}")
list=${list% and }

reason="Code changed in this repository but its documentation did not:
$(sed 's/^/  - /' <<<"$code")
Before finishing, invoke ${list} (Skill tool) to check whether these changes make the documentation stale. Update it if so; otherwise say in one line that no documentation change is needed."

jq -n --arg r "$reason" '{decision: "block", reason: $r}'
