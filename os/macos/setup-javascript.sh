#!/usr/bin/env bash

set -euo pipefail

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Default so `set -u` doesn't trip when run standalone (init.sh exports it)
FULL_MODE_SETUP="${FULL_MODE_SETUP:-false}"

# Ensure proto shims and binary are on PATH for this session.
# VERSION PINNING: all tool versions are declared in config/proto/.prototools,
# symlinked to ~/.proto/.prototools — do not hardcode versions here.
export PROTO_HOME="${PROTO_HOME:-$HOME/.proto}"
export PATH="$PROTO_HOME/shims:$PROTO_HOME/bin:$PATH"

install_lite_setup() {
  printf '%b' "\n\n${red}[js] =>${no_color} Install Node.js via proto\n\n"
  # proto reads the pinned version from ~/.proto/.prototools automatically
  proto install node
  proto install npm
}

install_additional_setup() {
  printf '%b' "\n\n${red}[js] =>${no_color} Install additional JS package managers via proto\n\n"
  proto install bun
  proto install pnpm
  proto install yarn

  printf '%b' "\n\n${red}[js] =>${no_color} Install npm global packages\n\n"
  npm install --global \
    @antfu/ni
}


# Install lite setup
install_lite_setup

# Install full setup
if [ "$FULL_MODE_SETUP" = "true" ]; then
  install_additional_setup
fi
