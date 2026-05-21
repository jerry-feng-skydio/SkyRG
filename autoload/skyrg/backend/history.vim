" autoload/skyrg/backend/history.vim — Query history persistence
"
" Saves and loads search queries, scoped by project. Append-only JSONL
" storage with deduplication and compaction.
"
" Storage:  ~/.local/share/skyrg/history/<hash>.jsonl
" See docs/architecture/history.md for the full spec.
"
" Usage:
"   call skyrg#backend#history#save(entry)
"   let all  = skyrg#backend#history#load_all()
"   let last = skyrg#backend#history#load_last()

let s:MAX_ENTRIES = 10000
let s:COMPACT_KEEP_DAYS = 30
let s:COMPACT_KEEP_OLD = 5000

"==============================================================================
" Project root detection
"==============================================================================

function! skyrg#backend#history#project_root() abort
  let l:root = trim(system('git rev-parse --show-toplevel 2>/dev/null'))
  if v:shell_error == 0 && !empty(l:root)
    return l:root
  endif
  return getcwd()
endfunction

"==============================================================================
" Storage path
"==============================================================================

function! s:data_dir() abort
  let l:base = exists('$XDG_DATA_HOME') && !empty($XDG_DATA_HOME)
    \ ? $XDG_DATA_HOME : expand('~/.local/share')
  return l:base . '/skyrg/history'
endfunction

function! s:history_file(...) abort
  let l:root = a:0 > 0 ? a:1 : skyrg#backend#history#project_root()
  let l:hash = sha256(l:root)[:11]
  return s:data_dir() . '/' . l:hash . '.jsonl'
endfunction

function! s:ensure_dir() abort
  let l:dir = s:data_dir()
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
endfunction

"==============================================================================
" Save
"==============================================================================

" Save a query entry to history. Deduplicates against the most recent entry.
"
" Entry shape: {query, types, dirs, preset, gitignore, timestamp, result_count}
function! skyrg#backend#history#save(entry) abort
  let l:entry = copy(a:entry)
  if !has_key(l:entry, 'timestamp')
    let l:entry.timestamp = localtime()
  endif
  " Skip empty queries
  if empty(get(l:entry, 'query', ''))
    return
  endif
  " Deduplicate: compare against most recent entry
  let l:last = skyrg#backend#history#load_last()
  if !empty(l:last) && s:entries_equal(l:entry, l:last)
    return
  endif
  call s:ensure_dir()
  let l:file = s:history_file()
  let l:line = json_encode(l:entry)
  call writefile([l:line], l:file, 'a')
  call skyrg#log#debug('history', 'saved query="%s"', l:entry.query)
endfunction

" Compare two entries ignoring timestamp and result_count.
function! s:entries_equal(a, b) abort
  return get(a:a, 'query', '') ==# get(a:b, 'query', '')
    \ && get(a:a, 'types', '') ==# get(a:b, 'types', '')
    \ && get(a:a, 'dirs', '') ==# get(a:b, 'dirs', '')
    \ && get(a:a, 'preset', '') ==# get(a:b, 'preset', '')
    \ && get(a:a, 'gitignore', 1) == get(a:b, 'gitignore', 1)
endfunction

"==============================================================================
" Load
"==============================================================================

" Load all history entries for the current project, newest first.
function! skyrg#backend#history#load_all(...) abort
  let l:t = skyrg#log#timer()
  let l:root = a:0 > 0 ? a:1 : skyrg#backend#history#project_root()
  let l:file = s:history_file(l:root)
  if !filereadable(l:file)
    return []
  endif
  let l:lines = readfile(l:file)
  let l:entries = []
  for l:line in l:lines
    try
      let l:e = json_decode(l:line)
      call add(l:entries, l:e)
    catch
      " Skip malformed lines
    endtry
  endfor
  " Newest first
  call reverse(l:entries)
  call skyrg#log#elapsed_debug(l:t, 'history', 'load_all entries=%d', len(l:entries))
  " Compact if over threshold
  if len(l:entries) > s:MAX_ENTRIES
    call s:compact(l:root, l:entries)
  endif
  return l:entries
endfunction

" Load the most recent entry for the current project, or {} if none.
function! skyrg#backend#history#load_last(...) abort
  let l:root = a:0 > 0 ? a:1 : skyrg#backend#history#project_root()
  let l:file = s:history_file(l:root)
  if !filereadable(l:file)
    return {}
  endif
  " Read last non-empty line (faster than parsing everything)
  let l:lines = readfile(l:file)
  let l:i = len(l:lines) - 1
  while l:i >= 0
    if !empty(trim(l:lines[l:i]))
      try
        return json_decode(l:lines[l:i])
      catch
      endtry
    endif
    let l:i -= 1
  endwhile
  return {}
endfunction

" Search history by substring filter on the query field.
function! skyrg#backend#history#search(filter, ...) abort
  let l:root = a:0 > 0 ? a:1 : skyrg#backend#history#project_root()
  let l:all = skyrg#backend#history#load_all(l:root)
  if empty(a:filter)
    return l:all
  endif
  let l:pat = tolower(a:filter)
  return filter(l:all, {_, e -> tolower(get(e, 'query', '')) =~# l:pat})
endfunction

"==============================================================================
" Delete
"==============================================================================

" Delete entry matching a given timestamp.
function! skyrg#backend#history#delete(timestamp, ...) abort
  let l:root = a:0 > 0 ? a:1 : skyrg#backend#history#project_root()
  let l:file = s:history_file(l:root)
  if !filereadable(l:file)
    return
  endif
  let l:lines = readfile(l:file)
  let l:kept = []
  for l:line in l:lines
    try
      let l:e = json_decode(l:line)
      if get(l:e, 'timestamp', 0) != a:timestamp
        call add(l:kept, l:line)
      endif
    catch
      call add(l:kept, l:line)
    endtry
  endfor
  call writefile(l:kept, l:file)
  call skyrg#log#debug('history', 'deleted ts=%d, %d entries remain', a:timestamp, len(l:kept))
endfunction

"==============================================================================
" Compaction
"==============================================================================

function! s:compact(root, entries) abort
  let l:now = localtime()
  let l:cutoff = l:now - (s:COMPACT_KEEP_DAYS * 86400)
  " Deduplicate: keep newest of each unique query
  let l:seen = {}
  let l:deduped = []
  for l:e in a:entries
    let l:key = get(l:e, 'query', '') . '|' . get(l:e, 'types', '')
      \ . '|' . get(l:e, 'dirs', '') . '|' . get(l:e, 'preset', '')
    if !has_key(l:seen, l:key)
      let l:seen[l:key] = 1
      call add(l:deduped, l:e)
    endif
  endfor
  " Keep all from last N days + up to MAX older entries
  let l:recent = filter(copy(l:deduped), {_, e -> get(e, 'timestamp', 0) >= l:cutoff})
  let l:older = filter(copy(l:deduped), {_, e -> get(e, 'timestamp', 0) < l:cutoff})
  if len(l:older) > s:COMPACT_KEEP_OLD
    let l:older = l:older[:s:COMPACT_KEEP_OLD - 1]
  endif
  let l:final = l:recent + l:older
  " Write back (oldest first for append-order)
  call reverse(l:final)
  let l:lines = map(copy(l:final), {_, e -> json_encode(e)})
  let l:file = s:history_file(a:root)
  let l:tmp = l:file . '.tmp'
  call writefile(l:lines, l:tmp)
  call rename(l:tmp, l:file)
  call skyrg#log#info('history', 'compacted %d → %d entries', len(a:entries), len(l:final))
endfunction
