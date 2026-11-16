#!/usr/bin/env bats

# Tests for os/helpers/fetch.sh: a download is kept only when its SHA-256 is
# the pinned one. fetch_verified runs for real, with curl stubbed.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  # `printf 'release payload\n' | sha256sum`
  PAYLOAD_SHA256=be110d6f8d61b5ddbd77bac7005548b01a51a7267183875866b264659d9d0753
  OUT="$BATS_TEST_TMPDIR/out"

  # "Downloads" $PAYLOAD, or fails after a partial write when CURL_FAILS is set.
  curl() {
    local out="" prev="" arg
    for arg in "$@"; do [ "$prev" = "-o" ] && out="$arg"; prev="$arg"; done
    if [ -n "${CURL_FAILS:-}" ]; then echo partial > "$out"; return 22; fi
    printf '%s\n' "$PAYLOAD" > "$out"
  }
  source "$REPO_ROOT/os/helpers/fetch.sh"
}

@test "fetch_verified keeps a download that matches its SHA-256" {
  PAYLOAD="release payload"
  run fetch_verified https://example.invalid/x "$PAYLOAD_SHA256" "$OUT"
  assert_success
  run cat "$OUT"
  assert_output "release payload"
}

@test "fetch_verified refuses a download that does not match, and leaves no file" {
  PAYLOAD="tampered payload"
  run fetch_verified https://example.invalid/x "$PAYLOAD_SHA256" "$OUT"
  assert_failure
  assert_file_not_exists "$OUT"
}

@test "fetch_verified removes the partial file of a failed download" {
  CURL_FAILS=1
  run fetch_verified https://example.invalid/x "$PAYLOAD_SHA256" "$OUT"
  assert_failure
  assert_file_not_exists "$OUT"
}

@test "fetch_verified refuses an empty or malformed pin without downloading" {
  PAYLOAD="release payload"
  local pin
  for pin in "" "be110d6f" "${PAYLOAD_SHA256}00" "${PAYLOAD_SHA256^^}"; do
    run fetch_verified https://example.invalid/x "$pin" "$OUT"
    assert_failure
    assert_file_not_exists "$OUT"
  done
}
