" ~/.vim/plugin/conflicts.vim
"
" Inline merge-conflict resolution, using VS Code's vocabulary: Current Change,
" Incoming Change, Accept Both. Everything happens in one buffer -- no splits.
"
" Depends on rhysd/conflict-marker.vim (declared in .vimrc). Auto-loaded from
" ~/.vim/plugin/, so it applies to vim and nvim alike.
"
"   ,x                    the Resolve Conflict menu
"   ]x  [x                next / previous conflict
"   :AcceptCurrentChange  :AcceptIncomingChange
"   :AcceptBothChanges    :DiscardBothChanges
"   :ContrastReport       measured WCAG ratios for the current theme

if exists('g:loaded_conflicts_ui')
  finish
endif
let g:loaded_conflicts_ui = 1

let g:conflict_marker_enable_highlight = 1
let g:conflict_marker_enable_mappings = 1

" ================================================================= colours ===
" Current = green, Incoming = blue: taken from the theme's own DiffAdd and
" DiffText, so this follows `theme` automatically. Every label sets BOTH a
" foreground and a background -- the previous version set only a background,
" which is why the words disappeared: no theme defines a fg on DiffAdd.
function! s:ConflictColours() abort
  let l:bg  = colorkit#bg()
  let l:cur = colorkit#attr('DiffAdd',  'bg')
  let l:inc = colorkit#attr('DiffText', 'bg')
  if empty(l:cur) | let l:cur = '#4a8f4a' | endif
  if empty(l:inc) | let l:inc = '#4a72b8' | endif
  let l:base = colorkit#mix(l:bg, colorkit#attr('Comment', 'fg') is# '' ? '#808080' : colorkit#attr('Comment', 'fg'), 0.55)

  " Header bars: solid accent, foreground chosen for contrast against it.
  execute printf('highlight ConflictMarkerBegin      guibg=%s guifg=%s gui=bold', l:cur, colorkit#readable(l:cur))
  execute printf('highlight ConflictMarkerSeparator  guibg=%s guifg=%s gui=bold', l:inc, colorkit#readable(l:inc))
  execute printf('highlight ConflictMarkerEnd        guibg=%s guifg=%s gui=bold', l:inc, colorkit#readable(l:inc))
  execute printf('highlight ConflictMarkerCommonAncestors guibg=%s guifg=%s gui=bold', l:base, colorkit#readable(l:base))

  " Content blocks: a light wash only, and deliberately no guifg, so your
  " syntax highlighting still shows through the tint.
  execute printf('highlight ConflictMarkerOurs                guibg=%s', colorkit#mix(l:bg, l:cur, 0.16))
  execute printf('highlight ConflictMarkerTheirs              guibg=%s', colorkit#mix(l:bg, l:inc, 0.16))
  execute printf('highlight ConflictMarkerCommonAncestorsHunk guibg=%s', colorkit#mix(l:bg, l:base, 0.12))

  " Virtual-text labels reuse the header bar colours.
  highlight! link ConflictLabelCurrent  ConflictMarkerBegin
  highlight! link ConflictLabelIncoming ConflictMarkerSeparator
  highlight! link ConflictLabelBase     ConflictMarkerCommonAncestors
endfunction

augroup ConflictColours
  autocmd!
  autocmd ColorScheme * call <SID>ConflictColours()
augroup END
call s:ConflictColours()

" ============================================================ text labels ====
if has('textprop')
  for s:t in ['cmCur', 'cmInc', 'cmBase']
    silent! call prop_type_delete(s:t)
  endfor
  call prop_type_add('cmCur',  {'highlight': 'ConflictLabelCurrent'})
  call prop_type_add('cmInc',  {'highlight': 'ConflictLabelIncoming'})
  call prop_type_add('cmBase', {'highlight': 'ConflictLabelBase'})
endif

function! s:Label() abort
  if !has('textprop') | return | endif
  for l:t in ['cmCur', 'cmInc', 'cmBase']
    silent! call prop_remove({'type': l:t, 'all': v:true})
  endfor
  let l:n = 0
  for l:lnum in range(1, line('$'))
    let l:line = getline(l:lnum)
    if l:line =~# '^<<<<<<<'
      let l:n += 1
      call prop_add(l:lnum, 0, {'type': 'cmCur', 'text_align': 'after',
            \ 'text': printf('  (Current Change)  conflict %d  ', l:n)})
    elseif l:line =~# '^|||||||'
      call prop_add(l:lnum, 0, {'type': 'cmBase', 'text_align': 'after',
            \ 'text': '  (Common Ancestor)  '})
    elseif l:line =~# '^======='
      call prop_add(l:lnum, 0, {'type': 'cmInc', 'text_align': 'after',
            \ 'text': '  (Incoming Change)  '})
    endif
  endfor
endfunction

" =================================================================== state ===
function! s:Count() abort
  return len(filter(getline(1, '$'), {_, l -> l =~# '^<<<<<<<'}))
endfunction

function! s:Report() abort
  let l:left = s:Count()
  if l:left == 0
    echohl MoreMsg
    echo '  All conflicts resolved — :w to save, then :Git commit'
    echohl None
  else
    echohl WarningMsg
    echo printf('  %d unresolved conflict%s   ,x for actions  ·  ]x next',
          \ l:left, l:left == 1 ? '' : 's')
    echohl None
  endif
endfunction

" ================================================================= actions ===
function! s:Accept(which) abort
  let l:plug = {
        \ 'current':  "\<Plug>(conflict-marker-ourselves)",
        \ 'incoming': "\<Plug>(conflict-marker-themselves)",
        \ 'both':     "\<Plug>(conflict-marker-both)",
        \ 'neither':  "\<Plug>(conflict-marker-none)"}[a:which]
  let l:name = {
        \ 'current':  'Accepted Current Change',
        \ 'incoming': 'Accepted Incoming Change',
        \ 'both':     'Accepted Both Changes',
        \ 'neither':  'Discarded Both Changes'}[a:which]
  if getline('.') !~# '^\(<<<<<<<\|||||||||\?\|=======\|>>>>>>>\)'
        \ && search('^<<<<<<<', 'bcnW') == 0
    silent! execute 'normal' "\<Plug>(conflict-marker-next-hunk)"
  endif
  execute 'normal' l:plug
  call s:Label()
  redraw
  echohl Title | echo '  ' . l:name | echohl None
  echon '  ·'
  call s:Report()
endfunction

function! s:Jump(dir) abort
  execute 'normal' (a:dir ==# 'next'
        \ ? "\<Plug>(conflict-marker-next-hunk)"
        \ : "\<Plug>(conflict-marker-prev-hunk)")
  normal! zz
  call s:Report()
endfunction

" ==================================================================== menu ===
function! s:Menu() abort
  redraw
  echohl Title | echo 'Resolve Conflict   ' | echohl None
  echohl ConflictMarkerBegin     | echon ' c ' | echohl None
  echon ' Accept Current Change   '
  echohl ConflictMarkerSeparator | echon ' i ' | echohl None
  echon ' Accept Incoming Change   '
  echohl DiffText                | echon ' b ' | echohl None
  echon ' Accept Both Changes   '
  echohl ErrorMsg                | echon ' n ' | echohl None
  echon ' Discard Both   '
  echohl Comment                 | echon ' j/k ' | echohl None
  echon ' next/prev   '
  echohl Comment                 | echon ' q ' | echohl None
  echon ' cancel'

  let l:c = nr2char(getchar())
  redraw | echo ''
  if     l:c ==# 'c' | call s:Accept('current')
  elseif l:c ==# 'i' | call s:Accept('incoming')
  elseif l:c ==# 'b' | call s:Accept('both')
  elseif l:c ==# 'n' | call s:Accept('neither')
  elseif l:c ==# 'j' | call s:Jump('next')
  elseif l:c ==# 'k' | call s:Jump('prev')
  endif
endfunction

" ================================================================ commands ===
command! AcceptCurrentChange   call <SID>Accept('current')
command! AcceptIncomingChange  call <SID>Accept('incoming')
command! AcceptBothChanges     call <SID>Accept('both')
command! DiscardBothChanges    call <SID>Accept('neither')
command! NextConflict          call <SID>Jump('next')
command! PrevConflict          call <SID>Jump('prev')
command! Conflicts             call <SID>Report()

nnoremap <silent> <leader>x :call <SID>Menu()<CR>

" ================================================================= on open ===
augroup ConflictOnOpen
  autocmd!
  autocmd BufReadPost,BufEnter * if s:Count() > 0 | call s:Label() | endif
  autocmd BufReadPost * if s:Count() > 0
        \ |   silent! execute 'normal' "\<Plug>(conflict-marker-next-hunk)"
        \ |   normal! zz
        \ |   call s:Report()
        \ | endif
augroup END

" A quick self-check: :ContrastReport prints the measured WCAG ratios.
function! s:ContrastReport() abort
  call s:ConflictColours()
  for [l:label, l:grp] in [['Current ', 'ConflictMarkerBegin'],
        \                  ['Incoming', 'ConflictMarkerSeparator'],
        \                  ['Ancestor', 'ConflictMarkerCommonAncestors']]
    let l:b = colorkit#attr(l:grp, 'bg')
    let l:f = colorkit#attr(l:grp, 'fg')
    echo printf('%s  bg=%s fg=%s  contrast %.1f:1  %s',
          \ l:label, l:b, l:f, colorkit#contrast(l:b, l:f),
          \ colorkit#contrast(l:b, l:f) >= 4.5 ? 'PASS (AA)' : 'FAIL')
  endfor
endfunction
command! -bar ContrastReport call <SID>ContrastReport()
