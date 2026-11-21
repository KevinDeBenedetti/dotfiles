#!/usr/bin/env bats
# Tests for the project-board Cloudflare Worker (.github/project-board/): a card
# moved on the board sets the issue's triage label, and closes or reopens it
# (docs/config/issue-workflow.md#from-the-board-to-the-labels). The Worker runs
# under Node with GitHub's API faked by tests/project-board-harness.mjs, which
# prints one line per call.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  WORKER="$REPO_ROOT/.github/project-board/worker.mjs"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  # The Docker test image has no Node; CI's runner and the owner's Mac do.
  command -v node >/dev/null || skip "node is not installed"

  export PAYLOAD='{"action":"edited","projects_v2_item":{"node_id":"PVTI_1","content_type":"Issue"}}'
}

# item STAGE STATE [LABELS_JSON] [REPO]: the project item the fake API returns.
item() {
  local stage="$1" state="$2" labels="${3:-[]}" repo="${4:-owner/repo}"
  local stage_json='null'
  [[ -n "$stage" ]] && stage_json="{\"name\":\"$stage\",\"field\":{\"id\":\"FIELD_STAGE\"}}"
  ITEM=$(jq -nc --argjson stage "$stage_json" --arg state "$state" --argjson labels "$labels" --arg repo "$repo" '{
    project: {number: 1, owner: {login: "labs"}},
    stage: $stage,
    content: {number: 7, state: $state, stateReason: null,
              labels: {nodes: ($labels | map({name: .}))},
              repository: {nameWithOwner: $repo}}}')
  export ITEM
}

deliver() {
  run node "$DIR/project-board-harness.mjs" "$WORKER"
}

@test "a card moved to another open column swaps the triage label" {
  item "Ready for agent" OPEN '["needs-info","urgent"]'
  deliver
  assert_success
  assert_line "GRAPHQL PVTI_1"
  # One call: labels and state change together, so the issue never shows a
  # half-applied move.
  assert_line 'PATCH /repos/owner/repo/issues/7 {"labels":["urgent","ready-for-agent"]}'
  assert_line --partial "=> 200"
}

@test "a card moved to Done closes the issue as completed, dropping wontfix" {
  item "Done" OPEN '["ready-for-agent","wontfix"]'
  deliver
  assert_success
  assert_line 'PATCH /repos/owner/repo/issues/7 {"labels":["ready-for-agent"],"state":"closed","state_reason":"completed"}'
}

@test "a card moved to Won't fix labels the issue and closes it as not planned" {
  item "Won't fix" OPEN '["needs-triage"]'
  deliver
  assert_success
  assert_line 'PATCH /repos/owner/repo/issues/7 {"labels":["wontfix"],"state":"closed","state_reason":"not_planned"}'
}

@test "a closed card moved back to an open column reopens the issue" {
  item "Needs info" CLOSED '["ready-for-agent"]'
  deliver
  assert_success
  assert_line 'PATCH /repos/owner/repo/issues/7 {"labels":["needs-info"],"state":"open"}'
}

@test "a column is matched whatever its case and surrounding spaces" {
  item " ready for HUMAN " OPEN '[]'
  deliver
  assert_success
  assert_line 'PATCH /repos/owner/repo/issues/7 {"labels":["ready-for-human"]}'
}

@test "a card already in step with its labels changes nothing (no ping-pong)" {
  # What the label-to-board workflow writes comes back as an edit: it must
  # stop here.
  item "Needs info" OPEN '["needs-info","ready-for-agent"]'
  deliver
  assert_success
  refute_line --partial "PATCH"
  item "Done" CLOSED '["ready-for-agent"]'
  deliver
  assert_success
  refute_line --partial "PATCH"
  item "Needs triage" OPEN '[]'
  deliver
  assert_success
  refute_line --partial "PATCH"
}

@test "an edit of another field of the card changes nothing" {
  # A label change may still be on its way to the Stage column: re-applying
  # the column now would undo it.
  item "Done" OPEN '[]'
  PAYLOAD='{"action":"edited","projects_v2_item":{"node_id":"PVTI_1","content_type":"Issue"},"changes":{"field_value":{"field_node_id":"FIELD_OTHER"}}}' deliver
  assert_success
  refute_line --partial "PATCH"
  PAYLOAD='{"action":"edited","projects_v2_item":{"node_id":"PVTI_1","content_type":"Issue"},"changes":{"field_value":{"field_node_id":"FIELD_STAGE"}}}' deliver
  assert_success
  assert_line --partial "PATCH /repos/owner/repo/issues/7"
}

@test "an unknown column, or none, changes nothing" {
  item "Backlog" OPEN '["needs-info"]'
  deliver
  assert_success
  refute_line --partial "PATCH"
  item "" OPEN '["needs-info"]'
  deliver
  assert_success
  refute_line --partial "PATCH"
}

@test "an issue of another repository, or another project, is left alone" {
  item "Done" OPEN '[]' "someone/else"
  deliver
  assert_success
  refute_line --partial "PATCH"
  item "Done" OPEN '[]'
  VARS='{"PROJECT_NUMBER":"2"}' deliver
  assert_success
  refute_line --partial "PATCH"
}

@test "a draft or pull request card, or another action, is not looked up" {
  item "Done" OPEN '[]'
  PAYLOAD='{"action":"edited","projects_v2_item":{"node_id":"PVTI_1","content_type":"DraftIssue"}}' deliver
  assert_success
  refute_line --partial "GRAPHQL"
  PAYLOAD='{"action":"reordered","projects_v2_item":{"node_id":"PVTI_1","content_type":"Issue"}}' deliver
  assert_success
  refute_line --partial "GRAPHQL"
}

@test "a delivery without a valid signature is refused before any call" {
  item "Done" OPEN '[]'
  SIGNATURE=bad deliver
  assert_success
  assert_line --partial "=> 401"
  refute_line --partial "GRAPHQL"
  SIGNATURE=none deliver
  assert_line --partial "=> 401"
  refute_line --partial "GRAPHQL"
}

@test "only signed POSTs are handled; a ping and other events are acknowledged" {
  METHOD=GET deliver
  assert_line --partial "=> 405"
  EVENT=ping deliver
  assert_line --partial "=> 200"
  EVENT=issues deliver
  assert_line --partial "=> 202"
  refute_line --partial "GRAPHQL"
}

@test "the Worker is configured for the organization board, its secrets kept out" {
  local toml="$REPO_ROOT/.github/project-board/wrangler.toml"
  assert_file_exists "$toml"
  run grep -E '^main = "worker.mjs"$' "$toml"
  assert_success
  # Secrets are set with `wrangler secret put`, never written here.
  run grep -Ei 'GITHUB_TOKEN|WEBHOOK_SECRET' "$toml"
  refute_output --regexp '^[[:space:]]*(GITHUB_TOKEN|WEBHOOK_SECRET)[[:space:]]*='
}

@test "the Worker and project-stage.sh agree on every issue's column" {
  # The two directions stop each other only if they compute the same column:
  # stageFor (plan.mjs) mirrors stage_for (project-stage.sh).
  local labels state js sh
  for labels in '[]' '["urgent"]' '["needs-triage"]' '["needs-info"]' '["ready-for-agent"]' \
    '["ready-for-human"]' '["wontfix"]' '["ready-for-agent","needs-info"]' \
    '["ready-for-human","ready-for-agent"]' '["wontfix","needs-info"]' '["needs-triage","ready-for-agent"]'; do
    for state in OPEN CLOSED; do
      js=$(node --input-type=module -e "const { stageFor } = await import(process.argv[1]); console.log(stageFor(JSON.parse(process.argv[2]), process.argv[3]))" \
        "$REPO_ROOT/.github/project-board/plan.mjs" "$labels" "$state")
      sh=$(bash -c "source '$REPO_ROOT/.github/scripts/project-stage.sh'; stage_for '$labels' '$state'")
      [[ "$js" == "$sh" ]] || fail "$labels $state: Worker says '$js', project-stage.sh says '$sh'"
    done
  done
}
