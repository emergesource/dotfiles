## dotfiles

Personal dotfiles for macOS and Linux: zsh, vim/nvim, tmux, git, bash.

Deployed with [GNU stow](https://www.gnu.org/software/stow/) as **symlinks**, not
copies. Editing `~/.vimrc` edits `vim/.vimrc` in this repo, so `git status` is
always the truth and there is nothing to copy back by hand.

### Install

```bash
brew install stow          # macOS
sudo apt install stow      # Debian/Ubuntu

git clone git@github.com:emergesource/dotfiles.git ~/devel/dotfiles
cd ~/devel/dotfiles
./install.sh               # -n to dry run, -D to remove
```

`install.sh` bootstraps oh-my-zsh if it is missing, then stows every package.
Packages are stowed with `--no-folding` so that `~/.vim` and `~/.config` stay
real directories: `~/.vim/plugged` and the various unmanaged app configs under
`~/.config` have to coexist with the linked files.

### Layout

Each top-level directory is a stow package mirroring its target layout under
`$HOME`.

| Package | Contents |
|---------|----------|
| `zsh` | `.zshrc`, `.p10k.zsh` |
| `vim` | `.vimrc`, `.vim/{autoload,colors,UltiSnips}` |
| `nvim` | `.config/nvim/init.vim` — sources `~/.vimrc`, so vim and nvim share one config |
| `tmux` | `.tmux.conf`, `.config/tmuxinator/` |
| `git` | `.gitconfig` |
| `bin` | `bin/` — on `$PATH` |
| `newsboat` | `.newsboat/` |
| `bash` | `.bashrc`, `.bash_profile` |
| `linux` | `.fonts/` — stowed on Linux only |

Repo infrastructure (`README.md`, `CLAUDE.md`, `Brewfile`, `install.sh`,
`.gitignore`, `.rsyncignore`) lives at the root, outside any package, and is
never deployed.

### Packages

```bash
brew bundle          # macOS, reads ./Brewfile
./bin/ubuntu.sh      # Linux, apt
```

### Plugin managers

Not vendored; install once per machine.

- **vim**: vim-plug is vendored at `vim/.vim/autoload/plug.vim`; run `:PlugInstall`.
- **tmux**: clone tpm to `~/.tmux/plugins/tpm`, then `prefix + I`.
- **zsh**: oh-my-zsh + powerlevel10k, handled by `install.sh`.

### Backup pgp key
```
gpg --armor --export > pgp-public-keys.asc
gpg --armor --export-secret-keys > pgp-private-keys.asc
gpg --export-ownertrust > pgp-ownertrust.asc
```

### Restore pgp key
```
gpg --import pgp-public-keys.asc
gpg --import pgp-private-keys.asc
gpg --import-ownertrust pgp-ownertrust.asc
```
