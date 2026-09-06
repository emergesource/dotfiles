#!/usr/bin/env bash
#
# Deploy these dotfiles into $HOME as symlinks, via GNU stow.
#
# This repo is a set of stow packages: each top-level directory (zsh/, vim/,
# ...) mirrors the layout it should have under $HOME. Because everything is
# symlinked rather than copied, editing ~/.vimrc edits vim/.vimrc in this
# repo -- `git diff` always tells the truth, and there is nothing to sync back
# by hand.
#
#   ./install.sh            deploy
#   ./install.sh -n         dry run, show what would happen
#   ./install.sh -D         remove the symlinks again
#
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cross-platform packages.
PACKAGES=(zsh vim nvim tmux git bin newsboat bash)

# linux/ carries ~/.fonts, which only means anything on X11; macOS wants fonts
# in ~/Library/Fonts instead.
case "$(uname -s)" in
    Linux) PACKAGES+=(linux) ;;
esac

STOW_ARGS=()
case "${1:-}" in
    -n|--dry-run) STOW_ARGS+=(--simulate --verbose=1) ;;
    -D|--delete)  STOW_ARGS+=(--delete) ;;
    "")           ;;
    *) echo "usage: $(basename "$0") [-n|--dry-run] [-D|--delete]" >&2; exit 2 ;;
esac

if ! command -v stow >/dev/null 2>&1; then
    echo "error: GNU stow is not installed." >&2
    case "$(uname -s)" in
        Darwin) echo "  brew install stow" >&2 ;;
        Linux)  echo "  sudo apt-get install stow" >&2 ;;
    esac
    exit 1
fi

# oh-my-zsh is not vendored here; .zshrc sources it and will error without it.
if [[ ! -d ~/.oh-my-zsh ]]; then
    echo "==> installing oh-my-zsh"
    RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# --no-folding is required, not cosmetic: without it stow turns ~/.vim into a
# symlink to vim/.vim, and then plugged/ and undo/ cannot live inside it.
echo "==> stow: ${PACKAGES[*]}"
# ${a[@]+"${a[@]}"} because macOS ships bash 3.2, where expanding an empty
# array under `set -u` is an "unbound variable" error.
stow --no-folding -d "$REPO" -t "$HOME" ${STOW_ARGS[@]+"${STOW_ARGS[@]}"} "${PACKAGES[@]}"

echo "==> done"
