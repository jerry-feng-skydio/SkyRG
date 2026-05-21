" autoload/skyrg/panel/events.vim — COMPAT SHIM
" Delegates to skyrg#ui#events#*. Use skyrg#ui#events#* directly in new code.

function! skyrg#panel#events#on(event, Fn) abort
  call skyrg#ui#events#on(a:event, a:Fn)
endfunction

function! skyrg#panel#events#emit(event, ...) abort
  call call('skyrg#ui#events#emit', [a:event] + a:000)
endfunction

function! skyrg#panel#events#reset() abort
  call skyrg#ui#events#reset()
endfunction
