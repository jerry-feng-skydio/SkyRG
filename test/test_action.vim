" test/test_action.vim — Tests for the action system (action, tasks, action_log)

let s:tmplog = '/tmp/skyrg_test_action_' . getpid() . '.log'
let s:tmpdir = '/tmp/skyrg_test_actions_' . getpid()

function! s:setup() abort
  let g:skyrg_log_file = s:tmplog
  let g:skyrg_log_level = 'DEBUG'
  let g:skyrg_log_echo = 0
  call skyrg#backend#tasks#reset()
  " Override action log dir via XDG
  let $XDG_DATA_HOME = s:tmpdir
  if !isdirectory(s:tmpdir)
    call mkdir(s:tmpdir, 'p')
  endif
endfunction

function! s:teardown() abort
  call skyrg#backend#tasks#reset()
  if isdirectory(s:tmpdir)
    call system('rm -rf ' . shellescape(s:tmpdir))
  endif
  if filereadable(s:tmplog)
    call delete(s:tmplog)
  endif
  unlet! g:skyrg_log_file
  unlet! g:skyrg_log_level
  unlet! g:skyrg_log_echo
  let $XDG_DATA_HOME = ''
endfunction

"==============================================================================
" Task registry tests
"==============================================================================

function! s:test_tasks_add_and_get()
  call s:setup()
  let l:id = skyrg#backend#tasks#add({
    \ 'title': 'Test task',
    \ 'cmd': 'echo hello',
    \ })
  call Assert(l:id >= 1, 'tasks add: returns positive id')
  let l:t = skyrg#backend#tasks#get(l:id)
  call AssertEqual('running', l:t.status, 'tasks add: status is running')
  call AssertEqual('Test task', l:t.title, 'tasks add: title preserved')
  call Assert(l:t.start_time > 0, 'tasks add: start_time set')
  call s:teardown()
endfunction
call s:test_tasks_add_and_get()

function! s:test_tasks_complete()
  call s:setup()
  let l:id = skyrg#backend#tasks#add({
    \ 'title': 'Complete task',
    \ 'cmd': 'echo hi',
    \ })
  call skyrg#backend#tasks#complete(l:id, 0)
  let l:t = skyrg#backend#tasks#get(l:id)
  call AssertEqual('done', l:t.status, 'tasks complete: status is done')
  call AssertEqual(0, l:t.exit_code, 'tasks complete: exit_code is 0')
  call Assert(l:t.end_time > 0, 'tasks complete: end_time set')
  call s:teardown()
endfunction
call s:test_tasks_complete()

function! s:test_tasks_complete_failure()
  call s:setup()
  let l:id = skyrg#backend#tasks#add({
    \ 'title': 'Failing task',
    \ 'cmd': 'false',
    \ })
  call skyrg#backend#tasks#complete(l:id, 1)
  let l:t = skyrg#backend#tasks#get(l:id)
  call AssertEqual('failed', l:t.status, 'tasks fail: status is failed')
  call AssertEqual(1, l:t.exit_code, 'tasks fail: exit_code is 1')
  call s:teardown()
endfunction
call s:test_tasks_complete_failure()

function! s:test_tasks_running()
  call s:setup()
  let l:id1 = skyrg#backend#tasks#add({'title': 'R1', 'cmd': 'sleep 1'})
  let l:id2 = skyrg#backend#tasks#add({'title': 'R2', 'cmd': 'sleep 2'})
  call AssertEqual(2, skyrg#backend#tasks#running_count(), 'tasks running: 2 tasks')
  call skyrg#backend#tasks#complete(l:id1, 0)
  call AssertEqual(1, skyrg#backend#tasks#running_count(), 'tasks running: 1 after complete')
  call s:teardown()
endfunction
call s:test_tasks_running()

function! s:test_tasks_append_output()
  call s:setup()
  let l:id = skyrg#backend#tasks#add({'title': 'Output', 'cmd': 'echo'})
  call skyrg#backend#tasks#append_output(l:id, 'stdout', 'line 1')
  call skyrg#backend#tasks#append_output(l:id, 'stderr', 'err 1')
  let l:t = skyrg#backend#tasks#get(l:id)
  call AssertEqual(1, len(l:t.stdout), 'tasks output: 1 stdout line')
  call AssertEqual('line 1', l:t.stdout[0], 'tasks output: correct content')
  call AssertEqual(1, len(l:t.stderr), 'tasks output: 1 stderr line')
  call s:teardown()
endfunction
call s:test_tasks_append_output()

function! s:test_tasks_statusline_empty()
  call s:setup()
  call AssertEqual('', skyrg#backend#tasks#statusline(), 'statusline: empty when no tasks')
  call s:teardown()
endfunction
call s:test_tasks_statusline_empty()

function! s:test_tasks_statusline_running()
  call s:setup()
  call skyrg#backend#tasks#add({'title': 'Build', 'cmd': 'make'})
  let l:sl = skyrg#backend#tasks#statusline()
  call Assert(l:sl =~# 'Build', 'statusline: contains task title')
  call Assert(l:sl =~# '⟳', 'statusline: has spinner icon')
  call s:teardown()
endfunction
call s:test_tasks_statusline_running()

function! s:test_tasks_all()
  call s:setup()
  let l:id1 = skyrg#backend#tasks#add({'title': 'A', 'cmd': 'a'})
  let l:id2 = skyrg#backend#tasks#add({'title': 'B', 'cmd': 'b'})
  let l:all = skyrg#backend#tasks#all()
  call AssertEqual(2, len(l:all), 'tasks all: 2 tasks')
  call s:teardown()
endfunction
call s:test_tasks_all()

"==============================================================================
" Action log tests
"==============================================================================

function! s:test_action_log_create_and_finalize()
  call s:setup()
  let l:id = skyrg#backend#tasks#add({'title': 'Log test', 'cmd': 'echo foo'})
  let l:t = skyrg#backend#tasks#get(l:id)
  call Assert(!empty(l:t.log_file), 'action_log: log_file set')
  call Assert(filereadable(l:t.log_file), 'action_log: log file exists')
  " Check header
  let l:lines = readfile(l:t.log_file)
  call Assert(l:lines[0] =~# 'SkyRG Action Log', 'action_log: header present')
  call Assert(join(l:lines, "\n") =~# 'Log test', 'action_log: title in header')
  " Finalize
  call skyrg#backend#tasks#complete(l:id, 0)
  let l:lines = readfile(l:t.log_file)
  call Assert(join(l:lines, "\n") =~# 'Exit code: 0', 'action_log: exit code in footer')
  call s:teardown()
endfunction
call s:test_action_log_create_and_finalize()

function! s:test_action_log_append()
  call s:setup()
  let l:id = skyrg#backend#tasks#add({'title': 'Append test', 'cmd': 'echo'})
  let l:t = skyrg#backend#tasks#get(l:id)
  call skyrg#backend#action_log#append(l:t.log_file, 'stdout', 'hello world')
  call skyrg#backend#action_log#append(l:t.log_file, 'stderr', 'oh no')
  let l:lines = readfile(l:t.log_file)
  let l:content = join(l:lines, "\n")
  call Assert(l:content =~# '\[stdout\] hello world', 'action_log append: stdout')
  call Assert(l:content =~# '\[stderr\] oh no', 'action_log append: stderr')
  call s:teardown()
endfunction
call s:test_action_log_append()

function! s:test_action_log_index()
  call s:setup()
  let l:id = skyrg#backend#tasks#add({'title': 'Index test', 'cmd': 'echo'})
  call skyrg#backend#tasks#complete(l:id, 0)
  let l:entries = skyrg#backend#action_log#list()
  call Assert(len(l:entries) >= 1, 'action_log index: has entry')
  call AssertEqual('Index test', l:entries[0].title, 'action_log index: correct title')
  call s:teardown()
endfunction
call s:test_action_log_index()

"==============================================================================
" Action dispatch tests (vim actions)
"==============================================================================

let s:dispatched = 0
function! s:test_dispatch_vim()
  call s:setup()
  let s:dispatched = 0
  let l:action = {
    \ 'name': 'vim test',
    \ 'execute': {ctx -> execute('let s:dispatched = 1')},
    \ }
  call skyrg#backend#action#dispatch(l:action, {'word': 'test'})
  call AssertEqual(1, s:dispatched, 'dispatch vim: action executed')
  call s:teardown()
endfunction
call s:test_dispatch_vim()

function! s:test_dispatch_shell()
  call s:setup()
  let l:action = {
    \ 'name': 'shell test',
    \ 'shell': 'echo hello_from_shell',
    \ 'job_opts': {'title': 'Shell test'},
    \ }
  call skyrg#backend#action#dispatch(l:action, {'word': 'test'})
  " Verify task was created and completed
  let l:all = skyrg#backend#tasks#all()
  call Assert(len(l:all) >= 1, 'dispatch shell: task created')
  call Assert(l:all[0].status ==# 'done' || l:all[0].status ==# 'failed',
    \ 'dispatch shell: task completed')
  call s:teardown()
endfunction
call s:test_dispatch_shell()

"==============================================================================
" Command resolution tests
"==============================================================================

function! s:test_resolve_cmd_string()
  call s:setup()
  " Test via a shell action with interpolation
  let l:action = {
    \ 'name': 'interp test',
    \ 'shell': 'echo {ctx.word}',
    \ 'job_opts': {'title': 'Interp'},
    \ }
  " We can't easily test s:resolve_cmd directly, but we can verify
  " the shell action runs without error
  call skyrg#backend#action#dispatch(l:action, {'word': 'foobar'})
  let l:all = skyrg#backend#tasks#all()
  call Assert(!empty(l:all), 'resolve cmd: task created')
  call s:teardown()
endfunction
call s:test_resolve_cmd_string()

function! s:test_resolve_cmd_funcref()
  call s:setup()
  let l:action = {
    \ 'name': 'funcref test',
    \ 'shell': {ctx -> 'echo ' . shellescape(ctx.word)},
    \ 'job_opts': {'title': 'Funcref'},
    \ }
  call skyrg#backend#action#dispatch(l:action, {'word': 'fromfunc'})
  let l:all = skyrg#backend#tasks#all()
  call Assert(!empty(l:all), 'resolve funcref: task created')
  call s:teardown()
endfunction
call s:test_resolve_cmd_funcref()
