set ai
set showmode
set ruler
syntax on 
set mouse=

" tabs
set ts=4
set softtabstop=4 
set shiftwidth=4
set shiftround
set expandtab

" search
set hlsearch
set incsearch
set ignorecase
set smartcase

" backup/swap files
set nobackup
set nowritebackup
set noswapfile

set bs=2
filetype on
set number
set nowrap
set tw=80
set colorcolumn=80
" highlight ColorColumn ctermbg=100
nnoremap  :set nonumber!:set foldcolumn=0
set cursorline

"set modelines=0

set go-=L


nnoremap <leader><space> :noh<cr>
nnoremap <leader>w <C-w>v<C-w>l
nnoremap <leader>1 :b1<cr>

" leader shortcuts...
let mapleader=","
" T-Comment Shortcut
map <leader>c <c-_><c-_>

"split mappings
map <leader>v :vsplit<cr>
map <leader>h :split<cr>

" vdebug breakpoint
map <leader>b :Breakpoint<cr>

" taglist
map <leader>t :TlistToggle<cr>

" nertree
map <leader>n :NERDTreeToggle<cr>

" quick insert date
map <leader>d :r!date<cr>

" comment out var dumps
map <leader>C :g/var_dump/norm gcc<cr>

" copy to clipboard
map <leader>y "+y 

" spelling
nnoremap <leader>s :setlocal spell! spelllang=en_us<cr>
map <leader>S z=

" Smart way to move between windows
map <C-j> <C-W>j
map <C-k> <C-W>k
map <C-h> <C-W>h
map <C-l> <C-W>l

" toggle paste mode  (turns off auto indent)
set pastetoggle=<leader>p

" hide buffers instead of closing them.  
" (This way you don't have to save when switching between buffers)
set hidden

" autosource the vimrc when it changes
autocmd! bufwritepost .vimrc source % 

" enable colours
set t_Co=256

" colour scheme
set background=dark
colorscheme hemisu 

" pathogen settings
call pathogen#infect()
call pathogen#helptags()
call pathogen#runtime_append_all_bundles()


set runtimepath^=~/.vim/bundle/ctrlp.vim
let g:ctrlp_working_path_mode = 'rw'
" don't want to pull up these folders/files when calling CtrlP
set wildignore+=*/vendor/**,*/node_modules/**,*.pyc,*venv/**

" completion options
filetype plugin on
autocmd FileType php set omnifunc=phpcomplete#CompletePHP
set completeopt=longest,menuone

" macvim settings
set guioptions-=r
set guifont=Monaco:h13
set antialias
if has("gui_macvim") 
    set transparency=5
endif

" hate the beeping
set visualbell
set noerrorbells

" new vertical splits open on the right side
set splitright

" Automatically read files when they were changed on the filesystem 
set autoread

" phpdoc settings
autocmd FileType php inoremap <C-d> <ESC>:call PhpDocSingle()<CR>i
autocmd FileType php inoremap <C-d> <ESC>:call PhpDocSingle()<CR>
autocmd FileType php inoremap <C-d> <ESC>:call PhpDocRange()<CR>

"Tag list settings
let Tlist_Use_Right_Window=1
let Tlist_Show_One_File=1
let Tlist_Inc_Winwidth=1
let Tlist_Compact_Format=1
let Tlist_Highlight_Tag_On_BufEnter=1

" Ultisnip settings
let g:UltiSnipsExpandTrigger="<Tab>"
let g:UltiSnipsJumpForwardTrigger="<C-b>"
let g:UltiSnipsEditSplit="vertical"
map <leader>e :UltiSnipsEdit<cr>

" make YCM compatible with UltiSnips (using supertab)
let g:ycm_key_list_select_completion = ['<C-n>', '<Down>']
let g:ycm_key_list_previous_completion = ['<C-p>', '<Up>']
let g:SuperTabDefaultCompletionType = '<C-n>'

" better key bindings for UltiSnipsExpandTrigger
let g:UltiSnipsExpandTrigger = "<tab>"
let g:UltiSnipsJumpForwardTrigger = "<tab>"
let g:UltiSnipsJumpBackwardTrigger = "<s-tab>"

" Fix wrapline colour 
highlight NonText ctermbg=none
hi Normal ctermbg=none
highlight ColorColumn ctermbg=0

autocmd Filetype javascript setlocal ts=2 sw=2 sts=0
autocmd Filetype html setlocal ts=2 sw=2 sts=0
filetype indent on

" for mutt
au BufRead /tmp/mutt-* set tw=72

let g:airline_powerline_fonts = 1
if !exists('g:airline_symbols')
    let g:airline_symbols = {}
endif
let g:airline#extensions#tabline#enabled = 1

set encoding=utf-8

function! FileSize()
 let bytes = getfsize(expand("%:p"))
 if bytes <= 0
   return "new file"
 endif
 if bytes<1024
   return bytes."b"
 else
   return (bytes/1024)."Kb"
 endif
endfunction

" Always show the status line
set laststatus=2
" set statusline =

" set statusline+=%#warningmsg#
" set statusline+=%{SyntasticStatuslineFlag()}
" set statusline+=%*

let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 0
let g:syntastic_check_on_open = 0
let g:syntastic_check_on_wq = 1
let g:syntastic_javascript_checkers = ['jshint']
let g:syntastic_error_symbol = '✗✗'
let g:syntastic_style_error_symbol = '✠✠'
let g:syntastic_warning_symbol = '∆∆'
let g:syntastic_style_warning_symbol = '≈≈'

command! Maketags !ctags -R
