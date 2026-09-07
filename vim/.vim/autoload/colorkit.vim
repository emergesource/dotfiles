" ~/.vim/autoload/colorkit.vim
"
" Small colour toolkit for deriving highlights from whatever theme is active,
" instead of hardcoding hex values that only suit one of them.
"
" The rule this exists to enforce: under 'termguicolors' vim uses guifg/guibg
" and ignores ctermfg/ctermbg entirely. A highlight that sets only cterm
" attributes is inert, and whatever the group already had shows instead --
" which is how ColorColumn ended up as vim's default DarkRed in every theme.
" Always set the gui attribute; set cterm too, for TTYs without truecolor.

function! colorkit#rgb(hex) abort
  let l:h = substitute(a:hex, '^#', '', '')
  return [str2nr(l:h[0:1], 16), str2nr(l:h[2:3], 16), str2nr(l:h[4:5], 16)]
endfunction

function! colorkit#hex(rgb) abort
  return printf('#%02x%02x%02x',
        \ max([0, min([255, a:rgb[0]])]),
        \ max([0, min([255, a:rgb[1]])]),
        \ max([0, min([255, a:rgb[2]])]))
endfunction

" WCAG relative luminance, 0.0 (black) .. 1.0 (white)
function! colorkit#lum(hex) abort
  let l:weights = [0.2126, 0.7152, 0.0722]
  let l:acc = 0.0
  let l:i = 0
  for l:c in colorkit#rgb(a:hex)
    let l:v = l:c / 255.0
    let l:v = l:v <= 0.03928 ? l:v / 12.92 : pow((l:v + 0.055) / 1.055, 2.4)
    let l:acc += l:v * l:weights[l:i]
    let l:i += 1
  endfor
  return l:acc
endfunction

" WCAG contrast ratio, 1.0 .. 21.0. AA body text wants >= 4.5.
function! colorkit#contrast(a, b) abort
  let l:x = colorkit#lum(a:a) + 0.05
  let l:y = colorkit#lum(a:b) + 0.05
  return l:x > l:y ? l:x / l:y : l:y / l:x
endfunction

" black or white, whichever is more readable on the given background
function! colorkit#readable(bg) abort
  return colorkit#contrast(a:bg, '#000000') >= colorkit#contrast(a:bg, '#ffffff')
        \ ? '#000000' : '#ffffff'
endfunction

" blend a towards b; t is 0.0 .. 1.0
function! colorkit#mix(a, b, t) abort
  let l:x = colorkit#rgb(a:a)
  let l:y = colorkit#rgb(a:b)
  return colorkit#hex([
        \ float2nr(l:x[0] + (l:y[0] - l:x[0]) * a:t),
        \ float2nr(l:x[1] + (l:y[1] - l:x[1]) * a:t),
        \ float2nr(l:x[2] + (l:y[2] - l:x[2]) * a:t)])
endfunction

" resolved gui colour of a highlight group, or '' -- a:what is 'fg' or 'bg'
function! colorkit#attr(group, what) abort
  let l:v = synIDattr(synIDtrans(hlID(a:group)), a:what . '#')
  return l:v =~? '^#\x\{6}$' ? l:v : ''
endfunction

" First non-empty gui colour among the given [group, what] pairs, else fallback.
function! colorkit#first(pairs, fallback) abort
  for [l:group, l:what] in a:pairs
    let l:v = colorkit#attr(l:group, l:what)
    if !empty(l:v) | return l:v | endif
  endfor
  return a:fallback
endfunction

" The editor background. Normal's guibg is NONE here (the vimrc keeps the
" terminal showing through), so fall back to the palette `theme` wrote, then to
" plain black/white by &background.
function! colorkit#bg() abort
  let l:bg = colorkit#attr('Normal', 'bg')
  if !empty(l:bg) | return l:bg | endif
  let l:pal = expand('~/.config/theme/current/palette.sh')
  if filereadable(l:pal)
    for l:line in readfile(l:pal)
      let l:m = matchlist(l:line, "^BG='\\?\\(\\x\\{6}\\)'\\?")
      if !empty(l:m) | return '#' . l:m[1] | endif
    endfor
  endif
  return &background ==# 'light' ? '#ffffff' : '#000000'
endfunction

function! colorkit#fg() abort
  return colorkit#first([['Normal', 'fg']], &background ==# 'light' ? '#000000' : '#ffffff')
endfunction

" True when the editor background is dark.
function! colorkit#is_dark() abort
  return colorkit#lum(colorkit#bg()) < 0.5
endfunction

" The active theme's 16-colour ANSI palette plus bg/fg, read from the file
" `theme` generates. This is exact for every upstream theme, where guessing
" from highlight groups is not -- Statement/Keyword vary wildly between
" colorschemes, but ANSI 1..6 always mean red/green/yellow/blue/magenta/cyan.
"
" Falls back to deriving from Diff* groups when no theme is installed.
let s:palette_cache = {}

function! colorkit#palette() abort
  let l:file = expand('~/.config/theme/current/palette.sh')
  let l:stamp = getftime(l:file)
  if has_key(s:palette_cache, 'stamp') && s:palette_cache.stamp == l:stamp
    return s:palette_cache.data
  endif

  let l:p = {'ansi': []}
  if filereadable(l:file)
    let l:vals = {}
    for l:line in readfile(l:file)
      let l:m = matchlist(l:line, "^\\(\\w\\+\\)='\\?\\([0-9a-fA-F]\\{6}\\)'\\?")
      if !empty(l:m) | let l:vals[l:m[1]] = '#' . l:m[2] | endif
    endfor
    let l:p.bg = get(l:vals, 'BG', colorkit#bg())
    let l:p.fg = get(l:vals, 'FG', colorkit#fg())
    for l:i in range(16)
      call add(l:p.ansi, get(l:vals, 'ANSI' . l:i, ''))
    endfor
  endif

  if empty(l:p.ansi) || empty(l:p.ansi[4])
    " no palette file: approximate from the theme's diff colours
    let l:p.bg = colorkit#bg()
    let l:p.fg = colorkit#fg()
    let l:red   = colorkit#first([['DiffDelete', 'bg']], '#bf616a')
    let l:green = colorkit#first([['DiffAdd', 'bg']], '#a3be8c')
    let l:yell  = colorkit#first([['DiffChange', 'bg']], '#ebcb8b')
    let l:blue  = colorkit#first([['DiffText', 'bg']], '#81a1c1')
    let l:p.ansi = ['#3b4252', l:red, l:green, l:yell, l:blue, '#b48ead',
          \ '#88c0d0', l:p.fg, '#4c566a', l:red, l:green, l:yell, l:blue,
          \ '#b48ead', '#8fbcbb', l:p.fg]
  endif

  let s:palette_cache = {'stamp': l:stamp, 'data': l:p}
  return l:p
endfunction
