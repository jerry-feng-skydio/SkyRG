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

function! skyrg#views#search#open(...) abort
  let l:params = a:0 > 0 && type(a:1) == v:t_dict ? a:1 : {}
  call skyrg#panel#open(l:params)
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
