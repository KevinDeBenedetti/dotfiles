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
# Using a permanent location (not mktemp) ensures that symlinks created by the install script
# remain valid across reboots — macOS wipes per-user temp dirs (/var/folders/.../T/) on logout.
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
REMOVE_TMP_CONTENT="false"
FULL_MODE_SETUP="true"

# Declare script helper
TEXT_HELPER="\nThis script aims to install a full setup for osx.
Following flags are available:

  -a    Full install: enables all profiles (ai, base, extras, javascript, python),
        copies dotfiles, installs completions and removes tmp files.

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

  -r    Remove all tmp files after installation.

  -h    Print script help.\n\n"

print_help() {
  printf "$TEXT_HELPER"
}

# Parse options
while getopts hacdlp:r flag; do
  case "${flag}" in
    a)
      INSTALL_AI="true"
      INSTALL_BASE="true"
      INSTALL_EXTRAS="true"
      INSTALL_JAVASCRIPT="true"
      INSTALL_PYTHON="true"
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
      [[ ",$OPTARG," =~ ",ai," ]] && INSTALL_AI="true"
      [[ ",$OPTARG," =~ ",base," ]] && INSTALL_BASE="true"
      [[ ",$OPTARG," =~ ",extras," ]] && INSTALL_EXTRAS="true"
      [[ ",$OPTARG," =~ ",javascript," ]] && INSTALL_JAVASCRIPT="true"
      [[ ",$OPTARG," =~ ",python," ]] && INSTALL_PYTHON="true";;
    r)
      REMOVE_TMP_CONTENT="true";;
    h | *)
      print_help
      exit 0;;
  esac
done

# Warn if no profile or action flag was provided
if [[ "$INSTALL_AI" = "false" && "$INSTALL_BASE" = "false" && "$INSTALL_EXTRAS" = "false" \
   && "$INSTALL_JAVASCRIPT" = "false" && "$INSTALL_PYTHON" = "false" \
   && "$COPY_DOTFILES" = "false" && "$INSTALL_COMPLETIONS" = "false" \
   && "$REMOVE_TMP_CONTENT" = "false" ]]; then
  printf "\n${red}[warning]${no_color} No profile or action flag provided. Nothing to do.\n"
  print_help
  exit 1
fi

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
  -> install ${red}[ai]${no_color} profile: ${red}$INSTALL_AI${no_color}
  -> install ${red}[base]${no_color} profile: ${red}$INSTALL_BASE${no_color}
  -> install ${red}[extras]${no_color} profile: ${red}$INSTALL_EXTRAS${no_color}
  -> install ${red}[javascript]${no_color} profile: ${red}$INSTALL_JAVASCRIPT${no_color}
  -> install ${red}[python]${no_color} profile: ${red}$INSTALL_PYTHON${no_color}\n"

export FULL_MODE_SETUP=$FULL_MODE_SETUP
export HOMEBREW_NO_AUTO_UPDATE=1

# Update brew once
printf "\n${red}${i}.${no_color} Update homebrew\n\n"
brew update --verbose || printf "\n${red}[warning]${no_color} brew update failed (non-fatal), continuing with existing index...\n\n"
i=$(($i + 1))

# Install formula, skipping already-managed ones
install_formula() {
  if brew list --formula "$1" &>/dev/null; then
    printf "${red}[brew]${no_color} $1 already installed — skipping.\n"
  else
    brew install --formula "$1"
  fi
}

# Install common
printf "\n${red}${i}.${no_color} Install commons\n\n"
for pkg in ca-certificates curl gnupg gsed gzip jq unzip wget xz; do
  install_formula "$pkg"
done
i=$(($i + 1))

# Install oh-my-zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  printf "\n${red}${i}.${no_color} Install oh-my-zsh\n\n"
  i=$(($i + 1))

  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi


# Install base profile
if [[ "$INSTALL_BASE" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install base profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-base.sh"

  # Configure proto proxies
  bash "$HELPERS_DIR/proto.sh"
fi


# Install extras profile
if [[ "$INSTALL_EXTRAS" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install extras profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-extras.sh"
fi


# Install javascript profile
if [[ "$INSTALL_JAVASCRIPT" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install javascript profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-javascript.sh"
fi


# Install python profile
if [[ "$INSTALL_PYTHON" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install python profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-python.sh"
fi


# Install ai profile
if [[ "$INSTALL_AI" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Install ai profile\n\n"
  i=$(($i + 1))

  bash "$SCRIPT_PATH/setup-ai.sh"
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
  # .zshrc needs machine-specific edits (sed alias, brew paths) so we copy instead of symlink
  cp "$CONFIG_DIR/zsh/.zshrc" "$HOME/.zshrc" && gsed -i 's/^# alias sed=.*/alias sed="gsed"/g' "$HOME/.zshrc"
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
  # These files are gitignored — safe to fill in per-machine without touching the repo
  if [ ! -f "$HOME/.zshrc.local" ]; then
    cat > "$HOME/.zshrc.local" <<'EOF'
# Machine-specific zsh overrides — not tracked by git
# Add aliases, exports, path additions, etc. specific to this machine.
# This file is sourced at the end of .zshrc and always wins.

# Example:
# export MY_WORK_TOKEN="secret"
# alias myserver="ssh me@192.168.1.1"
EOF
    printf "${red}[local]${no_color} Created stub: ~/.zshrc.local\n"
  fi

  if [ ! -f "$HOME/.gitconfig.local" ]; then
    cat > "$HOME/.gitconfig.local" <<'EOF'
# Machine-specific git overrides — not tracked by git
# Overrides values from .gitconfig (user.email, signingkey, etc.)

# Uncomment and fill in to override the shared .gitconfig:
# [user]
# 	email = you@example.com
# 	signingkey = ~/.ssh/id_ed25519.pub
EOF
    printf "${red}[local]${no_color} Created stub: ~/.gitconfig.local\n"
  fi

  if [ ! -f "$HOME/.config/dotfiles/env.local.sh" ]; then
    mkdir -p "$HOME/.config/dotfiles"
    cat > "$HOME/.config/dotfiles/env.local.sh" <<'EOF'
# Machine-specific environment variables — not tracked by git
# Overrides / supplements env.sh values for this machine.
# Sourced automatically at the end of .zshrc.

# Set your Context7 API key — used by the Copilot CLI MCP config (~/.copilot/mcp-config.json)
# Get your key at: https://context7.com
# export CONTEXT7_API_KEY="your-real-key-here"
EOF
    printf "${red}[local]${no_color} Created stub: ~/.config/dotfiles/env.local.sh\n"
  fi

  # Configure proto proxies
  bash "$HELPERS_DIR/proto.sh"


  # Install .vscode configs
  if [ -x "$(command -v code)" ]; then
    mkdir -p "$HOME/Library/Application Support/Code/User"
    backup_if_exists "$HOME/Library/Application Support/Code/User/settings.json"
    ln -sf "$CONFIG_DIR/vscode/settings.json" "$HOME/Library/Application Support/Code/User/settings.json"
    backup_if_exists "$HOME/Library/Application Support/Code/User/mcp.json"
    ln -sf "$CONFIG_DIR/vscode/mcp.json" "$HOME/Library/Application Support/Code/User/mcp.json"
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


  # Update brew links if architecture is arm64
  if [ "$(uname -m)" = "arm64" ] || [ "$(uname -m)" = "aarch64" ]; then
    gsed -i 's/\/usr\/local/\/opt\/homebrew/g' "$HOME/.zshrc"
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
    gsed -i 's|^# fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src|fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src|g' "$HOME/.zshrc"
  fi
fi


if [[ "$REMOVE_TMP_CONTENT" = "true" ]]; then
  printf "\n${red}${i}.${no_color} Remove tmp files\n\n"
  i=$(($i + 1))
  # Nothing to clean up — the bootstrap now clones to ~/.dotfiles (permanent),
  # so there is no temporary directory to remove.
  printf "${red}[cleanup]${no_color} No temporary files to remove.\n"
fi
