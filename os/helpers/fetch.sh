#!/usr/bin/env bash
# Verified downloads, shared by every script that installs a release file.
# Sourced, never executed.

# fetch_verified <url> <sha256> <dest>
# Download <url> to <dest> and keep it only if its SHA-256 is <sha256>. On any
# failure (HTTP error, truncated or tampered download) <dest> is removed and
# the function fails, so a caller can never use unverified bytes.
fetch_verified() {
  local url="$1" sha256="$2" dest="$3" actual
  # An empty or malformed pin must never compare equal to an empty result.
  [[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || return 1
  if ! curl -fsSL -o "$dest" "$url"; then
    rm -f "$dest"
    return 1
  fi
  # macOS ships shasum; sha256sum is not guaranteed there.
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$dest")
  elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$dest")
  else
    actual=""
  fi
  if [ "${actual%% *}" != "$sha256" ]; then
    rm -f "$dest"
    return 1
  fi
}
