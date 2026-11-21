#!/usr/bin/env bash
# Tells the setup scripts whether the infra repository manages this node.
# Sourced, never executed.

# The sshd drop-in the infra repo's Ansible `common` role writes. Its presence
# means sshd, the firewall and the container runtime of the node are theirs.
# One definition for every step that steps aside; tests point it elsewhere.
INFRA_MARKER="${INFRA_MARKER:-/etc/ssh/sshd_config.d/00-infra-hardening.conf}"

is_infra_managed() {
  [[ -f "$INFRA_MARKER" ]]
}
