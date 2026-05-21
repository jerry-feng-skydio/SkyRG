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

"==============================================================================
" Output parsing tests
"==============================================================================

function! s:test_parse_none()
  let l:result = skyrg#backend#action#parse_output(['hello'], 'none')
  call AssertEqual([], l:result, 'parse none: returns empty')
endfunction
call s:test_parse_none()

function! s:test_parse_empty()
  let l:result = skyrg#backend#action#parse_output([], 'matches')
  call AssertEqual([], l:result, 'parse empty: returns empty')
endfunction
call s:test_parse_empty()

function! s:test_parse_lines()
  let l:input = ['line one', 'line two', 'line three']
  let l:result = skyrg#backend#action#parse_output(l:input, 'lines')
  call AssertEqual(3, len(l:result), 'parse lines: count')
  call AssertEqual('line one', l:result[0], 'parse lines: first')
  call AssertEqual('line three', l:result[2], 'parse lines: last')
  " Verify it's a copy, not a reference
  call add(l:result, 'extra')
  call AssertEqual(3, len(l:input), 'parse lines: is a copy')
endfunction
call s:test_parse_lines()

function! s:test_parse_matches_file_line_col_text()
  let l:input = [
    \ 'src/main.cc:42:10:undefined reference',
    \ 'src/util.h:7:3: warning: unused var',
    \ ]
  let l:result = skyrg#backend#action#parse_output(l:input, 'matches')
  call AssertEqual(2, len(l:result), 'parse matches f:l:c:t count')
  call AssertEqual('src/main.cc', l:result[0].file, 'parse matches: file')
  call AssertEqual(42, l:result[0].lnum, 'parse matches: lnum')
  call AssertEqual(10, l:result[0].col, 'parse matches: col')
  call AssertEqual('undefined reference', l:result[0].text, 'parse matches: text')
  call AssertEqual(3, l:result[1].col, 'parse matches: second col')
endfunction
call s:test_parse_matches_file_line_col_text()

function! s:test_parse_matches_file_line_text()
  let l:input = ['Makefile:15:all: deps missing']
  let l:result = skyrg#backend#action#parse_output(l:input, 'matches')
  call AssertEqual(1, len(l:result), 'parse matches f:l:t count')
  call AssertEqual('Makefile', l:result[0].file, 'parse matches: file no col')
  call AssertEqual(15, l:result[0].lnum, 'parse matches: lnum no col')
  call AssertEqual(0, l:result[0].col, 'parse matches: col is 0')
endfunction
call s:test_parse_matches_file_line_text()

function! s:test_parse_matches_skip_non_matching()
  let l:input = [
    \ 'Building target //vehicle:main',
    \ 'src/main.cc:42:10:error here',
    \ '2 errors found',
    \ ]
  let l:result = skyrg#backend#action#parse_output(l:input, 'matches')
  call AssertEqual(1, len(l:result), 'parse matches: skips non-matching')
  call AssertEqual('src/main.cc', l:result[0].file, 'parse matches: correct match')
endfunction
call s:test_parse_matches_skip_non_matching()

function! s:test_parse_json_blob()
  let l:input = ['{"key": "value", "num": 42}']
  let l:result = skyrg#backend#action#parse_output(l:input, 'json')
  call Assert(type(l:result) == v:t_dict, 'parse json blob: is dict')
  call AssertEqual('value', l:result.key, 'parse json blob: key')
  call AssertEqual(42, l:result.num, 'parse json blob: num')
endfunction
call s:test_parse_json_blob()

function! s:test_parse_json_array()
  let l:input = ['[1, 2, 3]']
  let l:result = skyrg#backend#action#parse_output(l:input, 'json')
  call Assert(type(l:result) == v:t_list, 'parse json array: is list')
  call AssertEqual(3, len(l:result), 'parse json array: length')
endfunction
call s:test_parse_json_array()

function! s:test_parse_jsonl()
  let l:input = [
    \ '{"file": "a.cc", "line": 1}',
    \ '{"file": "b.cc", "line": 2}',
    \ '',
    \ ]
  let l:result = skyrg#backend#action#parse_output(l:input, 'json')
  call AssertEqual(2, len(l:result), 'parse jsonl: count')
  call AssertEqual('a.cc', l:result[0].file, 'parse jsonl: first file')
  call AssertEqual(2, l:result[1].line, 'parse jsonl: second line')
endfunction
call s:test_parse_jsonl()

function! s:test_parse_unknown_format()
  let l:result = skyrg#backend#action#parse_output(['hello'], 'bogus')
  call AssertEqual([], l:result, 'parse unknown: returns empty')
endfunction
call s:test_parse_unknown_format()
