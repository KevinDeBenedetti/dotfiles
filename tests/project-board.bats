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
  # A drag: GitHub names the edited field (the Stage field's node id).
  local stage_edit='{"field_value":{"field_node_id":"FIELD_STAGE"}}'
  PAYLOAD=$(jq -nc --arg type "${1:-User}" --argjson changes "${2:-$stage_edit}" --arg login "${3:-someone}" '{
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

@test "a card moved to Done closes the issue as completed, dropping every triage label" {
  # A closed issue carries no triage label (issue 135): Done is one set.
  item "Done" OPEN '["ready-for-agent","wontfix","done","urgent"]'
  deliver
  assert_line 'PATCH /repos/owner/repo/issues/7 {"labels":["urgent"],"state":"closed","state_reason":"completed"} as inst-11'
}

# closed_event REASON LABELS_JSON: an issues delivery for issue 7, closed with
# that state_reason.
closed_event() {
  PAYLOAD=$(jq -nc --arg reason "$1" --argjson labels "$2" '{action: "closed", sender: {login: "someone", type: "User"},
    issue: {node_id: "I_7", number: 7, state_reason: $reason, labels: ($labels | map({name: .}))},
    repository: {full_name: "owner/repo", private: false, owner: {login: "owner"}}}')
  export EVENT=issues PAYLOAD
}

@test "an issue closed as completed another way loses its triage labels too" {
  # A Fixes #n commit or the close button: the closed delivery strips them.
  closed_event completed '["ready-for-agent","done","urgent"]'
  export ISSUE='{"number":7,"state":"CLOSED","labels":["urgent"]}'
  deliver
  assert_success
  assert_line "DELETE /repos/owner/repo/issues/7/labels/ready-for-agent  as inst-11"
  assert_line "DELETE /repos/owner/repo/issues/7/labels/done  as inst-11"
  refute_line --partial "labels/urgent"
  assert_line "GRAPHQL update ITEM_I_7 OPT_DONE as inst-22"
}

@test "an issue closed as a duplicate loses its triage labels" {
  closed_event duplicate '["needs-triage"]'
  export ISSUE='{"number":7,"state":"CLOSED","labels":[]}'
  deliver
  assert_success
  assert_line "DELETE /repos/owner/repo/issues/7/labels/needs-triage  as inst-11"
}

@test "an issue closed as not planned keeps wontfix" {
  closed_event not_planned '["wontfix","urgent"]'
  export ISSUE='{"number":7,"state":"CLOSED","labels":["wontfix","urgent"]}'
  deliver
  assert_success
  refute_line --partial "DELETE"
  assert_line "GRAPHQL update ITEM_I_7 OPT_WONTFIX as inst-22"
}

@test "a reopened issue with no triage label lands in Needs triage" {
  PAYLOAD=$(jq -nc '{action: "reopened", sender: {login: "someone", type: "User"},
    issue: {node_id: "I_7", number: 7, labels: [{name: "urgent"}]},
    repository: {full_name: "owner/repo", private: false, owner: {login: "owner"}}}')
  export EVENT=issues PAYLOAD ISSUE='{"number":7,"state":"OPEN","labels":["urgent"]}' CURRENT_OPTION=OPT_DONE
  deliver
  assert_success
  refute_line --partial "DELETE"
  assert_line "GRAPHQL update ITEM_I_7 OPT_TRIAGE as inst-22"
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

@test "an edit that does not name the field changes nothing (issue 111)" {
  # Linking a pull request edits the card without naming a field: applying the
  # card's column then would turn a stale column back into labels.
  item "Ready for agent" OPEN '["done"]'
  moved_card User '{}'
  deliver
  assert_success
  refute_line --partial "PATCH"
  refute_line --partial "GRAPHQL item"
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
  moved_card Bot "" "board-app[bot]"
  deliver
  assert_success
  assert_line --partial "=> 202"
  refute_line --partial "GRAPHQL"
  # Another bot's move is a move like any other.
  moved_card Bot "" "other-app[bot]"
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

@test "a GET answers the commit the Worker was deployed from, and nothing else" {
  # A stale deploy is then a one-line check (issue 132).
  VARS='{"VERSION":"0123456789abcdef0123456789abcdef01234567"}' METHOD=GET deliver
  assert_line "=> 200 0123456789abcdef0123456789abcdef01234567"
  refute_line --partial "TOKEN"
  # Deployed without --var VERSION.
  METHOD=GET deliver
  assert_line "=> 200 unknown"
}

@test "only POSTs are handled; a ping and other events are acknowledged" {
  METHOD=PUT deliver
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

# --- scheduled reconcile --------------------------------------------------------

# card ID STAGE STATE LABELS_JSON [EXTRA_JSON]: one card of BOARD_ITEMS, its
# issue I_<ID> number <ID> of owner/repo; EXTRA_JSON is merged over the card.
card() {
  jq -nc --arg id "$1" --arg stage "$2" --arg state "$3" --argjson labels "$4" --argjson extra "${5:-{\}}" '{
    id: ("PVTI_" + $id), stage: (if $stage == "" then null else $stage end),
    content: {id: ("I_" + $id), number: ($id | tonumber), state: $state, labels: $labels, repo: "owner/repo"}} * $extra'
}

reconcile() {
  MODE=scheduled run node "$DIR/project-board-harness.mjs" "$BOARD"
}

@test "the scheduled reconcile puts drifted cards back in the column of their labels, closed issues included" {
  BOARD_ITEMS=$(jq -sc . <<<"$(card 1 "Needs triage" OPEN '["ready-for-agent","urgent"]')
$(card 2 "Ready for agent" CLOSED '["ready-for-agent"]')
$(card 3 "Needs info" OPEN '["needs-info"]')
$(card 4 "" OPEN '[]')")
  export BOARD_ITEMS
  reconcile
  assert_success
  # Every page of the board is read, with the organization's token.
  assert_line "GRAPHQL items labs/1 after - as inst-22"
  assert_line "GRAPHQL items labs/1 after 2 as inst-22"
  assert_line "GRAPHQL update PVTI_1 OPT_AGENT as inst-22"
  assert_line "GRAPHQL update PVTI_2 OPT_DONE as inst-22"
  # A card with no column yet gets the one of its labels.
  assert_line "GRAPHQL update PVTI_4 OPT_TRIAGE as inst-22"
  # Labels win: no issue is written.
  refute_line --partial "PATCH"
  # A card in step costs no write.
  refute_line --partial "add I_3"
  assert_line "reconcile: 4 cards read, 3 moved (owner/repo#1 → Ready for agent, owner/repo#2 → Done, owner/repo#4 → Needs triage)"
}

@test "the reconcile leaves alone drafts, pull requests, archived cards, other owners and cards just edited" {
  local recent
  recent=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  BOARD_ITEMS=$(jq -sc . <<<"$(card 1 "Done" OPEN '[]' '{"type":"DRAFT_ISSUE","content":null}')
$(card 2 "Done" OPEN '[]' '{"type":"PULL_REQUEST"}')
$(card 3 "Done" OPEN '[]' '{"isArchived":true}')
$(card 4 "Done" OPEN '[]' '{"content":{"repo":"stranger/repo"}}')
$(card 5 "Done" OPEN '[]' "{\"updatedAt\":\"$recent\"}")")
  export BOARD_ITEMS
  reconcile
  assert_success
  # A card edited minutes ago may be a drag whose label change is still on its
  # way: putting it back would undo it.
  refute_line --partial "GRAPHQL add"
  refute_line --partial "GRAPHQL update"
  assert_line "reconcile: 5 cards read, 0 moved"
}

@test "a card the App cannot see is reconciled through BOARD_TOKEN" {
  BOARD_ITEMS=$(jq -sc . <<<"$(card 1 "Needs triage" OPEN '["ready-for-human"]' '{"hidden":true}')")
  export BOARD_ITEMS
  reconcile
  assert_success
  assert_line "GRAPHQL items labs/1 after - as board-pat"
  assert_line "GRAPHQL update PVTI_1 OPT_HUMAN as board-pat"
  # Without BOARD_TOKEN, the card is counted, and named as out of reach.
  VARS='{"BOARD_TOKEN":""}' reconcile
  assert_success
  refute_line --partial "GRAPHQL update"
  assert_line --partial "1 card hidden from the App: set BOARD_TOKEN"
}

@test "the reconcile moves a bounded number of cards a run, the rest on the next one" {
  # A Worker invocation has a budget of subrequests: each move costs three.
  local cards="" n
  for n in $(seq 1 12); do cards+="$(card "$n" "Needs info" OPEN '[]')"$'\n'; done
  BOARD_ITEMS=$(jq -sc . <<<"$cards")
  export BOARD_ITEMS
  reconcile
  assert_success
  run grep -c "GRAPHQL update" <<<"$output"
  assert_output 10
  reconcile
  assert_line --partial "2 left for the next run"
}

# --- failed deliveries report ---------------------------------------------------

# delivery MINUTES_AGO EVENT ACTION STATUS: one of the App's webhook deliveries.
delivery() {
  jq -nc --argjson ago "$1" --arg event "$2" --arg action "$3" --argjson status "$4" '{
    id: 1, guid: "g", delivered_at: (now - $ago * 60 | floor | todate), redelivery: false,
    event: $event, action: $action, status_code: $status, status: "x", repository_id: 99}'
}

report_vars='{"REPORT_REPOSITORY":"owner/dotfiles"}'

# report NUMBER STATE [MINUTES_AGO]: a report issue of the App, which reported
# the deliveries up to MINUTES_AGO (none: an issue from before the marker).
report() {
  jq -nc --argjson number "$1" --arg state "$2" --arg ago "${3:-}" '{
    number: $number, state: $state, title: "Failed deliveries of the board Worker",
    body: ("| a table |" + (if $ago == "" then "" else
      "\n\n<!-- reported-until: \(now - ($ago | tonumber) * 60 | floor | todate) -->" end))}'
}

@test "no failed delivery in the last hour and no report yet, no write" {
  # Without a report to start from, the window is the schedule's period.
  DELIVERIES=$(jq -sc . <<<"$(delivery 5 issues labeled 200)
$(delivery 6 projects_v2_item edited 202)
$(delivery 75 issues labeled 500)")
  export DELIVERIES
  VARS="$report_vars" reconcile
  assert_success
  assert_line "DELIVERIES ?per_page=100 as the App"
  assert_line --regexp '^deliveries: 0 failed since [0-9T:.-]+Z$'
  refute_line --partial "POST /repos/owner/dotfiles"
  refute_line --partial "PATCH /repos/owner/dotfiles"
}

@test "a page without a failure is not compared with the last report" {
  DELIVERIES=$(jq -sc . <<<"$(delivery 5 issues labeled 200)")
  export DELIVERIES
  VARS="$report_vars" reconcile
  assert_success
  assert_line "deliveries: 0 failed"
  refute_line --partial "LIST /repos/owner/dotfiles/issues"
}

@test "the failures of a run that did not happen are reported by the next one" {
  # The last report stopped three hours ago: the run of the hour between was
  # skipped. What that report already held is not listed again.
  DELIVERIES=$(jq -sc . <<<"$(delivery 5 issues closed 500)
$(delivery 90 issues labeled 502)
$(delivery 200 issues opened 503)")
  REPORT_ISSUES=$(jq -sc . <<<"$(report 42 open 180)")
  export DELIVERIES REPORT_ISSUES
  VARS="$report_vars" reconcile
  assert_success
  local comment
  comment=$(grep '^POST /repos/owner/dotfiles/issues/42/comments ' <<<"$output")
  [[ "$comment" == *"| issues | closed | 500 |"* && "$comment" == *"| issues | labeled | 502 |"* ]] || fail "a failure since the last report is missing: $comment"
  [[ "$comment" != *"503"* ]] || fail "a failure of the last report is listed again"
  assert_line --partial "deliveries: 2 failed since "
}

@test "a report moves the start of the next one, in the issue itself" {
  DELIVERIES=$(jq -sc . <<<"$(delivery 5 issues closed 500)")
  REPORT_ISSUES=$(jq -sc . <<<"$(report 42 open 180)")
  export DELIVERIES REPORT_ISSUES
  VARS="$report_vars" reconcile
  assert_success
  local log="$output" patch body until
  patch=$(grep '^PATCH /repos/owner/dotfiles/issues/42 ' <<<"$log")
  [ -n "$patch" ] || fail "the report's issue was not updated"
  body=${patch#PATCH /repos/owner/dotfiles/issues/42 }
  body=$(jq -r '.body' <<<"${body% as inst-11}")
  # The table stays, one marker only, moved to this run.
  [[ "$body" == "| a table |"* ]] || fail "the report's text was lost: $body"
  run grep -c 'reported-until' <<<"$body"
  assert_output 1
  until=$(sed -n 's/.*<!-- reported-until: \(.*\) -->.*/\1/p' <<<"$body")
  run jq -n --arg until "$until" '(now - ($until | sub("\\.[0-9]+Z$"; "Z") | fromdate)) < 60'
  assert_output true
  # The comment first: a marker that could not be written repeats a report,
  # it never hides one.
  local commented patched
  commented=$(grep -n '^POST /repos/owner/dotfiles/issues/42/comments ' <<<"$log" | cut -d: -f1)
  patched=$(grep -n '^PATCH /repos/owner/dotfiles/issues/42 ' <<<"$log" | cut -d: -f1)
  [ "$commented" -lt "$patched" ]
}

@test "a failure already reported is not reported again" {
  # The hourly run after a report: the same failure is still in the hour.
  DELIVERIES=$(jq -sc . <<<"$(delivery 30 issues closed 500)")
  REPORT_ISSUES=$(jq -sc . <<<"$(report 42 open 10)")
  export DELIVERIES REPORT_ISSUES
  VARS="$report_vars" reconcile
  assert_success
  refute_line --partial "POST /repos/owner/dotfiles"
  refute_line --partial "PATCH /repos/owner/dotfiles"
}

@test "a closed report still gives the start, and the next failure opens a new one" {
  DELIVERIES=$(jq -sc . <<<"$(delivery 90 issues closed 500)
$(delivery 200 issues opened 503)")
  REPORT_ISSUES=$(jq -sc . <<<"$(report 42 closed 180)")
  export DELIVERIES REPORT_ISSUES
  VARS="$report_vars" reconcile
  assert_success
  refute_line --partial "issues/42"
  local post
  post=$(grep '^POST /repos/owner/dotfiles/issues {' <<<"$output")
  [[ "$post" == *"| issues | closed | 500 |"* ]] || fail "no new report: $post"
  [[ "$post" != *"503"* ]] || fail "a failure of the closed report is listed again"
  [[ "$post" == *"<!-- reported-until: "* ]] || fail "the new report holds no marker"
}

@test "a report from before the marker starts the window an hour back" {
  DELIVERIES=$(jq -sc . <<<"$(delivery 5 issues closed 500)
$(delivery 90 issues opened 503)")
  REPORT_ISSUES=$(jq -sc . <<<"$(report 42 open)")
  export DELIVERIES REPORT_ISSUES
  VARS="$report_vars" reconcile
  assert_success
  assert_line --regexp '^POST /repos/owner/dotfiles/issues/42/comments .*\| issues \| closed \| 500 \|.* as inst-11$'
  refute_output --partial "503"
  assert_line --regexp '^PATCH /repos/owner/dotfiles/issues/42 .*reported-until'
}

@test "a first failed delivery opens an issue that names no repository" {
  DELIVERIES=$(jq -sc . <<<"$(delivery 5 issues labeled 500)
$(delivery 9 projects_v2_item edited 401)
$(delivery 12 issues opened 200)")
  export DELIVERIES
  VARS="$report_vars" reconcile
  assert_success
  assert_line "LIST /repos/owner/dotfiles/issues by board-app[bot] as inst-11"
  assert_line --regexp '^deliveries: 2 failed since [0-9T:.-]+Z, reported in owner/dotfiles$'
  local post
  post=$(grep '^POST /repos/owner/dotfiles/issues ' <<<"$output")
  [ -n "$post" ] || fail "no issue opened"
  local body=${post#POST /repos/owner/dotfiles/issues }
  body=${body% as inst-11}
  run jq -r '.title' <<<"$body"
  assert_output "Failed deliveries of the board Worker"
  run jq -r '.labels | join(",")' <<<"$body"
  assert_output "needs-triage"
  run jq -r '.body' <<<"$body"
  assert_line --regexp '^\| [0-9T:-]+Z \| issues \| labeled \| 500 \|$'
  assert_line --regexp '^\| [0-9T:-]+Z \| projects_v2_item \| edited \| 401 \|$'
  refute_output --partial "opened"
  # Public: the deliveries' repository ids or names never reach it.
  refute_output --partial "99"
  refute_output --partial "owner/"
}

@test "a later failure is added to the report still open" {
  DELIVERIES=$(jq -sc . <<<"$(delivery 5 issues closed 500)")
  REPORT_ISSUES=$(jq -sc . <<<"$(report 43 open | jq -c '.title = "Something else"')
$(report 42 open 180)
$(report 41 closed 400)")
  export DELIVERIES REPORT_ISSUES
  VARS="$report_vars" reconcile
  assert_success
  assert_line --regexp '^POST /repos/owner/dotfiles/issues/42/comments .*\| issues \| closed \| 500 \|.* as inst-11$'
  refute_line --regexp '^POST /repos/owner/dotfiles/issues \{'
}

@test "a full page of deliveries says the report may be cut only when it reaches back to its start" {
  # GitHub keeps days of deliveries: a full page is the usual case.
  local cards="" n
  cards="$(delivery 5 issues labeled 500)"$'\n'
  for n in $(seq 1 99); do cards+="$(delivery $((60 + n)) issues labeled 200)"$'\n'; done
  DELIVERIES=$(jq -sc . <<<"$cards")
  export DELIVERIES
  VARS="$report_vars" reconcile
  assert_success
  refute_output --partial "the earliest ones are missing"
  cards="$(delivery 5 issues labeled 500)"$'\n'
  for n in $(seq 1 99); do cards+="$(delivery 30 issues labeled 200)"$'\n'; done
  DELIVERIES=$(jq -sc . <<<"$cards")
  VARS="$report_vars" reconcile
  assert_output --partial "the earliest ones are missing"
}

@test "without REPORT_REPOSITORY the deliveries are not read" {
  DELIVERIES=$(jq -sc . <<<"$(delivery 5 issues labeled 500)")
  export DELIVERIES
  reconcile
  assert_success
  refute_line --partial "DELIVERIES"
  assert_line "deliveries: REPORT_REPOSITORY is not set, not checked"
}

@test "the Worker's config names the board, and holds no secret" {
  local toml="$BOARD/wrangler.toml"
  run grep -E '^main = "worker.mjs"$' "$toml"
  assert_success
  run grep -E '^(PROJECT_OWNER|PROJECT_NUMBER|REPOSITORY_OWNERS|REPORT_REPOSITORY) = ' "$toml"
  assert_equal "${#lines[@]}" 4
  run grep -E '^[[:space:]]*(WEBHOOK_SECRET|GITHUB_APP_ID|GITHUB_APP_PRIVATE_KEY|BOARD_TOKEN|GITHUB_TOKEN)[[:space:]]*=' "$toml"
  assert_failure
}
