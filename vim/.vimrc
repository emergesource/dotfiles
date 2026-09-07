" ~/.vimrc
"
" Deployed by stow from ~/devel/dotfiles/vim/.vimrc, so editing this file edits
" the repo directly. nvim reads it too, via ~/.config/nvim/init.vim -- keep
" everything here working in both.
"
"   plugins / built-ins / options / filetypes / appearance / plugin config /
"   mappings / commands
"
" Colours are not set here: `theme` owns the colorscheme and the lightline
" palette. See the appearance section.

set nocompatible
let mapleader = ","

" =========================================================== plugins =========
call plug#begin('~/.vim/plugged')

" editing
Plug 'Raimondi/delimitMate'
Plug 'tpope/vim-surround'
Plug 'Yggdroot/indentLine'
Plug 'stefandtw/quickfix-reflector.vim'
Plug 'rhysd/conflict-marker.vim'    " inline merge conflicts; see .vim/plugin/conflicts.vim

" navigation and search
Plug 'ctrlpvim/ctrlp.vim'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'mileszs/ack.vim'
Plug 'scrooloose/nerdtree'
Plug 'Xuyuanp/nerdtree-git-plugin'
Plug 'christoomey/vim-tmux-navigator'

" git
Plug 'tpope/vim-fugitive'
Plug 'airblade/vim-gitgutter'

" interface
Plug 'itchyny/lightline.vim'
Plug 'ryanoasis/vim-devicons'
Plug 'arcticicestudio/nord-vim'         " fallback scheme when `theme` has none

" languages and preview
Plug 'plasticboy/vim-markdown'
Plug 'iamcco/markdown-preview.nvim', { 'do': 'cd app && yarn install' }
Plug 'aklt/plantuml-syntax'
Plug 'weirongxu/plantuml-previewer.vim'
Plug 'tyru/open-browser.vim'
Plug 'hashivim/vim-terraform'

" Snippets, currently disabled -- re-enable these two together. The snippet
" files in ~/.vim/UltiSnips are kept either way. Needs +python3 (present).
" Plug 'SirVer/ultisnips'
" Plug 'honza/vim-snippets'

call plug#end()

" ========================================================== built-ins ========
" vim 9.1 ships these; nvim has equivalents built in and needs no packadd.
if !has('nvim')
  silent! packadd comment                " gc / gcc, replaces tcomment_vim
  silent! packadd editorconfig           " per-project .editorconfig support
endif

" OSC 52 puts yanks on the *local* clipboard over SSH. Linux only on purpose:
" macOS vim uses the native pasteboard and ignores 'clipmethod' entirely, so
" loading it there either does nothing or, if forced, replaces a working
" clipboard with one that can block on paste.
if !has('nvim') && !has('macunix') && exists('+clipmethod')
  silent! packadd osc52
  set clipmethod+=osc52
endif

" =========================================================== options ========
filetype plugin indent on
syntax on

" editing
set autoindent
set backspace=indent,eol,start
set encoding=utf-8
set expandtab
set hidden
set shiftround
set shiftwidth=4
set smarttab
set tabstop=4
set textwidth=80

" interface
set colorcolumn=80
set completeopt=longest,menuone
set laststatus=2                         " always show the status line
set lazyredraw
set mouse=
set noerrorbells
set nowrap
set number
set ruler
set shortmess+=c                         " no |ins-completion-menu| messages
set showmode
set signcolumn=number
set splitright
set updatetime=100                       " gitgutter responsiveness
set visualbell
set wildignore+=*/vendor/**,*/node_modules/**,*.pyc,*venv/**

" search
set hlsearch
set ignorecase
set incsearch
set smartcase
set grepprg=rg\ --vimgrep\ --smart-case\ --follow

" No swap or backup files, but keep persistent undo. The directory has to
" exist -- without it 'undofile' silently writes nothing, which is how this
" was running for years.
set nobackup
set noswapfile
set nowritebackup
set undodir=$HOME/.vim/undo
set undofile
set undolevels=1000
set undoreload=10000
if !isdirectory(expand(&undodir))
  call mkdir(expand(&undodir), 'p', 0700)
endif

" has('macunix') rather than shelling out to `uname` on every startup
if has('macunix')
  set clipboard=unnamed
else
  set clipboard=unnamedplus
endif

if !has('nvim')
  set pastetoggle=<leader>p              " nvim removed it; its paste is native
endif

" ========================================================= filetypes ========
" Per-filetype defaults. A project's .editorconfig overrides these.
" setlocal, not set: the previous `set` here leaked tabstop and textwidth into
" every other buffer opened in the same session.
augroup FiletypeSettings
  autocmd!
  autocmd FileType python
        \ setlocal tabstop=4 softtabstop=4 shiftwidth=4 textwidth=79
        \          expandtab autoindent fileformat=unix
  autocmd FileType html,javascript,typescript
        \ setlocal tabstop=2 shiftwidth=2 softtabstop=0
  " <CR> in the quickfix window jumps, rather than whatever else is mapped
  autocmd BufReadPost quickfix nnoremap <buffer> <CR> <CR>
augroup END

augroup VimrcReload
  autocmd!
  autocmd BufWritePost .vimrc source $MYVIMRC
augroup END

" ======================================================== appearance ========
" 24-bit colour. tmux advertises RGB via terminal-overrides, so themes render
" as designed rather than being quantised to 256.
if has('termguicolors') && ($COLORTERM =~# 'truecolor\|24bit' || $TERM =~# 'tmux\|256color')
  set termguicolors
  if !has('nvim')
    " vim needs to be told the escape sequences for RGB inside tmux/screen.
    let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
    let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
  endif
endif

" Re-applied after every colorscheme change -- otherwise switching themes
" silently drops them. Colours are derived from the active theme via
" autoload/colorkit.vim rather than hardcoded, so they follow `theme`.
"
" How subtle the 80-column rule is: 0.0 invisible, 1.0 full foreground.
let g:colorcolumn_strength = get(g:, 'colorcolumn_strength', 0.10)

function! s:ThemeOverrides() abort
  " keep the terminal background showing through
  highlight Normal  ctermbg=none guibg=NONE
  highlight NonText ctermbg=none guibg=NONE
  highlight clear SignColumn

  " The 80-column rule, nudged a few percent off the background. This used to
  " be `ctermbg=0` only, which does nothing under 'termguicolors' -- so no one
  " set guibg and every theme fell through to vim's default DarkRed.
  let l:bg = colorkit#bg()
  execute printf('highlight ColorColumn guibg=%s ctermbg=%s',
        \ colorkit#mix(l:bg, colorkit#fg(), g:colorcolumn_strength),
        \ colorkit#is_dark() ? '234' : '254')

  " gitgutter signs, taken from the theme's own diff accents
  let l:add = colorkit#first([['DiffAdd', 'bg'], ['DiffAdd', 'fg']], '#a3be8c')
  let l:chg = colorkit#first([['DiffChange', 'bg'], ['DiffChange', 'fg']], '#ebcb8b')
  let l:del = colorkit#first([['DiffDelete', 'bg'], ['DiffDelete', 'fg']], '#bf616a')
  let l:txt = colorkit#first([['DiffText', 'bg'], ['DiffText', 'fg']], '#81a1c1')
  execute 'highlight GitGutterAdd          ctermfg=2 guifg=' . l:add
  execute 'highlight GitGutterChange       ctermfg=3 guifg=' . l:chg
  execute 'highlight GitGutterChangeDelete ctermfg=4 guifg=' . l:txt
  execute 'highlight GitGutterDelete       ctermfg=1 guifg=' . l:del
endfunction

augroup ThemeOverrides
  autocmd!
  autocmd ColorScheme * call <SID>ThemeOverrides()
augroup END

let g:lightline = {}

" `theme` writes ~/.config/theme/current/theme.vim, which owns both the
" colorscheme and the matching lightline palette. Fall back to nord when no
" theme has been installed yet (fresh machine).
if filereadable(expand('~/.config/theme/current/theme.vim'))
  source ~/.config/theme/current/theme.vim
else
  silent! runtime autoload/lightline/colorscheme/nord.vim
  let g:lightline.colorscheme = 'nord'
  silent! colorscheme nord
endif

" A running vim cannot be remote-controlled here (+clientserver but -X11), so
" pick up theme changes when the pane regains focus. Needs tmux focus-events on.
augroup ThemeFollow
  autocmd!
  autocmd FocusGained * silent! source ~/.config/theme/current/theme.vim
augroup END

" ===================================================== plugin config ========
" NERDTree
let g:NERDTreeIgnore = ['\.pyc$', '^__pycache__$']

" ctrlp -- kept alongside fzf, reachable on its own <C-p>
let g:ctrlp_user_command = ['.git/', 'git --git-dir=%s/.git ls-files -oc --exclude-standard']
let g:ctrlp_working_path_mode = 'rw'

" ack.vim -- defined once. The old duplicate also passed
" `--ignore-file ~/.gitignore_global`, a file that does not exist, which makes
" rg exit with an error instead of searching.
let g:ackprg = 'rg --vimgrep --type-not sql --smart-case'
let g:ack_autoclose = 1
let g:ack_use_cword_for_empty_search = 1

" gitgutter
let g:gitgutter_override_sign_column_highlight = 0

" markdown
let g:vim_markdown_folding_disabled = 1

" fzf
let g:fzf_layout = { 'down': '~40%' }
let g:fzf_preview_window = []
let g:fzf_colors =
      \ { 'fg':      ['fg', 'Normal'],
      \   'bg':      ['bg', 'Normal'],
      \   'hl':      ['fg', 'Comment'],
      \   'fg+':     ['fg', 'CursorLine', 'CursorColumn', 'Normal'],
      \   'bg+':     ['bg', 'CursorLine', 'CursorColumn'],
      \   'hl+':     ['fg', 'Statement'],
      \   'info':    ['fg', 'PreProc'],
      \   'border':  ['fg', 'Ignore'],
      \   'prompt':  ['fg', 'Conditional'],
      \   'pointer': ['fg', 'Exception'],
      \   'marker':  ['fg', 'Keyword'],
      \   'spinner': ['fg', 'Label'],
      \   'header':  ['fg', 'Comment'] }

" ========================================================== mappings ========
" Window movement is deliberately absent: vim-tmux-navigator owns <C-h/j/k/l>
" so the same keys cross from a vim split into a tmux pane. Mapping them to
" <C-W>h here overrode the plugin and stopped at the edge of vim.

" splits
map  <leader>h :split<cr>
map  <leader>v :vsplit<cr>
nnoremap <leader>w <C-w>v<C-w>l

" search and replace
nnoremap <Leader>r  :%s///g<Left><Left>
nnoremap <Leader>rc :%s///gc<Left><Left><Left>
xnoremap <Leader>r  :s///g<Left><Left>
xnoremap <Leader>rc :s///gc<Left><Left><Left>
nnoremap <leader><space> :noh<cr>

" finding
nnoremap <leader>f :Rg<cr>
nnoremap <leader>b :Buffers<cr>
nnoremap <Leader>/ :Ack!<Space>
cnoreabbrev Ack Ack!

" git -- :Gblame and :Glog were removed from fugitive, so the old mappings
" were no-ops; these are the current commands.
nnoremap <leader>g  :0Gclog<cr>
nnoremap <leader>gb :Git blame<cr>
nnoremap <leader>gg :GitGutterToggle<cr>

" toggles
map      <leader>n :NERDTreeToggle<cr>
map      <leader>N :set number!<cr>
nnoremap <leader>i :IndentLinesToggle<cr>
nnoremap <leader>C :call ToggleConcealLevel()<CR>
nnoremap <silent> <Leader>q :call QuickFix_toggle()<CR>

" commenting -- gcc/gc come from the built-in 'comment' package
nmap <leader>c gcc
xmap <leader>c gc

" spelling
map      <leader>S z=
nnoremap <leader>s :setlocal spell! spelllang=en_us<cr>

" misc
map <leader>d  :r!date<cr>
map <Leader>ev :tabnew $MYVIMRC<cr>
nmap <leader>sp :call <SID>SynStack()<CR>
" map <leader>y "+y

" preview tools
nmap <leader>m  <Plug>MarkdownPreviewToggle
nmap <leader>u  :PlantUmlOpen
nmap <leader>us :PlantUmlSave<cr>

" ========================================================== commands ========
command! Maketags !ctags -R

" fzf-driven ripgrep: re-runs rg on every keystroke rather than filtering a
" single result set.
function! RipgrepFzf(query, fullscreen)
    let command_fmt = 'rg --column --line-number --no-heading --color=always --smart-case -- %s || true'
    let initial_command = printf(command_fmt, shellescape(a:query))
    let reload_command = printf(command_fmt, '{q}')
    let spec = {'options': ['--phony', '--query', a:query, '--bind', 'change:reload:'.reload_command]}
    call fzf#vim#grep(initial_command, 1, fzf#vim#with_preview(spec), a:fullscreen)
endfunction
command! -nargs=* -bang Rg call RipgrepFzf(<q-args>, <bang>0)

function! QuickFix_toggle()
    for i in range(1, winnr('$'))
        let bnum = winbufnr(i)
        if getbufvar(bnum, '&buftype') == 'quickfix'
            cclose
            return
        endif
    endfor
    copen
endfunction

function! ToggleConcealLevel()
    if &conceallevel == 0
        setlocal conceallevel=2
    else
        setlocal conceallevel=0
    endif
endfunction

" name the syntax group under the cursor -- for debugging colorschemes
function! <SID>SynStack()
  if !exists("*synstack")
    return
  endif
  echo map(synstack(line('.'), col('.')), 'synIDattr(v:val, "name")')
endfunc
