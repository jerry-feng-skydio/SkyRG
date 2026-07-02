" autoload/skyrg/backend/action_log.vim — Per-task log files + retention
"
" Each dispatched action gets its own log file with a header containing
" command, CWD, context, and exit status, followed by interleaved
" stdout/stderr lines.
"
" Storage:  ~/.local/share/skyrg/actions/
"   index.jsonl                    — one JSON line per task (quick listing)
"   task_<id>_<timestamp>.log     — per-task output
"
" Retention (configurable):
"   g:skyrg_action_log_keep_days   — keep all logs for N days (default: 7)
"   g:skyrg_action_log_keep_failed — keep failed logs for N days (default: 30)
"
" Usage:
"   let file = skyrg#backend#action_log#create(task)
"   call skyrg#backend#action_log#append(file, 'stdout', 'line of output')
"   call skyrg#backend#action_log#finalize(task)
"   call skyrg#backend#action_log#compact()
"   let entries = skyrg#backend#action_log#list()

let s:compacted = 0

"==============================================================================
" Storage paths
"==============================================================================

function! s:data_dir() abort
  let l:base = exists('$XDG_DATA_HOME') && !empty($XDG_DATA_HOME)
    \ ? $XDG_DATA_HOME : expand('~/.local/share')
  return l:base . '/skyrg/actions'
endfunction

function! s:ensure_dir() abort
  let l:dir = s:data_dir()
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
endfunction

function! s:index_file() abort
  return s:data_dir() . '/index.jsonl'
endfunction

"==============================================================================
" Create — called when a task starts
"==============================================================================

" Create a log file for a task and write the header.
" Returns the absolute path to the log file.
function! skyrg#backend#action_log#create(task) abort
  call s:ensure_dir()
  let l:fname = printf('task_%d_%d.log', a:task.id, a:task.start_time)
  let l:path = s:data_dir() . '/' . l:fname

  let l:header = [
    \ '=== SkyRG Action Log ===',
    \ 'Task ID:   ' . a:task.id,
    \ 'Action:    ' . a:task.title,
    \ 'Command:   ' . a:task.cmd,
    \ 'CWD:       ' . get(a:task, 'cwd', getcwd()),
    \ 'Started:   ' . strftime('%Y-%m-%d %H:%M:%S', a:task.start_time),
    \ 'Context:   ' . json_encode(get(a:task, 'context', {})),
    \ repeat('=', 60),
    \ '',
    \ ]
  call writefile(l:header, l:path)
  return l:path
endfunction

"==============================================================================
" Append — called for each stdout/stderr line
"==============================================================================

function! skyrg#backend#action_log#append(log_file, stream, line) abort
  if empty(a:log_file) | return | endif
  let l:prefix = a:stream ==# 'stderr' ? '[stderr] ' : '[stdout] '
  call writefile([l:prefix . a:line], a:log_file, 'a')
endfunction

"==============================================================================
" Finalize — called when a task completes
"==============================================================================

" Append exit info to the log file and write the index entry.
function! skyrg#backend#action_log#finalize(task) abort
  let l:log = get(a:task, 'log_file', '')
  if !empty(l:log)
    let l:footer = [
      \ '',
      \ repeat('=', 60),
      \ 'Exit code: ' . a:task.exit_code,
      \ 'Duration:  ' . printf('%.1fs', (a:task.end_time - a:task.start_time)),
      \ 'Finished:  ' . strftime('%Y-%m-%d %H:%M:%S', a:task.end_time),
      \ ]
    call writefile(l:footer, l:log, 'a')
  endif

  " Append to index
  call s:ensure_dir()
  let l:entry = {
    \ 'id': a:task.id,
    \ 'title': a:task.title,
    \ 'cmd': a:task.cmd,
    \ 'status': a:task.status,
    \ 'exit_code': a:task.exit_code,
    \ 'start_time': a:task.start_time,
    \ 'end_time': a:task.end_time,
    \ 'log_file': fnamemodify(l:log, ':t'),
    \ }
  call writefile([json_encode(l:entry)], s:index_file(), 'a')
  call skyrg#log#debug('action_log', 'finalized task %d "%s" exit=%d',
    \ a:task.id, a:task.title, a:task.exit_code)
endfunction

"==============================================================================
" List — read index for task viewer
"==============================================================================

function! skyrg#backend#action_log#list() abort
  let l:file = s:index_file()
  if !filereadable(l:file) | return [] | endif
  let l:entries = []
  for l:line in readfile(l:file)
    try
      call add(l:entries, json_decode(l:line))
    catch
    endtry
  endfor
  call reverse(l:entries)
  return l:entries
endfunction

"==============================================================================
" Log file retrieval
"==============================================================================

" Return the absolute path for a task's log file.
function! skyrg#backend#action_log#path(task_or_entry) abort
  let l:fname = get(a:task_or_entry, 'log_file', '')
  if empty(l:fname) | return '' | endif
  " If already absolute, return as-is
  if l:fname[0] ==# '/'
    return l:fname
  endif
  return s:data_dir() . '/' . l:fname
endfunction

" Read the context dict from a log file header.
" Parses the 'Context:   {...}' line without reading the whole file.
function! skyrg#backend#action_log#read_context(path) abort
  if !filereadable(a:path) | return {} | endif
  for l:line in readfile(a:path, '', 15)
    if l:line =~# '^Context:\s\+'
      try
        return json_decode(substitute(l:line, '^Context:\s\+', '', ''))
      catch
      endtry
    endif
  endfor
  return {}
endfunction

" Return the actions data directory.
function! skyrg#backend#action_log#dir() abort
  return s:data_dir()
endfunction

"==============================================================================
" Retention / compaction
"==============================================================================

function! skyrg#backend#action_log#compact() abort
  let l:file = s:index_file()
  if !filereadable(l:file) | return | endif
  let l:t = skyrg#log#timer()
  let l:now = localtime()
  let l:keep_days = get(g:, 'skyrg_action_log_keep_days', 7)
  let l:keep_failed = get(g:, 'skyrg_action_log_keep_failed', 30)
  let l:keep_secs = l:keep_days * 86400
  let l:keep_failed_secs = l:keep_failed * 86400

  let l:lines = readfile(l:file)
  let l:kept = []
  let l:deleted = 0

  for l:line in l:lines
    try
      let l:e = json_decode(l:line)
      let l:age = l:now - get(l:e, 'end_time', get(l:e, 'start_time', 0))
      let l:is_failed = get(l:e, 'exit_code', 0) != 0

      if l:age < l:keep_secs
        " Hot: keep everything
        call add(l:kept, l:line)
      elseif l:is_failed && l:age < l:keep_failed_secs
        " Warm: keep failed tasks longer
        call add(l:kept, l:line)
      else
        " Cold: delete log file, drop from index
        let l:log_path = s:data_dir() . '/' . get(l:e, 'log_file', '')
        if filereadable(l:log_path)
          call delete(l:log_path)
        endif
        let l:deleted += 1
      endif
    catch
      " Keep unparseable lines (safety)
      call add(l:kept, l:line)
    endtry
  endfor

  if l:deleted > 0
    call writefile(l:kept, l:file)
    call skyrg#log#info('action_log', 'compacted: removed %d entries, %d remain',
      \ l:deleted, len(l:kept))
  endif
  call skyrg#log#elapsed_debug(l:t, 'action_log', 'compact check (%d entries)', len(l:lines))
endfunction

" Run compaction once per session (called from plugin load or first task).
function! skyrg#backend#action_log#maybe_compact() abort
  if s:compacted | return | endif
  let s:compacted = 1
  call skyrg#backend#action_log#compact()
endfunction
