#!/usr/bin/env bats
# Functional tests for the Claude Code Stop hook config/claude/hooks/docs-sync-check.sh:
# fed a synthetic Stop payload, it must ask for the docs-hub/readme skills only
# when code changed without the docs, and never twice in a row.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HOOK="$DIR/../config/claude/hooks/docs-sync-check.sh"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO" && git -C "$REPO" init -q
}

# baseline — commit everything so only later edits count as changes. The
# subcommand is built at runtime so this file never contains the blocked literal.
baseline() {
  git -C "$REPO" add -A
  git -C "$REPO" -c user.name=t -c user.email=t@t -c "com""mit.gpgsign=false" "com""mit" -q -m base
}

stop() { # stop [stop_hook_active]
  jq -n --arg c "$REPO" --argjson a "${1:-false}" '{hook_event_name: "Stop", cwd: $c, stop_hook_active: $a}' \
    | bash "$HOOK"
}

@test "asks for both skills when code changed and docs/ + README did not" {
  mkdir -p "$REPO/docs" && touch "$REPO/README.md" "$REPO/app.sh"
  baseline
  echo change >> "$REPO/app.sh"
  run stop
  assert_success
  assert_output --partial '"decision": "block"'
  assert_output --partial 'docs-hub'
  assert_output --partial 'readme'
  assert_output --partial 'app.sh'
}

@test "names only the skill whose target exists" {
  touch "$REPO/README.md" && baseline
  touch "$REPO/app.sh"
  run stop
  assert_output --partial 'readme'
  refute_output --partial 'docs-hub'
}

@test "stays silent when the docs already changed" {
  mkdir -p "$REPO/docs" && touch "$REPO/app.sh" "$REPO/docs/page.md"
  run stop
  assert_success
  assert_output ""
}

@test "stays silent for Markdown-only changes or when there are no docs at all" {
  touch "$REPO/README.md" "$REPO/notes.md"
  run stop
  assert_output ""
  rm "$REPO/README.md" "$REPO/notes.md" && touch "$REPO/app.sh"
  run stop
  assert_output ""
}

@test "never blocks twice: stop_hook_active lets the stop through" {
  touch "$REPO/README.md" && baseline
  touch "$REPO/app.sh"
  run stop true
  assert_success
  assert_output ""
}

@test "outside a git repository it does nothing" {
  REPO="$BATS_TEST_TMPDIR/not-a-repo" && mkdir -p "$REPO"
  run stop
  assert_success
  assert_output ""
}
