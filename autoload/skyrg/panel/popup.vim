" autoload/skyrg/panel/popup.vim — COMPAT SHIM
" Delegates to skyrg#ui#popup#*. Use skyrg#ui#popup#* directly in new code.

function! skyrg#panel#popup#create(content, opts) abort
  return skyrg#ui#popup#create(a:content, a:opts)
endfunction

function! skyrg#panel#popup#move(id, opts) abort
  call skyrg#ui#popup#move(a:id, a:opts)
endfunction
