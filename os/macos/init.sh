#!/usr/bin/env bash

set -euo pipefail

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Print the failing line on any error — much more informative than a silent exit
trap 'printf "\n%b[error]%b init.sh failed at line %s: %s\n" "$red" "$no_color" "$LINENO" "$BASH_COMMAND" >&2' ERR

# Console step increment
i=1

# Get project directories
SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
REPO_ROOT="$( cd -- "$SCRIPT_PATH/../.." >/dev/null 2>&1 ; pwd -P )"
CONFIG_DIR="$REPO_ROOT/config"
HELPERS_DIR="$REPO_ROOT/os/helpers"

# >>> remote bootstrap — the same text in os/debian/init.sh and os/macos/init.sh
# (tests/init.bats compares them): each script runs alone through
# "bash <(curl ...)", with nothing beside it to source, so a change made here
# is copied into the other.
#
# When the sub-scripts are missing, the whole repository is cloned and init.sh
# re-run from there with the same arguments. A full clone cannot miss a newly
# added sourced script the way a hand-maintained list of files could, and a
# permanent directory (not mktemp) keeps the symlinks the install creates valid
# across reboots: macOS wipes its per-user temp directories on logout.
REPO_URL="https://github.com/KevinDeBenedetti/dotfiles.git"
DOTFILES_INSTALL_DIR="${DOTFILES_INSTALL_DIR:-$HOME/.dotfiles}"
# The ref the bootstrap checks out: the latest release, bumped by
# release-please, so a fresh host never runs a half-merged main. Override it
# to test another one (DOTFILES_REF=main).
DOTFILES_REF="${DOTFILES_REF:-v0.20.0}" # x-release-please-version

# bootstrap_checkout: clones the repository at $DOTFILES_REF into
# $DOTFILES_INSTALL_DIR, or moves the clone already there to that ref.
bootstrap_checkout() {
  if [ -d "$DOTFILES_INSTALL_DIR/.git" ]; then
    printf '%b' "\n${red}[bootstrap]${no_color} Dotfiles repo found at $DOTFILES_INSTALL_DIR — checking out $DOTFILES_REF...\n\n"
    # A shallow clone (the bootstrap's own) stays shallow; a full one stays full.
    # (A plain variable, not an array: Bash 3.2 of macOS fails on an empty one under set -u.)
    _BOOTSTRAP_SHALLOW=""
    [ "$(git -C "$DOTFILES_INSTALL_DIR" rev-parse --is-shallow-repository 2>/dev/null)" = true ] && _BOOTSTRAP_SHALLOW=1
    { git -C "$DOTFILES_INSTALL_DIR" fetch ${_BOOTSTRAP_SHALLOW:+--depth=1} origin "$DOTFILES_REF" \
      && git -C "$DOTFILES_INSTALL_DIR" checkout --quiet --detach FETCH_HEAD; } \
      || printf '%b' "${red}[bootstrap]${no_color} Could not check out $DOTFILES_REF (non-fatal), using existing checkout.\n"
  else
    printf '%b' "\n${red}[bootstrap]${no_color} Sub-scripts not found locally — cloning dotfiles repository ($DOTFILES_REF) to $DOTFILES_INSTALL_DIR...\n\n"
    git clone --depth=1 --branch "$DOTFILES_REF" "$REPO_URL" "$DOTFILES_INSTALL_DIR"
  fi
}
# <<< remote bootstrap
if [ ! -f "$SCRIPT_PATH/setup-base.sh" ]; then
  bootstrap_checkout
  exec bash "$DOTFILES_INSTALL_DIR/os/macos/init.sh" "$@"
fi

# Default
INSTALL_AI="false"
INSTALL_BASE="false"
INSTALL_EXTRAS="false"
INSTALL_JAVASCRIPT="false"
INSTALL_PYTHON="false"
INSTALL_COMPLETIONS="false"
COPY_DOTFILES="false"
FULL_MODE_SETUP="true"

# Declare script helper
TEXT_HELPER="\nThis script aims to install a full setup for osx.
Following flags are available:

  -a    Full install: enables all profiles (ai, base, extras, javascript, python),
        copies dotfiles and installs completions.

  -c    Install cli completions.

  -d    Copy dotfiles.

  -l    Run with lite mode, only major tools will be installed.

  -p    Install additional packages according to the given profile, available profiles are :
          -> 'ai'
          -> 'base'
          -> 'extras' (for personnal use)
          -> 'javascript'
          -> 'python'
        Default is no profile, this flag can be used with a CSV list (ex: -p \"base,javascript\").

  -h    Print script help.\n\n"

print_help() {
  printf '%b' "$TEXT_HELPER"
}

# Parse options
while getopts hacdlp: flag; do
  case "${flag}" in
    a)
      INSTALL_AI="true"
      INSTALL_BASE="true"
      INSTALL_EXTRAS="true"
      INSTALL_JAVASCRIPT="true"
      INSTALL_PYTHON="true"
      INSTALL_COMPLETIONS="true"
      COPY_DOTFILES="true";;
    c)
      INSTALL_COMPLETIONS="true";;
    d)
      COPY_DOTFILES="true";;
    l)
      FULL_MODE_SETUP="false";;
    p)
      [[ ",$OPTARG," =~ ",ai," ]] && INSTALL_AI="true"
      [[ ",$OPTARG," =~ ",base," ]] && INSTALL_BASE="true"
      [[ ",$OPTARG," =~ ",extras," ]] && INSTALL_EXTRAS="true"
      [[ ",$OPTARG," =~ ",javascript," ]] && INSTALL_JAVASCRIPT="true"
      [[ ",$OPTARG," =~ ",python," ]] && INSTALL_PYTHON="true";;
    h)
      print_help
      exit 0;;
    *)
      # An unknown flag or a missing argument (getopts names it above).
      print_help
      exit 2;;
  esac
done

# Warn if no profile or action flag was provided
if [[ "$INSTALL_AI" = "false" && "$INSTALL_BASE" = "false" && "$INSTALL_EXTRAS" = "false" \
   && "$INSTALL_JAVASCRIPT" = "false" && "$INSTALL_PYTHON" = "false" \
   && "$COPY_DOTFILES" = "false" && "$INSTALL_COMPLETIONS" = "false" ]]; then
  printf '%b' "\n${red}[warning]${no_color} No profile or action flag provided. Nothing to do.\n"
  print_help
  exit 1
fi

# utils
install_clt() {
  printf '%b' "\n\n${red}Optional.${no_color} Installs Command Line Tools for Xcode from softwareupdate...\n\n"
  # This temporary file prompts the 'softwareupdate' utility to list the Command Line Tools
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  PROD=$(softwareupdate -l | grep "\*.*Command Line" | tail -n 1 | sed 's/^[^C]* //')
  softwareupdate -i "$PROD" --verbose;
  printf "\nCommand Line Tools version installed :\n%s\n\n" "$PROD"
}

# Homebrew installer pinned by commit and SHA-256 (os/helpers/homebrew.sh).
# shellcheck source=../helpers/homebrew.sh
source "$HELPERS_DIR/homebrew.sh"

install_homebrew_and_report() {
  printf '%b' "\n\n${red}Optional.${no_color} Installs homebrew...\n\n"
  NONINTERACTIVE=1 install_homebrew
  load_homebrew_env
  printf '%b' "\nhomebrew version installed :\n$(brew --version)\n\n"
}

if [ -z "$(xcode-select -p 2>/dev/null)" ]; then
  while true; do
    printf "\nYou need Command Line Tools to run this script. Do you wish to install Command Line Tools? "
    read -r yn
    case $yn in
      [Yy]*)
        install_clt
        break;;
      [Nn]*)
        exit;;
      *)
        printf "\nPlease answer yes or no.\n";;
    esac
  done
fi

# Homebrew may be installed but off PATH (Apple Silicon, /opt/homebrew).
load_homebrew_env
if ! command -v brew &>/dev/null; then
  while true; do
    printf "You need homebrew to run this script. Do you wish to install homebrew? "
    read -r yn
    case $yn in
      [Yy]*)
        install_homebrew_and_report
        break;;
      [Nn]*)
        exit;;
      *)
        printf "\nPlease answer y or n.\n";;
    esac
  done
fi


# Settings
printf '%b' "\nScript settings:
  -> install ${red}full setup${no_color}: ${red}$FULL_MODE_SETUP${no_color}
  -> install ${red}[ai]${no_color} profile: ${red}$INSTALL_AI${no_color}
  -> install ${red}[base]${no_color} profile: ${red}$INSTALL_BASE${no_color}
  -> install ${red}[extras]${no_color} profile: ${red}$INSTALL_EXTRAS${no_color}
  -> install ${red}[javascript]${no_color} profile: ${red}$INSTALL_JAVASCRIPT${no_color}
  -> install ${red}[python]${no_color} profile: ${red}$INSTALL_PYTHON${no_color}\n"

export FULL_MODE_SETUP=$FULL_MODE_SETUP
export HOMEBREW_NO_AUTO_UPDATE=1

# Update brew once
printf '%b' "\n${red}${i}.${no_color} Update homebrew\n\n"
brew update --verbose || printf '%b' "\n${red}[warning]${no_color} brew update failed (non-fatal), continuing with existing index...\n\n"
i=$(($i + 1))

# Install formula, skipping already-managed ones
install_formula() {
  if brew list --formula "$1" &>/dev/null; then
    printf '%b' "${red}[brew]${no_color} $1 already installed — skipping.\n"
  else
    brew install --formula "$1"
  fi
}

# Install common
printf '%b' "\n${red}${i}.${no_color} Install commons\n\n"
for pkg in ca-certificates curl gnupg gsed gzip jq unzip wget xz; do
  install_formula "$pkg"
done
i=$(($i + 1))

# Install oh-my-zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  printf '%b' "\n${red}${i}.${no_color} Install oh-my-zsh\n\n"
  i=$(($i + 1))

  # Cloned at a pinned commit, no installer script (os/helpers/oh-my-zsh.sh).
  # shellcheck source=../helpers/oh-my-zsh.sh
  source "$HELPERS_DIR/oh-my-zsh.sh"
  install_oh_my_zsh
fi


# Install base profile
if [[ "$INSTALL_BASE" = "true" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Install base profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-base.sh"

  # Install proto (pinned release, SHA-256 checked) and configure shell integration
  bash "$HELPERS_DIR/proto.sh"
fi


# Install extras profile
if [[ "$INSTALL_EXTRAS" = "true" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Install extras profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-extras.sh"
fi


# Shared symlink helpers (backup_if_exists, link_with_backup, link_shared_configs)
# shellcheck source=../helpers/links.sh
source "$HELPERS_DIR/links.sh"

# Proto for the toolchain profiles
# setup-javascript.sh and setup-python.sh install through proto, at the
# versions pinned in ~/.proto/.prototools: both must be there first, even
# without the base profile (proto.sh skips an existing install) and before the
# dotfiles step links the rest.
if [[ "$INSTALL_JAVASCRIPT" = "true" || "$INSTALL_PYTHON" = "true" ]]; then
  bash "$HELPERS_DIR/proto.sh"
  mkdir -p "$HOME/.proto"
  link_with_backup "$CONFIG_DIR/proto/.prototools" "$HOME/.proto/.prototools"
fi


# Install javascript profile
if [[ "$INSTALL_JAVASCRIPT" = "true" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Install javascript profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-javascript.sh"
fi


# Install python profile
if [[ "$INSTALL_PYTHON" = "true" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Install python profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-python.sh"
fi


# Install ai profile
if [[ "$INSTALL_AI" = "true" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Install ai profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-ai.sh"
fi


# Shared "link dotfiles" post-steps (create_allowed_signers, create_local_stubs,
# install_vscode_config) — kept in sync with os/debian/init.sh.
# shellcheck source=../helpers/dotfiles.sh
source "$HELPERS_DIR/dotfiles.sh"

# Link dotfiles
if [[ "$COPY_DOTFILES" = "true" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Link dotfiles\n\n"
  i=$(($i + 1))

  mkdir -p "$HOME/.config"
  backup_if_exists "$HOME/.zshrc"
  # .zshrc needs machine-specific edits (sed alias, brew paths) so we copy instead of symlink
  cp "$CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc" && gsed -i 's/^# alias sed=.*/alias sed="gsed"/g' "$HOME/.zshrc"
  link_shared_configs "$CONFIG_DIR"

  # SSH allowed_signers, per-machine override stubs, and VS Code config — shared
  # with os/debian/init.sh via os/helpers/dotfiles.sh.
  create_allowed_signers
  create_local_stubs
  install_vscode_config "$CONFIG_DIR" "$HOME/Library/Application Support/Code/User"

  # Update brew links if architecture is arm64
  if [ "$(uname -m)" = "arm64" ] || [ "$(uname -m)" = "aarch64" ]; then
    gsed -i 's/\/usr\/local/\/opt\/homebrew/g' "$HOME/.zshrc"
  fi
fi


# Install cli completions
if [[ "$INSTALL_COMPLETIONS" = "true" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Install cli completions\n\n"
  i=$(($i + 1))

  bash "$HELPERS_DIR/completions.sh"
  # Shared with the other init script (os/helpers/oh-my-zsh.sh).
  # shellcheck source=../helpers/oh-my-zsh.sh
  source "$HELPERS_DIR/oh-my-zsh.sh"
  setup_zsh_completions
fi
