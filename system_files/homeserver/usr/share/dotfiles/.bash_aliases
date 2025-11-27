# NB: This is being managed and manual changes will be overwritten

# Git aliases
alias gl='git pull'
alias gp='git push'
alias gc='git commit -v'
alias gca='git commit -v -a'
alias gb='git branch'
alias gba='git branch -a'
alias gco='git checkout'

# Aliases (if applicable)
grep --color=auto < /dev/null &>/dev/null &&
    alias grep='grep --color=auto'
xdg-open --version &>/dev/null &&
    alias open='xdg-open'
command -v system_profiler &>/dev/null &&
    alias wattage='system_profiler SPPowerDataType | grep Wattage'

# Enable color support of ls
if ls --color=auto &>/dev/null; then
	alias ls='ls -p --color=auto'
else
	alias ls='ls -p -G'
fi

mkcd () {
  \mkdir -p "$1"
  cd "$1"
}

tempe () {
  cd "$(mktemp -d)"
  chmod -R 0700 .
  if [[ $# -eq 1 ]]; then
    \mkdir -p "$1"
    cd "$1"
    chmod -R 0700 .
  fi
}

# print a colorized diff
colordiff() {
	local red=$(tput setaf 1 2>/dev/null)
	local green=$(tput setaf 2 2>/dev/null)
	local cyan=$(tput setaf 6 2>/dev/null)
	local reset=$(tput sgr0 2>/dev/null)

	diff -u "$@" | awk "
	/^\-/ {
		printf(\"%s\", \"$red\");
	}
	/^\+/ {
		printf(\"%s\", \"$green\");
	}
	/^@/ {
		printf(\"%s\", \"$cyan\");
	}

	{
		print \$0 \"$reset\";
	}"

	return "${PIPESTATUS[0]}"
}
