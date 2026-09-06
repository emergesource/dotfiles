# CLAUDE.md

Personal dotfiles for macOS and Linux. The repo is a set of **GNU stow packages**:
each top-level directory (`zsh/`, `vim/`, …) mirrors the layout it should have
under `$HOME`, so `vim/.vimrc` → `~/.vimrc` and `bin/bin/` → `~/bin/`.

## Deploy

```bash
./install.sh        # stow every package
./install.sh -n     # dry run
./install.sh -D     # unstow
```

**Everything is symlinked, not copied.** Editing `~/.vimrc` edits `vim/.vimrc`
in this repo — there is no sync-back step, and `git status` is authoritative.
`install.sh` bootstraps oh-my-zsh if missing, then runs stow.

`--no-folding` is mandatory. Without it stow makes `~/.vim` itself a symlink
into the package, and `~/.vim/plugged` / `~/.vim/undo` can then no longer exist
as real directories. The same applies to `~/.config`, which holds many
unmanaged app configs.

**Gotcha: `sed -i` cannot edit a symlink.** BSD sed refuses outright; GNU sed
needs `--follow-symlinks`. Edit through an editor, or edit the file in the repo
by its package path.

## Packages

| Package | Contents | Notes |
|---------|----------|-------|
| `zsh` | `.zshrc`, `.p10k.zsh` | |
| `vim` | `.vimrc`, `.vim/{autoload,colors,UltiSnips}` | |
| `nvim` | `.config/nvim/init.vim` | shim: prepends `~/.vim` to rtp, sources `~/.vimrc` |
| `tmux` | `.tmux.conf`, `.config/tmuxinator/` | |
| `git` | `.gitconfig` | |
| `bin` | `bin/` | |
| `newsboat` | `.newsboat/` | |
| `bash` | `.bashrc`, `.bash_profile` | cross-platform; `.bash_profile` sources `.bashrc` |
| `linux` | `.fonts/` | stowed on Linux only |

Root-level files (`README.md`, `CLAUDE.md`, `Brewfile`, `install.sh`,
`.gitignore`, `.rsyncignore`, `.gitmodules`) are repo infrastructure, belong to
no package, and are never deployed. New files must go **inside a package** to
be deployed, or stay at the root to be ignored.

## Package install

```bash
brew bundle          # macOS, reads ./Brewfile
./bin/ubuntu.sh      # Linux, apt
```

## Scripts (`bin/`, intended to be on `$PATH`)

| Script | Notes |
|--------|-------|
| `backup.sh` | rsync `~` to `$DEST`. **Run from the repo root** — `--exclude-from=".rsyncignore"` is relative. `DEST` is a block of commented per-machine paths; uncomment the right one. Note `~` is now full of symlinks; the real content is backed up via `~/devel/dotfiles`. |
| `freespace.sh` | docker prune, brew cleanup, deletes stale `venv`/`node_modules` under `~/devel`. Destructive. |
| `nameit` | random name generator; needs `/usr/share/dict/words` and `shuf`. |

## Editor

`vim/.vimrc` is the single source of truth. `nvim/.config/nvim/init.vim` sources
it, so vim 9.1 and nvim 0.11 share one config.

- `pastetoggle` is guarded with `if !has('nvim')` — nvim removed the option
  (E519). Both handle bracketed paste natively anyway.
- nvim errors with `E5422` if `init.lua` and `init.vim` both exist. A previous
  LazyVim install is parked at `~/.config/nvim-archive-2026/nvim.lazyvim`.

## Plugin managers

- **vim**: vim-plug, vendored at `vim/.vim/autoload/plug.vim`. Plugins declared
  at the top of `.vimrc`; run `:PlugInstall`. They install to `~/.vim/plugged`,
  outside the repo.
- **tmux**: tpm, **not** vendored and **not currently installed** — clone to
  `~/.tmux/plugins/tpm`, then `prefix + I`. Until then every `@plugin` line in
  `.tmux.conf` is inert, including `tmux-sensible`.
- **zsh**: oh-my-zsh + powerlevel10k, installed by `install.sh`, not vendored.

## Known issues

Carried over deliberately; reconciliation was kept behaviour-neutral.

- **`.vimrc:127`** `nnoremap  :set nonumber!:set foldcolumn=0` — lost its LHS
  (a raw `<C-n>`) and its `<CR>`s. It currently maps the normal-mode sequence
  `:set`.
- **`.vimrc:103`** `map <leader>c <c-_><c-_> " T-Comment Shortcut` — `map` has
  no trailing-comment syntax, so the comment is part of the RHS.
- **`.vimrc:85-88`** `map <C-h> <C-W>h` etc. override vim-tmux-navigator's own
  mappings, breaking vim→tmux pane crossing.
- **`undodir=$HOME/.vim/undo` does not exist**, so persistent undo silently
  never writes. With `noswapfile`/`nobackup` there is no recovery net.
- **`~/.gitignore_global` does not exist**, but `.gitconfig` `core.excludesfile`
  and `g:ackprg` both point at it.
- **`~/bin` is off `$PATH`** — the `export PATH=$PATH:~/bin` line in `.zshrc` is
  commented out.
- **coc.nvim and ultisnips are commented out** in `.vimrc`, so there is no LSP
  or snippet support; the coc extensions are still installed on disk.
- `.vim/.vimrc` is a dead 210-line fork that vim never reads.
- `.vim/UltiSnips/UltiSnips/` is a nested duplicate; both are loaded and the two
  `markdown.snippets` have diverged.
- `.config/tmuxinator/` is stale (references `/home/colin`, rails, a `venv`) and
  tmuxinator is not installed, though `.zshrc` still aliases `mux` to it.
- `.zshrc` hardcodes `ZSH="/Users/colin/.oh-my-zsh"`.
- `.gitignore` patterns `vim/plugged` / `vim/undo` do not match `.vim/plugged`.
- `.vimrc` still has `au BufRead /tmp/mutt-*`; the mail stack was removed.
- `Brewfile` lists `appcleaner` as a formula (it is a cask) and taps
  `homebrew/cask-versions`, which no longer exists — `brew bundle` aborts.

## Secrets

Never commit credentials. `.gitignore` blocks `*.asc` (the PGP exports README
documents).
