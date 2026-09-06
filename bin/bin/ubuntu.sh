#!/usr/bin/env bash

set -eox pipefail

sudo apt-get update && sudo apt-get upgrade
sudo apt-get install \
	git \
	vim \
	jq \
	rxvt-unicode \
	curl \
	tmux \
	htop \
	zsh \
	guake \
	firefox \
	thunderbird \
	pass \
	rsync \
	vlc \
	newsboat \
	w3m \
	ncal \

