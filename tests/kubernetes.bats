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
  run bash -c "grep -A1 'install_apt_key \"https://pkgs.k8s.io' '$K8S_SCRIPT'"
  assert_success
  assert_output --regexp '"[0-9A-F]{40}" /etc/apt/keyrings/kubernetes-apt-keyring\.gpg'
}

# load_install_kubectl — source install_kubectl with apt, sudo and the key
# check stubbed; every call lands in $LOG. HAS_KUBECTL=1 makes kubectl present,
# NO_GPG=1 makes gpg missing.
load_install_kubectl() {
  SUDO="" red="" no_color=""
  LOG="$BATS_TEST_TMPDIR/calls.log" LIST="$BATS_TEST_TMPDIR/kubernetes.list"
  : > "$LOG"
  install_apt_key() { echo "key $*" >> "$LOG"; return "${KEY_FAILS:-0}"; }
  apt-get() { echo "apt-get $*" >> "$LOG"; return "${APT_FAILS:-0}"; }
  command() {
    if [ "$1" = -v ] && [ "$2" = kubectl ]; then [ -n "${HAS_KUBECTL:-}" ]; return; fi
    if [ "$1" = -v ] && [ "$2" = gpg ]; then [ -z "${NO_GPG:-}" ]; return; fi
    builtin command "$@"
  }
  eval "$(sed -n '/^install_kubectl()/,/^}/p' "$K8S_SCRIPT")"
  declare -F install_kubectl >/dev/null || fail "install_kubectl not found in $K8S_SCRIPT"
}

@test "the kubectl apt channel is one pinned, supported minor, used for both the key and the repo" {
  local body
  body=$(sed -n '/^install_kubectl()/,/^}/p' "$K8S_SCRIPT")
  # v1.32 reached end of life on 2026-02-28: no security fixes since.
  run grep -cE '^[[:space:]]*local version="v1\.[0-9]+"$' <<<"$body"
  assert_output "1"
  run grep -E '^[[:space:]]*local version="v1\.(2[0-9]|3[0-2])"$' <<<"$body"
  assert_failure
  run grep -cE 'pkgs\.k8s\.io/core:/stable:/\$\{version\}/deb/' <<<"$body"
  assert_output "2"
  run grep -B1 -E '^[[:space:]]*local version="v1\.[0-9]+"$' <<<"$body"
  assert_output --partial '# renovate: datasource=github-releases depName=kubernetes/kubernetes'
}

@test "install_kubectl adds the pinned channel's key and repository, then installs kubectl" {
  load_install_kubectl
  run install_kubectl "$LIST"
  assert_success
  run cat "$LIST"
  assert_output --regexp '^deb \[signed-by=/etc/apt/keyrings/kubernetes-apt-keyring\.gpg\] https://pkgs\.k8s\.io/core:/stable:/v1\.[0-9]+/deb/ /$'
  run cat "$LOG"
  assert_line --index 0 --regexp '^key https://pkgs\.k8s\.io/core:/stable:/v1\.[0-9]+/deb/Release\.key [0-9A-F]{40} '
  assert_line --index 1 'apt-get update -qq'
  assert_line --index 2 'apt-get install -y kubectl'
}

@test "install_kubectl installs gnupg first on a system without gpg" {
  # Run on its own (not through init.sh, which installs gnupg) on a bare
  # Debian, the script failed the key check with a misleading fingerprint error.
  load_install_kubectl
  NO_GPG=1 run install_kubectl "$LIST"
  assert_success
  run cat "$LOG"
  assert_line --index 0 'apt-get update -qq'
  assert_line --index 1 'apt-get install -y -qq --no-install-recommends gnupg'
  assert_line --index 2 --regexp '^key https://pkgs\.k8s\.io/'
}

@test "install_kubectl stops before the key when gnupg cannot be installed" {
  load_install_kubectl
  APT_FAILS=1 NO_GPG=1 run install_kubectl "$LIST"
  assert_failure
  run grep -c '^key ' "$LOG"
  assert_output "0"
  [ ! -e "$LIST" ]
}

@test "install_kubectl moves a kubectl installed from an older channel to the pinned one" {
  load_install_kubectl
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' > "$LIST"
  HAS_KUBECTL=1 run install_kubectl "$LIST"
  assert_success
  assert_output --partial 'Moving'
  run grep -c 'v1.32' "$LIST"
  assert_output "0"
  run cat "$LOG"
  assert_line 'apt-get install -y kubectl'
}

@test "install_kubectl leaves kubectl alone when it is current, or not installed from pkgs.k8s.io" {
  load_install_kubectl
  install_kubectl "$LIST"
  : > "$LOG"
  HAS_KUBECTL=1 run install_kubectl "$LIST"
  assert_success
  assert_output --partial 'skipping'
  rm "$LIST"
  HAS_KUBECTL=1 run install_kubectl "$LIST"
  assert_success
  assert_output --partial 'skipping'
  run cat "$LOG"
  assert_output ""
  [ ! -e "$LIST" ]
}

@test "install_kubectl writes no repository when the key does not match" {
  load_install_kubectl
  echo old > "$LIST"
  KEY_FAILS=1 HAS_KUBECTL=1 run install_kubectl "$LIST"
  assert_failure
  run cat "$LIST"
  assert_output "old"
  run grep -c apt-get "$LOG"
  assert_output "0"
}

@test "Renovate moves the Kubernetes apt channel by minor only, never to a pre-release" {
  command -v perl >/dev/null || skip "perl not installed"
  run jq -r '.packageRules[] | select(.matchPackageNames | index("kubernetes/kubernetes")) | .extractVersion' "$REPO_ROOT/renovate.json"
  assert_success
  local re=${output//'(?<version>'/(}
  # Renovate applies extractVersion to each release tag; perl uses the same regex.
  run perl -e 'for (@ARGV) { print "$1\n" if /'"$re"'/ }' v1.37.2 v1.38.0 v1.38.0-alpha.1 v1.38.0-rc.0
  assert_output $'v1.37\nv1.38'
}

@test "the lite setup leaves kubectl and its apt repository off a node managed by the infra repo" {
  # Same marker as the Docker step of setup-base.sh: the infra `common` role
  # removes both on every run, a re-run must not put them back.
  run bash -c "sed -n '/^install_lite_setup()/,/^}/p' '$K8S_SCRIPT'"
  assert_output --partial 'infra_conf="/etc/ssh/sshd_config.d/00-infra-hardening.conf"'
  assert_output --partial 'if [[ -f "$infra_conf" ]]; then'
  # The marker is tested before the key and the repository are written, and
  # nothing is installed in its branch.
  local marker install
  marker=$(sed -n '/^install_lite_setup()/,/^}/p' "$K8S_SCRIPT" | grep -n 'if \[\[ -f "$infra_conf" \]\]' | head -n1 | cut -d: -f1)
  install=$(sed -n '/^install_lite_setup()/,/^}/p' "$K8S_SCRIPT" | grep -n 'install_kubectl' | head -n1 | cut -d: -f1)
  [ -n "$marker" ] && [ -n "$install" ] && [ "$marker" -lt "$install" ]
  run bash -c "sed -n '/^install_lite_setup()/,/^}/p' '$K8S_SCRIPT' | sed -n '/if \[\[ -f \"\$infra_conf\" \]\]; then/,/^  else/p' | grep -E 'apt-get|kubernetes.list|install_apt_key|install_kubectl'"
  assert_failure
}

@test "load_kernel_modules writes its config on a system with no /etc/sysctl.d yet" {
  # The slim debian image ships neither /etc/sysctl.d nor /etc/modules-load.d
  # (procps and kmod create them): the sysctl write stopped the whole script.
  ROOT="$BATS_TEST_TMPDIR/root" red="" no_color=""
  mkdir -p "$ROOT/etc"
  # Every command run through $SUDO acts under $ROOT instead of /.
  in_root() { local a=() x; for x in "$@"; do a+=("${x//\/etc\//$ROOT/etc/}"); done; "${a[@]}"; }
  modprobe() { return 1; }
  sysctl() { return 1; }
  eval "$(sed -n '/^load_kernel_modules()/,/^}/p' "$K8S_SCRIPT")"
  # Under the script's own `set -euo pipefail`: a failing write must fail the test.
  run bash -c "set -euo pipefail; $(declare -f in_root modprobe sysctl load_kernel_modules); ROOT='$ROOT' SUDO=in_root red= no_color= load_kernel_modules"
  assert_success
  run cat "$ROOT/etc/sysctl.d/99-zz-kubernetes-cri.conf"
  assert_output --partial 'net.ipv4.ip_forward                 = 1'
  run cat "$ROOT/etc/modules-load.d/k8s.conf"
  assert_output $'overlay\nbr_netfilter'
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
