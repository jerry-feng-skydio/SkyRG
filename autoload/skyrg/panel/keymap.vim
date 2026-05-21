" autoload/skyrg/panel/keymap.vim — COMPAT SHIM
" Delegates to skyrg#ui#keymap#*. Use skyrg#ui#keymap#* directly in new code.

function! skyrg#panel#keymap#get() abort
  return skyrg#ui#keymap#get()
endfunction

function! skyrg#panel#keymap#is(key, action) abort
  return skyrg#ui#keymap#is(a:key, a:action)
endfunction

function! skyrg#panel#keymap#reset() abort
  call skyrg#ui#keymap#reset()
endfunction
