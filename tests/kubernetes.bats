#!/usr/bin/env bats

# Tests for setup-kubernetes.sh script structure and function wiring.
# Like security.bats, most validate the script statically (syntax, function
# presence, lite-vs-full wiring) without running heavy installs on the host.
# The "Verified downloads" section at the end runs the download functions for
# real, with curl stubbed and a temp directory as the install target.
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

@test "no helm installer script is fetched" {
  run grep -c 'get-helm' "$K8S_SCRIPT"
  assert_output "0"
}

@test "the Kubernetes apt key is trusted only after its pinned fingerprint check" {
  # The key no longer goes from curl straight into the keyring (2026-11-12).
  # (The old form put the pipe on a continuation line: match the pipe itself.)
  run grep -E '\|[[:space:]]*\$SUDO gpg --dearmor' "$K8S_SCRIPT"
  assert_failure
  run bash -c "sed -n '/^install_apt_key()/,/^}/p' '$K8S_SCRIPT'"
  assert_success
  assert_output --partial 'grep -qx "$key_fpr"'
  assert_output --partial 'END { if (n == 1) print fpr }'
  assert_output --partial 'return 1'
  local check dearmor
  check=$(grep -n 'grep -qx "$key_fpr"' "$K8S_SCRIPT" | cut -d: -f1)
  dearmor=$(grep -n 'gpg --dearmor < "$key_tmp"' "$K8S_SCRIPT" | cut -d: -f1)
  [ -n "$check" ] && [ -n "$dearmor" ] && [ "$check" -lt "$dearmor" ]
  run bash -c "grep -A1 'install_apt_key https://pkgs.k8s.io' '$K8S_SCRIPT'"
  assert_success
  assert_output --regexp '"[0-9A-F]{40}" /etc/apt/keyrings/kubernetes-apt-keyring\.gpg'
}

@test "the lite setup leaves kubectl and its apt repository off a node managed by the infra repo" {
  # Same marker as the Docker step of setup-base.sh: the infra `common` role
  # removes both on every run, a re-run must not put them back.
  run bash -c "sed -n '/^install_lite_setup()/,/^}/p' '$K8S_SCRIPT'"
  assert_output --partial 'infra_conf="/etc/ssh/sshd_config.d/00-infra-hardening.conf"'
  assert_output --partial 'if [[ -f "$infra_conf" ]]; then'
  # The marker is tested before the key and the repository are written, and
  # nothing is installed in its branch.
  local marker repo
  marker=$(sed -n '/^install_lite_setup()/,/^}/p' "$K8S_SCRIPT" | grep -n 'if \[\[ -f "$infra_conf" \]\]' | head -n1 | cut -d: -f1)
  repo=$(sed -n '/^install_lite_setup()/,/^}/p' "$K8S_SCRIPT" | grep -n 'sources.list.d/kubernetes.list' | head -n1 | cut -d: -f1)
  [ -n "$marker" ] && [ -n "$repo" ] && [ "$marker" -lt "$repo" ]
  run bash -c "sed -n '/^install_lite_setup()/,/^}/p' '$K8S_SCRIPT' | sed -n '/if \[\[ -f \"\$infra_conf\" \]\]; then/,/^  elif/p' | grep -E 'apt-get|kubernetes.list|install_apt_key'"
  assert_failure
}

@test "kernel module + sysctl calls are best-effort (container-safe)" {
  run grep -q 'modprobe overlay || true' "$K8S_SCRIPT"
  assert_success
  run grep -q 'modprobe br_netfilter || true' "$K8S_SCRIPT"
  assert_success
  run grep -q 'sysctl --system > /dev/null 2>&1 || true' "$K8S_SCRIPT"
  assert_success
}

# --- Verified downloads (behaviour: the functions run, curl is stubbed) ---

# Defines the download functions from the script without running it, with
# curl stubbed to "download" $FAKE_DOWNLOAD (or to fail after a partial write
# when CURL_FAILS is set) and dpkg reporting $FAKE_ARCH.
stub_downloads_and_load_helm_functions() {
  SUDO="" red="" no_color=""
  curl() {
    local out="" prev="" arg
    for arg in "$@"; do [ "$prev" = "-o" ] && out="$arg"; prev="$arg"; done
    echo "$*" >> "$BATS_TEST_TMPDIR/curl.log"
    if [ -n "${CURL_FAILS:-}" ]; then echo partial > "$out"; return 22; fi
    cp "$FAKE_DOWNLOAD" "$out"
  }
  dpkg() { echo "${FAKE_ARCH:-amd64}"; }
  # Keep the functions' temp dirs inside the test's own directory.
  export TMPDIR="$BATS_TEST_TMPDIR"
  source "$REPO_ROOT/os/helpers/fetch.sh"
  local fn
  for fn in install_helm install_k9s; do
    eval "$(sed -n "/^$fn()/,/^}/p" "$K8S_SCRIPT")"
    declare -F "$fn" >/dev/null || fail "$fn not found in $K8S_SCRIPT"
  done
}

# A well-formed helm tarball for amd64 whose helm prints "fake helm".
fake_helm_tarball() {
  mkdir -p "$BATS_TEST_TMPDIR/pkg/linux-amd64" "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho fake helm\n' > "$BATS_TEST_TMPDIR/pkg/linux-amd64/helm"
  tar -czf "$BATS_TEST_TMPDIR/helm.tar.gz" -C "$BATS_TEST_TMPDIR/pkg" linux-amd64
  FAKE_DOWNLOAD="$BATS_TEST_TMPDIR/helm.tar.gz"
}

@test "install_helm installs linux-<arch>/helm from the tarball into /usr/local/bin, through sudo" {
  stub_downloads_and_load_helm_functions
  install_from_tarball() { echo "$*"; }
  FAKE_ARCH=arm64 run install_helm
  assert_success
  assert_output --regexp '^--sudo helm https://get\.helm\.sh/helm-v[0-9.]+-linux-arm64\.tar\.gz [0-9a-f]{64} /usr/local/bin linux-arm64/helm$'
}

@test "install_helm requests one pinned release from get.helm.sh and rejects other bytes" {
  fake_helm_tarball
  stub_downloads_and_load_helm_functions
  run install_helm
  assert_failure
  assert_output --partial "pinned SHA-256"
  run cat "$BATS_TEST_TMPDIR/curl.log"
  assert_output --regexp 'https://get\.helm\.sh/helm-v[0-9]+\.[0-9]+\.[0-9]+-linux-amd64\.tar\.gz$'
}

@test "install_helm fails clearly on an architecture with no pinned checksum" {
  FAKE_ARCH=riscv64
  stub_downloads_and_load_helm_functions
  run install_helm
  assert_failure
  assert_output --partial "riscv64"
  assert_file_not_exists "$BATS_TEST_TMPDIR/curl.log"
}

@test "install_k9s installs one pinned k9s release .deb, checked against its pinned SHA-256" {
  stub_downloads_and_load_helm_functions
  install_deb_verified() { echo "$*"; }
  FAKE_ARCH=arm64 run install_k9s
  assert_success
  assert_output --regexp '^k9s https://github\.com/derailed/k9s/releases/download/v[0-9.]+/k9s_linux_arm64\.deb [0-9a-f]{64}$'
}

@test "install_k9s fails clearly on an architecture with no pinned checksum" {
  FAKE_ARCH=armhf
  stub_downloads_and_load_helm_functions
  run install_k9s
  assert_failure
  assert_output --partial "armhf"
  assert_file_not_exists "$BATS_TEST_TMPDIR/curl.log"
}

@test "k9s no longer follows the latest release" {
  run grep -c 'derailed/k9s/releases/latest' "$K8S_SCRIPT"
  assert_output "0"
}
