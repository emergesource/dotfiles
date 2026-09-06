# CLAUDE.md

Personal dotfiles — zsh, vim, tmux. Guidance for Claude Code and any other
contributor.

## The one thing to know

`install.sh` **rsyncs the repo into `$HOME`**, so a file's path in this repo is
its path in the home directory:

| repo              | installed to        |
| ----------------- | ------------------- |
| `.zshrc`          | `~/.zshrc`          |
| `bin/foo`         | `~/bin/foo`         |
| `.config/nvim/…`  | `~/.config/nvim/…`  |

Add a file where it should land. `~/bin` is on `PATH` (set in `.zshrc`), so
anything in `bin/` becomes a command.

Not installed: `.git/`, `README.md`, `install.sh`, `Brewfile`, `.DS_Store`,
`.osx`, `LICENSE-MIT.txt`. The `Brewfile` is applied separately with
`brew bundle`.

## Working agreements

1. **Never run `install.sh`.** It overwrites files in `$HOME` and needs a real
   machine to matter. Edit files here; the owner runs it when ready.
2. **Nothing to build.** No tests, no CI, no dependencies. Shell scripts are
   checked with `bash -n`; that is the whole verification story.
3. **Edit on the go, run locally.** Work lands on a branch. The owner checks it
   out on the laptop, looks at it, then installs it. So: small, readable
   commits that are easy to eyeball, and no change that only makes sense as
   part of a larger unrun system.
4. **Never commit secrets.** `*.asc` is gitignored because PGP keys live in this
   shape (see the README for the export/restore commands). No keys, no tokens,
   no history files.
5. **Leave the machine-specific mess alone** unless asked. This tracks more than
   one machine and shows it: `.bash_profile` has MacPorts `PATH` lines and
   `.zshrc` sets `ZSH="/Users/colin/.oh-my-zsh"` (macOS), while `.zshrc`
   aliases assume Linux (`apt`, `xdg-open`). It is inconsistent on purpose
   more often than by accident — do not "fix" it as a drive-by.

## Layout

- `install.sh` — the rsync installer. Prompts unless given `-f` / `--force`;
  installs oh-my-zsh first if missing, sources `~/.zshrc` after.
- `bin/` — scripts that land on `PATH`. `.bash_profile` also sources
  `bin/git-completion.bash` and `bin/git-prompt.sh` from `~/bin`.
- `.config/tmuxinator/` — per-project tmux layouts. `.zshrc` aliases
  `mux` to `tmuxinator`.
- `.vim/`, `.vimrc`, `.config/nvim/` — vim and neovim.
- `Brewfile` — macOS packages, via `brew bundle`.

## Notes

- The default branch is **`master`**, not `main`.
- `git pull` is configured to rebase (`.gitconfig`), along with short aliases:
  `co`, `st`, `ci`, `br`, `pr`, `l`, `ll`, `up`.
