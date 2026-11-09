#!/usr/bin/env bats
# Functional tests for the Claude Code Stop hook config/claude/hooks/next-steps.sh:
# fed a synthetic Stop payload, it must show the owner the open manual steps of
# TODO.md and the next actions read from the repository, as a systemMessage
# that never blocks the stop, once per session until the message changes.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  HOOK="$DIR/../config/claude/hooks/next-steps.sh"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  unset DOTFILES_NEXT_STEPS DOTFILES_NEXT_STEPS_MANUAL
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO" && git -C "$REPO" init -q -b main
}

# The subcommand is built at runtime so this file never contains the blocked literal.
save() { # save <repo> — record everything as one revision
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@t -c "com""mit.gpgsign=false" "com""mit" -q -m snapshot
}

stop() { # stop [session] — run the hook, print only its message
  jq -n --arg c "$REPO" --arg s "${1:-s1}" '{hook_event_name: "Stop", cwd: $c, session_id: $s, stop_hook_active: false}' \
    | bash "$HOOK"
}

english_todo() {
  cat >"$REPO/TODO.md" <<'EOF'
# TODO

## 🔴 In progress
- [ ] FIX: retry uploads on 503 (src/upload.ts) — BLOCKED 2026-11-08: a decision on the retry budget.

## 🟡 To do
- [ ] DOCS: document the upload limits
- [ ] FIX(URGENT): stop logging session tokens (src/log.ts)

## 🖐 Manual — do it yourself, in order
### 1. Today
- [ ] 1.1 Run the Docker-backed tests: `make test` — Success: `0 failed`.
- [x] 1.0 Rotate the deploy key — done.
- [ ] 1.2 Enable the Dependency graph in the repository settings — Success: the review job passes.

## 🟢 Ideas / backlog
- [ ] FEAT: offline mode

## 🤖 Agent recommendations
- [ ] TEST: cover the 413 path (src/upload.ts) — no test reaches it.

## 🔒 Security audit
- [ ] FIX: [LOW] pin the base image (Dockerfile:1) — floating tag.

## ✅ Done
- [x] 2026-11-08 — FIX: refresh tokens — tests green.
EOF
}

@test "lists the open manual steps, blocked work, the next task and what awaits triage" {
  english_todo
  run stop
  assert_success
  run jq -r '.systemMessage' <<<"$output"
  assert_output --partial '🖐 Manual steps (2 open steps):'
  assert_output --partial '1.1 Run the Docker-backed tests'
  assert_output --partial '1.2 Enable the Dependency graph'
  refute_output --partial 'Rotate the deploy key'
  assert_output --partial 'Blocked — a decision on the retry budget → FIX: retry uploads on 503'
  # (URGENT) wins over the top-most task, and a blocked task is never next.
  assert_output --partial 'Next task (2 open tasks): /next-task → FIX(URGENT): stop logging session tokens'
  assert_output --partial 'Triage: 1 recommendation, 1 security finding'
  refute_output --partial 'offline mode'
}

@test "reads a TODO.md still in the former French layout" {
  cat >"$REPO/TODO.md" <<'EOF'
# TODO

## 🔴 En cours

## 🟡 À faire
- [ ] FEAT: export CSV

## 🟡 À faire (manuellement, étapes détaillées pas à pas)
- [ ] Créer le secret dans Vault — Succès : `vault kv get` répond.

## 🤖 Claude — recommandations
- [ ] CHORE: supprimer le code mort

## ✅ Fait
EOF
  run stop
  run jq -r '.systemMessage' <<<"$output"
  assert_output --partial '🖐 Manual steps (1 open step):'
  assert_output --partial 'Créer le secret dans Vault'
  assert_output --partial '/next-task → FEAT: export CSV'
  assert_output --partial 'Triage: 1 recommendation, 0 security findings'
}

@test "resumes in-progress work before starting the next task" {
  printf '# TODO\n\n## 🔴 In progress\n- [ ] FEAT: half-done export\n\n## 🟡 To do\n- [ ] FEAT: import\n' >"$REPO/TODO.md"
  run stop
  run jq -r '.systemMessage' <<<"$output"
  assert_output --partial 'Resume: /next-task → FEAT: half-done export'
  refute_output --partial 'FEAT: import'
}

@test "suggests re-staging, committing and pushing from the repository state" {
  touch "$REPO/a.sh" && save "$REPO"
  git clone -q "$REPO" "$BATS_TEST_TMPDIR/clone"
  REPO="$BATS_TEST_TMPDIR/clone"
  echo one >"$REPO/a.sh" && save "$REPO"
  echo two >"$REPO/a.sh" && git -C "$REPO" add a.sh
  echo three >>"$REPO/a.sh"
  touch "$REPO/new.sh"
  run stop
  run jq -r '.systemMessage' <<<"$output"
  assert_output --partial 'Re-stage what changed after git add: git add a.sh'
  assert_output --partial 'Commit: 1 file staged, 2 more not staged'
  assert_output --partial 'Push: 1 commit not pushed yet'
}

@test "never blocks the stop: the output is a systemMessage only" {
  english_todo
  run stop
  assert_success
  run jq -c 'keys' <<<"$output"
  assert_output '["systemMessage"]'
}

@test "shows a message once per session, and again when it changes" {
  english_todo
  run stop s1
  assert_output --partial 'systemMessage'
  run stop s1
  assert_output ""
  run stop s2
  assert_output --partial 'systemMessage'
  awk '{ print } /^- \[ \] 1\.2 / { print "- [ ] 1.3 Push the tag — Success: the release exists." }' \
    "$REPO/TODO.md" >"$REPO/TODO.new" && mv "$REPO/TODO.new" "$REPO/TODO.md"
  run stop s1
  assert_output --partial '1.3 Push the tag'
  DOTFILES_NEXT_STEPS=always run stop s1
  assert_output --partial 'systemMessage'
}

@test "caps the manual steps listed, and lists them all with 0" {
  { echo '## 🖐 Manual — do it yourself, in order'; for n in 1 2 3 4 5; do echo "- [ ] 1.$n step $n"; done; } >"$REPO/TODO.md"
  DOTFILES_NEXT_STEPS_MANUAL=2 run stop
  run jq -r '.systemMessage' <<<"$output"
  assert_output --partial 'step 2'
  refute_output --partial 'step 3'
  assert_output --partial '… 3 more in TODO.md'
  DOTFILES_NEXT_STEPS_MANUAL=0 run stop s2
  run jq -r '.systemMessage' <<<"$output"
  assert_output --partial 'step 5'
}

@test "cuts long lines without breaking multibyte characters" {
  printf '## 🖐 Manual\n- [ ] 1.1 %s\n' "$(printf 'é%.0s' $(seq 1 200))" >"$REPO/TODO.md"
  run stop
  assert_success
  run jq -r '.systemMessage | split("\n") | map(length) | max' <<<"$output"
  [ "$output" -le 110 ]
}

@test "stays silent with nothing to do, outside git, or when turned off" {
  touch "$REPO/a.sh" && save "$REPO"
  run stop
  assert_success
  assert_output ""
  english_todo
  DOTFILES_NEXT_STEPS=off run stop s2
  assert_output ""
  REPO="$BATS_TEST_TMPDIR/not-a-repo" && mkdir -p "$REPO"
  run stop s3
  assert_success
  assert_output ""
}
