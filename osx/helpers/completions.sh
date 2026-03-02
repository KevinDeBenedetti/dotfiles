#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

ZSH_COMP_DIR="$(brew --prefix)/share/zsh/site-functions"

# fzf - completion + key bindings
if command -v fzf &>/dev/null; then
  printf "\n\n${red}[completions] =>${no_color} Install fzf shell integration\n\n"
  "$(brew --prefix)/opt/fzf/install" --completion --key-bindings --no-update-rc
fi

# gh - GitHub CLI
if command -v gh &>/dev/null; then
  printf "\n\n${red}[completions] =>${no_color} Generate gh completions\n\n"
  gh completion -s zsh > "$ZSH_COMP_DIR/_gh"
fi

# proto - toolchain manager
if command -v proto &>/dev/null; then
  printf "\n\n${red}[completions] =>${no_color} Generate proto completions\n\n"
  proto completions --shell zsh > "$ZSH_COMP_DIR/_proto"
fi

# uv - python package manager
if command -v uv &>/dev/null; then
  printf "\n\n${red}[completions] =>${no_color} Generate uv completions\n\n"
  uv generate-shell-completion zsh > "$ZSH_COMP_DIR/_uv"
fi
