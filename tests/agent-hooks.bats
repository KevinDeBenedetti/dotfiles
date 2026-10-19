#!/usr/bin/env bats
# Functional tests for the agent guard rails: the PreToolUse hook commands
# embedded in config/claude/{settings,managed-settings}.json and the Copilot
# guard config/copilot/hooks/agent-guard.sh. Each hook is fed a synthetic tool
# call on stdin, exactly as the agent would send it.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  CONFIG_DIR="$REPO_ROOT/config"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  # Built at runtime so this file never contains the literal blocked commands.
  G=git
  K=kubectl
}

# run_hook <command-string> <tool command> — print the hook's decision JSON.
run_hook() {
  jq -n --arg c "$2" '{tool_name: "Bash", tool_input: {command: $c}}' | bash -c "$1"
}

hook_cmd() { # hook_cmd <settings file> <index in PreToolUse[0].hooks>
  jq -r ".hooks.PreToolUse[0].hooks[$2].command" "$CONFIG_DIR/claude/$1"
}

git_deny_cases() {
  printf '%s\n' \
    "$G commit -m x" \
    "cd x && $G push origin main" \
    "$G -C /tmp/r commit" \
    "$G -c user.name=x commit -m y" \
    "$G --git-dir .git push" \
    "bash -c \"$G push\"" \
    "sh -c '$G commit -m x'" \
    "echo \$($G commit -m x)" \
    "echo \`$G push\`" \
    "/usr/bin/$G push"
}

git_allow_cases() {
  printf '%s\n' \
    "$G status" \
    "$G log --grep commit" \
    "$G-aicommit --yes" \
    "echo legit commit" \
    "${G}leaks detect"
}

assert_hook_denies_git() {
  local hook="$1" c
  while IFS= read -r c; do
    run run_hook "$hook" "$c"
    assert_output --partial '"deny"' || { echo "not denied: $c" >&2; return 1; }
  done < <(git_deny_cases)
  while IFS= read -r c; do
    run run_hook "$hook" "$c"
    refute_output --partial '"deny"' || { echo "wrongly denied: $c" >&2; return 1; }
  done < <(git_allow_cases)
}

@test "settings.json hook blocks commit/push, including wrapped and -c forms" {
  assert_hook_denies_git "$(hook_cmd settings.json 0)"
}

@test "managed-settings.json hook blocks commit/push, including wrapped and -c forms" {
  assert_hook_denies_git "$(hook_cmd managed-settings.json 0)"
}

@test "agent-guard blocks commit/push, including wrapped and -c forms" {
  assert_hook_denies_git "bash '$CONFIG_DIR/copilot/hooks/agent-guard.sh'"
}

@test "kubectl hooks block mutating verbs, including wrapped forms" {
  local hook
  for hook in "$(hook_cmd settings.json 1)" "bash '$CONFIG_DIR/copilot/hooks/agent-guard.sh'"; do
    run run_hook "$hook" "$K --context prod delete pod x"
    assert_output --partial '"deny"'
    run run_hook "$hook" "bash -c \"$K delete pod x\""
    assert_output --partial '"deny"'
    run run_hook "$hook" "$K get pods -l app=run-x"
    refute_output --partial '"deny"'
  done
}
