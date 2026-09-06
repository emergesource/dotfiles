# CLAUDE.md

Personal dotfiles for macOS and Linux (Ubuntu + openbox). The repo is an **image of `$HOME`**:
paths here map 1:1 onto the home directory (`.vimrc` → `~/.vimrc`, `bin/` → `~/bin`).

## Deploy

```bash
./install.sh        # prompts before overwriting
./install.sh -f     # no prompt
```

**`install.sh` rsyncs — it does not symlink.** Editing `~/.vimrc` does *not* change the repo.
Any change made live in `$HOME` has to be copied back here by hand before committing
(that's what the "Latest zshrc" / "Latest vimrc" commits are). It also bootstraps oh-my-zsh
if `~/.oh-my-zsh` is missing, then `source ~/.zshrc`.

Everything in the repo is copied except `.git/`, `.DS_Store`, `.osx`, `bootstrap.sh`,
`install.sh`, `README.md`, `LICENSE-MIT.txt`, `Brewfile`, `CLAUDE.md`. New repo-only files
must be added to that exclude list in `install.sh` or they land in `$HOME`.

## Package install

```bash
brew bundle          # macOS, reads ./Brewfile
./bin/ubuntu.sh      # Linux, apt + snap
```

## Scripts (`bin/`, on `$PATH` via `.zshrc`)

| Script | Notes |
|--------|-------|
| `backup.sh` | rsync `~` to `$DEST`. **Run from the repo root** — `--exclude-from=".rsyncignore"` is relative. `DEST` is a block of commented per-machine paths; uncomment the right one. |
| `freespace.sh` | docker prune, brew cleanup, deletes stale `venv`/`node_modules` under `~/devel`. Destructive. |
| `term.sh` | `xrdb ~/.Xresources` then `urxvt` (Linux only). |
| `nameit` | random name generator; needs `/usr/share/dict/words` and `shuf`. |

## Plugin managers

- **vim**: vim-plug, vendored at `.vim/autoload/plug.vim`. Plugins declared at the top of `.vimrc`; run `:PlugInstall` after changing them. They install to `~/.vim/plugged`, outside the repo.
- **tmux**: tpm, **not** vendored — clone to `~/.tmux/plugins/tpm` manually, then `prefix + I`.
- **zsh**: oh-my-zsh + powerlevel10k, installed by `install.sh`, not vendored.
- `.gitmodules` is empty; nothing here is a submodule.

## Editor

`.vimrc` (305 lines) is the single source of truth. `.config/nvim/init.vim` just sources it,
so nvim and vim share one config.

## Gotchas

- **`.vim/.vimrc` is dead** — a stale 210-line fork of `.vimrc` that vim never reads. Don't edit it; consider deleting it.
- **`.vim/UltiSnips/UltiSnips/` is a nested duplicate.** `g:UltiSnipsSnippetDirectories = ['~/.vim/UltiSnips', 'UltiSnips']` loads both, and the two `markdown.snippets` have diverged. Edit the top-level `.vim/UltiSnips/` copy.
- **`.gitignore` patterns are stale**: `vim/plugged` and `vim/undo` never match `.vim/plugged` / `.vim/undo`.
- **`.zshrc` mixes platforms**: hardcodes `ZSH="/Users/colin/.oh-my-zsh"` (macOS) while aliasing `open=xdg-open`, `docker="sudo docker"`, `agu=apt` (Linux). Editing it means picking which host it's for.
- **`.p10k.zsh` is 82KB of generated config** — regenerate with `p10k configure`, never hand-edit.
- **`.rsyncignore` excludes `.config/`** from backups, because `.config/` is tracked here instead. Adding config there means it is backed up by git only.
- Linux-desktop configs (`.config/openbox`, `rofi`, `tint2`, `.Xresources`, `.xrdb`) are inert on macOS but still get rsynced there.

## Secrets

Never commit credentials. `.gitignore` blocks `*.asc` (the PGP exports README documents).
`.muttrc` and `.mbsyncrc` read the mail password via `pass gmail` — keep it that way.
