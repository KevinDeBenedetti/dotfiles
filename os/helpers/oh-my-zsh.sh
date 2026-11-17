#!/usr/bin/env bash
# Install oh-my-zsh and the zsh-completions plugin by cloning each at a pinned
# commit. No installer script is fetched or run. Sourced by the OS init
# scripts, never executed.

red="${red:-}"
no_color="${no_color:-}"

# shellcheck source=fetch.sh
source "$( cd -- "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P )/fetch.sh"

# install_oh_my_zsh
# Clone oh-my-zsh into ~/.oh-my-zsh at the commit pinned here (it ships no
# release tags). With its shell switch and .zshrc steps off, the official
# installer only clones the repository, and it clones whatever `master` holds.
# oh-my-zsh updates itself from master afterwards.
# To bump: read the changes since the commit below, then replace it:
#   https://github.com/ohmyzsh/ohmyzsh/compare/<commit>...master
install_oh_my_zsh() {
  # master on 2026-11-16.
  local commit="c0140703a53eb0d22be44f7bac318d0baacc927c"
  # oh-my-zsh.remote and oh-my-zsh.branch are what its updater reads.
  clone_at_commit oh-my-zsh https://github.com/ohmyzsh/ohmyzsh.git "$commit" "$HOME/.oh-my-zsh" \
    oh-my-zsh.remote=origin oh-my-zsh.branch=master
}

# install_zsh_completions <dest>
# Clone the zsh-completions plugin into <dest> at the commit pinned here; it is
# sourced by every shell, so its default branch is not taken as is.
# To bump: read the changes since the commit below, then replace it:
#   https://github.com/zsh-users/zsh-completions/compare/<commit>...master
install_zsh_completions() {
  # master on 2026-11-16 (last change 2026-10-16).
  local commit="989b23277ab33e8d5e82df6aed936e846db9d8b8"
  clone_at_commit zsh-completions https://github.com/zsh-users/zsh-completions.git "$commit" "$1"
}
