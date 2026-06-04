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
  " Reset input capture for history recording
  call skyrg#ui#input#reset()

  " Vim action (existing path)
  if has_key(a:action, 'execute')
    call skyrg#log#info('action', 'dispatch vim: "%s"', a:action.name)
    call a:action.execute(a:ctx)
    call skyrg#backend#context_history#record(a:action, a:ctx)
    return
  endif

  " Shell action (synchronous)
  if has_key(a:action, 'shell')
    call s:run_shell(a:action, a:ctx)
    call skyrg#backend#context_history#record(a:action, a:ctx)
    return
  endif

  " Job action (async or interactive terminal)
  if has_key(a:action, 'job')
    let l:opts = get(a:action, 'job_opts', {})
    if get(l:opts, 'interactive', 0)
      call s:run_interactive(a:action, a:ctx)
    else
      call s:run_job(a:action, a:ctx)
    endif
    call skyrg#backend#context_history#record(a:action, a:ctx)
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
  let l:Cwd_val = get(l:opts, 'cwd', '')
  let l:cwd = type(l:Cwd_val) == v:t_func ? l:Cwd_val(a:ctx) : l:Cwd_val

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
" Interactive — terminal split
"==============================================================================

" Opens a terminal split for commands needing user input (sudo, OTP, menus).
" On terminal exit, the normal task completion flow resumes (output parsing,
" followups, etc.).
function! s:run_interactive(action, ctx) abort
  let l:cmd = s:resolve_cmd(a:action.job, a:ctx)
  let l:opts = get(a:action, 'job_opts', {})
  let l:title = get(l:opts, 'title', a:action.name)
  let l:Cwd_val = get(l:opts, 'cwd', getcwd())
  let l:cwd = type(l:Cwd_val) == v:t_func ? l:Cwd_val(a:ctx) : l:Cwd_val

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

  call skyrg#log#info('action', 'dispatch interactive #%d: "%s" cmd=%s', l:task_id, l:title, l:cmd)

  " Build term options
  let l:term_opts = {
    \ 'term_name': '[SkyRG] ' . l:title,
    \ 'exit_cb': function('s:on_term_exit', [l:task_id]),
    \ 'term_finish': 'close',
    \ 'curwin': 1,
    \ }

  if !empty(l:cwd) && isdirectory(l:cwd)
    let l:term_opts.cwd = l:cwd
  endif

  if has_key(l:opts, 'env') && type(l:opts.env) == v:t_dict
    let l:term_opts.env = l:opts.env
  endif

  " Open terminal in a split
  let l:term_rows = get(l:opts, 'term_rows', min([&lines / 3, 15]))
  execute l:term_rows . 'split'
  let l:buf = term_start(['/bin/sh', '-c', l:cmd], l:term_opts)
  call skyrg#backend#tasks#update(l:task_id, {
    \ 'job': term_getjob(l:buf),
    \ 'term_buf': l:buf,
    \ })

  echom printf('[SkyRG] Interactive: %s', l:title)
endfunction

function! s:on_term_exit(task_id, job, exit_code) abort
  " Capture terminal buffer output before the buffer closes.
  " Interactive sessions don't use out_cb/err_cb, so this is the
  " only chance to get their output into the task log.
  let l:task = skyrg#backend#tasks#get(a:task_id)
  if !empty(l:task) && has_key(l:task, 'term_buf') && bufexists(l:task.term_buf)
    let l:lines = getbufline(l:task.term_buf, 1, '$')
    " Bounded to last 200 lines to keep log size reasonable
    let l:limit = 200
    if len(l:lines) > l:limit
      call skyrg#backend#action_log#append(l:task.log_file, 'stdout',
        \ printf('... (%d lines truncated)', len(l:lines) - l:limit))
      let l:lines = l:lines[-l:limit :]
    endif
    for l:line in l:lines
      call skyrg#backend#action_log#append(l:task.log_file, 'stdout', l:line)
    endfor
  endif

  let l:task = skyrg#backend#tasks#complete(a:task_id, a:exit_code)
  if empty(l:task) | return | endif

  let l:opts = get(l:task, 'action', {})
  let l:opts = get(l:opts, 'job_opts', {})
  let l:dur = l:task.end_time - l:task.start_time

  " Parse structured output if requested (unlikely for interactive, but supported)
  let l:fmt = get(l:opts, 'output_format', 'none')
  let l:task.task_output = skyrg#backend#action#parse_output(l:task.stdout, l:fmt)

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

  " Followup actions — store on task for on-demand access
  let l:followups = a:exit_code == 0
    \ ? get(l:task, 'on_success', [])
    \ : get(l:task, 'on_failure', [])

  if !empty(l:followups)
    let l:ctx = s:build_followup_ctx(l:task)
    call s:run_followups(a:task_id, l:followups, l:ctx)
  endif
endfunction

"==============================================================================
" Job — async
"==============================================================================

function! s:run_job(action, ctx) abort
  let l:cmd = s:resolve_cmd(a:action.job, a:ctx)
  let l:opts = get(a:action, 'job_opts', {})
  let l:title = get(l:opts, 'title', a:action.name)
  let l:Cwd_val = get(l:opts, 'cwd', getcwd())
  let l:cwd = type(l:Cwd_val) == v:t_func ? l:Cwd_val(a:ctx) : l:Cwd_val

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

  " Pipe stdin if specified
  if has_key(l:opts, 'stdin')
    let l:stdin = s:resolve_stdin(l:opts.stdin, a:ctx)
    if !empty(l:stdin)
      let l:ch = job_getchannel(l:job)
      call ch_sendraw(l:ch, l:stdin)
      call ch_close_in(l:ch)
      call skyrg#log#info('action', 'piped stdin to #%d (%d bytes)', l:task_id, len(l:stdin))
    endif
  endif

  echom printf('[SkyRG] Started: %s', l:title)

  " Auto-monitor: open log split immediately
  if get(l:opts, 'monitor', 0)
    let l:log = get(skyrg#backend#tasks#get(l:task_id), 'log_file', '')
    if !empty(l:log)
      call skyrg#views#tasks#open_monitor(l:log, l:task_id)
    endif
  endif
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

  " Auto-monitor: close on clean exit if configured, keep on failure
  if get(l:opts, 'monitor', 0)
    if a:exit_code == 0 && get(l:opts, 'monitor_on_success', 'keep') ==# 'close'
      call skyrg#views#tasks#close_monitor(a:task_id)
    else
      call skyrg#views#tasks#stop_monitor_tail(a:task_id)
    endif
  endif

  " Followup actions — store on task for on-demand access
  let l:followups = a:exit_code == 0
    \ ? get(l:task, 'on_success', [])
    \ : get(l:task, 'on_failure', [])

  if !empty(l:followups)
    let l:ctx = s:build_followup_ctx(l:task)
    call s:run_followups(a:task_id, l:followups, l:ctx)
  endif
endfunction

"=============================================================================="
" Followup routing
"=============================================================================="

" Execute auto followups immediately; store the rest for the popup.
function! s:run_followups(task_id, followups, ctx) abort
  let l:manual = []
  for l:f in a:followups
    if get(l:f, 'auto', 0)
      call skyrg#log#info('action', 'auto-execute followup "%s" for #%d', l:f.name, a:task_id)
      try
        call l:f.execute(a:ctx)
      catch
        call skyrg#log#error('action', 'auto followup "%s" failed: %s', l:f.name, v:exception)
      endtry
    else
      call add(l:manual, l:f)
    endif
  endfor
  if !empty(l:manual)
    call skyrg#backend#tasks#set_followups(a:task_id, l:manual, a:ctx)
  endif
endfunction

"=============================================================================="
" Followup popup
"=============================================================================="

" Build the enriched context for followup actions.
function! s:build_followup_ctx(task) abort
  let l:ctx = copy(get(a:task, 'context', {}))
  let l:ctx.task_id = a:task.id
  let l:ctx.task_title = a:task.title
  let l:ctx.task_exit = a:task.exit_code
  let l:ctx.task_stdout = a:task.stdout
  let l:ctx.task_stderr = a:task.stderr
  let l:ctx.task_output = get(a:task, 'task_output', [])
  let l:ctx.task_log = get(a:task, 'log_file', '')
  return l:ctx
endfunction

" Public: show followup popup for a specific task.
" Called from the task viewer (f key) and global shortcut (<Leader>f).
function! skyrg#backend#action#show_followups(task_id) abort
  let l:t = skyrg#backend#tasks#get(a:task_id)
  if empty(l:t) || l:t.status !=# 'awaiting' | return 0 | endif
  let l:followups = get(l:t, 'followups', [])
  let l:ctx = get(l:t, 'followup_ctx', {})
  if empty(l:followups) | return 0 | endif

  " Always add built-in options
  let l:actions = copy(l:followups)
  call add(l:actions, {
    \ 'name': 'View log',
    \ 'key': 'l',
    \ 'execute': {ctx -> execute('split ' . fnameescape(ctx.task_log))},
    \ })
  call add(l:actions, {
    \ 'name': 'Dismiss',
    \ 'key': 'd',
    \ 'execute': {ctx -> skyrg#backend#tasks#dismiss_followups(ctx.task_id)},
    \ })

  call skyrg#log#info('action', 'followup for #%d: %d actions', a:task_id, len(l:actions))
  call s:followup_popup(l:t, l:actions, l:ctx)
  return 1
endfunction

" Public: show followup popup for the most recent awaiting task.
function! skyrg#backend#action#show_latest_followup() abort
  let l:awaiting = skyrg#backend#tasks#awaiting()
  if empty(l:awaiting)
    echom '[SkyRG] No tasks awaiting followup'
    return
  endif
  call skyrg#backend#action#show_followups(l:awaiting[0].id)
endfunction

function! s:followup_popup(task, actions, ctx) abort
  let l:icon = a:task.exit_code == 0 ? '✓' : '✗'
  let l:title = printf(' %s %s ', l:icon, a:task.title)

  let s:followup_actions = a:actions
  let s:followup_ctx = a:ctx
  let s:followup_selected = 0

  let l:lines = s:followup_render()

  let l:max_w = 0
  for l:a in a:actions
    let l:key_str = has_key(l:a, 'key') ? '['.l:a.key.'] ' : '    '
    let l:label = has_key(l:a, 'label_fn') ? l:a.label_fn(a:ctx) : l:a.name
    let l:w = len(l:key_str) + len(l:label) + 6
    if l:w > l:max_w | let l:max_w = l:w | endif
  endfor
  let l:max_w = max([l:max_w, len(l:title) + 4])

  call skyrg#ui#style#init()
  let s:followup_popup_id = popup_create(l:lines, {
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
let s:followup_selected = 0
let s:followup_popup_id = 0

function! s:followup_render() abort
  let l:lines = []
  for l:i in range(len(s:followup_actions))
    let l:a = s:followup_actions[l:i]
    let l:key_str = has_key(l:a, 'key') ? '['.l:a.key.'] ' : '    '
    let l:label = has_key(l:a, 'label_fn') ? l:a.label_fn(s:followup_ctx) : l:a.name
    let l:text = '  ' . l:key_str . l:label
    if l:i == s:followup_selected
      call add(l:lines, skyrg#ui#util#hl_line(l:text, 'skyrg_sel'))
    else
      call add(l:lines, {'text': l:text})
    endif
  endfor
  return l:lines
endfunction

function! s:followup_key(winid, key) abort
  if a:key ==# "\<Esc>" || a:key ==# 'q'
    call popup_close(a:winid)
    return 1
  endif

  " Navigate with j/k or arrows
  if a:key ==# 'j' || a:key ==# "\<Down>"
    let s:followup_selected = min([len(s:followup_actions) - 1, s:followup_selected + 1])
    call popup_settext(a:winid, s:followup_render())
    return 1
  endif
  if a:key ==# 'k' || a:key ==# "\<Up>"
    let s:followup_selected = max([0, s:followup_selected - 1])
    call popup_settext(a:winid, s:followup_render())
    return 1
  endif

  " Enter: execute selected
  if a:key ==# "\<CR>"
    call s:followup_execute(a:winid, s:followup_actions[s:followup_selected])
    return 1
  endif

  " Letter shortcut
  if len(a:key) == 1
    for l:a in s:followup_actions
      if get(l:a, 'key', '') ==# a:key
        call s:followup_execute(a:winid, l:a)
        return 1
      endif
    endfor
  endif
  return 1
endfunction

function! s:followup_execute(winid, action) abort
  call popup_close(a:winid)
  call skyrg#log#info('action', 'followup execute "%s"', a:action.name)
  if a:action.name !=# 'Dismiss'
    call skyrg#backend#tasks#dismiss_followups(s:followup_ctx.task_id)
  endif
  if has_key(a:action, 'execute')
    call a:action.execute(s:followup_ctx)
  elseif has_key(a:action, 'shell') || has_key(a:action, 'job')
    call skyrg#backend#action#dispatch(a:action, s:followup_ctx)
  endif
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

" Resolve stdin value — funcref, list, or string.
function! s:resolve_stdin(spec, ctx) abort
  if type(a:spec) == v:t_func
    let l:val = a:spec(a:ctx)
  else
    let l:val = a:spec
  endif
  " List of lines → join with newlines
  if type(l:val) == v:t_list
    return join(l:val, "\n") . "\n"
  endif
  return l:val
endfunction
