#!/usr/bin/env bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Ensure proto shims and binary are on PATH for this session.
# VERSION PINNING: all tool versions are declared in config/proto/.prototools,
# symlinked to ~/.proto/.prototools — do not hardcode versions here.
export PROTO_HOME="${PROTO_HOME:-$HOME/.proto}"
export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"

install_lite_setup() {
  printf "\n\n${red}[python] =>${no_color} Install Python via proto\n\n"
  # proto reads the pinned version from ~/.proto/.prototools automatically
  proto install python

  printf "\n\n${red}[python] =>${no_color} Install homebrew packages (cli)\n\n"
  brew install --formula \
    uv
}

install_additional_setup() {
  # Install python tools via uv
  printf "\n\n${red}[python] =>${no_color} Install python tools\n\n"
  uv tool install ruff
  uv tool install ipython
  uv tool install httpie
}


# Install lite setup
install_lite_setup

# Install full setup
if [ "$FULL_MODE_SETUP" = "true" ]; then
  install_additional_setup
fi
