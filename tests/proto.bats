#!/usr/bin/env bats

# Tests for os/helpers/proto.sh: proto is installed from a pinned release
# tarball whose SHA-256 is pinned in the script, never from a remote installer
# script. The functions run for real, with curl and uname stubbed and a temp
# directory as the install target.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  PROTO_SCRIPT="$REPO_ROOT/os/helpers/proto.sh"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  curl() {
    local out="" prev="" arg
    for arg in "$@"; do [ "$prev" = "-o" ] && out="$arg"; prev="$arg"; done
    echo "$*" >> "$BATS_TEST_TMPDIR/curl.log"
    cp "$FAKE_DOWNLOAD" "$out"
  }
  uname() { case "$1" in -s) echo "${FAKE_OS:-Linux}" ;; -m) echo "${FAKE_MACHINE:-x86_64}" ;; esac; }
  export TMPDIR="$BATS_TEST_TMPDIR"
  # Sourcing defines the functions; the script's main part runs only when executed.
  source "$PROTO_SCRIPT"
}

# A well-formed proto release tarball for $1 whose binaries print their name.
fake_proto_tarball() {
  command -v xz >/dev/null || skip "xz not installed"
  local target="$1" dir="$BATS_TEST_TMPDIR/pkg/proto_cli-$1"
  mkdir -p "$dir"
  printf '#!/bin/sh\necho fake proto\n' > "$dir/proto"
  printf '#!/bin/sh\necho fake shim\n' > "$dir/proto-shim"
  chmod +x "$dir/proto" "$dir/proto-shim"
  tar -cJf "$BATS_TEST_TMPDIR/proto.tar.xz" -C "$BATS_TEST_TMPDIR/pkg" "proto_cli-$target"
  FAKE_DOWNLOAD="$BATS_TEST_TMPDIR/proto.tar.xz"
}

sha256_of() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

@test "proto_release_target names the release build of each supported platform" {
  FAKE_OS=Linux FAKE_MACHINE=x86_64 run proto_release_target
  assert_output "x86_64-unknown-linux-gnu"
  FAKE_OS=Linux FAKE_MACHINE=aarch64 run proto_release_target
  assert_output "aarch64-unknown-linux-gnu"
  FAKE_OS=Darwin FAKE_MACHINE=arm64 run proto_release_target
  assert_output "aarch64-apple-darwin"
  FAKE_OS=Darwin FAKE_MACHINE=x86_64 run proto_release_target
  assert_output "x86_64-apple-darwin"
}

@test "proto_release_target fails on a platform with no pinned build" {
  FAKE_OS=Linux FAKE_MACHINE=riscv64 run proto_release_target
  assert_failure
}

@test "install_proto_tarball installs proto and proto-shim from a tarball that matches" {
  fake_proto_tarball x86_64-unknown-linux-gnu
  run install_proto_tarball https://example.invalid/p.tar.xz "$(sha256_of "$FAKE_DOWNLOAD")" \
    x86_64-unknown-linux-gnu "$BATS_TEST_TMPDIR/home/bin"
  assert_success
  run "$BATS_TEST_TMPDIR/home/bin/proto"
  assert_output "fake proto"
  run "$BATS_TEST_TMPDIR/home/bin/proto-shim"
  assert_output "fake shim"
}

@test "install_proto_tarball installs nothing from a download that does not match" {
  printf 'not proto\n' > "$BATS_TEST_TMPDIR/payload"
  FAKE_DOWNLOAD="$BATS_TEST_TMPDIR/payload"
  run install_proto_tarball https://example.invalid/p.tar.xz \
    0000000000000000000000000000000000000000000000000000000000000000 \
    x86_64-unknown-linux-gnu "$BATS_TEST_TMPDIR/home/bin"
  assert_failure
  assert_output --partial "pinned SHA-256"
  assert_file_not_exists "$BATS_TEST_TMPDIR/home/bin/proto"
}

@test "install_proto requests one pinned GitHub release and rejects other bytes" {
  # Not the pinned bytes: any payload will do, no tarball (or xz) needed.
  printf 'not proto\n' > "$BATS_TEST_TMPDIR/payload"
  FAKE_DOWNLOAD="$BATS_TEST_TMPDIR/payload"
  run install_proto "$BATS_TEST_TMPDIR/home/bin"
  assert_failure
  assert_output --partial "pinned SHA-256"
  assert_file_not_exists "$BATS_TEST_TMPDIR/home/bin/proto"
  run cat "$BATS_TEST_TMPDIR/curl.log"
  assert_output --regexp 'https://github\.com/moonrepo/proto/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/proto_cli-x86_64-unknown-linux-gnu\.tar\.xz$'
}

@test "install_proto fails clearly on an unsupported platform, without downloading" {
  FAKE_MACHINE=riscv64 run install_proto "$BATS_TEST_TMPDIR/home/bin"
  assert_failure
  assert_output --partial "riscv64"
  assert_file_not_exists "$BATS_TEST_TMPDIR/curl.log"
}

@test "no remote installer script is piped into a shell for proto" {
  run grep -rn 'moonrepo.dev/install' "$REPO_ROOT/os"
  assert_failure
}

# --- The script itself, executed with a fake HOME and a stub curl on PATH ---

run_proto_script() {
  mkdir -p "$BATS_TEST_TMPDIR/stubs" "$BATS_TEST_TMPDIR/fakehome"
  printf '#!/bin/sh\nexit 22\n' > "$BATS_TEST_TMPDIR/stubs/curl"
  chmod +x "$BATS_TEST_TMPDIR/stubs/curl"
  # PROTO_HOME is pinned to the fake home: the owner's shell exports the real
  # one, which would make the script find the proto installed on this machine.
  run env HOME="$BATS_TEST_TMPDIR/fakehome" PROTO_HOME="$BATS_TEST_TMPDIR/fakehome/.proto" \
    PATH="$BATS_TEST_TMPDIR/stubs:/usr/bin:/bin" TMPDIR="$BATS_TEST_TMPDIR" bash "$PROTO_SCRIPT"
}

@test "proto.sh fails when proto cannot be installed, after writing the shell block" {
  run_proto_script
  assert_failure
  assert_output --partial "proto not installed"
  run grep -c 'PROTO_HOME' "$BATS_TEST_TMPDIR/fakehome/.zshrc"
  assert_success
}

@test "proto.sh leaves an existing proto alone and succeeds" {
  mkdir -p "$BATS_TEST_TMPDIR/fakehome/.proto/bin"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/fakehome/.proto/bin/proto"
  chmod +x "$BATS_TEST_TMPDIR/fakehome/.proto/bin/proto"
  run_proto_script
  assert_success
  assert_output --partial "already installed"
}
