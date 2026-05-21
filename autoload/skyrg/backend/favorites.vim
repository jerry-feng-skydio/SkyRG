" autoload/skyrg/backend/favorites.vim — Saved search favorites
"
" Persists favorite (starred) search queries per project. Simple JSON
" array storage with add/remove/edit operations.
"
" Storage: ~/.local/share/skyrg/favorites/<hash>.json
"
" Usage:
"   call skyrg#backend#favorites#add(entry)
"   call skyrg#backend#favorites#remove(idx)
"   let all = skyrg#backend#favorites#load_all()

"==============================================================================
" Storage path
"==============================================================================

function! s:data_dir() abort
  let l:base = exists('$XDG_DATA_HOME') && !empty($XDG_DATA_HOME)
    \ ? $XDG_DATA_HOME : expand('~/.local/share')
  return l:base . '/skyrg/favorites'
endfunction

function! s:fav_file(...) abort
  let l:root = a:0 > 0 ? a:1 : skyrg#backend#history#project_root()
  let l:hash = sha256(l:root)[:11]
  return s:data_dir() . '/' . l:hash . '.json'
endfunction

function! s:ensure_dir() abort
  let l:dir = s:data_dir()
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
endfunction

"==============================================================================
" CRUD
"==============================================================================

" Load all favorites for the current project.
function! skyrg#backend#favorites#load_all(...) abort
  let l:root = a:0 > 0 ? a:1 : skyrg#backend#history#project_root()
  let l:file = s:fav_file(l:root)
  if !filereadable(l:file)
    return []
  endif
  try
    let l:raw = join(readfile(l:file), '')
    return json_decode(l:raw)
  catch
    return []
  endtry
endfunction

" Add a favorite entry.
" Entry shape: {query, types, dirs, preset, gitignore, label, timestamp}
function! skyrg#backend#favorites#add(entry) abort
  let l:all = skyrg#backend#favorites#load_all()
  let l:entry = copy(a:entry)
  if !has_key(l:entry, 'timestamp')
    let l:entry.timestamp = localtime()
  endif
  if !has_key(l:entry, 'label')
    let l:entry.label = get(l:entry, 'query', 'Unnamed')
  endif
  call add(l:all, l:entry)
  call s:write(l:all)
endfunction

" Remove a favorite by index.
function! skyrg#backend#favorites#remove(idx) abort
  let l:all = skyrg#backend#favorites#load_all()
  if a:idx >= 0 && a:idx < len(l:all)
    call remove(l:all, a:idx)
    call s:write(l:all)
  endif
endfunction

" Update a favorite's label by index.
function! skyrg#backend#favorites#update_label(idx, label) abort
  let l:all = skyrg#backend#favorites#load_all()
  if a:idx >= 0 && a:idx < len(l:all)
    let l:all[a:idx].label = a:label
    call s:write(l:all)
  endif
endfunction

" Check if a query is already favorited.
function! skyrg#backend#favorites#is_favorited(query) abort
  let l:all = skyrg#backend#favorites#load_all()
  for l:f in l:all
    if get(l:f, 'query', '') ==# a:query
      return 1
    endif
  endfor
  return 0
endfunction

"==============================================================================
" Write helper
"==============================================================================

function! s:write(entries) abort
  call s:ensure_dir()
  let l:file = s:fav_file()
  let l:json = json_encode(a:entries)
  call writefile([l:json], l:file)
endfunction
