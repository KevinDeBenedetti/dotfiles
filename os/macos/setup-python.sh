#!/bin/bash

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'


export PROTO_AUTO_INSTALL=true
export PROTO_AUTO_CLEAN=true
export PATH="$HOME/.proto/shims:$HOME/.proto/bin:$PATH"

install_lite_setup() {
  # Install proto packages
  printf "\n\n${red}[python] =>${no_color} Install proto packages\n\n"
  PACKAGES=(
    python
  )
  for pkg in "${PACKAGES[@]}"; do
    proto install "$pkg"
  done

  # Install homebrew cli packages
  printf "\n\n${red}[python] =>${no_color} Install homebrew packages (cli)\n\n"
  brew install --formula \
    uv
}

install_additional_setup() {
  # Install python tools via uv
  printf "\n\n${red}[python] =>${no_color} Install python tools\n\n"
  uv tool install \
    ruff
  uv tool install \
    ipython
  uv tool install \
    httpie
}


# Install lite setup
install_lite_setup

# Install full setup
if [ "$FULL_MODE_SETUP" = "true" ]; then
  install_additional_setup
fi
