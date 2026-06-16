#!/usr/bin/env bats

# Unit tests for config/shell/functions.sh
# Only tests functions that can run without external tools (no docker, kubectl, etc.)

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'

  # Source functions (strip top-level `local` declarations that fail outside zsh)
  eval "$(sed '/^local /d' "$REPO_ROOT/config/shell/functions.sh")"

  # Export all functions so `run` (subshell) can find them
  export -f b64d b64e brewsuggest browser cheat_glow check_cert cleanmac _cleanmac_path dks kbp randompass timestampd timestampe vpn lsfn
}

# --- b64e / b64d ---

@test "b64e encodes string to base64" {
  run b64e "hello"
  assert_success
  assert_output "aGVsbG8="
}

@test "b64d decodes base64 string" {
  run b64d "aGVsbG8="
  assert_success
  assert_output "hello"
}

@test "b64e then b64d round-trips" {
  encoded=$(b64e "dotfiles")
  run b64d "$encoded"
  assert_success
  assert_output "dotfiles"
}

@test "b64e -h prints help" {
  run b64e -h
  assert_success
  assert_output --partial "Encode base64 string"
}

@test "b64d -h prints help" {
  run b64d -h
  assert_success
  assert_output --partial "Decode base64 string"
}

# --- randompass ---

@test "randompass generates output" {
  run randompass 16
  assert_success
  # Should produce exactly 16 characters
  assert_equal "${#output}" 16
}

@test "randompass default length is 24" {
  run randompass
  assert_success
  assert_equal "${#output}" 24
}

@test "randompass -h prints help" {
  run randompass -h
  assert_success
  assert_output --partial "Generate a password"
}

@test "randompass contains all required character classes" {
  run randompass 32
  assert_success
  [[ "$output" == *[A-Z]* ]]
  [[ "$output" == *[a-z]* ]]
  [[ "$output" == *[0-9]* ]]
  [[ "$output" == *[=\!?%~_-]* ]]
}

@test "randompass rejects length below 4 instead of looping forever" {
  run randompass 3
  assert_failure
  assert_output --partial "at least 4"
}

@test "randompass rejects non-numeric length" {
  run randompass abc
  assert_failure
  assert_output --partial "positive integer"
}

# --- timestampd ---

@test "timestampd -h prints help" {
  run timestampd -h
  assert_success
  assert_output --partial "human readable"
}

# --- timestampe ---

@test "timestampe -h prints help" {
  run timestampe -h
  assert_success
  assert_output --partial "timestamp"
}

# --- kbp ---

@test "kbp -h prints help" {
  run kbp -h
  assert_success
  assert_output --partial "Kill the process"
}

@test "kbp fails gracefully when no process is on the port" {
  # Stub lsof so the test doesn't depend on it being installed or on port state
  lsof() { return 1; }
  export -f lsof
  run kbp 64999
  assert_failure
  assert_output --partial "No process found"
}

# --- check_cert ---

@test "check_cert -h prints help" {
  run check_cert -h
  assert_success
  assert_output --partial "Print certificate infos"
}

# --- browser ---

@test "browser -h prints help" {
  run browser -h
  assert_success
  assert_output --partial "browsh web browser"
}

@test "browser forwards url after -- separator to browsh" {
  # Stub docker to capture the arguments it receives
  docker() { [ "$1" = "info" ] && return 0; echo "docker $*"; }
  export -f docker
  run browser -- https://example.com
  assert_success
  assert_output --partial "browsh/browsh https://example.com"
}

@test "browser forwards bare url to browsh" {
  docker() { [ "$1" = "info" ] && return 0; echo "docker $*"; }
  export -f docker
  run browser https://example.com
  assert_success
  assert_output --partial "browsh/browsh https://example.com"
}

# --- cheat_glow ---

@test "cheat_glow -h prints help" {
  run cheat_glow -h
  assert_success
  assert_output --partial "cheat sheet"
}

# --- brewsuggest ---

@test "brewsuggest -h prints help" {
  run brewsuggest -h
  assert_success
  assert_output --partial "Suggest useful Homebrew"
}

@test "brewsuggest marks installed tools and suggests missing ones" {
  # Stub brew: report only jq + fzf as installed
  brew() {
    if [ "$1" = "list" ]; then printf 'jq\nfzf\n'; else return 0; fi
  }
  export -f brew
  run brewsuggest
  assert_success
  # An installed tool and a missing one both appear, plus an install command
  assert_output --partial "jq"
  assert_output --partial "bat"
  assert_output --partial "brew install"
}

@test "brewsuggest fails gracefully without homebrew" {
  # Stub command so 'command -v brew' reports brew as absent
  command() {
    if [ "$1" = "-v" ] && [ "$2" = "brew" ]; then return 1; fi
    builtin command "$@"
  }
  export -f command
  run brewsuggest
  assert_failure
  assert_output --partial "Homebrew not installed"
}

# --- cleanmac ---

@test "cleanmac -h prints help" {
  run cleanmac -h
  assert_success
  assert_output --partial "Reclaim disk space"
}

@test "cleanmac with no args prints help (no destructive action)" {
  run cleanmac
  assert_success
  assert_output --partial "dry run"
}

# --- dks ---

@test "dks -h prints help" {
  run dks -h
  assert_success
  assert_output --partial "kubernetes secret"
}

# --- vpn ---

@test "vpn -h prints help" {
  run vpn -h
  assert_success
  assert_output --partial "WireGuard"
}

@test "vpn with no args prints help" {
  run vpn
  assert_success
  assert_output --partial "WireGuard"
}

@test "vpn up without a tunnel name fails gracefully" {
  run vpn up
  assert_failure
  assert_output --partial "missing tunnel name"
}

@test "vpn rejects an unknown subcommand" {
  run vpn bogus
  assert_failure
  assert_output --partial "unknown subcommand"
}
