#!/bin/bash

set -euo pipefail

# Colorize terminal
red='\e[0;31m'
no_color='\033[0m'

# Console step increment
i=1

# Get project directories
SCRIPT_PATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
REPO_ROOT="$( cd -- "$SCRIPT_PATH/../.." >/dev/null 2>&1 ; pwd -P )"
CONFIG_DIR="$REPO_ROOT/config"
HELPERS_DIR="$REPO_ROOT/os/helpers"

# Remote execution support: if sub-scripts are missing (e.g. running via "bash <(curl ...)"),
# clone the whole repo to a permanent directory and re-exec from there with the same
# arguments. Mirrors os/macos/init.sh — a full clone can't silently miss a newly-added
# sourced script the way the old hand-maintained curl file list could.
REPO_URL="https://github.com/KevinDeBenedetti/dotfiles.git"
DOTFILES_INSTALL_DIR="${DOTFILES_INSTALL_DIR:-$HOME/.dotfiles}"
if [ ! -f "$SCRIPT_PATH/setup-base.sh" ]; then
  # git is not guaranteed on a fresh Debian host (it's installed later by this
  # script) — install it first so the clone below can run.
  if ! command -v git >/dev/null 2>&1; then
    printf '%b' "\n${red}[bootstrap]${no_color} git not found — installing it before cloning...\n\n"
    _BOOTSTRAP_SUDO=""
    [ "$(id -u)" -ne 0 ] && _BOOTSTRAP_SUDO="sudo"
    $_BOOTSTRAP_SUDO apt-get update -qq
    $_BOOTSTRAP_SUDO apt-get install -y --no-install-recommends git
  fi

  if [ -d "$DOTFILES_INSTALL_DIR/.git" ]; then
    printf '%b' "\n${red}[bootstrap]${no_color} Dotfiles repo found at $DOTFILES_INSTALL_DIR — pulling latest...\n\n"
    git -C "$DOTFILES_INSTALL_DIR" pull --ff-only || printf '%b' "${red}[bootstrap]${no_color} Pull failed (non-fatal), using existing checkout.\n"
  else
    printf '%b' "\n${red}[bootstrap]${no_color} Sub-scripts not found locally — cloning dotfiles repository to $DOTFILES_INSTALL_DIR...\n\n"
    git clone --depth=1 "$REPO_URL" "$DOTFILES_INSTALL_DIR"
  fi

  exec bash "$DOTFILES_INSTALL_DIR/os/debian/init.sh" "$@"
fi

# Default
INSTALL_BASE="false"
INSTALL_KUBERNETES="false"
INSTALL_SECURITY="false"
INSTALL_COMPLETIONS="false"
COPY_DOTFILES="false"
REMOVE_TMP_CONTENT="false"
FULL_MODE_SETUP="true"

# Security options (used by setup-security.sh)
SSH_PORT="${SSH_PORT:-22}"

# User creation options (used by setup-user.sh via -u flag)
CREATE_USER="${CREATE_USER:-}"
SSH_NOPASSWD="${SSH_NOPASSWD:-false}"
COPY_ROOT_SSH_KEY="${COPY_ROOT_SSH_KEY:-true}"
SSH_ALLOWED_USERS="${SSH_ALLOWED_USERS:-}"

# Declare script helper
TEXT_HELPER="\nThis script aims to install a full setup for a Debian VPS.
Following flags are available:

  -a    Full install: enables all profiles (base, kubernetes, security),
        copies dotfiles, installs completions and removes tmp files.

  -c    Install cli completions.

  -d    Copy dotfiles.

  -l    Run with lite mode, only major tools will be installed.

  -p    Install additional packages according to the given profile, available profiles are :
          -> 'base'
          -> 'kubernetes'
          -> 'security'
        Default is no profile, this flag can be used with a CSV list (ex: -p \"base,kubernetes,security\").

  -r    Remove all tmp files after installation.

  -u USER  Create a non-root sudo user before security hardening.
           Copies /root/.ssh/authorized_keys to the new user.
           Set SSH_NOPASSWD=true to grant passwordless sudo (needed for remote provisioning).

  Environment variables (set before running):
    SSH_PORT=2222          Custom SSH port (default: 22)
    SSH_ALLOWED_USERS=bob  Space-separated list of users allowed to SSH in
    SSH_NOPASSWD=true      Grant NOPASSWD sudo to the user created via -u (default: false)
    COPY_ROOT_SSH_KEY=true Copy root authorized_keys to new user (default: true)
  -h    Print script help.\n\n"

print_help() {
  printf '%b' "$TEXT_HELPER"
}

# Parse options
while getopts hacdlp:ru: flag; do
  case "${flag}" in
    a)
      INSTALL_BASE="true"
      INSTALL_KUBERNETES="true"
      INSTALL_SECURITY="true"
      INSTALL_COMPLETIONS="true"
      COPY_DOTFILES="true"
      REMOVE_TMP_CONTENT="true";;
    c)
      INSTALL_COMPLETIONS="true";;
    d)
      COPY_DOTFILES="true";;
    l)
      FULL_MODE_SETUP="false";;
    p)
      [[ ",$OPTARG," =~ ",base," ]] && INSTALL_BASE="true"
      [[ ",$OPTARG," =~ ",kubernetes," ]] && INSTALL_KUBERNETES="true"
      [[ ",$OPTARG," =~ ",security," ]] && INSTALL_SECURITY="true";;
    r)
      REMOVE_TMP_CONTENT="true";;
    u)
      CREATE_USER="${OPTARG}";;
    h | *)
      print_help
      exit 0;;
  esac
done

# Warn if no profile or action flag was provided
if [[ "$INSTALL_BASE" = "false" && "$INSTALL_KUBERNETES" = "false" \
   && "$INSTALL_SECURITY" = "false" \
   && "$COPY_DOTFILES" = "false" && "$INSTALL_COMPLETIONS" = "false" \
   && "$REMOVE_TMP_CONTENT" = "false" && -z "${CREATE_USER:-}" ]]; then
  printf '%b' "\n${red}[warning]${no_color} No profile or action flag provided. Nothing to do.\n"
  print_help
  exit 1
fi

# Ensure running as root or with sudo
if [ "$(id -u)" -ne 0 ] && ! command -v sudo &>/dev/null; then
  printf '%b' "\n${red}[error]${no_color} This script requires root privileges or sudo.\n"
  exit 1
fi

# Use sudo if not root
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

# Settings
printf '%b' "\nScript settings:
  -> install ${red}full setup${no_color}: ${red}$FULL_MODE_SETUP${no_color}
  -> install ${red}[base]${no_color} profile: ${red}$INSTALL_BASE${no_color}
  -> install ${red}[kubernetes]${no_color} profile: ${red}$INSTALL_KUBERNETES${no_color}
  -> install ${red}[security]${no_color} profile: ${red}$INSTALL_SECURITY${no_color}\n"

export FULL_MODE_SETUP=$FULL_MODE_SETUP
export SUDO=$SUDO
export SSH_PORT=$SSH_PORT
export SSH_ALLOWED_USERS=$SSH_ALLOWED_USERS
export CREATE_USER=${CREATE_USER:-}
export SSH_NOPASSWD=${SSH_NOPASSWD:-false}
export COPY_ROOT_SSH_KEY=${COPY_ROOT_SSH_KEY:-true}

# Update apt
printf '%b' "\n${red}${i}.${no_color} Update apt\n\n"
$SUDO apt-get update -qq || printf '%b' "\n${red}[warning]${no_color} apt update failed (non-fatal), continuing...\n\n"
i=$(($i + 1))

# Apply security upgrades
printf '%b' "\n${red}${i}.${no_color} Apply security upgrades\n\n"
$SUDO apt-get upgrade -y --no-install-recommends || printf '%b' "\n${red}[warning]${no_color} apt upgrade failed (non-fatal), continuing...\n\n"
i=$(($i + 1))

# Install common
printf '%b' "\n${red}${i}.${no_color} Install commons\n\n"
$SUDO apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  gzip \
  jq \
  unzip \
  wget \
  xz-utils \
  git \
  build-essential
i=$(($i + 1))

# Install oh-my-zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  printf '%b' "\n${red}${i}.${no_color} Install oh-my-zsh\n\n"
  i=$(($i + 1))

  $SUDO apt-get install -y --no-install-recommends zsh
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi


# Install base profile
if [[ "$INSTALL_BASE" = "true" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Install base profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-base.sh"

  # Configure proto proxies
  bash "$HELPERS_DIR/proto.sh"
fi


# Create non-root user if requested (must run BEFORE security disables root login)
if [[ -n "${CREATE_USER:-}" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Create user '${CREATE_USER}'\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-user.sh"
fi


# Install kubernetes profile
if [[ "$INSTALL_KUBERNETES" = "true" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Install kubernetes profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-kubernetes.sh"
fi


# Install security profile
if [[ "$INSTALL_SECURITY" = "true" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Install security profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-security.sh"
fi


# Shared symlink helpers (backup_if_exists, link_with_backup, link_shared_configs)
# shellcheck source=../helpers/links.sh
source "$HELPERS_DIR/links.sh"
# Shared "link dotfiles" post-steps (create_allowed_signers, create_local_stubs,
# install_vscode_config) — kept in sync with os/macos/init.sh.
# shellcheck source=../helpers/dotfiles.sh
source "$HELPERS_DIR/dotfiles.sh"

# Link dotfiles
if [[ "$COPY_DOTFILES" = "true" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Link dotfiles\n\n"
  i=$(($i + 1))

  mkdir -p "$HOME/.config"
  backup_if_exists "$HOME/.zshrc"
  cp "$CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc"
  link_shared_configs "$CONFIG_DIR"

  # SSH allowed_signers and per-machine override stubs — shared with
  # os/macos/init.sh via os/helpers/dotfiles.sh.
  create_allowed_signers
  create_local_stubs

  # Configure proto proxies
  bash "$HELPERS_DIR/proto.sh"

  # VS Code config (Linux user dir) — shared helper from dotfiles.sh.
  install_vscode_config "$CONFIG_DIR" "$HOME/.config/Code/User"
fi


# Install cli completions
if [[ "$INSTALL_COMPLETIONS" = "true" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Install cli completions\n\n"
  i=$(($i + 1))

  bash "$HELPERS_DIR/completions.sh"
  ZSH_COMP_PLUGIN="${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-completions"
  if [ ! -d "$ZSH_COMP_PLUGIN" ]; then
    git clone https://github.com/zsh-users/zsh-completions.git "$ZSH_COMP_PLUGIN"
  else
    printf '%b' "${red}[completions]${no_color} zsh-completions already present — skipping clone.\n"
  fi
  if ! grep -q 'fpath+=.*zsh-completions' "$HOME/.zshrc" 2>/dev/null; then
    sed -i 's|^# fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src|fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src|g' "$HOME/.zshrc"
  fi
fi


if [[ "$REMOVE_TMP_CONTENT" = "true" ]]; then
  printf '%b' "\n${red}${i}.${no_color} Remove tmp files\n\n"
  i=$(($i + 1))
  printf '%b' "${red}[cleanup]${no_color} No temporary files to remove.\n"
fi

printf '%b' "\n${red}Done!${no_color} Setup complete.\n\n"
