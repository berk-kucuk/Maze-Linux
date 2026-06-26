# Maze Linux zsh theme — oh-my-zsh's "arch-linux" prompt with the logo removed.
# Prompt:  user@host ~/path/ [git-branch]      with  [HH:MM:SS]  on the right.
# No glyph/logo on the left — the prompt starts straight at user@host.

autoload -Uz vcs_info
zstyle ':vcs_info:*' check-for-changes true
zstyle ':vcs_info:*' unstagedstr '%F{red}*'   # unstaged changes
zstyle ':vcs_info:*' stagedstr '%F{yellow}+'  # staged changes
zstyle ':vcs_info:*' actionformats '%F{5}[%F{2}%b%F{3}|%F{1}%a%c%u%F{5}]%f '
zstyle ':vcs_info:*' formats '%F{5}[%F{2}%b%c%u%F{5}]%f '
zstyle ':vcs_info:svn:*' branchformat '%b'
zstyle ':vcs_info:svn:*' actionformats '%F{5}[%F{2}%b%F{1}:%F{3}%i%F{3}|%F{1}%a%c%u%F{5}]%f '
zstyle ':vcs_info:svn:*' formats '%F{5}[%F{2}%b%F{1}:%F{3}%i%c%u%F{5}]%f '
zstyle ':vcs_info:*' enable git cvs svn

theme_precmd () {
  vcs_info
}

setopt prompt_subst
PROMPT='%n@%m %~/ %{$reset_color%}${vcs_info_msg_0_}%{$reset_color%}'
RPROMPT='%{$fg[white]%}[%*]%{$reset_color%}'
autoload -U add-zsh-hook
add-zsh-hook precmd theme_precmd

# Berk Kucuk
