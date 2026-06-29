#!/usr/bin/env bash
# Shared "link dotfiles" post-steps — the single source of truth for the work
# that happens after configs are symlinked (link_shared_configs in links.sh).
# Sourced by the OS init scripts (os/macos/init.sh, os/debian/init.sh) so the
# two entry points cannot drift apart again.
#
# These functions reuse the caller's $red/$no_color (defined in each init
# script); the fallbacks below keep them safe if sourced standalone.
red="${red:-}"
no_color="${no_color:-}"

# Create the SSH allowed_signers file so local commit signatures verify.
create_allowed_signers() {
  local signing_key="$HOME/.ssh/id_rsa.pub"
  local allowed_signers="$HOME/.ssh/allowed_signers"
  local git_email
  git_email=$(git config --global user.email 2>/dev/null || echo "contact@kevindb.dev")
  if [ -f "$signing_key" ]; then
    mkdir -p "$HOME/.ssh"
    printf '%s %s\n' "$git_email" "$(tr -d '\r' < "$signing_key" | tr -d '\n')" > "$allowed_signers"
    chmod 600 "$allowed_signers"
    printf '%b' "${red}[git]${no_color} SSH allowed_signers file created at $allowed_signers\n"
  else
    printf '%b' "${red}[warning]${no_color} No SSH public key found — skipping allowed_signers setup.\n"
  fi
}

# Create the gitignored per-machine override stubs (only if they don't exist).
create_local_stubs() {
  if [ ! -f "$HOME/.zshrc.local" ]; then
    cat > "$HOME/.zshrc.local" <<'EOF'
# Machine-specific zsh overrides — not tracked by git
# Add aliases, exports, path additions, etc. specific to this machine.
# This file is sourced at the end of .zshrc and always wins.

# Example:
# export MY_WORK_TOKEN="secret"
# alias myserver="ssh me@192.168.1.1"
EOF
    printf '%b' "${red}[local]${no_color} Created stub: ~/.zshrc.local\n"
  fi

  if [ ! -f "$HOME/.gitconfig.local" ]; then
    cat > "$HOME/.gitconfig.local" <<'EOF'
# Machine-specific git overrides — not tracked by git
# Overrides values from .gitconfig (user.email, signingkey, etc.)

# Uncomment and fill in to override the shared .gitconfig:
# [user]
# 	email = you@example.com
# 	signingkey = ~/.ssh/id_rsa.pub
EOF
    printf '%b' "${red}[local]${no_color} Created stub: ~/.gitconfig.local\n"
  fi

  if [ ! -f "$HOME/.config/dotfiles/env.local.sh" ]; then
    mkdir -p "$HOME/.config/dotfiles"
    cat > "$HOME/.config/dotfiles/env.local.sh" <<'EOF'
# Machine-specific environment variables — not tracked by git
# Overrides / supplements env.sh values for this machine.
# Sourced automatically at the end of .zshrc.

# Set your Context7 API key — used by the VS Code MCP config (config/vscode/mcp.json)
# Get your key at: https://context7.com
# export CONTEXT7_API_KEY="your-real-key-here"
EOF
    printf '%b' "${red}[local]${no_color} Created stub: ~/.config/dotfiles/env.local.sh\n"
  fi
}

# Symlink the VS Code user config and install the recommended extensions.
# $1 = repo config/ dir, $2 = VS Code "User" dir (platform-specific).
install_vscode_config() {
  local config_dir="$1" user_dir="$2"
  command -v code >/dev/null 2>&1 || return 0

  mkdir -p "$user_dir"
  backup_if_exists "$user_dir/settings.json"
  ln -sf "$config_dir/vscode/settings.json" "$user_dir/settings.json"
  backup_if_exists "$user_dir/mcp.json"
  ln -sf "$config_dir/vscode/mcp.json" "$user_dir/mcp.json"

  local installed extension
  installed=$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]')
  while IFS= read -r extension; do
    if echo "$installed" | grep -qi "^${extension}$"; then
      printf '%b' "${red}[vscode]${no_color} $extension already installed — skipping.\n"
    else
      code --install-extension "$extension"
    fi
  done < <(grep -v '//' "$config_dir/vscode/extensions.json" \
    | grep -E '\S' \
    | jq -r '.recommendations[]')
}
