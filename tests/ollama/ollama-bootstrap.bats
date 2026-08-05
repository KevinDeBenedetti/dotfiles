#!/usr/bin/env bats
# Functional tests for scripts/ollama/ollama-bootstrap.
#
# `ollama` and `curl` are stubbed by shell scripts placed first on PATH, so no
# model is ever pulled and no network call is made. The script under test is
# copied into a throwaway tree mirroring the repo layout, because it resolves
# config/ollama/ relative to its own location.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/../.." && pwd)"

  load "$REPO_ROOT/tests/test_helper/bats-support/load"
  load "$REPO_ROOT/tests/test_helper/bats-assert/load"

  # Throwaway tree: <tmp>/scripts/ollama/ + <tmp>/config/ollama/
  TREE="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$TREE/scripts/ollama" "$TREE/config/ollama/modelfiles"
  cp "$REPO_ROOT/scripts/ollama/ollama-bootstrap" "$TREE/scripts/ollama/"
  chmod +x "$TREE/scripts/ollama/ollama-bootstrap"
  SCRIPT="$TREE/scripts/ollama/ollama-bootstrap"

  cat > "$TREE/config/ollama/models.txt" <<'EOF'
# a comment line
alpha:9b            # trailing comment

beta:4b
EOF

  # Stubs first on PATH. OLLAMA_LOG records every ollama invocation, so a test
  # can assert that nothing was pulled.
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  export OLLAMA_LOG="$BATS_TEST_TMPDIR/ollama.log"
  : > "$OLLAMA_LOG"

  cat > "$BIN/ollama" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$OLLAMA_LOG"
[ "${OLLAMA_STUB_FAIL:-0}" = "1" ] && exit 1
exit 0
EOF

  # Answers /api/version according to DAEMON_UP.
  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
[ "${DAEMON_UP:-1}" = "1" ] || exit 7
printf '{"version":"0.32.5"}'
EOF

  chmod +x "$BIN/ollama" "$BIN/curl"
  export PATH="$BIN:$PATH"
  export DAEMON_UP=1
}

@test "ollama-bootstrap --help prints usage and pulls nothing" {
  run bash "$SCRIPT" --help
  assert_success
  assert_output --partial "Usage: ollama-bootstrap"
  assert_equal "$(wc -l < "$OLLAMA_LOG" | tr -d ' ')" "0"
}

@test "ollama-bootstrap rejects an unknown argument" {
  run bash "$SCRIPT" --nope
  assert_failure
  assert_output --partial "unknown argument"
}

@test "ollama-bootstrap --dry-run lists the models without downloading" {
  run bash "$SCRIPT" --dry-run
  assert_success
  assert_output --partial "would pull  alpha:9b"
  assert_output --partial "would pull  beta:4b"
  assert_output --partial "nothing downloaded"
  # The whole point of the flag: ollama must never have been invoked.
  assert_equal "$(wc -l < "$OLLAMA_LOG" | tr -d ' ')" "0"
}

@test "ollama-bootstrap skips comments and blank lines" {
  # A '# a comment line' entry reaching `ollama pull` would be a parsing bug.
  run bash "$SCRIPT" --dry-run
  assert_success
  refute_output --partial "comment"
}

@test "ollama-bootstrap pulls every listed tag" {
  run bash "$SCRIPT"
  assert_success
  run cat "$OLLAMA_LOG"
  assert_line "pull alpha:9b"
  assert_line "pull beta:4b"
}

@test "ollama-bootstrap strips trailing comments from a tag" {
  # 'alpha:9b # trailing comment' must pull 'alpha:9b', not the whole line.
  run bash "$SCRIPT"
  assert_success
  run grep -c 'pull alpha:9b$' "$OLLAMA_LOG"
  assert_output "1"
}

@test "ollama-bootstrap builds the Modelfiles it finds" {
  printf 'FROM alpha:9b\n' > "$TREE/config/ollama/modelfiles/custom.Modelfile"
  run bash "$SCRIPT"
  assert_success
  assert_output --partial "building    custom"
  run grep -c 'create custom -f' "$OLLAMA_LOG"
  assert_output "1"
}

@test "ollama-bootstrap reports no Modelfile when the directory is empty" {
  run bash "$SCRIPT" --dry-run
  assert_success
  assert_output --partial "none"
}

@test "ollama-bootstrap fails clearly when the daemon is down" {
  export DAEMON_UP=0
  run bash "$SCRIPT" --dry-run
  assert_failure
  assert_output --partial "daemon is not answering"
  assert_equal "$(wc -l < "$OLLAMA_LOG" | tr -d ' ')" "0"
}

@test "ollama-bootstrap fails clearly when ollama is absent" {
  # Narrow PATH to the stub dir plus the system ones: merely deleting the stub
  # would fall through to the real ollama further along the developer's PATH,
  # and the test would pass vacuously.
  rm "$BIN/ollama"
  PATH="$BIN:/usr/bin:/bin"
  run bash "$SCRIPT" --dry-run
  assert_failure
  assert_output --partial "not on PATH"
  assert_output --partial "brew install"
}

@test "ollama-bootstrap fails when models.txt is missing" {
  rm "$TREE/config/ollama/models.txt"
  run bash "$SCRIPT" --dry-run
  assert_failure
  assert_output --partial "models.txt not found"
}

@test "ollama-bootstrap surfaces a failed pull in the summary" {
  export OLLAMA_STUB_FAIL=1
  run bash "$SCRIPT"
  assert_failure
  assert_output --partial "failures      : 2"
}
