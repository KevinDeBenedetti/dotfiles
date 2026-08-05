#!/usr/bin/env bats
# Functional tests for scripts/ollama/ollama-setenv.
#
# `uname` and `launchctl` are stubbed by shell scripts placed first on PATH, so
# both OS branches can be exercised on any host and nothing touches the real
# launchd session.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/ollama/ollama-setenv"

  load "$REPO_ROOT/tests/test_helper/bats-support/load"
  load "$REPO_ROOT/tests/test_helper/bats-assert/load"

  # Isolated config + state, so neither the real env.sh nor the real log is read
  # or written.
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  mkdir -p "$XDG_CONFIG_HOME/ollama" "$XDG_STATE_HOME"

  cat > "$XDG_CONFIG_HOME/ollama/env.sh" <<'EOF'
# a comment
OLLAMA_MAX_LOADED_MODELS=1
OLLAMA_KV_CACHE_TYPE=q8_0
NOT_AN_OLLAMA_VAR=ignored
EOF

  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$BIN"
  export LAUNCHCTL_LOG="$BATS_TEST_TMPDIR/launchctl.log"
  : > "$LAUNCHCTL_LOG"

  cat > "$BIN/launchctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$LAUNCHCTL_LOG"
EOF

  # FAKE_OS drives the branch under test.
  cat > "$BIN/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_OS:-Darwin}"
EOF

  chmod +x "$BIN/launchctl" "$BIN/uname"
  export PATH="$BIN:$PATH"
}

# ── macOS ────────────────────────────────────────────────────────────────────

@test "on macOS it pushes every OLLAMA_ var through launchctl setenv" {
  export FAKE_OS=Darwin
  run bash "$SCRIPT"
  assert_success
  run cat "$LAUNCHCTL_LOG"
  assert_line "setenv OLLAMA_MAX_LOADED_MODELS 1"
  assert_line "setenv OLLAMA_KV_CACHE_TYPE q8_0"
}

@test "it ignores assignments that are not OLLAMA_ variables" {
  export FAKE_OS=Darwin
  run bash "$SCRIPT"
  assert_success
  run grep -c NOT_AN_OLLAMA_VAR "$LAUNCHCTL_LOG"
  assert_output "0"
}

@test "it reminds the user to restart the app" {
  export FAKE_OS=Darwin
  run bash "$SCRIPT"
  assert_success
  # The server reads its environment only at startup; without a restart the
  # variables are set but unused, which is the confusing half-applied state.
  assert_output --partial "reopen Ollama.app"
}

# ── Linux ────────────────────────────────────────────────────────────────────

@test "on Linux it renders a systemd drop-in instead" {
  export FAKE_OS=Linux
  run bash "$SCRIPT"
  assert_success
  assert_output --partial "[Service]"
  assert_output --partial 'Environment="OLLAMA_MAX_LOADED_MODELS=1"'
  assert_output --partial 'Environment="OLLAMA_KV_CACHE_TYPE=q8_0"'
  # It must not touch launchd on Linux.
  assert_equal "$(wc -l < "$LAUNCHCTL_LOG" | tr -d ' ')" "0"
}

@test "on Linux it prints the install command rather than escalating itself" {
  export FAKE_OS=Linux
  run bash "$SCRIPT"
  assert_success
  assert_output --partial "sudo install -Dm644"
  assert_output --partial "/etc/systemd/system/ollama.service.d/override.conf"
  assert_output --partial "systemctl restart ollama"
}

@test "on Linux the drop-in lands in the state dir" {
  export FAKE_OS=Linux
  run bash "$SCRIPT"
  assert_success
  assert [ -f "$XDG_STATE_HOME/ollama-override.conf" ]
}

# ── Failure modes ────────────────────────────────────────────────────────────

@test "it fails clearly on an unsupported OS" {
  export FAKE_OS=SunOS
  run bash "$SCRIPT"
  assert_failure
  assert_output --partial "unsupported OS"
}

@test "it fails clearly when env.sh is missing" {
  rm "$XDG_CONFIG_HOME/ollama/env.sh"
  run bash "$SCRIPT"
  assert_failure
  assert_output --partial "not found"
}

@test "it fails when env.sh defines no OLLAMA_ variable" {
  printf '# nothing here\nFOO=bar\n' > "$XDG_CONFIG_HOME/ollama/env.sh"
  run bash "$SCRIPT"
  assert_failure
  assert_output --partial "no OLLAMA_* assignment"
}

# ── Logging ──────────────────────────────────────────────────────────────────

@test "it logs to the per-user state dir, never /tmp" {
  export FAKE_OS=Darwin
  run bash "$SCRIPT"
  assert_success
  assert [ -f "$XDG_STATE_HOME/ollama-env.log" ]
  run cat "$XDG_STATE_HOME/ollama-env.log"
  assert_output --partial "ollama-setenv"
}
