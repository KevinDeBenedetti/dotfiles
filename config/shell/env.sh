# shellcheck shell=bash
# Shared, tracked environment variables for every machine go here.
# Example: export EDITOR="nvim"
#
# Machine-specific secrets/overrides live in env.local.sh (untracked).
# That file is sourced separately at the end of .zshrc, so it is NOT
# sourced here — doing both would source it twice.

# OpenCode: load the untracked provider override when present. The tracked
# ~/.config/opencode/opencode.json is only a placeholder; the real endpoint and
# models live in opencode.local.json. A path, not a secret: safe to export.
if [ -f "$HOME/.config/opencode/opencode.local.json" ]; then
  export OPENCODE_CONFIG="$HOME/.config/opencode/opencode.local.json"
fi
