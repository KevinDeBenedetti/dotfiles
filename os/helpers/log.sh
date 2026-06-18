#!/usr/bin/env bash
# Shared logging helpers for dotfiles setup scripts.
# Source this file at the top of any setup script:
#   source "$(dirname "$0")/../helpers/log.sh"

# Colors (compatible with the $red/$no_color style used across setup-*.sh)
red='\e[0;31m'
green='\e[0;32m'
yellow='\e[1;33m'
cyan='\e[0;36m'
no_color='\033[0m'

# log_step SECTION MESSAGE — prints a section header (matches existing [tag] => style)
log_step() { printf '%b' "\n\n${red}[${1}] =>${no_color} ${2}\n\n"; }

# log_info / log_ok / log_warn / log_error — one-line status messages
log_info()  { printf '%b' "${cyan}[info]${no_color}   ${*}\n"; }
log_ok()    { printf '%b' "${green}[ok]${no_color}     ${*}\n"; }
log_warn()  { printf '%b' "${yellow}[warn]${no_color}    ${*}\n"; }
log_error() { printf '%b' "${red}[error]${no_color}   ${*}\n"; }
