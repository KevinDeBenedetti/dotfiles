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

# run_path_hook <path> — feed the guard a read tool call on <path>.
run_path_hook() {
  jq -n --arg p "$1" '{tool_name: "read_file", tool_input: {filePath: $p}}' \
    | bash "$CONFIG_DIR/copilot/hooks/agent-guard.sh"
}

@test "agent-guard protects every private key under ~/.ssh, not only id_*" {
  local p
  for p in /home/u/.ssh/id_rsa /home/u/.ssh/github_pro /home/u/.ssh/argocd_deploy_key \
    /home/u/.kube/config /home/u/.config/dotfiles/env.local.sh; do
    run run_path_hook "$p"
    assert_output --partial '"deny"' || { echo "not denied: $p" >&2; return 1; }
  done
  for p in /home/u/.ssh/github_pro.pub /home/u/.ssh/config /home/u/.ssh/config.d/x.conf \
    /home/u/.ssh/known_hosts; do
    run run_path_hook "$p"
    refute_output --partial '"deny"' || { echo "wrongly denied: $p" >&2; return 1; }
  done
}

@test "agent-guard blocks credential dumps and Kubernetes Secret reads" {
  local guard="bash '$CONFIG_DIR/copilot/hooks/agent-guard.sh'" GH=gh c
  for c in "$GH auth token" "$G credential fill" "$K get secrets -A -o yaml" \
    "$K -n x get secret db" "$K get secret/db -o json" "$K get all,secrets"; do
    run run_hook "$guard" "$c"
    assert_output --partial '"deny"' || { echo "not denied: $c" >&2; return 1; }
  done
  for c in "$GH auth status" "$K get secretstores" "$K describe secret db"; do
    run run_hook "$guard" "$c"
    refute_output --partial '"deny"' || { echo "wrongly denied: $c" >&2; return 1; }
  done
}

@test "kubectl Secret reads are denied by the settings and managed hooks, whatever the flags" {
  # The deny rules only match the plain `kubectl get secret…` form; the hook
  # covers namespaced, rtk-rewritten and comma-list forms too.
  local hook c
  for hook in "$(hook_cmd settings.json 2)" "$(hook_cmd managed-settings.json 1)"; do
    for c in "$K get secrets -A -o yaml" "$K -n x get secret db" "rtk $K get secret/db -o json" "$K get all,secrets"; do
      run run_hook "$hook" "$c"
      assert_output --partial '"deny"' || { echo "not denied: $c" >&2; return 1; }
    done
    for c in "$K get secretstores" "$K describe secret db" "$K -n x get pods"; do
      run run_hook "$hook" "$c"
      refute_output --partial '"deny"' || { echo "wrongly denied: $c" >&2; return 1; }
    done
  done
}

@test "agent-guard asks before gh api and kubectl config view" {
  local guard="bash '$CONFIG_DIR/copilot/hooks/agent-guard.sh'" GH=gh
  run run_hook "$guard" "$GH api repos/o/r"
  assert_output --partial '"ask"'
  run run_hook "$guard" "$K config view"
  assert_output --partial '"ask"'
}

# --- agent-guard: every secret path, command form and decision ---
# Copilot has no sandbox: this guard is its only protection.

# guard_decision <json tool call> — the guard's decision, or "" for none.
guard_decision() {
  bash "$CONFIG_DIR/copilot/hooks/agent-guard.sh" <<<"$1" | jq -r '.hookSpecificOutput.permissionDecision // empty'
}

@test "agent-guard denies every secret path, whatever the tool and its argument name" {
  local p
  for p in /p/.env /p/.env.production /p/app.env /p/server.pem /p/tls.key file:///p/.env \
    /home/u/.aws/credentials /home/u/.gnupg/pubring.kbx /home/u/.netrc /home/u/.npmrc \
    /home/u/.claude/.credentials.json /home/u/.config/opencode/llm-api-key; do
    # A read, a write under another key name, and a list of paths.
    assert_equal "$(guard_decision "$(jq -n --arg p "$p" '{tool_name: "read_file", tool_input: {filePath: $p}}')")" deny
    assert_equal "$(guard_decision "$(jq -n --arg p "$p" '{tool_name: "create_file", tool_input: {path: $p, content: "x"}}')")" deny
    assert_equal "$(guard_decision "$(jq -n --arg p "$p" '{tool_name: "edit_files", tool_input: {files: ["/p/ok.md", $p]}}')")" deny
  done
  for p in /p/.env.example /p/README.md /p/environment.md /p/keys.txt; do
    assert_equal "$(guard_decision "$(jq -n --arg p "$p" '{tool_name: "read_file", tool_input: {filePath: $p}}')")" ""
  done
}

@test "agent-guard denies a secret file named anywhere on a command line" {
  local c
  for c in "cat .env" "source .env.production" "cp id.key /tmp" "x=\$(cat ~/.aws/credentials)" \
    "grep TOKEN <.env" "less ~/.netrc"; do
    assert_equal "$(guard_decision "$(jq -n --arg c "$c" '{tool_name: "run_in_terminal", tool_input: {command: $c}}')")" deny
  done
  for c in "cat .env.example" "ls -la" "echo environment"; do
    assert_equal "$(guard_decision "$(jq -n --arg c "$c" '{tool_name: "run_in_terminal", tool_input: {command: $c}}')")" ""
  done
}

@test "agent-guard denies deleting a repository and asks before applying infrastructure or merging" {
  # Built at runtime, like G and K in setup: the agent's own hooks would block a
  # command line holding the guarded words literally.
  local GH=gh TF=terraform c
  assert_equal "$(guard_decision "$(jq -n --arg c "$GH repo delete o/r --yes" '{tool_input: {command: $c}}')")" deny
  for c in "$TF apply" "$TF destroy -auto-approve" "$GH pr merge 12 --squash"; do
    assert_equal "$(guard_decision "$(jq -n --arg c "$c" '{tool_input: {command: $c}}')")" ask
  done
  for c in "$TF plan" "$GH pr view 12"; do
    assert_equal "$(guard_decision "$(jq -n --arg c "$c" '{tool_input: {command: $c}}')")" ""
  done
}

@test "agent-guard fails closed when jq is missing" {
  mkdir -p "$BATS_TEST_TMPDIR/nojq"
  run env PATH="$BATS_TEST_TMPDIR/nojq" /bin/bash "$CONFIG_DIR/copilot/hooks/agent-guard.sh" <<<'{"tool_input":{"command":"ls"}}'
  assert_failure 2
  assert_output --partial "fail closed"
}

# --- The three guardrail files stay in step (AGENTS.md) ---
# config/claude/settings.json is the reference: each of its Bash denies must
# be denied by OpenCode and by the Copilot guard, and each file denied for
# reading must be denied for editing too.

# The reference's Bash deny patterns, without their `rtk ` twins.
reference_bash_denies() {
  jq -r '.permissions.deny[] | select(startswith("Bash(")) | ltrimstr("Bash(") | rtrimstr(")")
    | select(startswith("rtk ") | not)' "$CONFIG_DIR/claude/settings.json"
}

@test "every Bash deny of the reference settings is a deny in OpenCode" {
  local rule missing=()
  while IFS= read -r rule; do
    [ "$(jq -r --arg r "$rule" '.permission.bash[$r] // empty' "$CONFIG_DIR/opencode/opencode.json")" = deny ] \
      || missing+=("$rule")
  done < <(reference_bash_denies)
  [ "${#missing[@]}" -eq 0 ] || fail "denied in settings.json, not in opencode.json: ${missing[*]}"
}

@test "every Bash deny of the reference settings is denied by the Copilot guard" {
  # One command per pattern: each `*` stands for an argument (or nothing).
  local rule cmd decision missing=()
  while IFS= read -r rule; do
    cmd=$(sed -e 's#/\*#/x#g' -e 's# \*# x#g' -e 's#\*##g' <<<"$rule")
    decision=$(run_hook "bash '$CONFIG_DIR/copilot/hooks/agent-guard.sh'" "$cmd" \
      | jq -r '.hookSpecificOutput.permissionDecision // empty')
    [ "$decision" = deny ] || missing+=("$cmd")
  done < <(reference_bash_denies)
  [ "${#missing[@]}" -eq 0 ] || fail "not denied by agent-guard.sh: ${missing[*]}"
}

@test "OpenCode denies editing every file it denies reading" {
  run jq -r '.permission as $p | $p.read | to_entries[] | select(.value == "deny") | .key
    | select(($p.edit[.] // "") != "deny")' "$CONFIG_DIR/opencode/opencode.json"
  assert_success
  assert_output ""
}

@test "the reference settings deny editing every file they deny reading" {
  # Edit denies still to be added to settings.json, which is write-denied to
  # agents: remove each line here once the owner has added its Edit rule.
  local pending='~/.kube/config
~/.netrc
~/.npmrc
~/.config/opencode/llm-api-key
**/*.pem
**/*.key'
  run jq -r --arg pending "$pending" '.permissions.deny as $d
    | $d[] | select(startswith("Read(")) | ltrimstr("Read(") | rtrimstr(")")
    | select(("Edit(" + . + ")") as $e | ($d | index($e)) | not)
    | select(. as $p | ($pending | split("\n") | index($p)) | not)' "$CONFIG_DIR/claude/settings.json"
  assert_success
  assert_output ""
}
