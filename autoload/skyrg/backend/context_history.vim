" autoload/skyrg/backend/context_history.vim — Context action execution history
"
" In-memory ring buffer that records context popup action executions.
" Supports replay with captured user inputs (via skyrg#ui#input#prompt).
"
" Each entry: {
"   action:    the action dict (name, key, group, execute, etc.)
"   ctx:       the context at time of execution
"   inputs:    { key: value } captured from skyrg#ui#input#prompt()
"   timestamp: localtime()
"   label:     human-readable summary
" }

let s:ring = []
let s:max_size = 20

"==============================================================================
" Recording
"==============================================================================

" Record an action execution into the history ring.
function! skyrg#backend#context_history#record(action, ctx) abort
  " Don't record non-replayable actions
  if get(a:action, 'no_history', 0) | return | endif

  " Build a human-readable label
  let l:label = has_key(a:action, 'label_fn')
    \ ? a:action.label_fn(a:ctx) : a:action.name
  " Append captured inputs to label for clarity
  let l:inputs = skyrg#ui#input#harvest()
  if !empty(l:inputs)
    let l:input_parts = []
    for [l:k, l:v] in items(l:inputs)
      if !empty(l:v)
        let l:display = len(l:v) > 20 ? l:v[:17] . '...' : l:v
        call add(l:input_parts, l:display)
      endif
    endfor
    if !empty(l:input_parts)
      let l:label .= ' → ' . join(l:input_parts, ', ')
    endif
  endif

  let l:entry = {
    \ 'action': a:action,
    \ 'ctx': copy(a:ctx),
    \ 'inputs': l:inputs,
    \ 'timestamp': localtime(),
    \ 'label': l:label,
    \ }

  " Deduplicate: if the most recent entry has the same action name and
  " identical inputs, update its timestamp instead of adding a new entry.
  if !empty(s:ring)
    let l:last = s:ring[0]
    if l:last.action.name ==# a:action.name && l:last.inputs == l:inputs
      let l:last.timestamp = localtime()
      let l:last.ctx = copy(a:ctx)
      return
    endif
  endif

  " Prepend (newest first)
  call insert(s:ring, l:entry, 0)
  if len(s:ring) > s:max_size
    call remove(s:ring, s:max_size, -1)
  endif

  call skyrg#log#info('context_history', 'recorded "%s" (ring=%d)', l:label, len(s:ring))
endfunction

"==============================================================================
" Query
"==============================================================================

" Return the history ring (newest first).
function! skyrg#backend#context_history#entries() abort
  return s:ring
endfunction

" Return the Nth most recent entry (0-indexed), or {} if out of range.
function! skyrg#backend#context_history#get(idx) abort
  if a:idx >= 0 && a:idx < len(s:ring)
    return s:ring[a:idx]
  endif
  return {}
endfunction

" Return the ring size.
function! skyrg#backend#context_history#count() abort
  return len(s:ring)
endfunction

"==============================================================================
" Replay
"==============================================================================

" Replay a history entry.  Preloads captured inputs so that
" skyrg#ui#input#prompt() returns them automatically.
function! skyrg#backend#context_history#replay(idx) abort
  let l:entry = skyrg#backend#context_history#get(a:idx)
  if empty(l:entry)
    echohl WarningMsg | echo '[SkyRG] No history entry at index ' . a:idx | echohl None
    return
  endif

  call skyrg#log#info('context_history', 'replaying "%s"', l:entry.label)

  " Preload inputs for replay
  call skyrg#ui#input#preload(l:entry.inputs)

  " Re-execute the action with the original context
  call skyrg#backend#context#execute(l:entry.action, l:entry.ctx)
endfunction

"==============================================================================
" Formatting
"==============================================================================

" Format a human-readable relative time string.
function! skyrg#backend#context_history#relative_time(timestamp) abort
  let l:ago = localtime() - a:timestamp
  if l:ago < 60     | return l:ago . 's ago'     | endif
  if l:ago < 3600   | return (l:ago / 60) . 'm ago'   | endif
  if l:ago < 86400  | return (l:ago / 3600) . 'h ago'  | endif
  return (l:ago / 86400) . 'd ago'
endfunction
