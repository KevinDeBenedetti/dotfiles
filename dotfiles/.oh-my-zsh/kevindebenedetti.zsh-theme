# kevindebenedetti.zsh-theme
# A minimal prompt with git integration

# Colors
autoload -U colors && colors

# Prompt
PROMPT='%{$fg_bold[cyan]%}%c%{$reset_color%} $(git_prompt_info)%(?:%{$fg_bold[green]%}❯ :%{$fg_bold[red]%}❯ )%{$reset_color%}'

# Right prompt: timestamp
RPROMPT='%{$fg[240]%}%D{%H:%M}%{$reset_color%}'

# Git
ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg_bold[blue]%}(%{$fg[red]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%} "
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%}) %{$fg[yellow]%}✗"
ZSH_THEME_GIT_PROMPT_CLEAN="%{$fg[blue]%})"
