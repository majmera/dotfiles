# add tool to bin
if [[ -r /home/cyc/centos8_tools/bashrc_utils/framework_utilities.sh ]]; then
  source /home/cyc/centos8_tools/bashrc_utils/framework_utilities.sh
fi
# add bash completion
#source /home/cyc/centos8_tools/bashrc_utils/completions.sh
export PATH="$HOME/.local/bin:$PATH"
alias enw="emacs -nw"
alias tmux_attach="tmux a -t"
export EDITOR="emacs -nw"
export VISUAL="emacs -nw"
# Configure centos8_tools
#source /home/cyc/centos8_tools/optional/optional_startup_scripts.sh
# Override prompt
#source /home/cyc/centos8_tools/scripts/utilities/configure_prompt.sh

#exec zsh

alias itriage="~/iTriage-env/bin/itriage $@"
export NVS_HOME="$HOME/.nvs"
[ -s "/opt/nvs/nvs.sh" ] && . "/opt/nvs/nvs.sh"

# Workaround for bash 4.4 crashes in Windsurf terminal state replay.
# Windsurf replays shell options via `eval`, including `set -o emacs`/`set -o vi`.
# On this host, those commands can segfault in interactive shells.
if [[ "${WINDSURF_CASCADE_TERMINAL:-}" == "1" ]]; then
    set() {
        if [[ $# -ge 2 && ( "$1" == "-o" || "$1" == "+o" ) ]]; then
            case "$2" in
                emacs|vi)
                    return 0
                    ;;
            esac
        fi
        builtin set "$@"
    }
fi

[ -f ~/.fzf.bash ] && source ~/.fzf.bash

# >>>> BEGIN MANAGED DEVIN BLOCK >>>>
# Add ~/.local/bin to PATH for devin
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
fi
# <<<< END MANAGED DEVIN BLOCK <<<<

export CONFLUENCE_TOKEN="$(pass show confluence/pat)"
export JIRA_TOKEN="$(pass show jira/pat)"
export GITHUB_ENTERPRISE_TOKEN="$(pass show gh/pat)"
export GH_HOST="eos2git.cec.lab.emc.com"
unset GITHUB_TOKEN GH_TOKEN
export JENKINS_TOKEN="$(pass show jenkins/pat)"
export JIRA_CEC_TOKEN="$(pass show jira/pat)"
export ISG_GOVERNANCE_PATH="/home/cyc/isg-ai-governance"
export CYCLONE_PDR="/home/cyc/cyclone"
