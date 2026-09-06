# ~/.bash_profile -- login shells only.
#
# Everything interactive (aliases, functions, prompt, completion) lives in
# ~/.bashrc. Source it first so login and non-login shells behave identically:
# macOS Terminal/iTerm start login shells, Linux terminals usually do not, and
# `bash` typed at a zsh prompt is non-login on both.
[ -f ~/.bashrc ] && . ~/.bashrc

export CLICOLOR=1
#export LSCOLORS=GxFxCxDxBxegedabagaced

export EDITOR=vim
export GIT_EDITOR=vim

# --- PATH ------------------------------------------------------------------
export PATH="$HOME/bin:$PATH"
# Homebrew ruby (ships bundler 4.x) instead of macOS system ruby 2.6.
# Mirrors the same line in ~/.zshrc.
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
export PATH=~/.composer/vendor/bin:$PATH

# Retired PATH entries -- none of these exist on this machine any more.
# MacPorts, added twice by its 2012 and 2013 installers:
# export PATH=/opt/local/bin:/opt/local/sbin:$PATH
# export PATH="/Applications/MAMP/bin/php/php5.6.2/bin:$PATH"
# PATH="/Library/Frameworks/Python.framework/Versions/3.6/bin:${PATH}"
# export PATH=$PATH:/Users/colin/devel/crm/crm/vendor/bin:/Users/colin/.composer/vendor/bin
# export PATH=$PATH:/Applications/MAMP/Library/bin
# export PATH="$(brew --prefix homebrew/php/php56)/bin:$PATH"
### Added by the Heroku Toolbelt
# export PATH="/usr/local/heroku/bin:$PATH"

# --- environment -----------------------------------------------------------
export PASSWORD_STORE_DIR=~/Dropbox/.p
export REVIEW_BASE=master
export PIPENV_IGNORE_VIRTUALENVS=1

# TERM must come from the terminal emulator. Hardcoding it here breaks tmux,
# which sets its own (screen-256color / tmux-256color) -- inside tmux this
# line made every bash session lie about its terminal.
# export TERM=xterm-256color

# export WORKON_HOME=~/devel/.venv
#if [ -f /usr/local/bin/virtualenvwrapper.sh ]; then
#   . /usr/local/bin/virtualenvwrapper.sh
#fi

# gpg agent
# [ -f ~/.gpg-agent-info ] && source ~/.gpg-agent-info
# if [ -S "${GPG_AGENT_INFO%%:*}" ]; then
#   export GPG_AGENT_INFO
# else
#   eval $( gpg-agent --daemon --write-env-file ~/.gpg-agent-info )
# fi

# TMUX autostart, kept disabled
# if not running interactively, do not do anything
# [[ $- != *i* ]] && return
# [[ -z "$TMUX" ]] && exec tmux
#
# if which tmux >/dev/null 2>&1; then
#     # if no session is started, start a new session
#     test -z ${TMUX} && tmux
#
#     # when quitting tmux, try to attach
#     while test -z ${TMUX}; do
#         tmux attach || break
#     done
# fi

# (cat ~/.cache/wal/sequences &)
