#!/usr/bin/env bats
# Functional tests for the Claude Code skill hooks in config/claude/hooks/:
# skill-router.sh (UserPromptSubmit) names the skills a prompt matches, and
# skill-context.sh (SessionStart) gives the standing skill policy for the
# repository the session opens in. Both answer with additionalContext only.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  ROUTER="$DIR/../config/claude/hooks/skill-router.sh"
  CONTEXT="$DIR/../config/claude/hooks/skill-context.sh"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  unset DOTFILES_SKILL_ROUTER
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  echo '{"enabledPlugins": {"mattpocock-skills@claude-plugins-official": true}}' > "$HOME/.claude/settings.json"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO" && git -C "$REPO" init -q -b main
}

track() { # track <path>... — create and git-add files
  local f
  for f in "$@"; do mkdir -p "$REPO/$(dirname "$f")" && touch "$REPO/$f"; done
  git -C "$REPO" add -A
}

prompt() { # prompt <text> — run the router, print the hint text only
  jq -n --arg c "$REPO" --arg p "$1" '{hook_event_name: "UserPromptSubmit", cwd: $c, prompt: $p}' \
    | bash "$ROUTER" | jq -r '.hookSpecificOutput.additionalContext // empty'
}

session() { # session [source] — run the session hook, print its JSON
  jq -n --arg c "$REPO" --arg s "${1:-startup}" '{hook_event_name: "SessionStart", cwd: $c, source: $s}' \
    | bash "$CONTEXT"
}

@test "router: a reported failure asks for diagnosing-bugs" {
  run prompt "the install script crashes on Debian 12, see the log"
  assert_success
  assert_output --partial 'mattpocock-skills:diagnosing-bugs'
}

@test "router: a French failure report matches too" {
  run prompt "le hook ne marche pas depuis hier"
  assert_output --partial 'diagnosing-bugs'
}

@test "router: a failing CI run asks for debug-action, not diagnosing-bugs" {
  run prompt "fix this error in ci, the lint job failed"
  assert_output --partial '`debug-action`'
  refute_output --partial 'diagnosing-bugs'
}

@test "router: a failing infrastructure pipeline still asks for diagnosing-bugs" {
  run prompt "the helm deploy fails in the ci pipeline"
  assert_output --partial 'diagnosing-bugs'
}

@test "router: a fix in a repo with tests asks for tdd; without tests it does not" {
  run prompt "implement a --dry-run flag for the installer"
  refute_output --partial 'tdd'
  track tests/install.bats
  run prompt "implement a --dry-run flag for the installer"
  assert_output --partial 'mattpocock-skills:tdd'
}

@test "router: a bug fix gets the diagnosis first, then tdd" {
  track tests/install.bats
  run prompt "fix the bug where the installer hangs on macOS"
  assert_line --index 1 --partial 'diagnosing-bugs'
  assert_line --index 2 --partial 'tdd'
}

@test "router: never more than two hints" {
  track tests/a.bats
  run prompt "fix the bug, refactor the module interface, then review the changes and open a PR"
  assert_success
  [ "$(grep -c '^- ' <<<"$output")" -eq 2 ]
}

@test "router: reviews of changes, infrastructure audits, design and agent docs" {
  run prompt "review my changes since main before I merge"
  assert_output --partial 'mattpocock-skills:code-review'
  run prompt "audit the terraform and kubernetes setup for security"
  assert_output --partial '`audit`'
  run prompt "refactor the guardrail policy into one module"
  assert_output --partial 'codebase-design'
  run prompt "update AGENTS.md with the new port convention"
  assert_output --partial 'writing-for-agents'
  run prompt "grill me on this migration plan"
  assert_output --partial 'grilling'
}

@test "router: a whole-repo review is not a code-review of changes" {
  run prompt "review this repo for best practices"
  refute_output --partial 'code-review'
}

@test "router: words inside other words do not match" {
  run prompt "update the prefix of the debugger-free errorless config"
  assert_output ""
}

@test "router: silent for slash commands, short replies and prompts naming a skill" {
  run prompt "/next-task all, then fix the failing test"
  assert_output ""
  run prompt "yes, fix it"
  assert_output ""
  run prompt "use mattpocock-skills:tdd to fix the crash"
  assert_output ""
}

@test "router: silent for agent reports and app events, which are not the owner's prompts" {
  # A subagent's report holds review words ("refactor", "PR", "fails") that are
  # about work already done.
  run prompt $'Another Claude session sent a message:\n<agent-message from="a1">\nThe refactor fails; open a PR\n</agent-message>'
  assert_output ""
  run prompt $'<task-notification>\n<summary>Agent "Spec review" finished: the build is broken</summary>\n</task-notification>'
  assert_output ""
  run prompt $'<side-sessions-event>the fix session crashed</side-sessions-event>'
  assert_output ""
  run prompt $'<ci-monitor-event>CI failed on the lint job</ci-monitor-event>'
  assert_output ""
  # A tag may carry attributes.
  run prompt $'<task-notification id="t1">\nthe build is broken\n</task-notification>'
  assert_output ""
}

@test "router: silent for a command the owner ran in the app, whose output is not a request" {
  # The output echoes the command and its tool names ("fix end of files",
  # "ERROR" in a grep pattern), with no request behind them.
  run prompt $'<bash-input>git push</bash-input><bash-stdout>fix end of files....Passed\nshellcheck....Failed</bash-stdout><bash-stderr></bash-stderr>'
  assert_output ""
}

@test "router: a commit or push the owner ran from the chat asks for git-workflow, plugin or not" {
  git -C "$REPO" symbolic-ref HEAD refs/heads/feat/x
  run prompt "<bash-input>git push</bash-input><bash-stdout></bash-stdout><bash-stderr>To github.com:o/r.git
   1a2b3c4..5d6e7f8  feat/x -> feat/x</bash-stderr>"
  assert_output --partial '`git-workflow`'
  assert_output --partial 'pushed `feat/x`'
  assert_output --partial 'pull request'
  # A message that names an error is no failure: git's own start the line.
  run prompt "<bash-input>git add a.sh && git commit -m 'fix: retry on error: 503'</bash-input><bash-stdout>[feat/x 5d6e7f8] fix: retry on error: 503
 1 file changed</bash-stdout><bash-stderr></bash-stderr>"
  assert_output --partial 'committed on `feat/x`'
  assert_output --partial 'the push command'
  # On a shared branch the commit has to move off it first.
  assert_output --partial 'branch command that moves the commit off it'
  run prompt "<bash-input>git commit -m 'docs: explain when to push'</bash-input><bash-stdout>[feat/x 6e7f8a9] docs: explain when to push</bash-stdout><bash-stderr></bash-stderr>"
  assert_output --partial 'committed on'
  echo '{}' > "$HOME/.claude/settings.json"
  run prompt "<bash-input>git -C sub push -u origin feat/x</bash-input><bash-stdout></bash-stdout><bash-stderr>branch 'feat/x' set up to track 'origin/feat/x'.</bash-stderr>"
  assert_output --partial '`git-workflow`'
  DOTFILES_SKILL_ROUTER=off run prompt "<bash-input>git push</bash-input><bash-stdout></bash-stdout><bash-stderr></bash-stderr>"
  assert_output ""
}

@test "router: silent for a commit or push that failed, and for other commands" {
  run prompt "<bash-input>git push</bash-input><bash-stdout></bash-stdout><bash-stderr> ! [rejected]        feat/x -> feat/x (fetch first)
error: failed to push some refs</bash-stderr>"
  assert_output ""
  run prompt "<bash-input>git commit -m 'fix: a'</bash-input><bash-stdout>shellcheck....Failed
- hook id: shellcheck</bash-stdout><bash-stderr></bash-stderr>"
  assert_output ""
  run prompt "<bash-input>git commit -m 'fix: a'</bash-input><bash-stdout></bash-stdout><bash-stderr>fatal: unable to auto-detect email address</bash-stderr>"
  assert_output ""
  # push or commit as a word, not as git's subcommand.
  local other
  for other in 'git status --short' 'git stash push -m wip' 'git log --grep push' 'git help commit' 'echo git push'; do
    run prompt "<bash-input>$other</bash-input><bash-stdout> M a.sh</bash-stdout><bash-stderr></bash-stderr>"
    assert_output ""
  done
}

@test "router: still hints for an owner's prompt that quotes an agent tag mid-text" {
  run prompt "why does the <agent-message> parser crash on empty input"
  assert_output --partial 'diagnosing-bugs'
}

@test "router: silent when switched off or when the plugin is not enabled" {
  DOTFILES_SKILL_ROUTER=off run prompt "the install script crashes on Debian 12"
  assert_output ""
  echo '{}' > "$HOME/.claude/settings.json"
  run prompt "the install script crashes on Debian 12"
  assert_output ""
}

@test "router: emits UserPromptSubmit additionalContext, never a block" {
  run bash -c "jq -n --arg c '$REPO' '{cwd: \$c, prompt: \"the build is broken again\"}' | bash '$ROUTER'"
  assert_success
  run jq -r '.hookSpecificOutput.hookEventName, (has("decision"))' <<<"$output"
  assert_output $'UserPromptSubmit\nfalse'
}

@test "context: the standing policy, tdd only where there are tests" {
  run session
  assert_success
  run jq -r '.hookSpecificOutput.additionalContext' <<<"$output"
  assert_output --partial 'diagnosing-bugs'
  assert_output --partial 'Never use `implement`'
  refute_output --partial 'tdd'
  track src/app_test.go
  run bash -c "$(declare -f session); REPO='$REPO' CONTEXT='$CONTEXT' session | jq -r .hookSpecificOutput.additionalContext"
  assert_output --partial 'mattpocock-skills:tdd'
}

@test "context: names the infrastructure, CI and TODO.md it finds" {
  track infra/main.tf charts/app/Chart.yaml .github/workflows/ci.yml
  touch "$REPO/TODO.md"
  run bash -c "$(declare -f session); REPO='$REPO' CONTEXT='$CONTEXT' session | jq -r .hookSpecificOutput.additionalContext"
  assert_output --partial 'infrastructure (Terraform, Helm)'
  assert_output --partial '`debug-action`'
  assert_output --partial '/next-task'
  refute_output --partial 'domain-modeling'
}

@test "context: tells the owner, at startup only, when an agent repo lacks the plugin setup" {
  touch "$REPO/AGENTS.md"
  run bash -c "$(declare -f session); REPO='$REPO' CONTEXT='$CONTEXT' session startup | jq -r '.systemMessage // empty'"
  assert_output --partial 'setup-matt-pocock-skills'
  run bash -c "$(declare -f session); REPO='$REPO' CONTEXT='$CONTEXT' session compact | jq -r '.systemMessage // empty'"
  assert_output ""
  mkdir -p "$REPO/docs/agents" && touch "$REPO/docs/agents/issue-tracker.md"
  run bash -c "$(declare -f session); REPO='$REPO' CONTEXT='$CONTEXT' session startup | jq -r '.systemMessage // empty'"
  assert_output ""
}

@test "context: on a shared branch, asks for the branch command before the first commit" {
  local branch
  for branch in main dev; do
    git -C "$REPO" symbolic-ref HEAD "refs/heads/$branch"
    run bash -c "$(declare -f session); REPO='$REPO' CONTEXT='$CONTEXT' session | jq -r .hookSpecificOutput.additionalContext"
    assert_output --partial "This session is on \`$branch\`"
    assert_output --partial 'git checkout -b'
    assert_output --partial '`git-workflow`'
  done
  git -C "$REPO" symbolic-ref HEAD refs/heads/feat/x
  run bash -c "$(declare -f session); REPO='$REPO' CONTEXT='$CONTEXT' session | jq -r .hookSpecificOutput.additionalContext"
  refute_output --partial 'git checkout -b'
}

@test "context: silent when switched off; without the plugin, only the branch line" {
  DOTFILES_SKILL_ROUTER=off run session
  assert_output ""
  echo '{"enabledPlugins": {}}' > "$HOME/.claude/settings.json"
  run bash -c "$(declare -f session); REPO='$REPO' CONTEXT='$CONTEXT' session | jq -r .hookSpecificOutput.additionalContext"
  assert_output --partial 'This session is on `main`'
  refute_output --partial 'mattpocock-skills'
  git -C "$REPO" symbolic-ref HEAD refs/heads/feat/x
  run session
  assert_output ""
}
