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

## Screenshots

`docs/*.svg` are generated, not hand-captured. `./tools/make-screenshots.sh`
runs the real tools in a detached tmux session, captures the pane with
`capture-pane -e`, and renders the ANSI to SVG via `tools/ansi2svg.py`. They
pick up the colours of whatever theme is currently active, so regenerate after
changing theme if the images should match.

SVG on purpose: it diffs sensibly in git, stays a few KB, and needs no binaries
in the repo. `tools/` is repo infrastructure and is never stowed.

## Files changing underneath you

`.vimrc` sets `autoread` **and** an `AutoReload` augroup running `checktime` on
`FocusGained`/`BufEnter`/`CursorHold`. Both halves are required: `autoread`
permits a reload but never polls, so without `checktime` vim only notices on the
next explicit command. `FocusGained` additionally needs tmux `focus-events on`,
which `.tmux.conf` sets.

Removing `autoread` does not disable this — it makes it *worse*. `checktime`
then raises `W11` and prompts `[O]K, (L)oad File` on every external change.

`history-limit` is 50000 because the 2000-line default is about one agent build
log. `rerere.enabled` replays previous conflict resolutions, so repeated merges
and rebases mostly resolve themselves before `conflicts.vim` sees them.

## Deriving colours from the theme

`vim/.vim/autoload/colorkit.vim` holds the shared colour maths: `mix`, `lum`,
`contrast`, `readable`, `attr`, `bg`, `first`. Use it instead of hardcoding hex
values, so highlights follow `theme`.

**The rule it exists to enforce:** under `termguicolors` vim uses `guifg`/`guibg`
and ignores `ctermfg`/`ctermbg` completely. A highlight that sets only cterm
attributes is inert. Two bugs came from exactly this — `ColorColumn ctermbg=0`
left `guibg` unset, so every theme showed vim's default `DarkRed`; and the
conflict labels styled with `DiffAdd` had no foreground, because no colorscheme
defines a `fg` on that group. Always set the gui attribute.

`g:colorcolumn_strength` (default `0.10`) controls how far the 80-column rule is
nudged off the background — 0.0 invisible, 1.0 full foreground. It mixes toward
the *foreground*, so it darkens on light themes and lightens on dark ones.

## Statusline

`vim/.vim/plugin/statusline.vim` is a native statusline — no plugin. It replaced
lightline, which could only match a theme when one of its 37 bundled palettes
shared the theme's name; for the other ~570 upstream themes it silently fell
back to `one`.

Mode colours come from `colorkit#palette()`, which reads the ANSI values out of
`~/.config/theme/current/palette.sh`. ANSI 1–6 mean red/green/yellow/blue/
magenta/cyan in every theme, so the mapping holds for all 606 without a lookup
table. Bar backgrounds are the editor background mixed a step toward the
foreground; mode-block foregrounds are chosen by `colorkit#readable()`.

Active and inactive windows are swapped with `WinEnter`/`WinLeave` autocmds
setting a window-local `statusline`, rather than `g:statusline_winid`, which is
only populated during real statusline evaluation.

`set noshowmode` is deliberate — the mode block already says it.

## Merge conflicts

`vim/.vim/plugin/conflicts.vim` is an inline conflict-resolution UI over
`rhysd/conflict-marker.vim`, using VS Code's vocabulary. Everything happens in
one buffer — no diff splits.

- `,x` opens the Resolve Conflict menu (`c` Current, `i` Incoming, `b` Both,
  `n` Discard, `j`/`k` navigate).
- `:AcceptCurrentChange`, `:AcceptIncomingChange`, `:AcceptBothChanges`,
  `:DiscardBothChanges`, `:NextConflict`, `:PrevConflict`, `:Conflicts`.
- Virtual-text labels mark each block `(Current Change)` / `(Incoming Change)` /
  `(Common Ancestor)`. vim only — nvim gets colours and the menu, since the
  labels use text properties.

Colours derive from the active theme's `DiffAdd` (green, Current) and
`DiffText` (blue, Incoming), recomputed on `ColorScheme` so they follow `theme`.
Each bar sets an explicit foreground chosen by WCAG luminance — **do not set a
background without a foreground here**, which was the original bug: no theme
defines a `fg` on `DiffAdd`, so label text was invisible. `:ContrastReport`
prints the measured ratios; all bundled themes pass AA.

Content blocks get only a 16% wash and no `guifg`, so syntax highlighting still
reads through.

`merge.conflictstyle` is unset, so there is no `(Common Ancestor)` block.
`git config --global merge.conflictstyle zdiff3` enables it.

## Theming

`bin/bin/theme` switches iTerm2, vim and tmux together. Run `theme` for a picker
that applies live as you move, `theme browse` to install from the ~600-theme
upstream catalogue, `theme next`/`prev` to cycle.

State lives outside the repo, in `~/.config/theme/`, where `current` is a
**symlink** to the active theme directory. Configs point at that stable path, so
switching is just repointing the symlink:

- `.vimrc` sources `~/.config/theme/current/theme.vim`
- `.tmux.conf` does `source-file -q ~/.config/theme/current/tmux.conf`
- `.zshrc` runs `theme reapply` at startup

Themes come from `mbadolato/iTerm2-Color-Schemes`. Two things about that source:
`schemes/` uses spaces in filenames while `vim/` uses dashes (`Gruvbox
Dark.itermcolors` vs `Gruvbox-Dark.vim`), and its `yaml/` directory is an
incomplete 156-file subset, so the tmux theme is generated by parsing the
`.itermcolors` plist with `plistlib` instead.

Requirements, all now set in `.tmux.conf`: `allow-passthrough on` (iTerm is
recoloured with an OSC 1337 sequence that tmux otherwise swallows),
`focus-events on` (how a running vim notices a change — it cannot be
remote-controlled, being `+clientserver` but `-X11`), and `tmux-256color` +
`RGB` overrides for truecolor.

`theme reapply` in `.zshrc` is not optional: escape-code colours are per-session,
so a new iTerm window would otherwise revert to the profile's colours.

## Editor

`vim/.vimrc` is the single source of truth, organised into labelled sections:
plugins / built-ins / options / filetypes / appearance / plugin config /
mappings / commands. Add new settings to the matching section. `nvim/.config/nvim/init.vim` sources
it, so vim 9.1 and nvim 0.11 share one config.

- `pastetoggle` is guarded with `if !has('nvim')` — nvim removed the option
  (E519). Both handle bracketed paste natively anyway.
- nvim errors with `E5422` if `init.lua` and `init.vim` both exist. A previous
  LazyVim install is parked at `~/.config/nvim-archive-2026/nvim.lazyvim`.
- **No LSP by design.** coc.nvim is not loaded; code intelligence is the agent's
  job. `coc.nvim` and `ultisnips` are still in `~/.vim/plugged` and their Plug
  lines are commented, so re-enabling either is a one-line edit — but a
  `:PlugClean` would delete them from disk first.
- vim 9.1 built-ins in use: `comment` (gc/gcc, replaced tcomment_vim),
  `editorconfig`, and `osc52` — the last on Linux only, since macOS vim ignores
  `clipmethod` and uses the native pasteboard.
- Snippets are disabled but `.vim/UltiSnips/*.snippets` are kept.

## Plugin managers

- **vim**: vim-plug, vendored at `vim/.vim/autoload/plug.vim`. Plugins declared
  at the top of `.vimrc`; run `:PlugInstall`. They install to `~/.vim/plugged`,
  outside the repo.
- **tmux**: tpm, **not** vendored and **not currently installed** — clone to
  `~/.tmux/plugins/tpm`, then `prefix + I`. Until then every `@plugin` line in
  `.tmux.conf` is inert, including `tmux-sensible`.
- **zsh**: oh-my-zsh + powerlevel10k, installed by `install.sh`, not vendored.

## Known issues

Everything previously listed here has been fixed. Two deliberate choices remain,
so they are not bugs:

- **No LSP.** coc.nvim is not loaded; the agent does code intelligence. `coc` and
  `ultisnips` keep commented `Plug` lines so either is a one-line re-enable.
- **tpm is not installed**, so the `@plugin` lines in `.tmux.conf` are inert.
  Little is lost: `escape-time`, `mode-keys` and `status-keys` already hold the
  values `tmux-sensible` would set. `tmux-yank` and `tmux-better-mouse-mode` are
  what you would actually gain by cloning tpm to `~/.tmux/plugins/tpm`.

## Secrets

Never commit credentials. `.gitignore` blocks `*.asc` (the PGP exports README
documents).
