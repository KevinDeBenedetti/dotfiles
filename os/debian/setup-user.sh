#!/bin/bash
# =============================================================================
# setup-user.sh — Create a non-root sudo user and copy root's SSH access.
# Called by init.sh when the -u USER flag is provided, or sourced directly.
#
# Environment variables:
#   CREATE_USER         Username to create (required)
#   SSH_NOPASSWD        Grant passwordless sudo — true|false (default: false)
#   COPY_ROOT_SSH_KEY   Copy /root/.ssh/authorized_keys to the new user (default: true)
#   SUDO                sudo prefix, e.g. "sudo" (default: empty = running as root)
# =============================================================================

_SETUP_USER_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

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

printf "\n\n${red}[user] =>${no_color} Create user '${CREATE_USER}'\n\n"

# Create user if it doesn't exist
if ! id "${CREATE_USER}" &>/dev/null; then
  $SUDO adduser "${CREATE_USER}" --disabled-password --gecos ""
else
  printf "${red}[user]${no_color} User '${CREATE_USER}' already exists — skipping creation.\n"
fi

# Add to sudo group
$SUDO usermod -aG sudo "${CREATE_USER}"

# Copy root's authorized_keys so the same SSH key works for the new user
if [[ "${COPY_ROOT_SSH_KEY}" == "true" ]]; then
  if [[ -f /root/.ssh/authorized_keys ]]; then
    $SUDO mkdir -p "/home/${CREATE_USER}/.ssh"
    $SUDO cp /root/.ssh/authorized_keys "/home/${CREATE_USER}/.ssh/authorized_keys"
    $SUDO chown -R "${CREATE_USER}:${CREATE_USER}" "/home/${CREATE_USER}/.ssh"
    $SUDO chmod 700 "/home/${CREATE_USER}/.ssh"
    $SUDO chmod 600 "/home/${CREATE_USER}/.ssh/authorized_keys"
    printf "${red}[user]${no_color} SSH authorized_keys copied from root.\n"
  else
    printf "${red}[user]${no_color} /root/.ssh/authorized_keys not found — skipping key copy.\n"
  fi
fi

# Grant passwordless sudo (required for non-interactive provisioning, e.g. k3s install)
if [[ "${SSH_NOPASSWD}" == "true" ]]; then
  echo "${CREATE_USER} ALL=(ALL) NOPASSWD:ALL" | $SUDO tee "/etc/sudoers.d/${CREATE_USER}" > /dev/null
  $SUDO chmod 440 "/etc/sudoers.d/${CREATE_USER}"
  printf "${red}[user]${no_color} NOPASSWD sudo granted via /etc/sudoers.d/${CREATE_USER}.\n"
fi

printf "${red}[user]${no_color} ✅ User '${CREATE_USER}' ready.\n"
