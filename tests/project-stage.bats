#!/usr/bin/env bats
# Tests for .github/scripts/project-stage.sh: the issue-to-board sync of the
# GitHub Project (docs/config/issue-workflow.md#project-board). A fake `gh` on
# PATH answers the GraphQL queries and logs each call.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  SCRIPT="$REPO_ROOT/.github/scripts/project-stage.sh"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  export GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  export FIELD_JSON='{"id":"PVT_1","field":{"id":"FIELD_1","options":[
    {"id":"OPT_TRIAGE","name":"Needs triage"},{"id":"OPT_INFO","name":"Needs info"},
    {"id":"OPT_AGENT","name":"Ready for agent"},{"id":"OPT_HUMAN","name":"Ready for human"},
    {"id":"OPT_WONTFIX","name":"Won'"'"'t fix"},{"id":"OPT_DONE","name":"Done"}]}}'
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # The fake prints, for each call, what the real one would after --jq.
  cat > "$BATS_TEST_TMPDIR/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" | tr -s '\n ' ' ' >> "$GH_LOG"; echo >> "$GH_LOG"
case "$*" in
  *"projectV2(number"*) printf '%s\n' "$FIELD_JSON" ;;
  *addProjectV2ItemById*) echo "ITEM_${ISSUE_ID_SEEN:-1}" ;;
  *updateProjectV2ItemFieldValue*) : ;;
  "issue list"*) printf '%s\n' "${ISSUES_JSON:-[]}" ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export PROJECT_OWNER=owner PROJECT_NUMBER=3 GH_TOKEN=test-token
}

stage() {
  run bash -c "source '$SCRIPT'; stage_for '$1' '${2:-OPEN}'"
}

@test "each triage label maps to its column" {
  stage '["needs-triage"]';    assert_output "Needs triage"
  stage '["needs-info"]';      assert_output "Needs info"
  stage '["ready-for-agent"]'; assert_output "Ready for agent"
  stage '["ready-for-human"]'; assert_output "Ready for human"
  stage '["wontfix"]';         assert_output "Won't fix"
}

@test "an issue without a triage label waits for triage" {
  stage '[]';                    assert_output "Needs triage"
  stage '["urgent","security"]'; assert_output "Needs triage"
}

@test "the label that stops the work wins when several are set" {
  stage '["ready-for-agent","needs-info"]';      assert_output "Needs info"
  stage '["needs-triage","ready-for-agent"]';    assert_output "Ready for agent"
  stage '["ready-for-human","ready-for-agent"]'; assert_output "Ready for human"
  stage '["wontfix","needs-info"]';              assert_output "Won't fix"
}

@test "a closed issue is done, unless it was a wontfix" {
  stage '["ready-for-agent"]' CLOSED; assert_output "Done"
  stage '["wontfix"]' CLOSED;         assert_output "Won't fix"
}

@test "one issue is added to the board and its Stage set" {
  ISSUE_ID=I_42 ISSUE_STATE=OPEN LABELS='["needs-info","urgent"]' run bash "$SCRIPT"
  assert_success
  assert_output --partial "I_42 → Needs info"
  run cat "$GH_LOG"
  assert_line --partial "owner=owner"
  assert_line --partial "number=3"
  assert_line --regexp 'projectId=PVT_1 -f contentId=I_42 .*addProjectV2ItemById'
  assert_line --regexp 'itemId=ITEM_1 -f fieldId=FIELD_1 -f optionId=OPT_INFO .*updateProjectV2ItemFieldValue'
}

@test "without an issue, every open issue is synced (backfill)" {
  export ISSUES_JSON='[{"id":"I_1","state":"OPEN","labels":["ready-for-agent"]},{"id":"I_2","state":"OPEN","labels":[]}]'
  run bash "$SCRIPT"
  assert_success
  assert_output --partial "I_1 → Ready for agent"
  assert_output --partial "I_2 → Needs triage"
  run grep -c updateProjectV2ItemFieldValue "$GH_LOG"
  assert_output "2"
  # The project and its field are looked up once for the whole run.
  run grep -c 'projectV2(number' "$GH_LOG"
  assert_output "1"
}

@test "a Stage field without the column fails and names it" {
  export FIELD_JSON='{"id":"PVT_1","field":{"id":"FIELD_1","options":[{"id":"OPT_TRIAGE","name":"Needs triage"}]}}'
  ISSUE_ID=I_42 ISSUE_STATE=OPEN LABELS='["needs-info"]' run bash "$SCRIPT"
  assert_failure
  assert_output --partial "::error::The Stage field of project 3 has no 'Needs info' option"
  run grep -c updateProjectV2ItemFieldValue "$GH_LOG"
  assert_output "0"
}

@test "a column matches its option whatever the case and surrounding spaces" {
  export FIELD_JSON='{"id":"PVT_1","field":{"id":"FIELD_1","options":[{"id":"OPT_TRIAGE","name":" needs Triage "}]}}'
  ISSUE_ID=I_42 ISSUE_STATE=OPEN LABELS='[]' run bash "$SCRIPT"
  assert_success
  assert_output --partial "I_42 → Needs triage"
  run grep -c 'optionId=OPT_TRIAGE' "$GH_LOG"
  assert_output "1"
}

@test "a missing column lists the options the Stage field has" {
  export FIELD_JSON='{"id":"PVT_1","field":{"id":"FIELD_1","options":[{"id":"A","name":"Todo"},{"id":"B","name":"In Progress"}]}}'
  ISSUE_ID=I_42 ISSUE_STATE=OPEN LABELS='[]' run bash "$SCRIPT"
  assert_failure
  assert_output --partial "::error::The Stage field of project 3 has no 'Needs triage' option (it has: 'Todo', 'In Progress')"
  # A Stage field just created in the UI has no options at all.
  export FIELD_JSON='{"id":"PVT_1","field":{"id":"FIELD_1","options":[]}}'
  ISSUE_ID=I_42 ISSUE_STATE=OPEN LABELS='[]' run bash "$SCRIPT"
  assert_failure
  assert_output --partial "::error::The Stage field of project 3 has no 'Needs triage' option (it has no options yet)"
}

@test "a project without a Stage field fails before anything is added" {
  export FIELD_JSON='{"id":"PVT_1","field":null}'
  ISSUE_ID=I_42 ISSUE_STATE=OPEN LABELS='[]' run bash "$SCRIPT"
  assert_failure
  assert_output --partial "::error::Project 3 of owner has no single-select field named Stage"
  run grep -c addProjectV2ItemById "$GH_LOG"
  assert_output "0"
}

@test "missing settings fail with the variable to set" {
  PROJECT_NUMBER="" run bash "$SCRIPT"
  assert_failure
  assert_output --partial "::error::PROJECT_NUMBER is not set"
  PROJECT_NUMBER=abc run bash "$SCRIPT"
  assert_failure
  assert_output --partial "::error::PROJECT_NUMBER must be a number"
  # The secret is missing: fail on it by name, before any call to GitHub.
  GH_TOKEN="" run bash "$SCRIPT"
  assert_failure
  assert_output --partial "::error::GH_TOKEN is empty: set the PROJECT_TOKEN secret"
  assert_file_not_exists "$GH_LOG"
}

@test "the workflow passes the event through env, never into the script body" {
  local wf="$REPO_ROOT/.github/workflows/project-stage.yml"
  assert_file_exists "$wf"
  run grep -nE 'run:.*\$\{\{' "$wf"
  assert_failure
  run grep -F 'secrets.PROJECT_TOKEN' "$wf"
  assert_success
  # Only the issue events that change a column trigger it.
  run grep -F 'types: [opened, reopened, labeled, unlabeled, closed]' "$wf"
  assert_success
}
