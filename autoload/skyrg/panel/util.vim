" autoload/skyrg/panel/util.vim — COMPAT SHIM
" Delegates to skyrg#ui#util#*. Use skyrg#ui#util#* directly in new code.

function! skyrg#panel#util#line(text, ...) abort
  return call('skyrg#ui#util#line', [a:text] + a:000)
endfunction

function! skyrg#panel#util#hl_line(text, hl_type) abort
  return skyrg#ui#util#hl_line(a:text, a:hl_type)
endfunction

function! skyrg#panel#util#del_word(f) abort
  call skyrg#ui#util#del_word(a:f)
endfunction

function! skyrg#panel#util#short(path) abort
  return skyrg#ui#util#short(a:path)
endfunction
