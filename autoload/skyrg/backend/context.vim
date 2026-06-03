" autoload/skyrg/backend/context.vim — Context action registry
"
" Manages cursor-aware actions for the context popup. Actions are filtered
" by predicates that check the current context (filetype, visual mode,
" cursor position, etc.).
"
" See docs/architecture/context-popup.md for the full spec.
"
" Usage:
"   call skyrg#backend#context#register(action)
"   let actions = skyrg#backend#context#get(ctx)
"   call skyrg#backend#context#execute(action, ctx)
"
" Action shape: {
"   name:      'Search word under cursor',
"   key:       'w',
"   predicate: {ctx -> !empty(ctx.word)},
"   execute:   {ctx -> skyrg#views#search#open({'query': ctx.word})},
"   group:     'search',      " optional, for visual grouping
"   priority:  100,           " optional, lower = higher in list
" }
"
" Context shape (built by views/context.vim): {
"   word:      expand('<cword>'),
"   WORD:      expand('<cWORD>'),
"   line:      getline('.'),
"   col:       col('.'),
"   filetype:  &filetype,
"   visual:    selected text (in visual mode) or '',
"   mode:      'n' or 'v',
"   file:      expand('%:p'),
"   dir:       expand('%:p:h'),
" }

let s:actions = []
let s:initialized = 0

"==============================================================================
" Registration
"==============================================================================

function! skyrg#backend#context#register(action) abort
  call add(s:actions, a:action)
  " Sort by priority (lower = higher in list)
  call sort(s:actions, {a, b -> get(a, 'priority', 100) - get(b, 'priority', 100)})
endfunction

" Register multiple actions at once.
function! skyrg#backend#context#register_all(actions) abort
  for l:a in a:actions
    call add(s:actions, l:a)
  endfor
  call sort(s:actions, {a, b -> get(a, 'priority', 100) - get(b, 'priority', 100)})
endfunction

" Remove all registered actions (for testing).
function! skyrg#backend#context#reset() abort
  let s:actions = []
  let s:initialized = 0
endfunction

"==============================================================================
" Query
"==============================================================================

" Get all actions that pass their predicate for the given context.
function! skyrg#backend#context#get(ctx) abort
  call s:ensure_builtins()
  let l:result = []
  for l:a in s:actions
    if !has_key(l:a, 'predicate') || l:a.predicate(a:ctx)
      call add(l:result, l:a)
    endif
  endfor
  return l:result
endfunction

" Execute an action with the given context.
" Routes through the action dispatch engine which handles vim/shell/job types.
function! skyrg#backend#context#execute(action, ctx) abort
  call skyrg#backend#action#dispatch(a:action, a:ctx)
endfunction

"==============================================================================
" Built-in actions
"==============================================================================

function! s:ensure_builtins() abort
  if s:initialized | return | endif
  let s:initialized = 1

  " Also register user-defined actions
  for l:a in get(g:, 'skyrg_context_actions', [])
    call skyrg#backend#context#register(l:a)
  endfor

  call skyrg#backend#context#register_all([
    \ {
    \   'name': 'Search word under cursor',
    \   'label_fn': {ctx -> printf('Search "%s"', ctx.word)},
    \   'key': 'w',
    \   'group': 'search',
    \   'priority': 10,
    \   'predicate': {ctx -> !empty(ctx.word)},
    \   'execute': {ctx -> skyrg#views#search#open({'query': ctx.word})},
    \ },
    \ {
    \   'name': 'Search selection',
    \   'label_fn': {ctx -> printf('Search "%s"', len(ctx.visual) > 30 ? ctx.visual[:27].'...' : ctx.visual)},
    \   'key': 's',
    \   'group': 'search',
    \   'priority': 11,
    \   'predicate': {ctx -> ctx.mode ==# 'v' && !empty(ctx.visual)},
    \   'execute': {ctx -> skyrg#views#search#open({'query': ctx.visual})},
    \ },
    \ {
    \   'name': 'Search in this directory',
    \   'key': 'd',
    \   'group': 'search',
    \   'priority': 20,
    \   'predicate': {ctx -> !empty(ctx.dir)},
    \   'execute': {ctx -> skyrg#views#search#open({'dirs': ctx.dir})},
    \ },
    \ {
    \   'name': 'Search word in this directory',
    \   'label_fn': {ctx -> printf('Search "%s" in %s/', ctx.word, fnamemodify(ctx.dir, ':t'))},
    \   'key': 'D',
    \   'group': 'search',
    \   'priority': 21,
    \   'predicate': {ctx -> !empty(ctx.word) && !empty(ctx.dir)},
    \   'execute': {ctx -> skyrg#views#search#open({'query': ctx.word, 'dirs': ctx.dir})},
    \ },
    \ {
    \   'name': 'Search this filetype',
    \   'key': 't',
    \   'group': 'search',
    \   'priority': 30,
    \   'predicate': {ctx -> !empty(ctx.filetype)},
    \   'execute': {ctx -> skyrg#views#search#open({'types': ctx.filetype})},
    \ },
    \ {
    \   'name': 'Search word in this filetype',
    \   'label_fn': {ctx -> printf('Search "%s" in *.%s', ctx.word, ctx.filetype)},
    \   'key': 'T',
    \   'group': 'search',
    \   'priority': 31,
    \   'predicate': {ctx -> !empty(ctx.word) && !empty(ctx.filetype)},
    \   'execute': {ctx -> skyrg#views#search#open({'query': ctx.word, 'types': ctx.filetype})},
    \ },
    \ {
    \   'name': 'Open SkyRG',
    \   'key': 'o',
    \   'group': 'open',
    \   'priority': 50,
    \   'execute': {ctx -> skyrg#views#search#open()},
    \ },
    \ {
    \   'name': 'History browser',
    \   'key': 'h',
    \   'group': 'open',
    \   'priority': 60,
    \   'predicate': {ctx -> exists('*skyrg#views#history#open')},
    \   'execute': {ctx -> skyrg#views#history#open()},
    \ },
    \ {
    \   'name': 'Revup Topics',
    \   'key': 'r',
    \   'group': 'revup',
    \   'priority': 70,
    \   'predicate': {ctx -> ctx.filetype ==# 'gitcommit'},
    \   'execute': {ctx -> skyrg#revup#show()},
    \ },
    \ {
    \   'name': 'Build flashpack',
    \   'key': 'b',
    \   'group': 'device',
    \   'priority': 80,
    \   'predicate': {ctx -> skyrg#backend#device#is_connected()},
    \   'execute': {ctx -> skyrg#views#device#build_flashpack(ctx)},
    \ },
    \ {
    \   'name': 'Tail device logs',
    \   'key': 'l',
    \   'group': 'device',
    \   'priority': 81,
    \   'predicate': {ctx -> skyrg#backend#device#is_connected()},
    \   'execute': {ctx -> skyrg#views#device#tail_logs(ctx)},
    \ },
    \ {
    \   'name': 'View remote file',
    \   'key': 'v',
    \   'group': 'device',
    \   'priority': 82,
    \   'predicate': {ctx -> skyrg#backend#device#is_connected()},
    \   'execute': {ctx -> skyrg#views#device#view_file(ctx)},
    \ },
    \ {
    \   'name': 'SSH to device',
    \   'key': 'S',
    \   'group': 'device',
    \   'priority': 83,
    \   'predicate': {ctx -> skyrg#backend#device#is_connected()},
    \   'execute': {ctx -> skyrg#views#device#ssh(ctx)},
    \ },
    \ {
    \   'name': 'Refresh device detection',
    \   'key': 'R',
    \   'group': 'device',
    \   'priority': 89,
    \   'execute': {ctx -> skyrg#views#device#refresh(ctx)},
    \ },
    \ {
    \   'name': 'Instabug (dump screen to log)',
    \   'key': '!',
    \   'group': 'debug',
    \   'priority': 99,
    \   'execute': {ctx -> skyrg#instabug#dump()},
    \ },
    \ {
    \   'name': 'Save log to file',
    \   'key': 'w',
    \   'group': 'live_split',
    \   'priority': 90,
    \   'predicate': {ctx -> skyrg#ui#live_split#is_live_split(bufnr('%'))},
    \   'execute': {ctx -> skyrg#ui#live_split#save_current()},
    \ },
    \ {
    \   'name': 'Close live split',
    \   'key': 'q',
    \   'group': 'live_split',
    \   'priority': 91,
    \   'predicate': {ctx -> skyrg#ui#live_split#is_live_split(bufnr('%'))},
    \   'execute': {ctx -> skyrg#ui#live_split#close_current()},
    \ },
    \ ])
endfunction
