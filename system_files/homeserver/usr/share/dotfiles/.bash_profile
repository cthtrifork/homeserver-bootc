# NB: This file is being managed by the bootable container and manual changes will be overwritten
source ~/.bashrc

# Set environment
export EDITOR='nano'
export GREP_COLOR='mt=1;36'
export HISTCONTROL='ignoredups'
export HISTSIZE=5000
export HISTFILESIZE=5000
export LSCOLORS='ExGxbEaECxxEhEhBaDaCaD'
export PAGER='less'
export TZ='Europe/Copenhagen'
export BAT_PAGER=''

export PATH="$PATH:$HOME/.local/bin"

# Shell Options
shopt -s cdspell
shopt -s checkwinsize
shopt -s extglob

. ~/.local/bin/z.sh

# Load external files
. ~/.bash_aliases    2>/dev/null || true
. ~/.bashrc.local    2>/dev/null || true
