#!/usr/bin/env bats
# Tests for the project-board Cloudflare Worker (.github/project-board/), a
# GitHub App's webhook receiver that keeps the organization's board and the
# triage labels of every repository in step, both ways
# (docs/config/issue-workflow.md#project-board). The Worker runs under Node
# against the fake GitHub of tests/project-board-harness.mjs, which prints one
# line per call and the token it carried: inst-11 is the App's installation on
# the account owning the repositories, inst-22 the one on the organization.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  BOARD="$REPO_ROOT/.github/project-board"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  # The Docker test image has no Node; CI's runner and the owner's Mac do.
  command -v node >/dev/null || skip "node is not installed"

  moved_card
}

# moved_card [SENDER_TYPE] [CHANGES_JSON] [SENDER_LOGIN]: a projects_v2_item
# edit, as the delivery after a card is dragged.
moved_card() {
  PAYLOAD=$(jq -nc --arg type "${1:-User}" --argjson changes "${2:-null}" --arg login "${3:-someone}" '{
    action: "edited", sender: {login: $login, type: $type},
    projects_v2_item: {node_id: "PVTI_1", content_type: "Issue"}} + (if $changes then {changes: $changes} else {} end)')
  export EVENT=projects_v2_item PAYLOAD
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

# issue_event ACTION [REPO] [PRIVATE]: an issues delivery for issue 7 of REPO.
issue_event() {
  PAYLOAD=$(jq -nc --arg action "$1" --arg repo "${2:-owner/repo}" --argjson private "${3:-false}" '{
    action: $action, sender: {login: "someone", type: "User"},
    issue: {node_id: "I_7", number: 7, labels: [{name: "stale-in-payload"}]},
    repository: {full_name: $repo, private: $private, owner: {login: ($repo | split("/")[0])}}}')
  export EVENT=issues PAYLOAD
}

deliver() {
  run node "$DIR/project-board-harness.mjs" "$BOARD"
}

# --- from the board to the labels ---------------------------------------------

@test "a card moved to another open column swaps the triage label" {
  item "Ready for agent" OPEN '["needs-info","urgent"]'
  deliver
  assert_success
  # The item is read with the organization's token, the issue is written with
  # the token of the account owning its repository.
  assert_line "GRAPHQL item PVTI_1 as inst-22"
  # One call: labels and state change together, never half a move.
  assert_line 'PATCH /repos/owner/repo/issues/7 {"labels":["urgent","ready-for-agent"]} as inst-11'
  assert_line --partial "=> 200"
}

@test "a card moved to Done closes the issue as completed, dropping wontfix" {
  item "Done" OPEN '["ready-for-agent","wontfix"]'
  deliver
  assert_line 'PATCH /repos/owner/repo/issues/7 {"labels":["ready-for-agent"],"state":"closed","state_reason":"completed"} as inst-11'
}

@test "a card moved to Won't fix labels the issue and closes it as not planned" {
  item "Won't fix" OPEN '["needs-triage"]'
  deliver
  assert_line 'PATCH /repos/owner/repo/issues/7 {"labels":["wontfix"],"state":"closed","state_reason":"not_planned"} as inst-11'
}

@test "a closed card moved back to an open column reopens the issue" {
  item "Needs info" CLOSED '["ready-for-agent"]'
  deliver
  assert_line 'PATCH /repos/owner/repo/issues/7 {"labels":["needs-info"],"state":"open"} as inst-11'
}

@test "an issue an agent finished (done) is in Done while it waits for the commit" {
  # /next-issue swaps ready-for-agent for done: the issue stays open until the
  # owner's commit reaches the default branch.
  issue_event labeled
  export ISSUE='{"number":7,"state":"OPEN","labels":["done","urgent"]}'
  deliver
  assert_line "GRAPHQL update ITEM_I_7 OPT_DONE as inst-22"
  # Its card already in Done: nothing to change, the issue is not closed.
  moved_card
  item "Done" OPEN '["done"]'
  deliver
  refute_line --partial "PATCH"
}

@test "a reopened issue loses the done label, so it leaves Done" {
  # Its commit closed it with done still on; reopened, it is work again.
  PAYLOAD=$(jq -nc '{action: "reopened", sender: {login: "someone", type: "User"},
    issue: {node_id: "I_7", number: 7, labels: [{name: "done"}, {name: "urgent"}]},
    repository: {full_name: "owner/repo", private: false, owner: {login: "owner"}}}')
  export EVENT=issues PAYLOAD ISSUE='{"number":7,"state":"OPEN","labels":["urgent"]}'
  deliver
  assert_success
  assert_line "DELETE /repos/owner/repo/issues/7/labels/done  as inst-11"
  assert_line "GRAPHQL update ITEM_I_7 OPT_TRIAGE as inst-22"
}

@test "a card moved out of Done loses the done label" {
  item "Needs info" OPEN '["done","urgent"]'
  deliver
  assert_line 'PATCH /repos/owner/repo/issues/7 {"labels":["urgent","needs-info"]} as inst-11'
}

@test "a column is matched whatever its case and surrounding spaces" {
  item " ready for HUMAN " OPEN '[]'
  deliver
  assert_line 'PATCH /repos/owner/repo/issues/7 {"labels":["ready-for-human"]} as inst-11'
}

@test "a card already in step with its labels changes nothing" {
  item "Needs info" OPEN '["needs-info","ready-for-agent"]'
  deliver
  assert_success
  refute_line --partial "PATCH"
  item "Done" CLOSED '["ready-for-agent"]'
  deliver
  refute_line --partial "PATCH"
}

@test "an unknown column, or none, changes nothing" {
  item "Backlog" OPEN '["needs-info"]'
  deliver
  refute_line --partial "PATCH"
  item "" OPEN '["needs-info"]'
  deliver
  refute_line --partial "PATCH"
}

@test "an edit of another field of the card changes nothing" {
  item "Done" OPEN '[]'
  moved_card User '{"field_value":{"field_node_id":"FIELD_OTHER"}}'
  deliver
  refute_line --partial "PATCH"
  moved_card User '{"field_value":{"field_node_id":"FIELD_STAGE"}}'
  deliver
  assert_line --partial "PATCH /repos/owner/repo/issues/7"
}

@test "the App's own column writes are not turned back into labels" {
  # Its label-to-board write comes back as an edit: answering it could undo a
  # drag made in the meantime.
  item "Done" OPEN '[]'
  moved_card Bot "null" "board-app[bot]"
  deliver
  assert_success
  assert_line --partial "=> 202"
  refute_line --partial "GRAPHQL"
  # Another bot's move is a move like any other.
  moved_card Bot "null" "other-app[bot]"
  deliver
  assert_line --partial "PATCH /repos/owner/repo/issues/7"
}

@test "a card of another project, owner or uninstalled account is left alone" {
  item "Done" OPEN '[]'
  VARS='{"PROJECT_NUMBER":"2"}' deliver
  refute_line --partial "PATCH"
  item "Done" OPEN '[]' "stranger/repo"
  deliver
  refute_line --partial "PATCH"
  refute_line "TOKEN inst-11"
  item "Done" OPEN '[]' "owner/repo"
  INSTALLED='{"labs":22}' deliver
  assert_success
  refute_line --partial "PATCH"
  assert_line --partial "not installed"
}

@test "a draft, a pull request or a reorder is not looked up" {
  PAYLOAD='{"action":"edited","projects_v2_item":{"node_id":"PVTI_1","content_type":"DraftIssue"}}' deliver
  refute_line --partial "GRAPHQL"
  PAYLOAD='{"action":"reordered","projects_v2_item":{"node_id":"PVTI_1","content_type":"Issue"}}' deliver
  refute_line --partial "GRAPHQL"
}

@test "a card whose private issue the App cannot see is read with the board token" {
  # The organization's installation sees the card, not a private issue of the
  # account: the board token reads it, the App's account token writes it.
  local hidden
  for hidden in null error; do
    item "Ready for agent" OPEN '["needs-triage"]'
    HIDDEN_ITEM=$hidden deliver
    assert_success
    assert_line "GRAPHQL item PVTI_1 as inst-22"
    assert_line "GRAPHQL item PVTI_1 as board-pat"
    assert_line 'PATCH /repos/owner/repo/issues/7 {"labels":["ready-for-agent"]} as inst-11'
  done
}

@test "a hidden issue without a board token fails and names the secret" {
  item "Ready for agent" OPEN '["needs-triage"]'
  HIDDEN_ITEM=null VARS='{"BOARD_TOKEN":""}' deliver
  assert_line --partial "=> 500"
  assert_line --partial "BOARD_TOKEN"
  refute_line --partial "PATCH"
}

# --- from the labels to the board ---------------------------------------------

@test "a labelled issue is put on the board, in the column of its labels now" {
  issue_event labeled
  # The payload's labels are stale: the column comes from the issue as it is.
  export ISSUE='{"number":7,"state":"OPEN","labels":["needs-info","urgent"]}'
  deliver
  assert_success
  assert_line "GRAPHQL project labs/1 as inst-22"
  assert_line "GRAPHQL add I_7 as inst-22"
  assert_line "GRAPHQL update ITEM_I_7 OPT_INFO as inst-22"
  assert_line --partial "=> 200 owner/repo#7 → Needs info"
}

@test "a private issue of another account is put on the board with the board token" {
  issue_event labeled owner/secret true
  export ISSUE='{"number":7,"state":"OPEN","labels":["needs-info"]}'
  deliver
  assert_success
  assert_line "GRAPHQL add I_7 as board-pat"
  assert_line "GRAPHQL update ITEM_I_7 OPT_INFO as board-pat"
  refute_line --partial "as inst-22"
  # The organization's own private repositories stay with the App.
  issue_event labeled labs/internal true
  deliver
  assert_line "GRAPHQL add I_7 as inst-22"
}

@test "every action that can change the column syncs the issue" {
  local action
  for action in opened reopened labeled unlabeled closed; do
    issue_event "$action"
    deliver
    assert_line "GRAPHQL add I_7 as inst-22"
  done
  issue_event assigned
  deliver
  refute_line --partial "GRAPHQL"
}

@test "a column written from labels that changed meanwhile is written again" {
  # Deliveries run in parallel: an older one may write after a newer one. The
  # issue is read again after the write, and the column follows it.
  issue_event labeled
  export ISSUE='{"number":7,"state":"OPEN","labels":["needs-info"]}'
  export ISSUE_AFTER='{"number":7,"state":"OPEN","labels":["ready-for-agent"]}'
  deliver
  assert_success
  assert_line "GRAPHQL update ITEM_I_7 OPT_INFO as inst-22"
  assert_line "GRAPHQL update ITEM_I_7 OPT_AGENT as inst-22"
  assert_line --partial "→ Ready for agent"
}

@test "a token GitHub refuses is replaced once, and the call made again" {
  # A cached token outlives a reinstall of the App.
  issue_event opened
  REVOKED="22" deliver
  assert_success
  assert_line "REFUSED inst-22-stale"
  assert_line "GRAPHQL project labs/1 as inst-22"
  assert_line --partial "=> 200"
}

@test "an item already in its column is not written again" {
  issue_event unlabeled
  export ISSUE='{"number":7,"state":"CLOSED","labels":[]}' CURRENT_OPTION=OPT_DONE
  deliver
  assert_success
  refute_line --partial "GRAPHQL update"
  assert_line --partial "Done (already there)"
}

@test "an issue of another owner's repository never reaches the board" {
  issue_event opened "stranger/repo"
  deliver
  assert_success
  refute_line --partial "GRAPHQL"
  refute_line --partial "TOKEN"
}

@test "a Stage field without the column fails and lists its options" {
  issue_event opened
  export OPTIONS='[{"id":"A","name":"Todo"}]'
  deliver
  assert_line --partial "=> 500"
  assert_line --partial "no 'Needs triage' option (it has: 'Todo')"
  refute_line --partial "GRAPHQL update"
}

# --- the webhook and the App ---------------------------------------------------

@test "a delivery without a valid signature is refused before any call" {
  item "Done" OPEN '[]'
  SIGNATURE=bad deliver
  assert_line --partial "=> 401"
  refute_line --partial "GRAPHQL"
  SIGNATURE=none deliver
  assert_line --partial "=> 401"
}

@test "only POSTs are handled; a ping and other events are acknowledged" {
  METHOD=GET deliver
  assert_line --partial "=> 405"
  EVENT=ping deliver
  assert_line --partial "=> 200 pong"
  EVENT=push deliver
  assert_line --partial "=> 202"
  refute_line --partial "TOKEN"
}

@test "a key in GitHub's PKCS#1 format fails with the command converting it" {
  item "Done" OPEN '[]'
  KEY_FORMAT=pkcs1 deliver
  assert_line --partial "=> 500"
  assert_line --partial "openssl pkcs8 -topk8 -nocrypt"
}

# --- backfill -------------------------------------------------------------------

@test "the backfill puts every open issue of the given repositories on the board" {
  export REPO_ISSUES='{"owner/a":[{"node_id":"I_1","number":1},{"node_id":"PR_2","number":2,"pull_request":{}}],
                       "owner/b":[{"node_id":"I_3","number":3}]}'
  MODE=backfill REPOS="owner/a owner/b" run node "$DIR/project-board-harness.mjs" "$BOARD"
  assert_success
  assert_line "GRAPHQL project labs/1 as pat"
  assert_line "owner/a#1 → Needs triage"
  assert_line "owner/b#3 → Needs triage"
  # Pull requests are listed with the issues: they are skipped.
  refute_line --partial "PR_2"
}

@test "the Worker's config names the board, and holds no secret" {
  local toml="$BOARD/wrangler.toml"
  run grep -E '^main = "worker.mjs"$' "$toml"
  assert_success
  run grep -E '^(PROJECT_OWNER|PROJECT_NUMBER|REPOSITORY_OWNERS) = ' "$toml"
  assert_equal "${#lines[@]}" 3
  run grep -E '^[[:space:]]*(WEBHOOK_SECRET|GITHUB_APP_ID|GITHUB_APP_PRIVATE_KEY|BOARD_TOKEN|GITHUB_TOKEN)[[:space:]]*=' "$toml"
  assert_failure
}
