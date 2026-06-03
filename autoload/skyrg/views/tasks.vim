" autoload/skyrg/views/tasks.vim — Task viewer popup
"
" Shows active and recent tasks with live output preview.
"
" Usage:
"   call skyrg#views#tasks#open()
"
" Keys:
"   j/k or Down/Up   — select task
"   Enter             — open full log in a split
"   c                 — cancel running task
"   f                 — trigger followup actions
"   q / Esc           — close

let s:popup_list = 0
let s:popup_output = 0
let s:selected = 0
let s:refresh_timer = 0
let s:out_opts = {}

"==============================================================================
" Open
"==============================================================================

" Open the most recent task's log file in a split.
function! skyrg#views#tasks#open_last_log() abort
  let l:all = skyrg#backend#tasks#all()
  if !empty(l:all)
    let l:log = get(l:all[0], 'log_file', '')
    if !empty(l:log) && filereadable(l:log)
      call s:open_log_split(l:log, l:all[0].status ==# 'running')
      return
    endif
  endif
  " Fall back to index
  let l:entries = skyrg#backend#action_log#list()
  if !empty(l:entries)
    let l:path = skyrg#backend#action_log#path(l:entries[0])
    if !empty(l:path) && filereadable(l:path)
      call s:open_log_split(l:path, 0)
      return
    endif
  endif
  echo '[SkyRG] No action logs found'
endfunction

function! skyrg#views#tasks#open() abort
  let l:tasks = skyrg#backend#tasks#all()
  " Also include recent tasks from the action log if memory is empty
  if empty(l:tasks)
    let l:log_entries = skyrg#backend#action_log#list()
    if empty(l:log_entries)
      echo '[SkyRG] No tasks'
      return
    endif
  endif

  call s:close_popups()
  call skyrg#ui#style#init()
  let s:selected = 0

  let l:width = min([&columns - 4, 80])
  let l:list_h = min([&lines / 3, 12])
  let l:out_h = &lines - l:list_h - 8

  " Task list popup
  let s:popup_list = popup_create(s:render_list(), {
    \ 'title': ' Tasks ',
    \ 'line': 2,
    \ 'col': (&columns - l:width) / 2,
    \ 'pos': 'topleft',
    \ 'border': [1,1,1,1],
    \ 'borderchars': ['─','│','─','│','┌','┐','┘','└'],
    \ 'borderhighlight': ['Title'],
    \ 'padding': [0,1,0,1],
    \ 'minwidth': l:width,
    \ 'maxwidth': l:width,
    \ 'minheight': l:list_h,
    \ 'maxheight': l:list_h,
    \ 'scrollbar': 1,
    \ 'filter': function('s:on_key'),
    \ 'mapping': 0,
    \ 'callback': function('s:on_close'),
    \ 'zindex': 250,
    \ })

  " Output preview popup — stored opts for recreation on refresh
  let s:out_opts = {
    \ 'title': ' Output ',
    \ 'line': l:list_h + 5,
    \ 'col': (&columns - l:width) / 2,
    \ 'pos': 'topleft',
    \ 'border': [1,1,1,1],
    \ 'borderchars': ['─','│','─','│','┌','┐','┘','└'],
    \ 'padding': [0,1,0,1],
    \ 'minwidth': l:width,
    \ 'maxwidth': l:width,
    \ 'minheight': l:out_h,
    \ 'maxheight': l:out_h,
    \ 'scrollbar': 1,
    \ 'zindex': 249,
    \ }
  call s:recreate_output()

  " Auto-refresh while open (for running tasks)
  let s:refresh_timer = timer_start(1000, function('s:refresh'), {'repeat': -1})
  call skyrg#log#info('views/tasks', 'open')
endfunction

"==============================================================================
" Rendering
"==============================================================================

function! s:render_list() abort
  let l:tasks = skyrg#backend#tasks#all()
  if empty(l:tasks)
    " Fall back to log index
    let l:entries = skyrg#backend#action_log#list()
    return s:render_log_entries(l:entries)
  endif

  let l:lines = []
  for l:i in range(len(l:tasks))
    let l:t = l:tasks[l:i]
    let l:icon = s:status_icon(l:t.status)
    let l:dur = s:format_dur(l:t)
    let l:text = printf('  %s %-35s %6s  [%s]', l:icon, l:t.title[:34], l:dur, l:t.status)
    if l:i == s:selected
      call add(l:lines, {'text': l:text, 'props': [{'col': 1, 'length': len(l:text), 'type': 'skyrg_sel'}]})
    else
      call add(l:lines, {'text': l:text})
    endif
  endfor
  return l:lines
endfunction

function! s:render_log_entries(entries) abort
  let l:lines = []
  for l:i in range(len(a:entries))
    let l:e = a:entries[l:i]
    let l:icon = get(l:e, 'exit_code', 0) == 0 ? '✓' : '✗'
    let l:dur = ''
    if has_key(l:e, 'end_time') && has_key(l:e, 'start_time')
      let l:secs = l:e.end_time - l:e.start_time
      let l:dur = l:secs >= 60 ? printf('%dm', l:secs / 60) : printf('%ds', l:secs)
    endif
    let l:text = printf('  %s %-35s %6s  [%s]',
      \ l:icon, get(l:e, 'title', '?')[:34], l:dur, get(l:e, 'status', '?'))
    if l:i == s:selected
      call add(l:lines, {'text': l:text, 'props': [{'col': 1, 'length': len(l:text), 'type': 'skyrg_sel'}]})
    else
      call add(l:lines, {'text': l:text})
    endif
  endfor
  return empty(l:lines) ? [{'text': '  (no tasks)'}] : l:lines
endfunction

function! s:render_output() abort
  let l:tasks = skyrg#backend#tasks#all()

  " In-memory task available
  if !empty(l:tasks) && s:selected < len(l:tasks)
    let l:t = l:tasks[s:selected]
    let l:title = l:t.title
    let l:stdout_ref = l:t.stdout
    let l:stderr_ref = l:t.stderr
    call skyrg#log#debug('views/tasks', 'render_output: task=%s status=%s stdout=%d stderr=%d',
      \ l:title, l:t.status, len(l:stdout_ref), len(l:stderr_ref))
    let l:combined = []
    " NOTE: explicit while-loop — list[-N:] slicing has edge cases with
    " async-modified lists on Vim 9.1
    let l:start = len(l:stdout_ref) > 50 ? len(l:stdout_ref) - 50 : 0
    let l:idx = l:start
    while l:idx < len(l:stdout_ref)
      call add(l:combined, {'text': '  ' . l:stdout_ref[l:idx]})
      let l:idx += 1
    endwhile
    if !empty(l:stderr_ref)
      call add(l:combined, {'text': ''})
      let l:idx = len(l:stderr_ref) > 20 ? len(l:stderr_ref) - 20 : 0
      while l:idx < len(l:stderr_ref)
        let l:line = l:stderr_ref[l:idx]
        call add(l:combined, {'text': '  ' . l:line, 'props': [{'col': 3, 'length': len(l:line), 'type': 'skyrg_dim'}]})
        let l:idx += 1
      endwhile
    endif
    if !empty(l:combined)
      call s:set_output_title(l:title)
      return l:combined
    endif
    " Task exists but no output buffered — try reading log file from disk
    let l:log = get(l:t, 'log_file', '')
    if !empty(l:log)
      let l:from_disk = s:read_log_output(l:log)
      if !empty(l:from_disk)
        call s:set_output_title(l:title)
        return l:from_disk
      endif
    endif
    call s:set_output_title(l:title)
    return [{'text': '  (no output yet)'}]
  endif

  " Fall back to log index entries (previous session tasks)
  let l:entries = skyrg#backend#action_log#list()
  if !empty(l:entries) && s:selected < len(l:entries)
    let l:e = l:entries[s:selected]
    let l:title = get(l:e, 'title', '?')
    let l:path = skyrg#backend#action_log#path(l:e)
    if !empty(l:path)
      let l:from_disk = s:read_log_output(l:path)
      if !empty(l:from_disk)
        call s:set_output_title(l:title)
        return l:from_disk
      endif
    endif
    call s:set_output_title(l:title)
    return [{'text': '  (log file not found)'}]
  endif

  return [{'text': '  (select a task)'}]
endfunction

" Read a task log file and return popup-formatted output lines.
" Log format: header (=== ... ===), blank, output lines, blank, footer (=== ...)
function! s:read_log_output(path) abort
  if !filereadable(a:path) | return [] | endif
  let l:raw = readfile(a:path)
  let l:combined = []
  let l:sep_count = 0
  for l:line in l:raw
    " Count separator lines (====...): 1st ends the header preamble,
    " 2nd ends the header block, 3rd starts the footer
    if l:line =~# '^=\+$'
      let l:sep_count += 1
      continue
    endif
    " Skip everything in the header (before 2nd separator)
    if l:sep_count < 2
      continue
    endif
    " Skip blank lines immediately after header
    if empty(l:line) && empty(l:combined)
      continue
    endif
    if l:line =~# '^\[stderr\]'
      call add(l:combined, {'text': '  ' . l:line, 'props': [{'col': 3, 'length': len(l:line), 'type': 'skyrg_dim'}]})
    else
      call add(l:combined, {'text': '  ' . substitute(l:line, '^\[stdout\] ', '', '')})
    endif
  endfor
  " Cap at last 70 lines
  return l:combined[-70:]
endfunction

function! s:set_output_title(title) abort
  if !empty(s:out_opts)
    let s:out_opts.title = ' Output: ' . a:title . ' '
  endif
endfunction

function! s:status_icon(status) abort
  if a:status ==# 'running'  | return '⟳' | endif
  if a:status ==# 'awaiting' | return '❗' | endif
  if a:status ==# 'done'     | return '✓' | endif
  if a:status ==# 'failed'   | return '✗' | endif
  return '?'
endfunction

function! s:format_dur(task) abort
  let l:end = a:task.end_time > 0 ? a:task.end_time : localtime()
  let l:secs = l:end - a:task.start_time
  if l:secs >= 60
    return printf('%dm%ds', l:secs / 60, l:secs % 60)
  endif
  return printf('%ds', l:secs)
endfunction

"==============================================================================
" Key handling
"==============================================================================

function! s:on_key(winid, key) abort
  let l:count = s:item_count()

  if a:key ==# "\<Esc>" || a:key ==# 'q'
    call s:close_popups()
    return 1
  endif

  if a:key ==# 'j' || a:key ==# "\<Down>"
    let s:selected = min([l:count - 1, s:selected + 1])
    call s:update()
    return 1
  endif
  if a:key ==# 'k' || a:key ==# "\<Up>"
    let s:selected = max([0, s:selected - 1])
    call s:update()
    return 1
  endif

  " Enter: open full log with styling + auto-tail
  if a:key ==# "\<CR>"
    let l:log = s:selected_log_path()
    let l:is_running = s:selected_is_running()
    if !empty(l:log) && filereadable(l:log)
      call s:close_popups()
      call s:open_log_split(l:log, l:is_running)
    endif
    return 1
  endif

  " c: cancel running task
  if a:key ==# 'c'
    let l:tasks = skyrg#backend#tasks#all()
    if s:selected < len(l:tasks)
      let l:t = l:tasks[s:selected]
      if l:t.status ==# 'running' && has_key(l:t, 'job')
        call job_stop(l:t.job)
        call skyrg#log#info('views/tasks', 'cancel #%d "%s"', l:t.id, l:t.title)
        echom printf('[SkyRG] Cancelling: %s', l:t.title)
      endif
    endif
    return 1
  endif

  " f: open followup actions for awaiting task
  if a:key ==# 'f'
    let l:tasks = skyrg#backend#tasks#all()
    if s:selected < len(l:tasks)
      let l:t = l:tasks[s:selected]
      if l:t.status ==# 'awaiting'
        call s:close_popups()
        call skyrg#backend#action#show_followups(l:t.id)
      endif
    endif
    return 1
  endif

  " d: dismiss followups on awaiting task
  if a:key ==# 'd'
    let l:tasks = skyrg#backend#tasks#all()
    if s:selected < len(l:tasks)
      let l:t = l:tasks[s:selected]
      if l:t.status ==# 'awaiting'
        call skyrg#backend#tasks#dismiss_followups(l:t.id)
        call s:update()
      endif
    endif
    return 1
  endif

  return 1
endfunction

" Return the total number of items (in-memory tasks or log entries).
function! s:item_count() abort
  let l:tasks = skyrg#backend#tasks#all()
  if !empty(l:tasks) | return len(l:tasks) | endif
  return len(skyrg#backend#action_log#list())
endfunction

" Return the log file path for the currently selected item.
function! s:selected_log_path() abort
  let l:tasks = skyrg#backend#tasks#all()
  if !empty(l:tasks) && s:selected < len(l:tasks)
    return get(l:tasks[s:selected], 'log_file', '')
  endif
  let l:entries = skyrg#backend#action_log#list()
  if !empty(l:entries) && s:selected < len(l:entries)
    return skyrg#backend#action_log#path(l:entries[s:selected])
  endif
  return ''
endfunction

function! s:on_close(id, result) abort
  call s:stop_refresh()
  let s:popup_list = 0
  if s:popup_output
    silent! call popup_close(s:popup_output)
    let s:popup_output = 0
  endif
endfunction

"==============================================================================
" Refresh / update
"==============================================================================

function! s:update() abort
  if s:popup_list
    call popup_settext(s:popup_list, s:render_list())
  endif
  call s:recreate_output()
endfunction

" Recreate the output popup from scratch.
" popup_settext from timer callbacks doesn't visually update a non-filtered
" popup while another popup's filter is active — so we close + recreate.
function! s:recreate_output() abort
  if s:popup_output
    silent! call popup_close(s:popup_output)
    let s:popup_output = 0
  endif
  if !empty(s:out_opts)
    let s:popup_output = popup_create(s:render_output(), s:out_opts)
  endif
endfunction

function! s:refresh(timer) abort
  " Stop if popups are gone
  if !s:popup_list || empty(popup_getpos(s:popup_list))
    call s:stop_refresh()
    return
  endif
  call s:update()
endfunction

function! s:stop_refresh() abort
  if s:refresh_timer
    call timer_stop(s:refresh_timer)
    let s:refresh_timer = 0
  endif
endfunction

function! s:close_popups() abort
  call s:stop_refresh()
  if s:popup_list
    silent! call popup_close(s:popup_list)
    let s:popup_list = 0
  endif
  if s:popup_output
    silent! call popup_close(s:popup_output)
    let s:popup_output = 0
  endif
endfunction

" Check if the currently selected task is running.
function! s:selected_is_running() abort
  let l:tasks = skyrg#backend#tasks#all()
  if !empty(l:tasks) && s:selected < len(l:tasks)
    return l:tasks[s:selected].status ==# 'running'
  endif
  return 0
endfunction

"==============================================================================
" Log split helper — delegates to skyrg#ui#live_split
"==============================================================================

function! s:open_log_split(path, tail) abort
  call skyrg#ui#live_split#open({
    \ 'title': fnamemodify(a:path, ':t'),
    \ 'source': 'file',
    \ 'path': a:path,
    \ })
endfunction

"==============================================================================
" Monitor — public API for auto-opening log splits from action.vim
"==============================================================================

" { task_id: live_split_id }
let s:monitors = {}

function! skyrg#views#tasks#open_monitor(log_path, task_id) abort
  let l:id = skyrg#ui#live_split#open({
    \ 'title': fnamemodify(a:log_path, ':t'),
    \ 'source': 'file',
    \ 'path': a:log_path,
    \ })
  let s:monitors[a:task_id] = l:id
endfunction

function! skyrg#views#tasks#close_monitor(task_id) abort
  let l:id = get(s:monitors, a:task_id, -1)
  if l:id == -1 | return | endif
  call skyrg#ui#live_split#close(l:id)
  call remove(s:monitors, a:task_id)
endfunction

function! skyrg#views#tasks#stop_monitor_tail(task_id) abort
  let l:id = get(s:monitors, a:task_id, -1)
  if l:id == -1 | return | endif
  call skyrg#ui#live_split#stop(l:id)
  call remove(s:monitors, a:task_id)
endfunction
