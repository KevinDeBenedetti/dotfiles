#!/usr/bin/env bats

# Tests for os/helpers/fetch.sh: a download is kept only when its SHA-256 is
# the pinned one. fetch_verified and install_from_tarball run for real, with
# curl stubbed and fixture tarballs.

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

# --- install_from_tarball: verified download, then binaries into a directory ---

# A tarball holding pkg/tool, which prints "fake tool": gzip, or xz with "xz".
fake_tool_tarball() {
  local compress="-z"
  if [ "${1:-}" = xz ]; then
    command -v xz >/dev/null || skip "xz not installed"
    compress="-J"
  fi
  mkdir -p "$BATS_TEST_TMPDIR/src/pkg"
  printf '#!/bin/sh\necho fake tool\n' > "$BATS_TEST_TMPDIR/src/pkg/tool"
  tar "$compress" -cf "$BATS_TEST_TMPDIR/tool.tar.gz" -C "$BATS_TEST_TMPDIR/src" pkg
  curl() {
    local out="" prev="" arg
    for arg in "$@"; do [ "$prev" = "-o" ] && out="$arg"; prev="$arg"; done
    cp "$BATS_TEST_TMPDIR/tool.tar.gz" "$out"
  }
  TOOL_SHA256=$( { sha256sum "$BATS_TEST_TMPDIR/tool.tar.gz" 2>/dev/null || shasum -a 256 "$BATS_TEST_TMPDIR/tool.tar.gz"; } | cut -d' ' -f1)
}

@test "install_from_tarball installs the named members of a matching tarball, executable" {
  fake_tool_tarball
  export TMPDIR="$BATS_TEST_TMPDIR"
  run install_from_tarball tool https://example.invalid/t.tar.gz "$TOOL_SHA256" "$BATS_TEST_TMPDIR/bin" pkg/tool
  assert_success
  run "$BATS_TEST_TMPDIR/bin/tool"
  assert_output "fake tool"
}

@test "install_from_tarball installs nothing from a download that does not match" {
  fake_tool_tarball
  export TMPDIR="$BATS_TEST_TMPDIR"
  run install_from_tarball tool https://example.invalid/t.tar.gz "$PAYLOAD_SHA256" "$BATS_TEST_TMPDIR/bin" pkg/tool
  assert_failure 1
  assert_output --partial "tool not installed"
  assert_file_not_exists "$BATS_TEST_TMPDIR/bin/tool"
}

@test "install_from_tarball fails when a member is missing, and cleans up its temp dir" {
  fake_tool_tarball
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
  run install_from_tarball tool https://example.invalid/t.tar.gz "$TOOL_SHA256" "$BATS_TEST_TMPDIR/bin" pkg/missing
  assert_failure 1
  assert_file_not_exists "$BATS_TEST_TMPDIR/bin/missing"
  run find "$TMPDIR" -mindepth 1
  assert_output ""
}

@test "install_from_tarball --sudo runs the install steps through \$SUDO" {
  fake_tool_tarball
  export TMPDIR="$BATS_TEST_TMPDIR"
  printf '#!/bin/sh\necho "$@" >> "%s/sudo.log"\nexec "$@"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/fake-sudo"
  chmod +x "$BATS_TEST_TMPDIR/fake-sudo"
  SUDO="$BATS_TEST_TMPDIR/fake-sudo" run install_from_tarball --sudo tool https://example.invalid/t.tar.gz \
    "$TOOL_SHA256" "$BATS_TEST_TMPDIR/bin" pkg/tool
  assert_success
  run cat "$BATS_TEST_TMPDIR/sudo.log"
  assert_output --partial "mkdir -p"
  assert_output --partial "install -m 0755"
}

@test "install_from_tarball extracts an xz tarball too (proto ships .tar.xz)" {
  fake_tool_tarball xz
  export TMPDIR="$BATS_TEST_TMPDIR"
  run install_from_tarball tool https://example.invalid/t.tar.xz "$TOOL_SHA256" "$BATS_TEST_TMPDIR/bin" pkg/tool
  assert_success
  run "$BATS_TEST_TMPDIR/bin/tool"
  assert_output "fake tool"
}

# --- install_deb_verified: verified download, then apt-get install as $SUDO ---

# A fake `sudo` that logs what it runs and fakes apt-get (no real install).
fake_sudo_with_apt() {
  printf '#!/bin/sh\necho "$*" >> "%s/sudo.log"\n[ "$1" = apt-get ] && { cp "$5" "%s/installed.deb"; exit 0; }\nexec "$@"\n' \
    "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/fake-sudo"
  chmod +x "$BATS_TEST_TMPDIR/fake-sudo"
  export SUDO="$BATS_TEST_TMPDIR/fake-sudo" TMPDIR="$BATS_TEST_TMPDIR"
}

@test "install_deb_verified installs a matching .deb with apt-get, through \$SUDO" {
  PAYLOAD="release payload"
  fake_sudo_with_apt
  run install_deb_verified tool https://example.invalid/tool.deb "$PAYLOAD_SHA256"
  assert_success
  run cat "$BATS_TEST_TMPDIR/sudo.log"
  assert_output --regexp '^apt-get install -y --no-install-recommends /.*/tool\.deb$'
  run cat "$BATS_TEST_TMPDIR/installed.deb"
  assert_output "release payload"
  run find "$BATS_TEST_TMPDIR" -maxdepth 1 -name 'tool.*'
  assert_output ""
}

@test "install_deb_verified never hands a .deb that does not match to apt" {
  PAYLOAD="tampered payload"
  fake_sudo_with_apt
  run install_deb_verified tool https://example.invalid/tool.deb "$PAYLOAD_SHA256"
  assert_failure 1
  assert_output --partial "tool not installed"
  assert_file_not_exists "$BATS_TEST_TMPDIR/sudo.log"
  run find "$BATS_TEST_TMPDIR" -maxdepth 1 -name 'tool.*'
  assert_output ""
}

# --- install_apt_key: an apt key reaches the keyring only with its pinned fingerprint ---

# gpg stub: --show-keys prints one `pub`/`fpr` pair per line of $KEY_FPRS, in
# gpg's colon format; --dearmor copies stdin. NO_GPG=1 makes gpg missing.
load_apt_key_stubs() {
  export TMPDIR="$BATS_TEST_TMPDIR"
  SUDO="" KEYRING="$BATS_TEST_TMPDIR/keyrings/vendor.gpg" PAYLOAD="armored key"
  FPR=0123456789ABCDEF0123456789ABCDEF01234567
  # Another key: same length, different fingerprint.
  OTHER_FPR="FFFF${FPR:4}"
  gpg() {
    local fpr
    case " $* " in
      *" --show-keys "*) for fpr in $KEY_FPRS; do printf 'pub:-:255:22:%s:\nfpr:::::::::%s:\n' "${fpr: -16}" "$fpr"; done ;;
      *" --dearmor "*) cat ;;
    esac
  }
  command() {
    if [ "$1" = -v ] && [ "$2" = gpg ]; then [ -z "${NO_GPG:-}" ]; return; fi
    builtin command "$@"
  }
}

@test "install_apt_key writes the keyring when the one key has the pinned fingerprint" {
  load_apt_key_stubs
  KEY_FPRS="$FPR" run install_apt_key https://example.invalid/key "$FPR" "$KEYRING"
  assert_success
  assert_equal "$(cat "$KEYRING")" "armored key"
}

@test "install_apt_key refuses another key, and writes no keyring" {
  load_apt_key_stubs
  KEY_FPRS="$OTHER_FPR" run install_apt_key https://example.invalid/key "$FPR" "$KEYRING"
  assert_failure
  assert_output --partial "does not match fingerprint $FPR"
  assert_file_not_exists "$KEYRING"
}

@test "install_apt_key refuses a file that holds a second key next to the pinned one" {
  load_apt_key_stubs
  KEY_FPRS="$FPR $OTHER_FPR" run install_apt_key https://example.invalid/key "$FPR" "$KEYRING"
  assert_failure
  assert_file_not_exists "$KEYRING"
}

@test "install_apt_key says gpg is not installed, before any download, when gpg is missing" {
  load_apt_key_stubs
  curl() { echo "curl called"; }
  NO_GPG=1 KEY_FPRS="$FPR" run install_apt_key https://example.invalid/key "$FPR" "$KEYRING"
  assert_failure
  assert_output --partial 'gpg is not installed'
  refute_output --partial 'does not match fingerprint'
  refute_output --partial 'curl called'
  assert_file_not_exists "$KEYRING"
}

@test "install_apt_key fails without a keyring when the key cannot be downloaded" {
  load_apt_key_stubs
  CURL_FAILS=1 KEY_FPRS="$FPR" run install_apt_key https://example.invalid/key "$FPR" "$KEYRING"
  assert_failure
  assert_output --partial 'could not be downloaded'
  assert_file_not_exists "$KEYRING"
}

@test "the Debian scripts share this install_apt_key: none keeps a copy of the check" {
  local script
  for script in setup-base.sh setup-kubernetes.sh setup-security.sh; do
    run grep -c 'helpers/fetch.sh"$' "$REPO_ROOT/os/debian/$script"
    assert_output "1"
    run grep -nE '^install_apt_key\(\)|gpg --(show-keys|dearmor)' "$REPO_ROOT/os/debian/$script"
    assert_failure
    run grep -c 'install_apt_key ' "$REPO_ROOT/os/debian/$script"
    refute_output "0"
  done
}
