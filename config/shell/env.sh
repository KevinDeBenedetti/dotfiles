# Machine-specific secrets and env vars go in env.local.sh (not tracked by git)
# Example: export CONTEXT7_API_KEY="your-real-key"
[ -f "$HOME/.config/dotfiles/env.local.sh" ] && source "$HOME/.config/dotfiles/env.local.sh"
