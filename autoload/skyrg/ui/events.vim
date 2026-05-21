" autoload/skyrg/ui/events.vim — Lightweight event bus
"
" Decouples cross-pane updates. Panels register listeners, and any module
" can emit an event without knowing who cares.
"
" Events:
"   'results_changed'  — result list or selection changed
"   'form_changed'     — form field value changed
"   'pane_changed'     — active pane switched
"
" Usage:
"   call skyrg#ui#events#on('results_changed', function('s:my_handler'))
"   call skyrg#ui#events#emit('results_changed')

let s:listeners = {}

function! skyrg#ui#events#on(event, Fn) abort
  if !has_key(s:listeners, a:event)
    let s:listeners[a:event] = []
  endif
  call add(s:listeners[a:event], a:Fn)
endfunction

function! skyrg#ui#events#emit(event, ...) abort
  for l:Fn in get(s:listeners, a:event, [])
    call call(l:Fn, a:000)
  endfor
endfunction

function! skyrg#ui#events#reset() abort
  let s:listeners = {}
endfunction
