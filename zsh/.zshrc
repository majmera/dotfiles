# Load zsh functions
FPATH=~/.my_zsh_functions:$FPATH
autoload -Uz split_file
autoload -Uz wd
autoload -Uz ws_remind
autoload -Uz cd_sm
autoload -Uz _cd_sm

WORDCHARS=${WORDCHARS//\/}

# Show workspace branches on SSH login
#if [[ -n "$SSH_CONNECTION" ]]; then
#  echo "Workspaces:"
#  ws_remind
#fi

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
# Note: zsh-syntax-highlighting must be loaded AFTER zsh-autosuggestions,
# otherwise it breaks partial-accept (word-by-word Ctrl+arrow) for suggestions.
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
#zinit light Aloxaf/fzf-tab
zinit light zsh-users/zsh-syntax-highlighting
#zinit light marlonrichert/zsh-autocomplete
zinit light zsh-users/zaw

# Add in snippets
zinit snippet OMZP::git

# Load completions
autoload -U compinit && compinit
compdef _cd_sm cd_sm

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

# Alt+Backspace deletes one word at a time
bindkey '^[^?' backward-kill-word

# Tag to accept auto-suggestions
#bindkey '^I' autosuggest-accept

#zaw customizations 
bindkey '^R' zaw-history
zstyle ':filter-select:highlight' selected
zstyle ':filter-select:highlight' matched
zstyle ':filter-select:highlight' marked
zstyle ':filter-select:highlight' title
zstyle ':filter-select:highlight' error

# Completion styling
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
#zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
#zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'
zstyle ':completion:*' menu select

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



# Aliases
alias ls='ls --color'
alias enw="emacs -nw"
alias tmux_attach="tmux a -t"

export EDITOR="/usr/bin/emacs -nw"
export VISUAL="/usr/bin/emacs -nw"
export PATH="$PATH:/home/cyc/centos8_tools/bin"
path+=('/home/cyc/.local/bin')
path+=('/home/cyc/.cargo/bin')

# Shell integrations
#eval "$(fzf --zsh)"
eval "$(zoxide init --cmd cd zsh)"

# Based on https://medium.com/@hitechluddite/ditch-cleartext-secrets-how-to-safeguard-api-keys-in-zsh-and-bash-with-pass-77f694b9ff64
export CONFLUENCE_TOKEN=$(pass show confluence/pat)
export JIRA_TOKEN=$(pass show jira/pat)
export GITHUB_TOKEN=$(pass show gh/pat)
export JENKINS_TOKEN=$(pass show jenkins/pat)

source /home/cyc/.local/share/zinit/plugins/zsh-users---zaw/zaw.zsh
