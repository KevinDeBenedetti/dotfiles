#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

printf "\n\n${red}[proto] =>${no_color} Configure proto shell integration\n\n"

ZSHRC="$HOME/.zshrc"

if ! grep -q 'PROTO_HOME' "$ZSHRC" 2>/dev/null; then
  printf '\n# proto\nexport PROTO_HOME="$HOME/.proto"\nexport PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"\n' >> "$ZSHRC"
  printf "${red}[proto]${no_color} PROTO_HOME exports added to $ZSHRC\n"
else
  printf "${red}[proto]${no_color} PROTO_HOME already configured in $ZSHRC, skipping\n"
fi
