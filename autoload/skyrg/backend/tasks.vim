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
  let l:t.status = a:exit_code == 0 ? 'done' : 'failed'
  let l:t.exit_code = a:exit_code
  let l:t.end_time = localtime()

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

"==============================================================================
" Statusline component
"==============================================================================

" Returns a string for the statusline. Empty when no tasks are active.
"
" Examples:
"   ''                                  — no tasks
"   '⟳ Build firmware (12s)'           — one running task
"   '⟳ 2 tasks running'               — multiple running
"   '✓ Build firmware'                  — just completed (shows for 5s)
"   '✗ Build firmware'                  — just failed (shows for 5s)
function! skyrg#backend#tasks#statusline() abort
  let l:running = skyrg#backend#tasks#running()
  if !empty(l:running)
    if len(l:running) == 1
      let l:t = l:running[0]
      let l:elapsed = localtime() - l:t.start_time
      return printf(' ⟳ %s (%ds) ', l:t.title, l:elapsed)
    else
      return printf(' ⟳ %d tasks running ', len(l:running))
    endif
  endif

  " Show most recent completion for 5 seconds
  let l:now = localtime()
  for l:t in values(s:tasks)
    if l:t.status !=# 'running' && l:t.end_time > 0 && (l:now - l:t.end_time) < 5
      let l:icon = l:t.status ==# 'done' ? '✓' : '✗'
      return printf(' %s %s ', l:icon, l:t.title)
    endif
  endfor

  return ''
endfunction

"==============================================================================
" Internal
"==============================================================================

" Remove old completed tasks from memory (keep s:max_recent).
function! s:prune() abort
  let l:completed = filter(values(s:tasks), {_, t -> t.status !=# 'running'})
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
