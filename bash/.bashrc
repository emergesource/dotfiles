# ~/.bashrc -- interactive shell configuration.
#
# Read directly by non-login interactive shells (Linux terminals, and `bash`
# typed at a zsh prompt on macOS), and sourced by ~/.bash_profile for login
# shells (macOS Terminal/iTerm). Keeping everything interactive here is what
# makes bash behave identically on both platforms.

# --- aliases ---------------------------------------------------------------
alias weather='weather -m cykz'
alias l='ls -alh'
alias grep='grep --color -n'
alias dc='docker-compose'
alias vi='nvim'
alias vim='nvim'
alias p='ps aux'
alias k='kill'
alias h=history

# --- history ---------------------------------------------------------------
export HISTCONTROL=ignoreboth

# --- functions -------------------------------------------------------------
code () { VSCODE_CWD="$PWD" open -n -b "com.microsoft.VSCode" --args $* ;}
cd() { builtin cd "$@"; ls; } # Always list directory contents upon 'cd'
f () { /usr/bin/find . -name "$@" ; }

# --- colours ---------------------------------------------------------------
export black="\[\033[0;38;5;0m\]"
export red="\[\033[0;38;5;1m\]"
export green="\[\033[0;38;5;2m\]"
export yellow="\[\033[0;38;5;3m\]"
export blue="\[\033[0;38;5;4m\]"
export magenta="\[\033[0;38;5;55m\]"
export cyan="\[\033[0;38;5;6m\]"
export white="\[\033[0;38;5;7m\]"
export coldblue="\[\033[0;38;5;33m\]"
export smoothblue="\[\033[0;38;5;111m\]"
export iceblue="\[\033[0;38;5;45m\]"
export turqoise="\[\033[0;38;5;50m\]"
export smoothgreen="\[\033[0;38;5;42m\]"

#export cyan="\e[0;36m\]"
#export default="\e[0;39m"

# --- git prompt ------------------------------------------------------------
# git-prompt.sh provides __git_ps1, which parse_git_branch below depends on.
# It must be sourced here, not in .bash_profile: non-login shells never read
# .bash_profile, and would otherwise get an undefined function in PS1.
[ -f ~/bin/git-completion.bash ] && source ~/bin/git-completion.bash
[ -f ~/bin/git-prompt.sh ] && source ~/bin/git-prompt.sh

parse_git_branch() {
    branch=`__git_ps1 "%s"`
    if [[ `tput cols` -lt 110 ]]; then
        branch=`echo $branch | sed s/feature/f/1`
        branch=`echo $branch | sed s/hotfix/h/1`
        branch=`echo $branch | sed s/release/\r/1`
        branch=`echo $branch | sed s/master/mstr/1`
        branch=`echo $branch | sed s/develop/dev/1`
    fi
    if [[ $branch != "" ]]; then
        if [[ $(git status 2> /dev/null | tail -n1) == "nothing to commit, working tree clean" ]]; then
            echo "${green}$branch${white} "
        else
        echo "${red}$branch${white} "
        fi
    fi
}

# Superseded by prompt() below -- PROMPT_COMMAND is reassigned, so this never
# runs. Kept because the fill/newPWD maths belongs with the banner PS1 variants
# commented out underneath prompt().
function pre_prompt {
	newPWD="${PWD}"
	user="whoami"
	host=$(echo -n $HOSTNAME | sed -e "s/[\.].*//")
	datenow=$(date "+%a, %d %b %y")
	let promptsize=$(echo -n "--($user@$host ddd, DD mmm YY)---(${PWD})---" \
                 | wc -c | tr -d " ")
	let fillsize=${COLUMNS}-${promptsize}
	fill=""
	if [ "$fillsize" -lt "0" ]
	then
		let cutt=3-${fillsize}
		newPWD="...$(echo -n $PWD | sed -e "s/\(^.\{$cutt\}\)\(.*\)/\2/")"
	fi
}

#PS1="\[\033[01;36m\]┌─(\[\033[01;37m\]\u@\h\[\033[01;32m\]\[\033[00m\])─\${fill}─(\$newPWD\
#)────┐\n└─(\$)─>$default "
# PS1="${green}┌─(${coldblue}\u@\h${green})─\${fill}─(${coldblue}\$newPWD ${green})────┐\n${green}└─(\$${green})─>${white} "
#PS1="\w ${BRANCH} › "

prompt() {
    #PS1="${white}┌─╼[${smoothgreen}\u${white}:${smoothgreen}\h${white}]╾─╼[${smoothgreen}\w${white}$(parse_git_branch)]\n└─╼ "
    PS1="${green}\u@\h ${blue}\w $(parse_git_branch)${blue}› ${white}"
}

PROMPT_COMMAND=prompt

# --- completion ------------------------------------------------------------
[ -f /usr/local/etc/bash_completion ] && . /usr/local/etc/bash_completion
[ -f /opt/homebrew/etc/bash_completion ] && . /opt/homebrew/etc/bash_completion
# source /usr/local/etc/bash_completion.d/password-store
