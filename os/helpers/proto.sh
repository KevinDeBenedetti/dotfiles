#!/usr/bin/env bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

PROTO_HOME="${PROTO_HOME:-$HOME/.proto}"
ZSHRC="$HOME/.zshrc"

printf "\n\n${red}[proto] =>${no_color} Configure proto\n\n"

# Install proto via the official installer if the binary is not already present.
# --no-profile: skip patching shell files — we manage that ourselves below.
if ! command -v proto &>/dev/null && [ ! -x "$PROTO_HOME/bin/proto" ]; then
  printf "${red}[proto]${no_color} Installing proto via official installer...\n"
  curl -fsSL https://moonrepo.dev/install/proto.sh | bash -s -- --no-profile
else
  printf "${red}[proto]${no_color} proto already installed — skipping.\n"
fi

# Add the minimal proto shell block to .zshrc if not already present.
# The block exports PROTO_HOME and prepends both shims/ (tool intercepts)
# and bin/ (proto itself) to PATH so that proto and managed tools are found.
if ! grep -q 'PROTO_HOME' "$ZSHRC" 2>/dev/null; then
  printf '\n# proto\nexport PROTO_HOME="$HOME/.proto"\nexport PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"\n' >> "$ZSHRC"
  printf "${red}[proto]${no_color} proto shell integration added to $ZSHRC\n"
else
  printf "${red}[proto]${no_color} proto already configured in $ZSHRC — skipping.\n"
fi
