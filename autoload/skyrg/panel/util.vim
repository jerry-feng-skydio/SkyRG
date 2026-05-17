" autoload/skyrg/panel/util.vim — Shared utilities
"
" Design notes:
"   - line() / hl_line(): Build popup line dicts {'text':..., 'props':[...]}
"     Used by every panel to avoid duplicating the same dict construction.
"   - short(): Relative path display helper.
"   - del_word(): Backward-delete for form field editing.

"==============================================================================
" Popup line builders
"==============================================================================

" Build a popup line with optional text-property spans.
"   skyrg#panel#util#line('hello')           → {'text': 'hello'}
"   skyrg#panel#util#line('hello', [props])  → {'text': 'hello', 'props': [...]}
function! skyrg#panel#util#line(text, ...) abort
  if a:0 > 0 && !empty(a:1)
    return {'text': a:text, 'props': a:1}
  endif
  return {'text': a:text}
endfunction

" Build a popup line highlighted with a single prop type across the full text.
"   skyrg#panel#util#hl_line('selected item', 'skyrg_sel')
function! skyrg#panel#util#hl_line(text, hl_type) abort
  return {'text': a:text, 'props': [
    \ {'col': 1, 'length': len(a:text), 'type': a:hl_type}]}
endfunction

"==============================================================================
" Path / text helpers
"==============================================================================

" Delete backward to the nearest comma, slash, or space
function! skyrg#panel#util#del_word(f) abort
  if a:f.pos == 0 | return | endif
  let l:b = a:f.value[:a:f.pos-1]
  let l:a = a:f.value[a:f.pos:]
  let l:b = substitute(l:b, '[^,/ ]*[,/ ]*$', '', '')
  let a:f.value = l:b . l:a | let a:f.pos = len(l:b)
endfunction

" Shorten a path relative to cwd
function! skyrg#panel#util#short(path) abort
  let l:cwd = getcwd() . '/'
  return a:path[:len(l:cwd)-1] ==# l:cwd ? a:path[len(l:cwd):] : a:path
endfunction
