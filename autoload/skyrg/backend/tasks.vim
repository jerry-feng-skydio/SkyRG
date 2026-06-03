" autoload/skyrg/backend/tasks.vim — Task registry and lifecycle
"
" Tracks all active and recently-completed async tasks. Provides a
" statusline component and task listing for the task viewer.
"
" Usage:
"   let id = skyrg#backend#tasks#add(task_dict)
"   let task = skyrg#backend#tasks#get(id)
"   call skyrg#backend#tasks#update(id, changes)
"   call skyrg#backend#tasks#complete(id, exit_code)
"   let running = skyrg#backend#tasks#running()
"   let all = skyrg#backend#tasks#all()
"   let str = skyrg#backend#tasks#statusline()

let s:tasks = {}
let s:next_id = 1
let s:max_recent = 20

"==============================================================================
" Registration
"==============================================================================

" Add a new task. Returns the task ID.
"
" Required keys: title, cmd
" Optional: cwd, context, action, on_success, on_failure
function! skyrg#backend#tasks#add(task) abort
  let l:id = s:next_id
  let s:next_id += 1

  let l:t = extend(copy(a:task), {
    \ 'id':         l:id,
    \ 'status':     'running',
    \ 'start_time': localtime(),
    \ 'end_time':   0,
    \ 'exit_code':  -1,
    \ 'stdout':     [],
    \ 'stderr':     [],
    \ })

  " Create log file
  let l:t.log_file = skyrg#backend#action_log#create(l:t)
  let s:tasks[l:id] = l:t

  call skyrg#log#info('tasks', 'started #%d "%s"', l:id, l:t.title)
  return l:id
endfunction

"==============================================================================
" Lifecycle
"==============================================================================

" Get a task by ID.
function! skyrg#backend#tasks#get(id) abort
  return get(s:tasks, a:id, {})
endfunction

" Update task fields (e.g. job handle).
function! skyrg#backend#tasks#update(id, changes) abort
  if has_key(s:tasks, a:id)
    call extend(s:tasks[a:id], a:changes)
  endif
endfunction

" Append an output line to a task's buffer and log file.
function! skyrg#backend#tasks#append_output(id, stream, line) abort
  if !has_key(s:tasks, a:id) | return | endif
  let l:t = s:tasks[a:id]
  let l:buf = a:stream ==# 'stderr' ? l:t.stderr : l:t.stdout
  " Ring buffer: keep last 500 lines in memory
  if len(l:buf) >= 500
    call remove(l:buf, 0)
  endif
  call add(l:buf, a:line)
  call skyrg#backend#action_log#append(l:t.log_file, a:stream, a:line)
endfunction

" Mark a task as complete.
function! skyrg#backend#tasks#complete(id, exit_code) abort
  if !has_key(s:tasks, a:id) | return | endif
  let l:t = s:tasks[a:id]
  let l:t.exit_code = a:exit_code
  let l:t.end_time = localtime()
  let l:t.status = a:exit_code == 0 ? 'done' : 'failed'

  " Finalize the log file
  call skyrg#backend#action_log#finalize(l:t)

  let l:dur = l:t.end_time - l:t.start_time
  call skyrg#log#info('tasks', 'completed #%d "%s" exit=%d (%ds)',
    \ a:id, l:t.title, a:exit_code, l:dur)

  " Prune old completed tasks from memory
  call s:prune()

  return l:t
endfunction

"==============================================================================
" Query
"==============================================================================

" Return list of currently running tasks.
function! skyrg#backend#tasks#running() abort
  return filter(values(s:tasks), {_, t -> t.status ==# 'running'})
endfunction

" Return all tasks (running + recent completed), newest first.
function! skyrg#backend#tasks#all() abort
  let l:list = values(s:tasks)
  call sort(l:list, {a, b -> b.start_time - a.start_time})
  return l:list
endfunction

" Return count of running tasks.
function! skyrg#backend#tasks#running_count() abort
  return len(skyrg#backend#tasks#running())
endfunction

" Return list of tasks awaiting followup, newest first.
function! skyrg#backend#tasks#awaiting() abort
  let l:list = filter(values(s:tasks), {_, t -> t.status ==# 'awaiting'})
  call sort(l:list, {a, b -> b.end_time - a.end_time})
  return l:list
endfunction

" Store followup actions on a task and mark it as awaiting.
function! skyrg#backend#tasks#set_followups(id, followups, ctx) abort
  if !has_key(s:tasks, a:id) | return | endif
  let l:t = s:tasks[a:id]
  let l:t.followups = a:followups
  let l:t.followup_ctx = a:ctx
  let l:t.status = 'awaiting'
  call skyrg#log#info('tasks', 'awaiting #%d "%s" (%d followups)',
    \ a:id, l:t.title, len(a:followups))
endfunction

" Dismiss followups on a task (mark as done/failed based on exit_code).
function! skyrg#backend#tasks#dismiss_followups(id) abort
  if !has_key(s:tasks, a:id) | return | endif
  let l:t = s:tasks[a:id]
  if l:t.status !=# 'awaiting' | return | endif
  let l:t.status = l:t.exit_code == 0 ? 'done' : 'failed'
  let l:t.followups = []
  let l:t.followup_ctx = {}
endfunction

"==============================================================================
" Statusline component
"==============================================================================

" Returns a string for the statusline showing running tasks with elapsed time,
" awaiting followups, or recent completions.
"
" Examples:
"   ''
"   '[Build firmware: 45s]'
"   '[Build firmware: 2m 15s] [Deploy: 30s]'
"   '[❗Build firmware (⌥f)]'
"   '[✓ Build firmware] [✗ Lint]'
function! skyrg#backend#tasks#statusline() abort
  let l:running = skyrg#backend#tasks#running()
  if !empty(l:running)
    let l:parts = []
    for l:t in l:running
      let l:elapsed = localtime() - l:t.start_time
      call add(l:parts, printf('[%s: %s]', l:t.title, s:fmt_duration(l:elapsed)))
    endfor
    return join(l:parts, ' ')
  endif

  " Show awaiting tasks (highest priority after running)
  let l:awaiting = skyrg#backend#tasks#awaiting()
  if !empty(l:awaiting)
    let l:t = l:awaiting[0]
    return printf('[❗%s (<Leader>f)]', l:t.title)
  endif

  " Show most recent completions for 5 seconds
  let l:now = localtime()
  let l:parts = []
  for l:t in values(s:tasks)
    if l:t.status !=# 'running' && l:t.status !=# 'awaiting'
      \ && l:t.end_time > 0 && (l:now - l:t.end_time) < 5
      let l:icon = l:t.status ==# 'done' ? '✓' : '✗'
      call add(l:parts, printf('[%s %s]', l:icon, l:t.title))
    endif
  endfor
  return join(l:parts, ' ')
endfunction

" Format seconds into human-readable duration: 45s, 2m 15s, 1h 3m
function! s:fmt_duration(secs) abort
  if a:secs < 60
    return printf('%ds', a:secs)
  elseif a:secs < 3600
    let l:m = a:secs / 60
    let l:s = a:secs % 60
    return l:s > 0 ? printf('%dm %ds', l:m, l:s) : printf('%dm', l:m)
  else
    let l:h = a:secs / 3600
    let l:m = (a:secs % 3600) / 60
    return l:m > 0 ? printf('%dh %dm', l:h, l:m) : printf('%dh', l:h)
  endif
endfunction

"==============================================================================
" Internal
"==============================================================================

" Remove old completed tasks from memory (keep s:max_recent).
" Never prune running or awaiting tasks.
function! s:prune() abort
  let l:completed = filter(values(s:tasks),
    \ {_, t -> t.status !=# 'running' && t.status !=# 'awaiting'})
  if len(l:completed) <= s:max_recent | return | endif
  call sort(l:completed, {a, b -> a.start_time - b.start_time})
  let l:to_remove = l:completed[:len(l:completed) - s:max_recent - 1]
  for l:t in l:to_remove
    call remove(s:tasks, l:t.id)
  endfor
endfunction

" Reset (for testing).
function! skyrg#backend#tasks#reset() abort
  let s:tasks = {}
  let s:next_id = 1
endfunction
