#!/usr/bin/env sh

set -e -o pipefail

figlet "free your space..."

# docker
sudo docker system prune -af

# homebrew
if [[ "$OSTYPE" == "darwin"* ]]; then
    brew cleanup -s
fi

# old dev dependencies
find ~/devel -name "venv|env" -type d -mtime +120 | xargs rm -rf
find ~/devel -name "node_modules" -type d -mtime +120 | xargs rm -rf


if [[ "$OSTYPE" == "darwin"* ]]; then
    diskutil info / | grep "Free Space"
fi
