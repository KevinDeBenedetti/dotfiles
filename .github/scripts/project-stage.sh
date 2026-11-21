#!/usr/bin/env bash
# Mirror the triage label of an issue into the Stage field of the repository's
# GitHub Project, so its board shows one column per label
# (docs/config/issue-workflow.md#project-board). The item is added to the
# project first: a new issue lands on the board without a manual step.
#
# Run by .github/workflows/project-stage.yml. Env:
#   PROJECT_OWNER   login of the user owning the project
#   PROJECT_NUMBER  the project's number (its URL ends with it)
#   ISSUE_ID        node id of the issue; empty: sync every open issue
#   ISSUE_STATE     OPEN or CLOSED (with ISSUE_ID)
#   LABELS          JSON array of the issue's label names (with ISSUE_ID)
# gh reads its token from GH_TOKEN: a classic PAT with the `project` scope,
# since GITHUB_TOKEN and GitHub Apps cannot write to a user-owned project.
set -euo pipefail

# stage_for LABELS_JSON STATE: the Stage column of an issue. When several
# triage labels are set, the one that stops the work wins.
stage_for() {
  local labels="$1" state="$2"
  jq -r --arg state "$state" '
    if index("wontfix") then "Won'"'"'t fix"
    elif $state == "CLOSED" then "Done"
    elif index("needs-info") then "Needs info"
    elif index("ready-for-human") then "Ready for human"
    elif index("ready-for-agent") then "Ready for agent"
    else "Needs triage" end' <<<"$labels"
}

fail() {
  echo "::error::$*"
  exit 1
}

# IDs go through -f (always a string); -F would turn an all-digit option ID
# into a number. The project number is an Int, so it takes -F.

# load_project: PROJECT_ID, FIELD_ID and OPTIONS (JSON array of {id,name}).
load_project() {
  local project
  # shellcheck disable=SC2016 # GraphQL variables, not shell ones.
  project=$(gh api graphql -F owner="$PROJECT_OWNER" -F number="$PROJECT_NUMBER" -f query='
    query($owner: String!, $number: Int!) {
      user(login: $owner) {
        projectV2(number: $number) {
          id
          field(name: "Stage") { ... on ProjectV2SingleSelectField { id options { id name } } }
        }
      }
    }' --jq '.data.user.projectV2')
  PROJECT_ID=$(jq -r '.id // empty' <<<"$project")
  FIELD_ID=$(jq -r '.field.id // empty' <<<"$project")
  OPTIONS=$(jq -c '.field.options // []' <<<"$project")
  [[ -n "$PROJECT_ID" ]] || fail "Project $PROJECT_NUMBER of $PROJECT_OWNER not found, or the token cannot read it"
  [[ -n "$FIELD_ID" ]] || fail "Project $PROJECT_NUMBER of $PROJECT_OWNER has no single-select field named Stage"
}

# sync_issue ID STATE LABELS_JSON
sync_issue() {
  local issue="$1" stage option item
  stage=$(stage_for "$3" "$2")
  # Matched without regard to case or surrounding spaces: "Needs Triage" typed
  # in the project's UI is the same column.
  option=$(jq -r --arg s "$stage" \
    'first(.[] | select((.name | ascii_downcase | gsub("^\\s+|\\s+$"; "")) == ($s | ascii_downcase)) | .id) // empty' \
    <<<"$OPTIONS")
  [[ -n "$option" ]] || fail "The Stage field of project $PROJECT_NUMBER has no '$stage' option ($(jq -r \
    'if length == 0 then "it has no options yet" else "it has: " + (map("'"'"'\(.name)'"'"'") | join(", ")) end' <<<"$OPTIONS"))"
  # Adding an issue already on the board returns its existing item.
  # shellcheck disable=SC2016
  item=$(gh api graphql -f projectId="$PROJECT_ID" -f contentId="$issue" -f query='
    mutation($projectId: ID!, $contentId: ID!) {
      addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) { item { id } }
    }' --jq '.data.addProjectV2ItemById.item.id')
  # shellcheck disable=SC2016
  gh api graphql -f projectId="$PROJECT_ID" -f itemId="$item" -f fieldId="$FIELD_ID" -f optionId="$option" -f query='
    mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
      updateProjectV2ItemFieldValue(input: {projectId: $projectId, itemId: $itemId, fieldId: $fieldId,
        value: {singleSelectOptionId: $optionId}}) { projectV2Item { id } }
    }' >/dev/null
  echo "$issue → $stage"
}

main() {
  [[ -n "${PROJECT_OWNER:-}" ]] || fail "PROJECT_OWNER is not set"
  [[ -n "${PROJECT_NUMBER:-}" ]] || fail "PROJECT_NUMBER is not set (repository variable)"
  [[ "$PROJECT_NUMBER" =~ ^[0-9]+$ ]] || fail "PROJECT_NUMBER must be a number, not '$PROJECT_NUMBER'"
  [[ -n "${GH_TOKEN:-}" ]] || fail "GH_TOKEN is empty: set the PROJECT_TOKEN secret (classic token, project scope)"
  load_project
  if [[ -n "${ISSUE_ID:-}" ]]; then
    sync_issue "$ISSUE_ID" "${ISSUE_STATE:-OPEN}" "${LABELS:-[]}"
    return
  fi
  local issue
  while IFS= read -r issue; do
    sync_issue "$(jq -r .id <<<"$issue")" "$(jq -r .state <<<"$issue")" "$(jq -c .labels <<<"$issue")"
  done < <(gh issue list --state open --limit 1000 --json id,state,labels \
    --jq '[.[] | {id, state, labels: [.labels[].name]}]' | jq -c '.[]')
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
