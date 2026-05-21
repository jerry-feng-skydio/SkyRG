" autoload/skyrg/views/search.vim — Search view (canonical entry point)
"
" Composes the search form, results list, preview, info, and tree panes
" with the rg backend. This is the primary entry point for the search UI.
"
" The view currently delegates to the existing panel.vim for popup lifecycle
" and key dispatch, while adding query-loading capability. Future phases
" will migrate the internal wiring onto the generic window system.
"
" Usage:
"   " Open with defaults
"   call skyrg#views#search#open()
"
"   " Open with pre-filled fields (for history, favorites, context actions)
"   call skyrg#views#search#open({
"     \ 'query':     'TODO',
"     \ 'types':     'py',
"     \ 'dirs':      'src/',
"     \ 'preset':    'python',
"     \ 'gitignore': 1,
"     \ })

"==============================================================================
" Open
"==============================================================================

" History navigation state (PageUp/PageDown through past queries)
let s:hist_nav = {'entries': [], 'nav_idx': -1, 'saved_query': {}}

function! skyrg#views#search#open(...) abort
  let l:params = a:0 > 0 && type(a:1) == v:t_dict ? a:1 : {}
  if empty(l:params) && get(g:, 'skyrg_restore_last', 1)
    " No params at all: full restore from history
    let l:last = skyrg#backend#history#load_last()
    if !empty(l:last)
      let l:params = l:last
    endif
  elseif !empty(l:params) && !get(l:params, '_complete', 0)
    " Partial params (e.g. context action passes only 'query'):
    " merge on top of last history so the user keeps their filter scope
    let l:last = skyrg#backend#history#load_last()
    if !empty(l:last)
      let l:merged = copy(l:last)
      call extend(l:merged, l:params)
      let l:params = l:merged
      call skyrg#log#debug('views/search', 'merged partial params with last history')
    endif
  endif
  " Strip internal flag before passing downstream
  if has_key(l:params, '_complete')
    call remove(l:params, '_complete')
  endif
  call skyrg#panel#set_opening_via_view()
  call skyrg#panel#open(l:params)
  call skyrg#log#info('views/search', 'open')
  " Reset history navigation state
  let s:hist_nav = {'entries': [], 'nav_idx': -1, 'saved_query': {}}
endfunction

"==============================================================================
" Query loading (used by history, context actions, favorites)
"==============================================================================

" Load a query dict into the currently-open search form.
" Does nothing if the panel isn't open.
function! skyrg#views#search#load_query(params) abort
  try
    let l:s = skyrg#panel#state()
  catch
    return
  endtry
  let l:c = skyrg#panel#const()
  if has_key(a:params, 'query')
    let l:s.form.fields[l:c.QUERY].value = a:params.query
    let l:s.form.fields[l:c.QUERY].pos = len(a:params.query)
  endif
  if has_key(a:params, 'dirs')
    let l:s.form.fields[l:c.DIRS].value = a:params.dirs
    let l:s.form.fields[l:c.DIRS].pos = len(a:params.dirs)
  endif
  if has_key(a:params, 'types')
    let l:s.form.fields[l:c.TYPES].value = a:params.types
    let l:s.form.fields[l:c.TYPES].pos = len(a:params.types)
  endif
  if has_key(a:params, 'preset')
    let l:s.form.fields[l:c.PRESET].value = a:params.preset
    let l:s.form.fields[l:c.PRESET].pos = len(a:params.preset)
    " Apply preset side-effects (types + dirs)
    if !empty(a:params.preset)
      call skyrg#panel#preset#apply(a:params.preset)
    endif
  endif
  if has_key(a:params, 'gitignore')
    let l:s.form.fields[l:c.GITIGN].value = a:params.gitignore ? 'on' : 'off'
  endif
  let l:s._search_dirty = 1
  call skyrg#panel#form#redraw()
endfunction

"==============================================================================
" Query snapshot (for history saving)
"==============================================================================

" Return a dict capturing the current search form state.
function! skyrg#views#search#get_query() abort
  try
    let l:s = skyrg#panel#state()
  catch
    return {}
  endtry
  let l:c = skyrg#panel#const()
  return {
    \ 'query':     l:s.form.fields[l:c.QUERY].value,
    \ 'dirs':      l:s.form.fields[l:c.DIRS].value,
    \ 'types':     l:s.form.fields[l:c.TYPES].value,
    \ 'preset':    l:s.form.fields[l:c.PRESET].value,
    \ 'gitignore': l:s.form.fields[l:c.GITIGN].value ==# 'on' ? 1 : 0,
    \ }
endfunction

"==============================================================================
" Browse mode (references, etc.)
"==============================================================================

function! skyrg#views#search#browse(matches, title) abort
  call skyrg#panel#browse(a:matches, a:title)
endfunction

"==============================================================================
" History commit (called when user executes a search or jumps to a match)
"==============================================================================

function! skyrg#views#search#commit_to_history(...) abort
  let l:q = skyrg#views#search#get_query()
  if empty(get(l:q, 'query', ''))
    return
  endif
  let l:entry = copy(l:q)
  let l:entry.timestamp = localtime()
  if a:0 > 0
    let l:entry.result_count = a:1
  endif
  call skyrg#log#info('views/search', 'commit_to_history query="%s"', l:entry.query)
  call skyrg#backend#history#save(l:entry)
endfunction

"==============================================================================
" History navigation (PageUp/PageDown in the form pane)
"==============================================================================

" Navigate backward through history (older queries).
function! skyrg#views#search#history_prev() abort
  call s:ensure_hist_entries()
  if empty(s:hist_nav.entries) | return | endif

  if s:hist_nav.nav_idx == -1
    " First PageUp: snapshot current query, load most recent history entry
    let s:hist_nav.saved_query = skyrg#views#search#get_query()
    let s:hist_nav.nav_idx = 0
  elseif s:hist_nav.nav_idx < len(s:hist_nav.entries) - 1
    let s:hist_nav.nav_idx += 1
  else
    return
  endif
  call skyrg#log#debug('views/search', 'history_prev idx=%d/%d', s:hist_nav.nav_idx, len(s:hist_nav.entries))
  call skyrg#views#search#load_query(s:hist_nav.entries[s:hist_nav.nav_idx])
endfunction

" Navigate forward through history (newer queries / back to current).
function! skyrg#views#search#history_next() abort
  if s:hist_nav.nav_idx < 0 | return | endif

  if s:hist_nav.nav_idx > 0
    let s:hist_nav.nav_idx -= 1
    call skyrg#views#search#load_query(s:hist_nav.entries[s:hist_nav.nav_idx])
  else
    " Back to the original (pre-navigation) query
    let s:hist_nav.nav_idx = -1
    call skyrg#views#search#load_query(s:hist_nav.saved_query)
  endif
endfunction

" Reset navigation state (called when user edits a field manually).
function! skyrg#views#search#history_nav_reset() abort
  let s:hist_nav.nav_idx = -1
  let s:hist_nav.saved_query = {}
endfunction

" Lazy-load history entries on first navigation.
function! s:ensure_hist_entries() abort
  if !empty(s:hist_nav.entries) | return | endif
  let s:hist_nav.entries = skyrg#backend#history#load_all()
endfunction

"==============================================================================
" Clear all fields (Ctrl+Backspace in form pane)
"==============================================================================

function! skyrg#views#search#clear_all() abort
  call skyrg#log#info('views/search', 'clear_all')
  try
    let l:s = skyrg#panel#state()
  catch
    return
  endtry
  let l:c = skyrg#panel#const()
  for l:i in range(l:c.NFIELDS)
    if l:i == l:c.GITIGN
      let l:s.form.fields[l:i].value = 'on'
    else
      let l:s.form.fields[l:i].value = ''
    endif
    let l:s.form.fields[l:i].pos = 0
  endfor
  let l:s._search_dirty = 1
  call skyrg#panel#form#redraw()
endfunction
