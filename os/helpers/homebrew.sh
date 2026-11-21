#!/usr/bin/env bash
# Install Homebrew from its installer script, pinned by commit and SHA-256.
# Sourced by os/macos/init.sh, never executed.

red="${red:-}"
no_color="${no_color:-}"

# shellcheck source=fetch.sh
source "$( cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P )/fetch.sh"

# run_homebrew_installer <url> <sha256>
# Download the installer and run it only if its SHA-256 is <sha256>. Its exit
# status is returned; its temp dir is removed either way. NONINTERACTIVE is
# the caller's choice: with it set, the installer skips its prompts but uses
# sudo only when sudo is already authorised.
run_homebrew_installer() {
  local url="$1" sha256="$2" brew_tmp rc=0
  brew_tmp=$(mktemp -d "${TMPDIR:-/tmp}/homebrew.XXXXXX") || return 1
  if ! fetch_verified "$url" "$sha256" "$brew_tmp/install.sh"; then
    rm -rf "$brew_tmp"
    printf '%b' "${red}[error]${no_color} $url could not be downloaded or does not match its pinned SHA-256 — Homebrew not installed.\n"
    return 1
  fi
  /bin/bash "$brew_tmp/install.sh" || rc=$?
  rm -rf "$brew_tmp"
  return "$rc"
}

# install_homebrew
# Run the Homebrew installer as it was at a pinned commit, so the script that
# runs here is one that was read first, not whatever HEAD holds on the day.
# Only the installer is pinned: it then checks out Homebrew's latest release.
# To bump: read the changes since the commit below, then replace both values:
#   https://github.com/Homebrew/install/compare/<commit>...HEAD
#   curl -fsSL https://raw.githubusercontent.com/Homebrew/install/<commit>/install.sh | shasum -a 256
install_homebrew() {
  # HEAD on 2026-11-16.
  local commit="e5b3c5834e3932c8aaa42deef4794076c9b0cbf0"
  local sha256="5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148"
  run_homebrew_installer \
    "https://raw.githubusercontent.com/Homebrew/install/${commit}/install.sh" "$sha256"
}

# load_homebrew_env [prefix...]
# Put an installed brew on PATH when it is not there yet. The installer writes
# to /opt/homebrew on Apple Silicon, which the default macOS PATH does not
# hold: without this, the script that just installed Homebrew cannot run it,
# and a second run would offer to install it again. Does nothing when brew is
# already on PATH or installed under none of the prefixes.
load_homebrew_env() {
  local prefix
  command -v brew &>/dev/null && return 0
  [ "$#" -gt 0 ] || set -- /opt/homebrew /usr/local
  for prefix in "$@"; do
    if [ -x "$prefix/bin/brew" ]; then
      eval "$("$prefix/bin/brew" shellenv)"
      return 0
    fi
  done
  return 0
}
