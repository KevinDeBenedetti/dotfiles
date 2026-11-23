#!/bin/bash
# =============================================================================
# setup-user.sh — Create a non-root sudo user and copy root's SSH access.
# Called by init.sh when the -u USER flag is provided, or sourced directly.
#
# Environment variables:
#   CREATE_USER         Username to create (required)
#   SSH_NOPASSWD        Grant passwordless sudo — true|false (default: false)
#   COPY_ROOT_SSH_KEY   Add the keys of /root/.ssh/authorized_keys to the new
#                       user's, keeping its own (default: true)
#   SUDO                sudo prefix, e.g. "sudo" (default: empty = running as root)
#
# NOTE: the user is created with --disabled-password (key-only login). When
# SSH_NOPASSWD is not "true", sudo will prompt for a password the account does
# not have, so the user cannot escalate until you run `sudo passwd <user>`.
# setup-security.sh keeps root login (key only) until then: set a password OR
# pass SSH_NOPASSWD=true, then re-run it to turn root login off.
# =============================================================================

set -euo pipefail

_SETUP_USER_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 || exit 1 ; pwd -P )"

# Source shared logging helper if available, otherwise define minimal fallback
if [[ -f "${_SETUP_USER_DIR}/../helpers/log.sh" ]]; then
  source "${_SETUP_USER_DIR}/../helpers/log.sh"
else
  red='\e[0;31m'; no_color='\033[0m'
fi

SUDO="${SUDO:-}"
CREATE_USER="${CREATE_USER:?'[setup-user] CREATE_USER must be set'}"
SSH_NOPASSWD="${SSH_NOPASSWD:-false}"
COPY_ROOT_SSH_KEY="${COPY_ROOT_SSH_KEY:-true}"

# The name ends up in a path (/home/<user>, /etc/sudoers.d/<user>) and in a
# sudoers rule. sudo silently skips sudoers.d files whose name has a dot, so
# a name like "first.last" would get no sudo at all. Debian's default
# NAME_REGEX, minus the dot.
if [[ ! "$CREATE_USER" =~ ^[a-z][-a-z0-9_]*$ ]]; then
  printf '%b' "${red}[error]${no_color} Invalid user name '${CREATE_USER}': use lowercase letters, digits, '-' and '_' (no dots), starting with a letter.\n" >&2
  exit 1
fi

printf '%b' "\n\n${red}[user] =>${no_color} Create user '${CREATE_USER}'\n\n"

# Create user if it doesn't exist
if ! id "${CREATE_USER}" &>/dev/null; then
  $SUDO adduser "${CREATE_USER}" --disabled-password --gecos ""
else
  printf '%b' "${red}[user]${no_color} User '${CREATE_USER}' already exists — skipping creation.\n"
fi

# Add to sudo group
$SUDO usermod -aG sudo "${CREATE_USER}"

# Copy root's authorized_keys so the same SSH key works for the new user
if [[ "${COPY_ROOT_SSH_KEY}" == "true" ]]; then
  # Through $SUDO, like the copy: /root is mode 700, so a sudo user running
  # this script cannot see the file itself.
  if $SUDO test -f /root/.ssh/authorized_keys; then
    # The home the passwd database gives, which is not always /home/<user>.
    user_home=$(getent passwd "${CREATE_USER}" | cut -d: -f6)
    user_home="${user_home:-/home/${CREATE_USER}}"
    user_keys="${user_home}/.ssh/authorized_keys"
    $SUDO mkdir -p "${user_home}/.ssh"
    $SUDO touch "$user_keys"
    # Root's keys are added to the user's, never copied over them: on a re-run,
    # the keys the user added since stay. A file saved without a final newline
    # gets one first, so the next key does not land on its last line.
    if $SUDO test -s "$user_keys" && [ -n "$($SUDO tail -c 1 "$user_keys")" ]; then
      echo | $SUDO tee -a "$user_keys" > /dev/null
    fi
    added=0
    # `|| [ -n "$key" ]`: a last key with no final newline counts too; the CR
    # of a file saved on Windows is dropped, or the key would never match.
    while IFS= read -r key || [ -n "$key" ]; do
      key="${key%$'\r'}"
      [[ -z "$key" || "$key" == \#* ]] && continue
      if ! $SUDO grep -qxF -- "$key" "$user_keys"; then
        printf '%s\n' "$key" | $SUDO tee -a "$user_keys" > /dev/null
        added=$((added + 1))
      fi
    done < <($SUDO cat /root/.ssh/authorized_keys)
    $SUDO chown -R "${CREATE_USER}:${CREATE_USER}" "${user_home}/.ssh"
    $SUDO chmod 700 "${user_home}/.ssh"
    $SUDO chmod 600 "$user_keys"
    printf '%b' "${red}[user]${no_color} SSH authorized_keys: ${added} key(s) from root added, the user's own kept.\n"
  else
    printf '%b' "${red}[user]${no_color} /root/.ssh/authorized_keys not found — skipping key copy.\n"
  fi
fi

# Grant passwordless sudo (required for non-interactive provisioning, e.g. k3s install)
if [[ "${SSH_NOPASSWD}" == "true" ]]; then
  # Written to a temp file and checked with visudo first: a sudoers.d file
  # with a syntax error makes sudo refuse to run for everyone.
  sudoers_tmp=$(mktemp)
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "${CREATE_USER}" > "$sudoers_tmp"
  if ! $SUDO visudo -cqf "$sudoers_tmp"; then
    rm -f "$sudoers_tmp"
    printf '%b' "${red}[error]${no_color} Generated sudoers rule failed visudo validation — not installing it.\n" >&2
    exit 1
  fi
  $SUDO install -m 0440 -o root -g root "$sudoers_tmp" "/etc/sudoers.d/${CREATE_USER}"
  rm -f "$sudoers_tmp"
  printf '%b' "${red}[user]${no_color} NOPASSWD sudo granted via /etc/sudoers.d/${CREATE_USER}.\n"
else
  # The user was created with --disabled-password and is in the sudo group, but
  # sudo prompts for a password the account does not have — so it can never
  # escalate until one is set. setup-security.sh keeps root login (key only)
  # until it can (can_escalate), so admin access is not lost, but root stays
  # the way in. Warn loudly and tell the operator how to fix.
  printf '%b' "${red}[warning]${no_color} '${CREATE_USER}' has no password and cannot run sudo yet.\n"
  printf '%b' "${red}[warning]${no_color} Set one with: ${red}sudo passwd ${CREATE_USER}${no_color} (or re-run with SSH_NOPASSWD=true for passwordless sudo).\n"
fi

printf '%b' "${red}[user]${no_color} ✅ User '${CREATE_USER}' ready.\n"
