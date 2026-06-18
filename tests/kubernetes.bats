#!/usr/bin/env bats

# Tests for setup-kubernetes.sh script structure and function wiring.
# Like security.bats, these validate the script statically (syntax, function
# presence, lite-vs-full wiring) without running heavy installs on the host.
# They close the gap where only the lite path was exercised by the Docker stages.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  K8S_SCRIPT="$REPO_ROOT/os/debian/setup-kubernetes.sh"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'
}

# --- Script existence & syntax ---

@test "setup-kubernetes.sh exists" {
  assert_file_exists "$K8S_SCRIPT"
}

@test "setup-kubernetes.sh has valid bash syntax" {
  run bash -n "$K8S_SCRIPT"
  assert_success
}

@test "setup-kubernetes.sh starts with shebang" {
  run head -1 "$K8S_SCRIPT"
  assert_output "#!/bin/bash"
}

@test "setup-kubernetes.sh runs in strict mode" {
  run grep -q 'set -euo pipefail' "$K8S_SCRIPT"
  assert_success
}

# --- Function definitions ---

@test "setup-kubernetes.sh defines load_kernel_modules" {
  run grep -c 'load_kernel_modules()' "$K8S_SCRIPT"
  assert_output "1"
}

@test "setup-kubernetes.sh defines install_lite_setup" {
  run grep -c 'install_lite_setup()' "$K8S_SCRIPT"
  assert_output "1"
}

@test "setup-kubernetes.sh defines install_additional_setup" {
  run grep -c 'install_additional_setup()' "$K8S_SCRIPT"
  assert_output "1"
}

# --- Lite vs full mode wiring ---

@test "lite setup loads kernel modules and installs kubectl" {
  run bash -c "sed -n '/^install_lite_setup()/,/^}/p' '$K8S_SCRIPT'"
  assert_success
  assert_output --partial "load_kernel_modules"
  assert_output --partial "kubectl"
}

@test "full (additional) setup installs helm and k9s" {
  # The full-mode path was never exercised by the lite Docker stages.
  run bash -c "sed -n '/^install_additional_setup()/,/^}/p' '$K8S_SCRIPT'"
  assert_success
  assert_output --partial "helm"
  assert_output --partial "k9s"
}

@test "full mode is gated on FULL_MODE_SETUP variable" {
  run grep 'FULL_MODE_SETUP' "$K8S_SCRIPT"
  assert_success
  assert_output --partial '"true"'
}

@test "FULL_MODE_SETUP has a default so set -u does not trip standalone" {
  run grep -q 'FULL_MODE_SETUP="${FULL_MODE_SETUP:-false}"' "$K8S_SCRIPT"
  assert_success
}

# --- Regressions: guards that keep full mode robust ---

@test "k9s install is guarded against an empty/invalid version" {
  # A failed/rate-limited GitHub API must not produce a broken download URL.
  run grep -Eq 'K9S_VERSION.*=~[[:space:]]*\^v\[0-9\]' "$K8S_SCRIPT"
  assert_success
}

@test "kernel module + sysctl calls are best-effort (container-safe)" {
  run grep -q 'modprobe overlay || true' "$K8S_SCRIPT"
  assert_success
  run grep -q 'modprobe br_netfilter || true' "$K8S_SCRIPT"
  assert_success
  run grep -q 'sysctl --system > /dev/null 2>&1 || true' "$K8S_SCRIPT"
  assert_success
}
