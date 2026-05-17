" autoload/skyrg/panel/popup.vim — Popup factory with shared defaults
"
" Eliminates popup_create boilerplate. All SkyRG popups go through here,
" guaranteeing consistent styling (Normal highlight, rounded borders, etc.).
"
" Usage:
"   let id = skyrg#panel#popup#create(content, {
"     \ 'title': ' Results ',
"     \ 'line': 5, 'col': 3, 'width': 80, 'height': 20,
"     \ })
"
"   Optional overrides: any key accepted by popup_create().
"   The factory merges caller opts on top of defaults, so callers
"   only specify what differs.

let s:borderchars = ['─','│','─','│','╭','╮','╯','╰']

let s:defaults = {
  \ 'border': [],
  \ 'borderchars': s:borderchars,
  \ 'highlight': 'Normal',
  \ 'borderhighlight': ['Comment'],
  \ 'padding': [0,1,0,1],
  \ 'scrollbar': 1,
  \ 'zindex': 100,
  \ }

"==============================================================================
" Factory
"==============================================================================

" Create a popup with SkyRG defaults merged under caller overrides.
" Shorthand keys: 'width' → minwidth+maxwidth, 'height' → minheight+maxheight
function! skyrg#panel#popup#create(content, opts) abort
  let l:merged = copy(s:defaults)
  call extend(l:merged, a:opts)
  " Expand width/height shorthands
  if has_key(l:merged, 'width')
    let l:w = remove(l:merged, 'width')
    let l:merged.minwidth = l:w
    let l:merged.maxwidth = l:w
  endif
  if has_key(l:merged, 'height')
    let l:h = remove(l:merged, 'height')
    let l:merged.minheight = l:h
    let l:merged.maxheight = l:h
  endif
  return popup_create(a:content, l:merged)
endfunction

" Move + resize a popup using the same width/height shorthands.
function! skyrg#panel#popup#move(id, opts) abort
  let l:o = copy(a:opts)
  if has_key(l:o, 'width')
    let l:w = remove(l:o, 'width')
    let l:o.minwidth = l:w
    let l:o.maxwidth = l:w
  endif
  if has_key(l:o, 'height')
    let l:h = remove(l:o, 'height')
    let l:o.minheight = l:h
    let l:o.maxheight = l:h
  endif
  call popup_move(a:id, l:o)
endfunction
