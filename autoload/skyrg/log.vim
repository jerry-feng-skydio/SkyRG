" skyrg/log.vim - Logging utilities
" Uses g:skyrg_verbose to gate debug output.

function! skyrg#log#status(msg, ...) abort
  echom call('printf', [a:msg] + a:000)
endfunction

function! skyrg#log#debug(msg, ...) abort
  if !get(g:, 'skyrg_verbose', 0)
    return
  endif
  echom call('printf', [a:msg] + a:000)
endfunction

function! skyrg#log#error(msg, ...) abort
  echohl ErrorMsg
  echom call('printf', [a:msg] + a:000)
  echohl None
endfunction
