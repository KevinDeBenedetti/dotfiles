#!/usr/bin/env bash
# Install oh-my-zsh from its installer script, pinned by commit and SHA-256.
# Sourced by the OS init scripts, never executed.

red="${red:-}"
no_color="${no_color:-}"

# shellcheck source=fetch.sh
source "$( cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P )/fetch.sh"

# run_oh_my_zsh_installer <url> <sha256>
# Download the installer and run it only if its SHA-256 is <sha256>:
# unattended (no shell switch, no zsh started), keeping the existing ~/.zshrc.
run_oh_my_zsh_installer() {
  local url="$1" sha256="$2" omz_tmp status=0
  omz_tmp=$(mktemp -d "${TMPDIR:-/tmp}/oh-my-zsh.XXXXXX") || return 1
  if ! fetch_verified "$url" "$sha256" "$omz_tmp/install.sh"; then
    rm -rf "$omz_tmp"
    printf '%b' "${red}[error]${no_color} $url could not be downloaded or does not match its pinned SHA-256 — oh-my-zsh not installed.\n"
    return 1
  fi
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$omz_tmp/install.sh" || status=$?
  rm -rf "$omz_tmp"
  return "$status"
}

# install_oh_my_zsh
# Run the installer as it was at a pinned commit (oh-my-zsh ships no release
# tags), so the script that runs here is one that was read first, not whatever
# `master` holds on the day. Only the installer is pinned: it still clones the
# current oh-my-zsh, which then keeps itself up to date.
# To bump: take a commit of https://github.com/ohmyzsh/ohmyzsh, read the diff
# of tools/install.sh since the commit below, then replace both values:
#   curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/<commit>/tools/install.sh | sha256sum
install_oh_my_zsh() {
  # master on 2026-11-16.
  local commit="c0140703a53eb0d22be44f7bac318d0baacc927c"
  local sha256="3f9f1b6269deddc51cdcab2a689f54821e6e62c24401f970de4bfafad328b2ef"
  run_oh_my_zsh_installer \
    "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/${commit}/tools/install.sh" "$sha256"
}
