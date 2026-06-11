#!/usr/bin/env bash
# Install the Claude Code managed settings policy (system-wide, root-owned).
#
# Managed settings must be a real file owned by root — a symlink to a
# user-writable file in this repo would let any user process (including
# Claude Code itself) rewrite the policy and defeat its purpose.
# This script therefore COPIES the file instead of symlinking it.
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$DOTFILES_DIR/config/claude/managed-settings.json"

case "$(uname -s)" in
  Darwin) DEST="/Library/Application Support/ClaudeCode/managed-settings.json" ;;
  Linux)  DEST="/etc/claude-code/managed-settings.json" ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

if command -v jq >/dev/null 2>&1 && ! jq empty "$SRC"; then
  echo "❌ $SRC is not valid JSON, aborting" >&2
  exit 1
fi

if [ -f "$DEST" ] && diff -q "$SRC" "$DEST" >/dev/null 2>&1; then
  echo "✅ Managed settings already up to date ($DEST)"
  exit 0
fi

if [ -f "$DEST" ]; then
  echo "Current policy differs from repo version:"
  diff -u "$DEST" "$SRC" || true
  printf "Apply this policy? [y/N] "
  read -r answer
  case "$answer" in
    [yY]*) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
fi

echo "🔐 Installing managed settings to $DEST (sudo required)"
sudo mkdir -p "$(dirname "$DEST")"
sudo install -m 0644 -o root "$SRC" "$DEST"
echo "✅ Managed settings installed"
