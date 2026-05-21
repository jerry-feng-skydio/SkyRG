" autoload/skyrg/backend/action.vim — Action execution engine
"
" Dispatches actions from the context popup. Supports three execution types:
"
"   'execute' — Vimscript funcref/lambda (existing path, synchronous)
"   'shell'   — Synchronous system() call (for quick scripts < 1s)
"   'job'     — Async job_start() (for builds, deploys, long scripts)
"
" Actions with 'job' are tracked in backend/tasks and logged in
" backend/action_log.
"
" Usage:
"   call skyrg#backend#action#dispatch(action, ctx)

"==============================================================================
" Dispatch — detect type and route
"==============================================================================

function! skyrg#backend#action#dispatch(action, ctx) abort
  " Vim action (existing path)
  if has_key(a:action, 'execute')
    call skyrg#log#info('action', 'dispatch vim: "%s"', a:action.name)
    call a:action.execute(a:ctx)
    return
  endif

  " Shell action (synchronous)
  if has_key(a:action, 'shell')
    call s:run_shell(a:action, a:ctx)
    return
  endif

  " Job action (async)
  if has_key(a:action, 'job')
    call s:run_job(a:action, a:ctx)
    return
  endif

  call skyrg#log#warn('action', 'no execute/shell/job key in action "%s"', a:action.name)
endfunction

"==============================================================================
" Shell — synchronous
"==============================================================================

function! s:run_shell(action, ctx) abort
  let l:cmd = s:resolve_cmd(a:action.shell, a:ctx)
  let l:opts = get(a:action, 'job_opts', {})
  let l:title = get(l:opts, 'title', a:action.name)
  let l:cwd = get(l:opts, 'cwd', '')

  call skyrg#log#info('action', 'dispatch shell: "%s" cmd=%s', l:title, l:cmd)
  let l:t = skyrg#log#timer()

  let l:saved_cwd = ''
  if !empty(l:cwd) && isdirectory(l:cwd)
    let l:saved_cwd = getcwd()
    execute 'cd' fnameescape(l:cwd)
  endif

  let l:output = system(l:cmd)
  let l:exit = v:shell_error

  if !empty(l:saved_cwd)
    execute 'cd' fnameescape(l:saved_cwd)
  endif

  call skyrg#backend#action_log#maybe_compact()

  " Register and immediately complete the task
  let l:task_id = skyrg#backend#tasks#add({
    \ 'title': l:title,
    \ 'cmd': l:cmd,
    \ 'cwd': !empty(l:cwd) ? l:cwd : getcwd(),
    \ 'context': a:ctx,
    \ })

  " Log output lines
  for l:line in split(l:output, "\n")
    call skyrg#backend#tasks#append_output(l:task_id, 'stdout', l:line)
  endfor
  call skyrg#backend#tasks#complete(l:task_id, l:exit)

  call skyrg#log#elapsed(l:t, 'action', 'shell done "%s" exit=%d', l:title, l:exit)

  if l:exit != 0
    call skyrg#log#warn('action', 'shell failed: %s', l:output)
    echohl ErrorMsg | echom printf('[SkyRG] %s failed (exit %d)', l:title, l:exit) | echohl None
  else
    if get(l:opts, 'notify', 1)
      echom printf('[SkyRG] %s done', l:title)
    endif
  endif
endfunction

"==============================================================================
" Job — async
"==============================================================================

function! s:run_job(action, ctx) abort
  let l:cmd = s:resolve_cmd(a:action.job, a:ctx)
  let l:opts = get(a:action, 'job_opts', {})
  let l:title = get(l:opts, 'title', a:action.name)
  let l:cwd = get(l:opts, 'cwd', getcwd())

  call skyrg#backend#action_log#maybe_compact()

  " Register task
  let l:task_id = skyrg#backend#tasks#add({
    \ 'title': l:title,
    \ 'cmd': l:cmd,
    \ 'cwd': l:cwd,
    \ 'context': a:ctx,
    \ 'action': a:action,
    \ 'on_success': get(l:opts, 'on_success', []),
    \ 'on_failure': get(l:opts, 'on_failure', []),
    \ })

  call skyrg#log#info('action', 'dispatch job #%d: "%s" cmd=%s', l:task_id, l:title, l:cmd)

  " Build job options
  let l:job_opts = {
    \ 'out_cb': function('s:on_out', [l:task_id]),
    \ 'err_cb': function('s:on_err', [l:task_id]),
    \ 'exit_cb': function('s:on_exit', [l:task_id]),
    \ 'out_mode': 'nl',
    \ 'err_mode': 'nl',
    \ }

  if !empty(l:cwd) && isdirectory(l:cwd)
    let l:job_opts.cwd = l:cwd
  endif

  if has_key(l:opts, 'env') && type(l:opts.env) == v:t_dict
    let l:job_opts.env = l:opts.env
  endif

  " Start the job
  let l:job = job_start(['/bin/sh', '-c', l:cmd], l:job_opts)
  call skyrg#backend#tasks#update(l:task_id, {
    \ 'job': l:job,
    \ 'pid': job_info(l:job).process,
    \ })

  echom printf('[SkyRG] Started: %s', l:title)
endfunction

"==============================================================================
" Job callbacks
"==============================================================================

function! s:on_out(task_id, ch, msg) abort
  call skyrg#backend#tasks#append_output(a:task_id, 'stdout', a:msg)
endfunction

function! s:on_err(task_id, ch, msg) abort
  call skyrg#backend#tasks#append_output(a:task_id, 'stderr', a:msg)
endfunction

function! s:on_exit(task_id, job, exit_code) abort
  " Drain any remaining buffered output — Vim's exit_cb can fire before
  " all out_cb/err_cb calls are processed
  let l:ch = job_getchannel(a:job)
  while ch_status(l:ch, {'part': 'out'}) ==# 'buffered'
    call skyrg#backend#tasks#append_output(a:task_id, 'stdout', ch_read(l:ch))
  endwhile
  while ch_status(l:ch, {'part': 'err'}) ==# 'buffered'
    call skyrg#backend#tasks#append_output(a:task_id, 'stderr', ch_read(l:ch, {'part': 'err'}))
  endwhile

  let l:task = skyrg#backend#tasks#complete(a:task_id, a:exit_code)
  if empty(l:task) | return | endif

  let l:opts = get(l:task, 'action', {})
  let l:opts = get(l:opts, 'job_opts', {})
  let l:dur = l:task.end_time - l:task.start_time

  " Parse structured output if requested
  let l:fmt = get(l:opts, 'output_format', 'none')
  let l:task.task_output = s:parse_output(l:task.stdout, l:fmt)
  if l:fmt !=# 'none'
    call skyrg#log#info('action', 'parsed output format=%s items=%d',
      \ l:fmt, type(l:task.task_output) == v:t_list ? len(l:task.task_output) : 1)
  endif

  " Notification
  if get(l:opts, 'notify', 1)
    if a:exit_code == 0
      echom printf('[SkyRG] ✓ %s (%ds)', l:task.title, l:dur)
    else
      echohl ErrorMsg
      echom printf('[SkyRG] ✗ %s failed (exit %d, %ds)', l:task.title, a:exit_code, l:dur)
      echohl None
    endif
  endif

  " Followup actions
  let l:followups = a:exit_code == 0
    \ ? get(l:task, 'on_success', [])
    \ : get(l:task, 'on_failure', [])

  if !empty(l:followups)
    call s:show_followup(l:task, l:followups)
  endif
endfunction

"==============================================================================
" Followup popup
"==============================================================================

" Show a small popup offering followup actions after task completion.
function! s:show_followup(task, followups) abort
  " Enrich followup context with task output
  let l:ctx = copy(get(a:task, 'context', {}))
  let l:ctx.task_id = a:task.id
  let l:ctx.task_title = a:task.title
  let l:ctx.task_exit = a:task.exit_code
  let l:ctx.task_stdout = a:task.stdout
  let l:ctx.task_stderr = a:task.stderr
  let l:ctx.task_output = get(a:task, 'task_output', [])
  let l:ctx.task_log = get(a:task, 'log_file', '')

  " Register followups as temporary context actions and show popup
  " We use a timer to defer, since we're in exit_cb and can't open popups
  let s:pending_followup = {'task': a:task, 'actions': a:followups, 'ctx': l:ctx}
  call timer_start(50, function('s:do_followup'))
endfunction

let s:pending_followup = {}

function! s:do_followup(timer) abort
  if empty(s:pending_followup) | return | endif
  let l:f = s:pending_followup
  let s:pending_followup = {}

  " Always add a "View log" and "Dismiss" option
  let l:actions = copy(l:f.actions)
  call add(l:actions, {
    \ 'name': 'View log',
    \ 'key': 'l',
    \ 'execute': {ctx -> execute('split ' . fnameescape(ctx.task_log))},
    \ })

  " Show as a temporary context popup
  " We register them, show the popup, then clean up
  let l:saved = []
  for l:a in l:actions
    let l:a.group = 'followup'
    let l:a.priority = get(l:a, 'priority', 100)
    call add(l:saved, l:a)
  endfor

  call skyrg#log#info('action', 'followup for #%d: %d actions', l:f.task.id, len(l:actions))

  " Use a lightweight popup instead of the full context system
  call s:followup_popup(l:f.task, l:actions, l:f.ctx)
endfunction

function! s:followup_popup(task, actions, ctx) abort
  let l:icon = a:task.exit_code == 0 ? '✓' : '✗'
  let l:title = printf(' %s %s ', l:icon, a:task.title)

  let l:lines = []
  for l:i in range(len(a:actions))
    let l:a = a:actions[l:i]
    let l:key_str = has_key(l:a, 'key') ? '['.l:a.key.'] ' : '    '
    let l:label = has_key(l:a, 'label_fn') ? l:a.label_fn(a:ctx) : l:a.name
    call add(l:lines, '  ' . l:key_str . l:label)
  endfor

  let l:max_w = 0
  for l:l in l:lines
    if len(l:l) > l:max_w | let l:max_w = len(l:l) | endif
  endfor
  let l:max_w = max([l:max_w + 4, len(l:title) + 4])

  let s:followup_actions = a:actions
  let s:followup_ctx = a:ctx

  let l:popup = popup_create(l:lines, {
    \ 'title': l:title,
    \ 'border': [1,1,1,1],
    \ 'borderchars': ['─','│','─','│','╭','╮','╯','╰'],
    \ 'padding': [0,1,0,1],
    \ 'pos': 'center',
    \ 'minwidth': l:max_w,
    \ 'maxwidth': l:max_w,
    \ 'filter': function('s:followup_key'),
    \ 'mapping': 0,
    \ 'zindex': 300,
    \ })
endfunction

let s:followup_actions = []
let s:followup_ctx = {}

function! s:followup_key(winid, key) abort
  if a:key ==# "\<Esc>" || a:key ==# 'q'
    call popup_close(a:winid)
    return 1
  endif
  " Match by key shortcut
  if len(a:key) == 1
    for l:a in s:followup_actions
      if get(l:a, 'key', '') ==# a:key
        call popup_close(a:winid)
        call skyrg#log#info('action', 'followup execute "%s"', l:a.name)
        if has_key(l:a, 'execute')
          call l:a.execute(s:followup_ctx)
        elseif has_key(l:a, 'shell') || has_key(l:a, 'job')
          call skyrg#backend#action#dispatch(l:a, s:followup_ctx)
        endif
        return 1
      endif
    endfor
  endif
  return 1
endfunction

"==============================================================================
" Output parsing
"==============================================================================

" Public API for output parsing (also used in tests).
function! skyrg#backend#action#parse_output(stdout, format) abort
  return s:parse_output(a:stdout, a:format)
endfunction

" Parse raw stdout lines into structured data based on output_format.
"
" Formats:
"   'matches' — file:line[:col]:text (ripgrep/compiler output)
"   'json'    — parse entire stdout as JSON (or one JSON object per line)
"   'lines'   — raw string list (passthrough)
"   'none'    — no parsing, returns []
function! s:parse_output(stdout, format) abort
  if a:format ==# 'none' || empty(a:stdout)
    return []
  endif

  if a:format ==# 'lines'
    return copy(a:stdout)
  endif

  if a:format ==# 'json'
    return s:parse_json(a:stdout)
  endif

  if a:format ==# 'matches'
    return s:parse_matches(a:stdout)
  endif

  call skyrg#log#warn('action', 'unknown output_format: %s', a:format)
  return []
endfunction

" Parse file:line[:col]:text matches (rg, gcc, clang, etc.)
" Returns list of dicts: {'file': ..., 'lnum': ..., 'col': ..., 'text': ...}
function! s:parse_matches(lines) abort
  let l:results = []
  for l:line in a:lines
    " Try file:line:col:text first
    let l:m = matchlist(l:line, '\v^(.+):(\d+):(\d+):(.*)$')
    if !empty(l:m)
      call add(l:results, {
        \ 'file': l:m[1], 'lnum': str2nr(l:m[2]),
        \ 'col': str2nr(l:m[3]), 'text': trim(l:m[4]),
        \ })
      continue
    endif
    " Try file:line:text (no column)
    let l:m = matchlist(l:line, '\v^(.+):(\d+):(.*)$')
    if !empty(l:m)
      call add(l:results, {
        \ 'file': l:m[1], 'lnum': str2nr(l:m[2]),
        \ 'col': 0, 'text': trim(l:m[3]),
        \ })
      continue
    endif
    " Skip non-matching lines (header, summary, etc.)
  endfor
  return l:results
endfunction

" Parse JSON output — try full blob first, then per-line.
function! s:parse_json(lines) abort
  let l:blob = join(a:lines, "\n")
  try
    return json_decode(l:blob)
  catch
  endtry
  " Fall back to per-line JSON (JSONL)
  let l:results = []
  for l:line in a:lines
    if empty(trim(l:line)) | continue | endif
    try
      call add(l:results, json_decode(l:line))
    catch
    endtry
  endfor
  return l:results
endfunction

"==============================================================================
" Command resolution
"==============================================================================

" Resolve a command string or funcref into an executable shell command.
function! s:resolve_cmd(cmd_spec, ctx) abort
  if type(a:cmd_spec) == v:t_func
    return a:cmd_spec(a:ctx)
  endif
  " String with {ctx.*} interpolation
  let l:cmd = a:cmd_spec
  let l:cmd = substitute(l:cmd, '{ctx\.word}', shellescape(get(a:ctx, 'word', '')), 'g')
  let l:cmd = substitute(l:cmd, '{ctx\.WORD}', shellescape(get(a:ctx, 'WORD', '')), 'g')
  let l:cmd = substitute(l:cmd, '{ctx\.file}', shellescape(get(a:ctx, 'file', '')), 'g')
  let l:cmd = substitute(l:cmd, '{ctx\.dir}', shellescape(get(a:ctx, 'dir', '')), 'g')
  let l:cmd = substitute(l:cmd, '{ctx\.visual}', shellescape(get(a:ctx, 'visual', '')), 'g')
  let l:cmd = substitute(l:cmd, '{ctx\.filetype}', shellescape(get(a:ctx, 'filetype', '')), 'g')
  let l:cmd = substitute(l:cmd, '{ctx\.line}', shellescape(get(a:ctx, 'line', '')), 'g')
  return l:cmd
endfunction
