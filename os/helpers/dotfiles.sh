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

# Create or update the SSH allowed_signers file so local commit signatures
# verify. The key is the one git signs with (user.signingkey: a path, or a
# literal `key::`/`ssh-…` key), else the first ~/.ssh/id_*.pub, ed25519 first.
# Only this key's line is replaced: the other signers in the file stay.
create_allowed_signers() {
  local allowed_signers="$HOME/.ssh/allowed_signers"
  local git_email configured key="" candidate key_id
  git_email=$(git config --global user.email 2>/dev/null || echo "contact@kevindb.dev")
  configured=$(git config --global user.signingkey 2>/dev/null || true)
  case "$configured" in
    "") ;;
    key::*) key="${configured#key::}" ;;
    ssh-* | ecdsa-* | sk-*) key="$configured" ;;
    *)
      # git also takes the private key's path: its .pub is the one to read,
      # never the private key itself.
      configured="${configured/#\~/$HOME}"
      [[ "$configured" == *.pub ]] || configured="$configured.pub"
      [ -f "$configured" ] && key=$(tr -d '\r' < "$configured" | tr -d '\n') ;;
  esac
  if [ -z "$key" ]; then
    for candidate in id_ed25519 id_ecdsa id_rsa; do
      if [ -f "$HOME/.ssh/$candidate.pub" ]; then
        key=$(tr -d '\r' < "$HOME/.ssh/$candidate.pub" | tr -d '\n')
        break
      fi
    done
  fi
  if [ -z "$key" ]; then
    printf '%b' "${red}[warning]${no_color} No SSH public key found — skipping allowed_signers setup.\n"
    return 0
  fi

  mkdir -p "$HOME/.ssh"
  # A line is this key's when it carries the same type and base64 blob, after
  # the principals and any options (namespaces="git", …).
  key_id=$(awk '{ print $1 " " $2 }' <<<"$key")
  {
    if [ -f "$allowed_signers" ]; then
      awk -v id="$key_id" '{ for (i = 2; i < NF; i++) if ($i " " $(i + 1) == id) next; print }' "$allowed_signers"
    fi
    printf '%s %s\n' "$git_email" "$key"
  } > "$allowed_signers.new"
  mv "$allowed_signers.new" "$allowed_signers"
  chmod 600 "$allowed_signers"
  printf '%b' "${red}[git]${no_color} SSH allowed_signers updated at $allowed_signers\n"
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

# Do NOT export API keys here: every process started from the shell inherits
# them, AI agents included, whatever their file-level secret rules say.
# The Context7 key is prompted for once by VS Code (config/vscode/mcp.json).
EOF
    printf '%b' "${red}[local]${no_color} Created stub: ~/.config/dotfiles/env.local.sh\n"
  fi
}

# Symlink the VS Code user config and install the recommended extensions.
# $1 = repo config/ dir, $2 = VS Code "User" dir (platform-specific).
install_vscode_config() {
  local config_dir="$1" user_dir="$2"
  command -v code >/dev/null 2>&1 || return 0

  # The links themselves live in links.sh, like every other config.
  mkdir -p "$user_dir"
  link_vscode_configs "$config_dir" "$user_dir"

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
