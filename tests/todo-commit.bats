#!/usr/bin/env bats

# Unit tests for scripts/todo-commit.sh
# Covers the `message` and `strip` subcommands (the pure, offline logic).

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  SCRIPT="$REPO_ROOT/scripts/todo-commit.sh"
  TODO="$BATS_TEST_TMPDIR/TODO.md"

  # Keep the suite deterministic and offline: never call the `claude` CLI.
  # The `hook` tests thus exercise the deterministic fallback path.
  export TODO_COMMIT_NO_AI=1
}

make_todo() {
  cat > "$TODO" <<'EOF'
# TODO

## 🔴 En cours

## 🟡 À faire
- [ ] feat: something still pending

## 🟢 Idées / backlog

## 🤖 Claude — recommandations

## ✅ Fait
- [x] 2026-06-17 — FIX: Fix the thing — with an em-dash detail
- [x] 2026-06-16 — FEAT: Add a feature
EOF
}

# --- message ---

@test "message: single entry produces a conventional header, no body" {
  cat > "$TODO" <<'EOF'
## ✅ Fait
- [x] 2026-06-17 — FEAT: Add docker compose aliases
EOF
  run "$SCRIPT" message "$TODO"
  assert_success
  assert_output "feat: Add docker compose aliases"
}

@test "message: multiple entries produce header plus a bullet body" {
  make_todo
  run "$SCRIPT" message "$TODO"
  assert_success
  assert_line --index 0 "fix: Fix the thing — with an em-dash detail"
  assert_line "- fix: Fix the thing — with an em-dash detail"
  assert_line "- feat: Add a feature"
}

@test "message: strips the (URGENT) marker from the type" {
  cat > "$TODO" <<'EOF'
## ✅ Fait
- [x] 2026-06-16 — FEAT(URGENT): Critical thing
EOF
  run "$SCRIPT" message "$TODO"
  assert_success
  assert_output "feat: Critical thing"
}

@test "message: no Fait entries exits non-zero" {
  cat > "$TODO" <<'EOF'
## ✅ Fait

## 🟡 À faire
- [ ] feat: not done yet
EOF
  run "$SCRIPT" message "$TODO"
  assert_failure
}

# --- ai (claude -p) ---

@test "ai: disabled via TODO_COMMIT_NO_AI exits non-zero (forces fallback)" {
  cat > "$TODO" <<'EOF'
## ✅ Fait
- [x] 2026-06-17 — FEAT: A thing
EOF
  run "$SCRIPT" ai "$TODO"
  assert_failure
}

# --- strip ---

@test "strip: removes done entries but keeps heading and other sections" {
  make_todo
  run "$SCRIPT" strip "$TODO"
  assert_success

  run cat "$TODO"
  assert_line "## ✅ Fait"
  assert_line "## 🟡 À faire"
  assert_line "- [ ] feat: something still pending"
  refute_line --partial "Fix the thing"
  refute_line --partial "Add a feature"
}

@test "strip: leaves a Fait section that is already empty untouched" {
  cat > "$TODO" <<'EOF'
## ✅ Fait
EOF
  run "$SCRIPT" strip "$TODO"
  assert_success
  run cat "$TODO"
  assert_output "## ✅ Fait"
}

# --- hook (prepare-commit-msg) ---

# Build a throwaway git repo with a staged TODO.md and a COMMIT_EDITMSG.
# Echoes "<repo>|<msgfile>". (git init/add only — no commit, which is blocked.)
setup_hook_repo() {
  local repo="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  cat > "$repo/TODO.md" <<'EOF'
# TODO

## ✅ Fait
- [x] 2026-06-17 — FEAT: Do a thing
EOF
  git -C "$repo" add TODO.md
  printf '%s' "$repo"
}

@test "hook: full commit pre-fills the message and strips the Fait entries" {
  repo="$(setup_hook_repo repo-full)"
  msg="$repo/.git/COMMIT_EDITMSG"
  printf '\n# git template comment\n' > "$msg"

  run env -u GIT_INDEX_FILE bash -c "cd '$repo' && '$SCRIPT' hook '$msg' '' ''"
  assert_success

  run head -n1 "$msg"
  assert_output "feat: Do a thing"

  run grep -c '^- \[x\]' "$repo/TODO.md"
  assert_output "0"
}

@test "hook: partial commit (temporary index) is a no-op" {
  repo="$(setup_hook_repo repo-partial)"
  msg="$repo/.git/COMMIT_EDITMSG"
  printf 'original message\n# comment\n' > "$msg"

  run bash -c "cd '$repo' && GIT_INDEX_FILE='$repo/.git/next-index-999' '$SCRIPT' hook '$msg' '' ''"
  assert_success

  run head -n1 "$msg"          # message untouched
  assert_output "original message"

  run grep -c '^- \[x\]' "$repo/TODO.md"   # Fait entry still present
  assert_output "1"
}

@test "hook: pre-existing message (content, empty source) is a no-op" {
  repo="$(setup_hook_repo repo-content)"
  msg="$repo/.git/COMMIT_EDITMSG"
  # message already present (e.g. prek didn't forward source for a -m commit)
  printf 'fix: already written\n# comment\n' > "$msg"

  run env -u GIT_INDEX_FILE bash -c "cd '$repo' && '$SCRIPT' hook '$msg' '' ''"
  assert_success

  run head -n1 "$msg"
  assert_output "fix: already written"

  run grep -c '^- \[x\]' "$repo/TODO.md"
  assert_output "1"
}

@test "hook: -m commit (non-empty source) is a no-op" {
  repo="$(setup_hook_repo repo-m)"
  msg="$repo/.git/COMMIT_EDITMSG"
  printf 'user message via -m\n' > "$msg"

  run env -u GIT_INDEX_FILE bash -c "cd '$repo' && '$SCRIPT' hook '$msg' 'message' ''"
  assert_success

  run cat "$msg"
  assert_output "user message via -m"

  run grep -c '^- \[x\]' "$repo/TODO.md"
  assert_output "1"
}

# --- usage ---

@test "unknown subcommand exits 2 with usage" {
  run "$SCRIPT" bogus
  assert_failure 2
  assert_output --partial "usage:"
}
