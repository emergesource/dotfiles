#!/usr/bin/env bash

# stolen from https://github.com/mathiasbynens/dotfiles/blob/master/bootstrap.sh

#cd "$(dirname "${BASH_SOURCE}")";
#git pull origin master;

if [[ ! -d ~/.oh-my-zsh ]]
then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" 
fi

function doIt() {
	rsync --exclude ".git/" \
		--exclude ".DS_Store" \
		--exclude ".osx" \
		--exclude "bootstrap.sh" \
		--exclude "install.sh" \
		--exclude "README.md" \
		--exclude "CLAUDE.md" \
		--exclude "LICENSE-MIT.txt" \
        --exclude "Brewfile" \
		-avh --no-perms . ~;
	source ~/.zshrc;
}

if [ "$1" == "--force" -o "$1" == "-f" ]; then
	doIt;
else
	read -p "This may overwrite existing files in your home directory. Are you sure? (y/n) " -n 1;
	echo "";
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		doIt;
	fi;
fi;
unset doIt;
