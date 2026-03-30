# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Directory for the Zinit plugin manager
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.config}/zinit/zinit.git"

# Download Zinit if it is not there yet.
if [ ! -d "$ZINIT_HOME" ]; then
    mkdir -p "$(dirname $ZINIT_HOME)"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source/Load Zinit
source "${ZINIT_HOME}/zinit.zsh"

# Enable manually installed fzf. Zypper installs an older version
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Add in PowerLevel10K
zinit ice depth=1; zinit light romkatv/powerlevel10k

# Add zsh-syntax highlight, autocomplete, autosuggestion
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# Add in snippets
zinit snippet OMZP::git

# Load completions
autoload -U compinit && compinit

zinit cdreplay -q

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Keybindings
bindkey -e
bindkey '^p' history-search-backward
bindkey '^n' history-search-forward

# Workaround for broken Ctrl+-> and CTRL+<-
bindkey "^[[1;5C" forward-word
bindkey "^[[1;5D" backward-word

# workaround for broke alt+-> and alt+<-
bindkey "^[[1;3C" forward-word
bindkey "^[[1;3D" backward-word

# Tag to accept auto-suggestions
bindkey '^I' autosuggest-accept

# History
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# Completion styling
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

# Aliases
alias ls='ls --color'
alias enw="emacs -nw"
alias tmux_attach="tmux a -t"

FPATH=~/.my_zsh_functions:$FPATH
autoload -Uz split_file
autoload -Uz wd
autoload -Uz ws_remind

export EDITOR="/usr/bin/emacs -nw"
export VISUAL="/usr/bin/emacs -nw"
export PATH="$PATH:/home/cyc/centos8_tools/bin"
path+=('/home/cyc/.local/bin')

# Shell integrations
eval "$(fzf --zsh)"
eval "$(zoxide init --cmd cd zsh)"

# Based on https://medium.com/@hitechluddite/ditch-cleartext-secrets-how-to-safeguard-api-keys-in-zsh-and-bash-with-pass-77f694b9ff64
export CONFLUENCE_TOKEN=$(pass show confluence/pat)
export JIRA_TOKEN=$(pass show jira/pat)
export GITHUB_TOKEN=$(pass show gh/pat)
export JENKINS_TOKEN=$(pass show jenkins/pat)

# Show workspace branches on SSH login
if [[ -n "$SSH_CONNECTION" ]]; then
  echo "Workspaces:"
  ws_remind
fi
