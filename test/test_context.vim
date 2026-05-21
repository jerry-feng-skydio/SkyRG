" test/test_context.vim — Tests for context action registry

function! s:test_context_register_and_get()
  call skyrg#backend#context#reset()
  call skyrg#backend#context#register({
    \ 'name': 'Test Action',
    \ 'key': 'x',
    \ 'execute': {ctx -> 0},
    \ })
  let l:ctx = {'word': 'hello', 'WORD': 'hello', 'line': '', 'col': 1,
    \ 'filetype': 'vim', 'mode': 'n', 'file': '/test.vim', 'dir': '/',
    \ 'visual': ''}
  let l:actions = skyrg#backend#context#get(l:ctx)
  " Should include our custom action + built-in actions
  call Assert(len(l:actions) >= 1, 'context: at least 1 action returned')
  " Find our custom action
  let l:found = 0
  for l:a in l:actions
    if l:a.name ==# 'Test Action'
      let l:found = 1
      break
    endif
  endfor
  call Assert(l:found, 'context: custom action found')
  call skyrg#backend#context#reset()
endfunction
call s:test_context_register_and_get()

function! s:test_context_predicate_filtering()
  call skyrg#backend#context#reset()
  call skyrg#backend#context#register({
    \ 'name': 'Only in visual',
    \ 'predicate': {ctx -> ctx.mode ==# 'v'},
    \ 'execute': {ctx -> 0},
    \ })
  call skyrg#backend#context#register({
    \ 'name': 'Always visible',
    \ 'execute': {ctx -> 0},
    \ })
  " Normal mode context
  let l:ctx_n = {'word': '', 'WORD': '', 'line': '', 'col': 1,
    \ 'filetype': '', 'mode': 'n', 'file': '', 'dir': '', 'visual': ''}
  let l:actions_n = skyrg#backend#context#get(l:ctx_n)
  let l:has_visual = 0
  for l:a in l:actions_n
    if l:a.name ==# 'Only in visual' | let l:has_visual = 1 | endif
  endfor
  call Assert(!l:has_visual, 'context predicate: visual-only not in normal mode')
  " Visual mode context
  let l:ctx_v = copy(l:ctx_n)
  let l:ctx_v.mode = 'v'
  let l:ctx_v.visual = 'text'
  let l:actions_v = skyrg#backend#context#get(l:ctx_v)
  let l:has_visual = 0
  for l:a in l:actions_v
    if l:a.name ==# 'Only in visual' | let l:has_visual = 1 | endif
  endfor
  call Assert(l:has_visual, 'context predicate: visual-only in visual mode')
  call skyrg#backend#context#reset()
endfunction
call s:test_context_predicate_filtering()

function! s:test_context_priority_ordering()
  call skyrg#backend#context#reset()
  call skyrg#backend#context#register_all([
    \ {'name': 'Low', 'priority': 200, 'execute': {ctx -> 0}},
    \ {'name': 'High', 'priority': 5, 'execute': {ctx -> 0}},
    \ {'name': 'Mid', 'priority': 50, 'execute': {ctx -> 0}},
    \ ])
  let l:ctx = {'word': '', 'WORD': '', 'line': '', 'col': 1,
    \ 'filetype': '', 'mode': 'n', 'file': '', 'dir': '', 'visual': ''}
  let l:actions = skyrg#backend#context#get(l:ctx)
  " High should come before Mid, Mid before Low
  let l:hi = -1 | let l:mi = -1 | let l:lo = -1
  for l:i in range(len(l:actions))
    if l:actions[l:i].name ==# 'High' | let l:hi = l:i | endif
    if l:actions[l:i].name ==# 'Mid'  | let l:mi = l:i | endif
    if l:actions[l:i].name ==# 'Low'  | let l:lo = l:i | endif
  endfor
  call Assert(l:hi >= 0 && l:mi >= 0 && l:lo >= 0, 'context priority: all actions found')
  call Assert(l:hi < l:mi, 'context priority: High before Mid')
  call Assert(l:mi < l:lo, 'context priority: Mid before Low')
  call skyrg#backend#context#reset()
endfunction
call s:test_context_priority_ordering()

function! s:test_context_builtins_loaded()
  call skyrg#backend#context#reset()
  let l:ctx = {'word': 'test', 'WORD': 'test', 'line': 'test line', 'col': 1,
    \ 'filetype': 'vim', 'mode': 'n', 'file': '/tmp/test.vim', 'dir': '/tmp',
    \ 'visual': ''}
  let l:actions = skyrg#backend#context#get(l:ctx)
  " Should have at least the built-in actions
  call Assert(len(l:actions) >= 4, 'context builtins: at least 4 actions for vim file with word')
  " Check that 'Search word under cursor' is present
  let l:found = 0
  for l:a in l:actions
    if l:a.name ==# 'Search word under cursor' | let l:found = 1 | break | endif
  endfor
  call Assert(l:found, 'context builtins: search-word action found')
  call skyrg#backend#context#reset()
endfunction
call s:test_context_builtins_loaded()
