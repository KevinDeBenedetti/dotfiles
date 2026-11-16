#!/usr/bin/env bash
# Install proto (https://moonrepo.dev/proto) from a pinned release and add its
# shell block to ~/.zshrc. Run by the OS init scripts; its functions can also
# be sourced (the main part at the bottom only runs when the file is executed).

# Colorize terminal
red="${red:-\e[0;31m}"
no_color="${no_color:-\033[0m}"

# shellcheck source=fetch.sh
source "$( cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P )/fetch.sh"

# proto_release_target
# Print the name of proto's release build for this machine, or fail when the
# platform has none pinned below.
proto_release_target() {
  case "$(uname -s)/$(uname -m)" in
    Linux/x86_64) echo "x86_64-unknown-linux-gnu" ;;
    Linux/aarch64 | Linux/arm64) echo "aarch64-unknown-linux-gnu" ;;
    Darwin/arm64) echo "aarch64-apple-darwin" ;;
    Darwin/x86_64) echo "x86_64-apple-darwin" ;;
    *) return 1 ;;
  esac
}

# install_proto_tarball <url> <sha256> <target> <bin_dir>
# Install proto and proto-shim from a release tarball into <bin_dir>, only if
# the tarball's SHA-256 is <sha256>. Every step is checked explicitly, so the
# function is also correct where errexit is off.
install_proto_tarball() {
  local url="$1" sha256="$2" target="$3" bin_dir="$4" proto_tmp
  proto_tmp=$(mktemp -d "${TMPDIR:-/tmp}/proto.XXXXXX") || return 1
  if ! fetch_verified "$url" "$sha256" "$proto_tmp/proto.tar.xz"; then
    rm -rf "$proto_tmp"
    printf '%b' "${red}[error]${no_color} $url could not be downloaded or does not match its pinned SHA-256 — proto not installed.\n"
    return 1
  fi
  if ! tar -xJf "$proto_tmp/proto.tar.xz" -C "$proto_tmp" \
        "proto_cli-${target}/proto" "proto_cli-${target}/proto-shim" \
      || ! mkdir -p "$bin_dir" \
      || ! install -m 0755 "$proto_tmp/proto_cli-${target}/proto" "$proto_tmp/proto_cli-${target}/proto-shim" "$bin_dir/"; then
    rm -rf "$proto_tmp"
    printf '%b' "${red}[error]${no_color} proto could not be extracted from its tarball or installed into $bin_dir.\n"
    return 1
  fi
  rm -rf "$proto_tmp"
}

# install_proto <bin_dir>
# Install the pinned proto release. The SHA-256 of each platform's tarball is
# pinned here, so no installer script and no checksum fetched at install time
# is trusted. `proto upgrade` later moves to newer releases on its own.
# To bump: change the version, then copy the `digest` of each asset
# (read 2026-11-16 for the values below):
#   gh release view <version> -R moonrepo/proto --json assets -q '.assets[] | "\(.name) \(.digest)"'
install_proto() {
  local bin_dir="$1" version="v0.64.0" target sha256
  if ! target=$(proto_release_target); then
    printf '%b' "${red}[error]${no_color} No pinned proto build for $(uname -s)/$(uname -m) — proto not installed.\n"
    return 1
  fi
  case "$target" in
    x86_64-unknown-linux-gnu) sha256="44c80d7c3492a3c8c34af359470faf4e35a69fc8c8ba49190fd1c5f9e60c876c" ;;
    aarch64-unknown-linux-gnu) sha256="9583a4a4b7674428d29ea424eb92a2b2bcea78d2d1a3139994a6a9d21cd3ddab" ;;
    aarch64-apple-darwin) sha256="05f6fbeb1064a7181adfa9c4a331e290f6e1d89cb2f5dcfce542b33cd4b7b220" ;;
    x86_64-apple-darwin) sha256="af901e2198825507811ca354dea43c256049e44b5389c67eee8e20da294db442" ;;
    *)
      printf '%b' "${red}[error]${no_color} No pinned proto checksum for $target — proto not installed.\n"
      return 1 ;;
  esac
  install_proto_tarball \
    "https://github.com/moonrepo/proto/releases/download/${version}/proto_cli-${target}.tar.xz" \
    "$sha256" "$target" "$bin_dir"
}

# Add the minimal proto shell block to .zshrc if not already present.
# The block exports PROTO_HOME and prepends both shims/ (tool intercepts)
# and bin/ (proto itself) to PATH so that proto and managed tools are found.
configure_proto_shell() {
  local zshrc="$1"
  if ! grep -q 'PROTO_HOME' "$zshrc" 2>/dev/null; then
    # shellcheck disable=SC2016  # written literally: expanded by zsh, not here
    printf '\n# proto\nexport PROTO_HOME="$HOME/.proto"\nexport PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"\n' >> "$zshrc"
    printf '%b' "${red}[proto]${no_color} proto shell integration added to $zshrc\n"
  else
    printf '%b' "${red}[proto]${no_color} proto already configured in $zshrc — skipping.\n"
  fi
}

# Main part: only when executed, not when sourced.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  PROTO_HOME="${PROTO_HOME:-$HOME/.proto}"

  printf '%b' "\n\n${red}[proto] =>${no_color} Configure proto\n\n"

  if ! command -v proto &>/dev/null && [ ! -x "$PROTO_HOME/bin/proto" ]; then
    printf '%b' "${red}[proto]${no_color} Installing proto from its pinned release...\n"
    # A failed install fails this script (and the bootstrap that runs it),
    # but only after the shell block below is written, so PATH is already
    # right once proto is installed.
    proto_install_status=0
    install_proto "$PROTO_HOME/bin" || proto_install_status=1
  else
    proto_install_status=0
    printf '%b' "${red}[proto]${no_color} proto already installed — skipping.\n"
  fi

  configure_proto_shell "$HOME/.zshrc"
  exit "$proto_install_status"
fi
