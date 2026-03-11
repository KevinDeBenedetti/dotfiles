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
# clone the repo to a permanent directory and re-exec from there with the same arguments.
REPO_URL="https://github.com/KevinDeBenedetti/dotfiles.git"
DOTFILES_INSTALL_DIR="${DOTFILES_INSTALL_DIR:-$HOME/.dotfiles}"
if [ ! -f "$SCRIPT_PATH/setup-base.sh" ]; then
  if [ -d "$DOTFILES_INSTALL_DIR/.git" ]; then
    printf "\n${red}[bootstrap]${no_color} Dotfiles repo found at $DOTFILES_INSTALL_DIR — pulling latest...\n\n"
    git -C "$DOTFILES_INSTALL_DIR" pull --ff-only || printf "${red}[bootstrap]${no_color} Pull failed (non-fatal), using existing checkout.\n"
  else
    printf "\n${red}[bootstrap]${no_color} Sub-scripts not found locally — cloning dotfiles repository to $DOTFILES_INSTALL_DIR...\n\n"
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
  Environment variables (set before running):
    SSH_PORT=2222          Custom SSH port (default: 22)
    SSH_ALLOWED_USERS=bob  Space-separated list of users allowed to SSH in
  -h    Print script help.\n\n"

print_help() {
  printf "$TEXT_HELPER"
}

# Parse options
while getopts hacdlp:r flag; do
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
    h | *)
      print_help
      exit 0;;
  esac
done

# Warn if no profile or action flag was provided
if [[ "$INSTALL_BASE" = "false" && "$INSTALL_KUBERNETES" = "false" \
   && "$INSTALL_SECURITY" = "false" \
   && "$COPY_DOTFILES" = "false" && "$INSTALL_COMPLETIONS" = "false" \
   && "$REMOVE_TMP_CONTENT" = "false" ]]; then
  printf "\n${red}[warning]${no_color} No profile or action flag provided. Nothing to do.\n"
  print_help
  exit 1
fi

# Ensure running as root or with sudo
if [ "$(id -u)" -ne 0 ] && ! command -v sudo &>/dev/null; then
  printf "\n${red}[error]${no_color} This script requires root privileges or sudo.\n"
  exit 1
fi

# Use sudo if not root
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

# Settings
printf "\nScript settings:
  -> install ${red}full setup${no_color}: ${red}$FULL_MODE_SETUP${no_color}
  -> install ${red}[base]${no_color} profile: ${red}$INSTALL_BASE${no_color}
  -> install ${red}[kubernetes]${no_color} profile: ${red}$INSTALL_KUBERNETES${no_color}
  -> install ${red}[security]${no_color} profile: ${red}$INSTALL_SECURITY${no_color}\n"

export FULL_MODE_SETUP=$FULL_MODE_SETUP
export SUDO=$SUDO
export SSH_PORT=$SSH_PORT
export SSH_ALLOWED_USERS=$SSH_ALLOWED_USERS

# Update apt
printf "\n${red}${i}.${no_color} Update apt\n\n"
$SUDO apt-get update -qq || printf "\n${red}[warning]${no_color} apt update failed (non-fatal), continuing...\n\n"
i=$(($i + 1))

# Apply security upgrades
printf "\n${red}${i}.${no_color} Apply security upgrades\n\n"
$SUDO apt-get upgrade -y --no-install-recommends || printf "\n${red}[warning]${no_color} apt upgrade failed (non-fatal), continuing...\n\n"
i=$(($i + 1))

# Install common
printf "\n${red}${i}.${no_color} Install commons\n\n"
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
  printf "\n${red}${i}.${no_color} Install oh-my-zsh\n\n"
  i=$(($i + 1))

  $SUDO apt-get install -y --no-install-recommends zsh
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi


# Install base profile
if [[ "$INSTALL_BASE" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install base profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-base.sh"

  # Configure proto proxies
  bash "$HELPERS_DIR/proto.sh"
fi


# Install kubernetes profile
if [[ "$INSTALL_KUBERNETES" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install kubernetes profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-kubernetes.sh"
fi


# Install security profile
if [[ "$INSTALL_SECURITY" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install security profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-security.sh"
fi


# Helper: backup a file if it exists and is not already a symlink to our dotfiles
backup_if_exists() {
  local target="$1"
  if [ -f "$target" ] && [ ! -L "$target" ]; then
    cp "$target" "${target}.bak.$(date +%Y%m%d)"
    printf "${red}[backup]${no_color} Backed up $target\n"
  fi
}

# Link dotfiles
if [[ "$COPY_DOTFILES" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Link dotfiles\n\n"
  i=$(($i + 1))

  mkdir -p "$HOME/.config"
  backup_if_exists "$HOME/.zshrc"
  cp "$CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc"
  THEME_SRC="$CONFIG_DIR/oh-my-zsh/kevin-de-benedetti.zsh-theme"
  if [ -f "$THEME_SRC" ]; then
    mkdir -p "$HOME/.oh-my-zsh/custom/themes"
    backup_if_exists "$HOME/.oh-my-zsh/custom/themes/kevin-de-benedetti.zsh-theme"
    ln -sf "$THEME_SRC" "$HOME/.oh-my-zsh/custom/themes/kevin-de-benedetti.zsh-theme"
  else
    printf "${red}[warning]${no_color} Theme file not found, skipping: $THEME_SRC\n"
  fi
  mkdir -p "$HOME/.proto"
  backup_if_exists "$HOME/.proto/.prototools"
  ln -sf "$CONFIG_DIR/proto/.prototools" "$HOME/.proto/.prototools"
  backup_if_exists "$HOME/.gitconfig"
  ln -sf "$CONFIG_DIR/git/.gitconfig" "$HOME/.gitconfig"
  # Symlink shell config files into ~/.config/dotfiles/
  mkdir -p "$HOME/.config/dotfiles"
  for item in "$CONFIG_DIR/shell/"*; do
    local_name=$(basename "$item")
    backup_if_exists "$HOME/.config/dotfiles/$local_name"
    ln -sf "$item" "$HOME/.config/dotfiles/$local_name"
  done

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

  # Create local override stubs if they don't already exist
  if [ ! -f "$HOME/.zshrc.local" ]; then
    cat > "$HOME/.zshrc.local" <<'EOF'
# Machine-specific zsh overrides — not tracked by git
# Add aliases, exports, path additions, etc. specific to this machine.
# This file is sourced at the end of .zshrc and always wins.
EOF
    printf "${red}[local]${no_color} Created stub: ~/.zshrc.local\n"
  fi

  if [ ! -f "$HOME/.gitconfig.local" ]; then
    cat > "$HOME/.gitconfig.local" <<'EOF'
# Machine-specific git overrides — not tracked by git
# Overrides values from .gitconfig (user.email, signingkey, etc.)
EOF
    printf "${red}[local]${no_color} Created stub: ~/.gitconfig.local\n"
  fi

  if [ ! -f "$HOME/.config/dotfiles/env.local.sh" ]; then
    mkdir -p "$HOME/.config/dotfiles"
    cat > "$HOME/.config/dotfiles/env.local.sh" <<'EOF'
# Machine-specific environment variables — not tracked by git
# Overrides / supplements env.sh values for this machine.
# Sourced automatically at the end of .zshrc.
EOF
    printf "${red}[local]${no_color} Created stub: ~/.config/dotfiles/env.local.sh\n"
  fi

  # Configure proto proxies
  bash "$HELPERS_DIR/proto.sh"

  # Install .vscode configs
  if [ -x "$(command -v code)" ]; then
    mkdir -p "$HOME/.config/Code/User"
    backup_if_exists "$HOME/.config/Code/User/settings.json"
    ln -sf "$CONFIG_DIR/vscode/settings.json" "$HOME/.config/Code/User/settings.json"
    backup_if_exists "$HOME/.config/Code/User/mcp.json"
    ln -sf "$CONFIG_DIR/vscode/mcp.json" "$HOME/.config/Code/User/mcp.json"
    INSTALLED_EXTENSIONS=$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')
    while IFS= read -r extension; do
      if echo "$INSTALLED_EXTENSIONS" | grep -qi "^${extension}$"; then
        printf "${red}[vscode]${no_color} $extension already installed — skipping.\n"
      else
        code --install-extension "$extension"
      fi
    done < <(grep -v '//' "$CONFIG_DIR/vscode/extensions.json" \
      | grep -E '\S' \
      | jq -r '.recommendations[]')
  fi
fi


# Install cli completions
if [[ "$INSTALL_COMPLETIONS" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install cli completions\n\n"
  i=$(($i + 1))

  bash "$HELPERS_DIR/completions.sh"
  ZSH_COMP_PLUGIN="${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions"
  if [ ! -d "$ZSH_COMP_PLUGIN" ]; then
    git clone https://github.com/zsh-users/zsh-completions.git "$ZSH_COMP_PLUGIN"
  else
    printf "${red}[completions]${no_color} zsh-completions already present — skipping clone.\n"
  fi
  if ! grep -q 'fpath+=.*zsh-completions' "$HOME/.zshrc" 2>/dev/null; then
    sed -i 's|^# fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src|fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src|g' "$HOME/.zshrc"
  fi
fi


if [[ "$REMOVE_TMP_CONTENT" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Remove tmp files\n\n"
  i=$(($i + 1))
  printf "${red}[cleanup]${no_color} No temporary files to remove.\n"
fi

printf "\n${red}Done!${no_color} Setup complete.\n\n"
