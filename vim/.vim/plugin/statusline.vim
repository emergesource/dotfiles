" ~/.vim/plugin/statusline.vim
"
" Native statusline, coloured from the active theme's ANSI palette via
" autoload/colorkit.vim. Replaces lightline, which could only match a theme
" when one of its 37 bundled palettes happened to share the theme's name --
" for the other ~570 upstream themes it silently fell back to `one`.
"
"   [ MODE ]  branch  file [+]                    ff | enc | ft | 42% | 12:3
"
" Mode colours use ANSI 1..6, which mean the same thing in every theme:
" red / green / yellow / blue / magenta / cyan.

if exists('g:loaded_statusline_ui')
  finish
endif
let g:loaded_statusline_ui = 1

" ------------------------------------------------------------------ colours --
function! s:Highlights() abort
  let l:p = colorkit#palette()
  let l:bg = l:p.bg
  let l:fg = l:p.fg

  " the bar itself: a step off the editor background, and a dimmer inactive one
  let l:bar      = colorkit#mix(l:bg, l:fg, 0.14)
  let l:bar_dim  = colorkit#mix(l:bg, l:fg, 0.07)
  let l:sub      = colorkit#mix(l:bg, l:fg, 0.22)

  execute printf('highlight StatusLine   guibg=%s guifg=%s gui=NONE cterm=NONE ctermbg=236 ctermfg=252', l:bar, l:fg)
  execute printf('highlight StatusLineNC guibg=%s guifg=%s gui=NONE cterm=NONE ctermbg=234 ctermfg=244',
        \ l:bar_dim, colorkit#mix(l:bg, l:fg, 0.45))
  execute printf('highlight StatusBranch guibg=%s guifg=%s ctermbg=238 ctermfg=252', l:sub, l:fg)
  execute printf('highlight StatusInfo   guibg=%s guifg=%s ctermbg=236 ctermfg=245',
        \ l:bar, colorkit#mix(l:bg, l:fg, 0.62))

  " mode blocks -- solid accent, foreground picked for contrast against it
  for [l:name, l:idx] in [['Normal', 4], ['Insert', 2], ['Visual', 5],
        \                 ['Replace', 1], ['Command', 3], ['Terminal', 6]]
    let l:c = l:p.ansi[l:idx]
    execute printf('highlight StatusMode%s guibg=%s guifg=%s gui=bold cterm=bold ctermbg=%d ctermfg=0',
          \ l:name, l:c, colorkit#readable(l:c), l:idx)
  endfor
endfunction

augroup StatuslineColours
  autocmd!
  autocmd ColorScheme * call <SID>Highlights()
augroup END
call s:Highlights()

" -------------------------------------------------------------------- parts --
let s:modes = {
      \ 'n': ['NORMAL', 'Normal'],   'no': ['O-PEND', 'Normal'],
      \ 'i': ['INSERT', 'Insert'],   'ic': ['INSERT', 'Insert'],
      \ 'v': ['VISUAL', 'Visual'],   'V':  ['V-LINE', 'Visual'],
      \ "\<C-v>": ['V-BLOCK', 'Visual'],
      \ 's': ['SELECT', 'Visual'],   'S':  ['S-LINE', 'Visual'],
      \ 'R': ['REPLACE', 'Replace'], 'Rv': ['V-REPL', 'Replace'],
      \ 'c': ['COMMAND', 'Command'], 'cv': ['EX', 'Command'],
      \ 'r': ['PROMPT', 'Command'],  'rm': ['MORE', 'Command'],
      \ '!': ['SHELL', 'Command'],   't':  ['TERMINAL', 'Terminal'],
      \ }

function! StatuslineMode() abort
  return get(s:modes, mode(), ['?', 'Normal'])[0]
endfunction

function! StatuslineModeHL() abort
  return '%#StatusMode' . get(s:modes, mode(), ['?', 'Normal'])[1] . '#'
endfunction

" fugitive's branch, empty outside a repo
function! StatuslineBranch() abort
  if !exists('*FugitiveHead')
    return ''
  endif
  let l:head = FugitiveHead()
  return empty(l:head) ? '' : '  ' . l:head . ' '
endfunction

function! StatuslineFile() abort
  let l:name = expand('%:t')
  if empty(l:name) | let l:name = '[No Name]' | endif
  let l:flags = ''
  if &readonly || !&modifiable | let l:flags .= ' ' | endif
  if &modified | let l:flags .= ' +' | endif
  return ' ' . l:name . l:flags . ' '
endfunction

" ------------------------------------------------------------------- render --
function! StatuslineActive() abort
  let l:s  = '%{%StatuslineModeHL()%} %{StatuslineMode()} '
  let l:s .= '%#StatusBranch#%{StatuslineBranch()}'
  let l:s .= '%#StatusLine#%{StatuslineFile()}'
  let l:s .= '%='
  let l:s .= '%#StatusInfo# %{&ff} %{&fenc!=#""?&fenc:&enc} %{&ft!=#""?&ft:"no ft"} '
  let l:s .= '%#StatusLine# %3p%% %#StatusBranch# %3l:%-2c '
  return l:s
endfunction

function! StatuslineInactive() abort
  return ' %{StatuslineFile()}%= %{&ft} '
endfunction

augroup StatuslineSwap
  autocmd!
  autocmd WinEnter,BufWinEnter * setlocal statusline=%!StatuslineActive()
  autocmd WinLeave             * setlocal statusline=%!StatuslineInactive()
augroup END

set laststatus=2
set noshowmode                       " the mode block already says it
set statusline=%!StatuslineActive()
