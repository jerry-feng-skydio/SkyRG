" autoload/skyrg/ui/input.vim — Input prompt with record/replay support
"
" Drop-in replacement for input() that captures user responses for
" history replay.  During normal execution, behaves like input() but
" records the response.  During replay (after preload()), returns the
" stored value instead of prompting.
"
" Usage:
"   " Normal — prompts and records
"   let val = skyrg#ui#input#prompt('search_term', '[SkyRG] Search for: ')
"   let val = skyrg#ui#input#prompt('search_term', '[SkyRG] Search for: ', 'default')
"
"   " Replay — preload inputs, then calls to prompt() return stored values
"   call skyrg#ui#input#preload({'search_term': 'ucon'})
"
"   " Harvest — retrieve all captured inputs (called after action executes)
"   let inputs = skyrg#ui#input#harvest()

" Captured inputs during current action execution.
" { key: value }
let s:captured = {}

" Preloaded inputs for replay. When set, prompt() returns these
" instead of calling input().  Consumed on harvest().
let s:preloaded = {}

"==============================================================================
" Public API
"==============================================================================

" Prompt the user for input. Records the response under `key` for replay.
"
"   key     — unique identifier for this input within the action
"   prompt  — the prompt string shown to the user
"   default — optional default value
"
" During replay (after preload), returns the stored value without prompting.
function! skyrg#ui#input#prompt(key, prompt, ...) abort
  let l:default = a:0 > 0 ? a:1 : ''

  " Replay mode: return preloaded value
  if has_key(s:preloaded, a:key)
    let l:val = s:preloaded[a:key]
    let s:captured[a:key] = l:val
    echo printf('%s%s (replayed)', a:prompt, l:val)
    return l:val
  endif

  " Normal mode: prompt and record
  let l:val = input(a:prompt, l:default)
  let s:captured[a:key] = l:val
  return l:val
endfunction

" Preload inputs for replay. Next calls to prompt() will return these
" values instead of prompting the user.
function! skyrg#ui#input#preload(inputs) abort
  let s:preloaded = copy(a:inputs)
  let s:captured = {}
endfunction

" Harvest all captured inputs and reset state.
" Called by the history recorder after an action completes.
function! skyrg#ui#input#harvest() abort
  let l:result = copy(s:captured)
  let s:captured = {}
  let s:preloaded = {}
  return l:result
endfunction

" Reset all state (e.g. before a new action execution).
function! skyrg#ui#input#reset() abort
  let s:captured = {}
  let s:preloaded = {}
endfunction
