#!/bin/bash

set -euo pipefail

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Console step increment
i=1

# Get project directories
SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# Remote execution support: if sub-scripts are missing (e.g. running via "bash <(curl ...)"),
# clone the repo to a temp dir and re-exec from there with the same arguments.
REPO_URL="https://github.com/KevinDeBenedetti/dotfiles.git"
if [ ! -f "$SCRIPT_PATH/setup/base.sh" ]; then
  printf "\n${red}[bootstrap]${no_color} Sub-scripts not found locally — cloning dotfiles repository...\n\n"
  TMP_DIR=$(mktemp -d)
  trap "rm -rf '$TMP_DIR'" EXIT
  git clone --depth=1 "$REPO_URL" "$TMP_DIR"
  exec bash "$TMP_DIR/osx/init.sh" "$@"
fi

# Default
INSTALL_AI="false"
INSTALL_BASE="false"
INSTALL_EXTRAS="false"
INSTALL_JAVASCRIPT="false"
INSTALL_PYTHON="false"
INSTALL_COMPLETIONS="false"
COPY_DOTFILES="false"
REMOVE_TMP_CONTENT="false"
FULL_MODE_SETUP="true"
FORCE_INSTALL="false"

# Declare script helper
TEXT_HELPER="\nThis script aims to install a full setup for osx.
Following flags are available:

  -c    Install cli completions.

  -d    Copy dotfiles.

  -f    Force reinstall / override existing packages and config files.

  -l    Run with lite mode, only major tools will be installed.

  -p    Install additional packages according to the given profile, available profiles are :
          -> 'ai'
          -> 'base'
          -> 'extras' (for personnal use)
          -> 'javascript'
          -> 'python'
        Default is no profile, this flag can be used with a CSV list (ex: -p \"base,javascript\").

  -r    Remove all tmp files after installation.

  -h    Print script help.\n\n"

print_help() {
  printf "$TEXT_HELPER"
}

# Parse options
while getopts hcdflp:r flag; do
  case "${flag}" in
    c)
      INSTALL_COMPLETIONS="true";;
    d)
      COPY_DOTFILES="true";;
    f)
      FORCE_INSTALL="true";;
    l)
      FULL_MODE_SETUP="false";;
    p)
      [[ "$OPTARG" =~ "ai" ]] && INSTALL_AI="true"
      [[ "$OPTARG" =~ "base" ]] && INSTALL_BASE="true"
      [[ "$OPTARG" =~ "extras" ]] && INSTALL_EXTRAS="true"
      [[ "$OPTARG" =~ "javascript" ]] && INSTALL_JAVASCRIPT="true"
      [[ "$OPTARG" =~ "python" ]] && INSTALL_PYTHON="true";;
    r)
      REMOVE_TMP_CONTENT="true";;
    h | *)
      print_help
      exit 0;;
  esac
done


# utils
install_clt() {
  printf "\n\n${red}Optional.${no_color} Installs Command Line Tools for Xcode from softwareupdate...\n\n"
  # This temporary file prompts the 'softwareupdate' utility to list the Command Line Tools
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  PROD=$(softwareupdate -l | grep "\*.*Command Line" | tail -n 1 | sed 's/^[^C]* //')
  softwareupdate -i "$PROD" --verbose;
  printf "\Command Line Tools version installed :\n$PROD\n\n"
}

install_homebrew() {
  printf "\n\n${red}Optional.${no_color} Installs homebrew...\n\n"
  export NONINTERACTIVE=1
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  printf "\nhomebrew version installed :\n$(brew --version)\n\n"
}

if [ -z "$(xcode-select -p 2>/dev/null)" ]; then
  while true; do
    read -p "\nYou need Command Line Tools to run this script. Do you wish to install Command Line Tools?\n" yn
    case $yn in
      [Yy]*)
        install_clt;;
      [Nn]*)
        exit;;
      *)
        echo "\nPlease answer yes or no.\n";;
    esac
  done
fi

if ! command -v brew &>/dev/null; then
  while true; do
    read -p "You need homebrew to run this script. Do you wish to install homebrew?" yn
    case $yn in
      [Yy]*)
        install_homebrew;;
      [Nn]*)
        exit;;
      *)
        printf "\nPlease answer y or n.\n";;
    esac
  done
fi


# Settings
printf "\nScript settings:
  -> install ${red}full setup${no_color}: ${red}$FULL_MODE_SETUP${no_color}
  -> force install / override: ${red}$FORCE_INSTALL${no_color}
  -> install ${red}[ai]${no_color} profile: ${red}$INSTALL_AI${no_color}
  -> install ${red}[base]${no_color} profile: ${red}$INSTALL_BASE${no_color}
  -> install ${red}[extras]${no_color} profile: ${red}$INSTALL_EXTRAS${no_color}
  -> install ${red}[javascript]${no_color} profile: ${red}$INSTALL_JAVASCRIPT${no_color}
  -> install ${red}[python]${no_color} profile: ${red}$INSTALL_PYTHON${no_color}\n"

export FULL_MODE_SETUP=$FULL_MODE_SETUP
export FORCE_INSTALL=$FORCE_INSTALL
export HOMEBREW_NO_AUTO_UPDATE=1

# Update brew once
printf "\n${red}${i}.${no_color} Update homebrew\n\n"
brew update --verbose || printf "\n${red}[warning]${no_color} brew update failed (non-fatal), continuing with existing index...\n\n"
i=$(($i + 1))

# Install common
printf "\n${red}${i}.${no_color} Install commons\n\n"
BREW_CMD=$([ "$FORCE_INSTALL" = "true" ] && echo "reinstall" || echo "install")
brew $BREW_CMD --formula \
  ca-certificates \
  curl \
  gnupg \
  gsed \
  gzip \
  jq \
  unzip \
  wget \
  xz
i=$(($i + 1))

# Install oh-my-zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  printf "\n${red}${i}.${no_color} Install oh-my-zsh\n\n"
  i=$(($i + 1))

  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi


# Install base profile
if [[ "$INSTALL_BASE" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install base profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup/base.sh"

  # Configure proto proxies
  bash "$SCRIPT_PATH/helpers/proto.sh"
fi


# Install extras profile
if [[ "$INSTALL_EXTRAS" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install extras profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup/extras.sh"
fi


# Install javascript profile
if [[ "$INSTALL_JAVASCRIPT" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install javascript profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup/javascript.sh"
fi


# Install python profile
if [[ "$INSTALL_PYTHON" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install python profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup/python.sh"
fi


# Install ai profile
if [[ "$INSTALL_AI" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install ai profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup/ai.sh"
fi


# Copy dotfiles
if [[ "$COPY_DOTFILES" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Copy dotfiles\n\n"
  i=$(($i + 1))

  mkdir -p "$HOME/.config"
  cp "$SCRIPT_PATH/../dotfiles/.zshrc" "$HOME/.zshrc" && gsed -i 's/^# alias sed=.*/alias sed="gsed"/g' "$HOME/.zshrc"
  THEME_SRC="$SCRIPT_PATH/../dotfiles/.oh-my-zsh/kevin-de-benedetti.zsh-theme"
  if [ -f "$THEME_SRC" ]; then
    mkdir -p "$HOME/.oh-my-zsh/custom/themes"
    cp "$THEME_SRC" "$HOME/.oh-my-zsh/custom/themes/kevin-de-benedetti.zsh-theme"
  else
    printf "${red}[warning]${no_color} Theme file not found, skipping: $THEME_SRC\n"
  fi
  mkdir -p "$HOME/.proto"
  cp "$SCRIPT_PATH/../dotfiles/.prototools" "$HOME/.proto/.prototools"
  cp "$SCRIPT_PATH/../dotfiles/.gitconfig" "$HOME/.gitconfig"
  cp -R $SCRIPT_PATH/../dotfiles/.config/* "$HOME/.config"

  # Create SSH allowed signers file for local commit signature verification
  SSH_SIGNING_KEY="$HOME/.ssh/id_rsa.pub"
  ALLOWED_SIGNERS="$HOME/.ssh/allowed_signers"
  GIT_EMAIL=$(git config --global user.email 2>/dev/null || echo "contact@kevindb.dev")
  if [ -f "$SSH_SIGNING_KEY" ]; then
    mkdir -p "$HOME/.ssh"
    printf '%s %s\n' "$GIT_EMAIL" "$(tr -d '\r' < "$SSH_SIGNING_KEY" | tr -d '\n')" > "$ALLOWED_SIGNERS"
    chmod 600 "$ALLOWED_SIGNERS"
    printf "${red}[git]${no_color} SSH allowed_signers file created at $ALLOWED_SIGNERS\n"
  else
    printf "${red}[warning]${no_color} No SSH public key found — skipping allowed_signers setup.\n"
  fi


  # Configure proto proxies
  bash "$SCRIPT_PATH/helpers/proto.sh"


  # Install .vscode configs
  if [ -x "$(command -v code)" ]; then
    mkdir -p "$HOME/Library/Application Support/Code/User"
    cp "$SCRIPT_PATH/../dotfiles/.vscode/settings.json" "$HOME/Library/Application Support/Code/User/settings.json"
    cp "$SCRIPT_PATH/../dotfiles/.vscode/mcp.json" "$HOME/Library/Application Support/Code/User/mcp.json"
    while IFS= read -r extension; do
      code --install-extension "$extension"
    done < <(grep -v '//' "$SCRIPT_PATH/../dotfiles/.vscode/extensions.json" \
      | grep -E '\S' \
      | jq -r '.recommendations[]')
  fi


  # Update brew links if architecture is arm64
  if [ "$(uname -m)" = "arm64" ] || [ "$(uname -m)" = "aarch64" ]; then
    gsed -i 's/\/usr\/local/\/opt\/homebrew/g' "$HOME/.zshrc"
  fi
fi


# Install cli completions
if [[ "$INSTALL_COMPLETIONS" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install cli completions\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/helpers/completions.sh"
  ZSH_COMP_PLUGIN="${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions"
  if [ -d "$ZSH_COMP_PLUGIN" ]; then
    if [ "$FORCE_INSTALL" = "true" ]; then
      printf "${red}[completions]${no_color} Removing existing zsh-completions plugin (force)...\n"
      rm -rf "$ZSH_COMP_PLUGIN"
      git clone https://github.com/zsh-users/zsh-completions.git "$ZSH_COMP_PLUGIN"
    else
      printf "${red}[completions]${no_color} zsh-completions already present — skipping clone.\n"
    fi
  else
    git clone https://github.com/zsh-users/zsh-completions.git "$ZSH_COMP_PLUGIN"
  fi
  if ! grep -q 'fpath+=.*zsh-completions' "$HOME/.zshrc" 2>/dev/null; then
    gsed -i 's|^# fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src|fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src|g' "$HOME/.zshrc"
  fi
fi


if [[ "$REMOVE_TMP_CONTENT" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Remove tmp files\n\n"
  i=$(($i + 1))

  rm -rf /tmp/*
fi