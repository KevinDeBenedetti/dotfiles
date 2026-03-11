#!/bin/bash

set -euo pipefail

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Detect OS and set completion directory + write strategy
SUDO="${SUDO:-}"
if [ "$(uname)" = "Darwin" ] && command -v brew &>/dev/null; then
  ZSH_COMP_DIR="$(brew --prefix)/share/zsh/site-functions"
else
  ZSH_COMP_DIR="/usr/local/share/zsh/site-functions"
  $SUDO mkdir -p "$ZSH_COMP_DIR"
fi

# Helper: write completion to the correct directory (handles sudo on Linux)
write_completion() {
  local content="$1"
  local dest="$2"
  if [ -n "$SUDO" ]; then
    echo "$content" | $SUDO tee "$dest" >/dev/null
  else
    echo "$content" > "$dest"
  fi
}

# fzf - completion + key bindings (macOS only via Homebrew)
if [ "$(uname)" = "Darwin" ] && command -v fzf &>/dev/null && command -v brew &>/dev/null; then
  printf "\n\n${red}[completions] =>${no_color} Install fzf shell integration\n\n"
  "$(brew --prefix)/opt/fzf/install" --completion --key-bindings --no-update-rc
fi

# gh - GitHub CLI
if command -v gh &>/dev/null; then
  printf "\n\n${red}[completions] =>${no_color} Generate gh completions\n\n"
  write_completion "$(gh completion -s zsh)" "$ZSH_COMP_DIR/_gh"
fi

# proto - toolchain manager
if command -v proto &>/dev/null; then
  printf "\n\n${red}[completions] =>${no_color} Generate proto completions\n\n"
  write_completion "$(proto completions --shell zsh)" "$ZSH_COMP_DIR/_proto"
fi

# uv - python package manager
if command -v uv &>/dev/null; then
  printf "\n\n${red}[completions] =>${no_color} Generate uv completions\n\n"
  write_completion "$(uv generate-shell-completion zsh)" "$ZSH_COMP_DIR/_uv"
fi
