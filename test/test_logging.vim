" test/test_logging.vim — Tests for the structured logging system

let s:tmplog = '/tmp/skyrg_test_log_' . getpid() . '.log'

function! s:setup() abort
  let g:skyrg_log_file = s:tmplog
  let g:skyrg_log_level = 'DEBUG'
  let g:skyrg_log_echo = 0
  if filereadable(s:tmplog)
    call delete(s:tmplog)
  endif
endfunction

function! s:teardown() abort
  if filereadable(s:tmplog)
    call delete(s:tmplog)
  endif
  unlet! g:skyrg_log_file
  unlet! g:skyrg_log_level
  unlet! g:skyrg_log_echo
endfunction

function! s:read_log() abort
  return filereadable(s:tmplog) ? readfile(s:tmplog) : []
endfunction

"==============================================================================
" Tests
"==============================================================================

function! s:test_log_debug()
  call s:setup()
  call skyrg#log#debug('test', 'hello %s', 'world')
  let l:lines = s:read_log()
  call Assert(len(l:lines) >= 1, 'log debug: at least 1 line')
  call Assert(l:lines[-1] =~# '\[DEBUG\]', 'log debug: contains [DEBUG]')
  call Assert(l:lines[-1] =~# '\[test\]', 'log debug: contains [test]')
  call Assert(l:lines[-1] =~# 'hello world', 'log debug: contains message')
  call s:teardown()
endfunction
call s:test_log_debug()

function! s:test_log_info()
  call s:setup()
  call skyrg#log#info('mod', 'info message')
  let l:lines = s:read_log()
  call Assert(l:lines[-1] =~# '\[INFO\]', 'log info: contains [INFO]')
  call Assert(l:lines[-1] =~# '\[mod\]', 'log info: contains [mod]')
  call s:teardown()
endfunction
call s:test_log_info()

function! s:test_log_warn()
  call s:setup()
  call skyrg#log#warn('w', 'warning msg')
  let l:lines = s:read_log()
  call Assert(l:lines[-1] =~# '\[WARN\]', 'log warn: contains [WARN]')
  call s:teardown()
endfunction
call s:test_log_warn()

function! s:test_log_error()
  call s:setup()
  call skyrg#log#error('e', 'error msg')
  let l:lines = s:read_log()
  call Assert(l:lines[-1] =~# '\[ERROR\]', 'log error: contains [ERROR]')
  call s:teardown()
endfunction
call s:test_log_error()

function! s:test_log_level_filtering()
  call s:setup()
  let g:skyrg_log_level = 'WARN'
  call skyrg#log#debug('x', 'should not appear')
  call skyrg#log#info('x', 'should not appear')
  call skyrg#log#warn('x', 'should appear')
  call skyrg#log#error('x', 'should appear too')
  let l:lines = s:read_log()
  " Only WARN and ERROR should be present (rotation line possible too)
  let l:content = filter(copy(l:lines), {_, l -> l !~# '^---'})
  call AssertEqual(2, len(l:content), 'log level filter: 2 lines (WARN + ERROR)')
  call s:teardown()
endfunction
call s:test_log_level_filtering()

function! s:test_log_off()
  call s:setup()
  let g:skyrg_log_level = 'OFF'
  call skyrg#log#debug('x', 'nope')
  call skyrg#log#info('x', 'nope')
  call skyrg#log#warn('x', 'nope')
  call skyrg#log#error('x', 'nope')
  let l:lines = s:read_log()
  let l:content = filter(copy(l:lines), {_, l -> l !~# '^---'})
  call AssertEqual(0, len(l:content), 'log OFF: nothing logged')
  call s:teardown()
endfunction
call s:test_log_off()

function! s:test_log_data()
  call s:setup()
  call skyrg#log#data('test', 'mydata', {'key': 'val', 'n': 42})
  let l:lines = s:read_log()
  call Assert(l:lines[-1] =~# 'mydata:', 'log data: contains label')
  call Assert(l:lines[-1] =~# '"key"', 'log data: contains JSON key')
  call Assert(l:lines[-1] =~# '42', 'log data: contains JSON value')
  call s:teardown()
endfunction
call s:test_log_data()

function! s:test_log_timestamp_format()
  call s:setup()
  call skyrg#log#info('t', 'ts test')
  let l:lines = s:read_log()
  " Should match YYYY-MM-DD HH:MM:SS format
  call Assert(l:lines[-1] =~# '^\d\{4}-\d\{2}-\d\{2} \d\{2}:\d\{2}:\d\{2}', 'log timestamp: correct format')
  call s:teardown()
endfunction
call s:test_log_timestamp_format()

function! s:test_log_file_path()
  call s:setup()
  let l:f = skyrg#log#file()
  call AssertEqual(s:tmplog, l:f, 'log file: returns configured path')
  call s:teardown()
endfunction
call s:test_log_file_path()

function! s:test_log_clear()
  call s:setup()
  call skyrg#log#info('t', 'before clear')
  call Assert(len(s:read_log()) >= 1, 'log clear: has lines before')
  call skyrg#log#clear()
  call AssertEqual(0, len(s:read_log()), 'log clear: empty after')
  call s:teardown()
endfunction
call s:test_log_clear()

function! s:test_log_status_compat()
  call s:setup()
  call skyrg#log#status('compat %s', 'test')
  let l:lines = s:read_log()
  call Assert(l:lines[-1] =~# 'compat test', 'log status compat: message logged')
  call Assert(l:lines[-1] =~# '\[INFO\]', 'log status compat: maps to INFO')
  call s:teardown()
endfunction
call s:test_log_status_compat()

function! s:test_log_timer_and_elapsed()
  call s:setup()
  let l:t = skyrg#log#timer()
  " Do a tiny bit of work
  let l:x = 0
  for l:i in range(100)
    let l:x += l:i
  endfor
  call skyrg#log#elapsed(l:t, 'test', 'timer work')
  let l:lines = s:read_log()
  call Assert(l:lines[-1] =~# 'timer work', 'log timer: contains message')
  call Assert(l:lines[-1] =~# 'ms)', 'log timer: contains ms unit')
  call Assert(l:lines[-1] =~# '\[INFO\]', 'log timer: elapsed logs at INFO')
  call s:teardown()
endfunction
call s:test_log_timer_and_elapsed()

function! s:test_log_elapsed_debug()
  call s:setup()
  let l:t = skyrg#log#timer()
  call skyrg#log#elapsed_debug(l:t, 'test', 'debug timing')
  let l:lines = s:read_log()
  call Assert(l:lines[-1] =~# 'debug timing', 'log elapsed_debug: contains message')
  call Assert(l:lines[-1] =~# '\[DEBUG\]', 'log elapsed_debug: logs at DEBUG')
  call s:teardown()
endfunction
call s:test_log_elapsed_debug()

function! s:test_log_elapsed_ms()
  call s:setup()
  let l:t = skyrg#log#timer()
  let l:ms = skyrg#log#elapsed_ms(l:t)
  call Assert(type(l:ms) == v:t_float, 'log elapsed_ms: returns float')
  call Assert(l:ms >= 0.0, 'log elapsed_ms: non-negative')
  call s:teardown()
endfunction
call s:test_log_elapsed_ms()

function! s:test_log_elapsed_with_printf_args()
  call s:setup()
  let l:t = skyrg#log#timer()
  call skyrg#log#elapsed(l:t, 'test', 'done n=%d name=%s', 42, 'hello')
  let l:lines = s:read_log()
  call Assert(l:lines[-1] =~# 'done n=42 name=hello', 'log elapsed printf: formatted correctly')
  call s:teardown()
endfunction
call s:test_log_elapsed_with_printf_args()

function! s:test_log_elapsed_level_filtering()
  call s:setup()
  let g:skyrg_log_level = 'ERROR'
  let l:t = skyrg#log#timer()
  call skyrg#log#elapsed(l:t, 'test', 'should not appear')
  call skyrg#log#elapsed_debug(l:t, 'test', 'also not')
  let l:lines = s:read_log()
  let l:content = filter(copy(l:lines), {_, l -> l !~# '^---'})
  call AssertEqual(0, len(l:content), 'log elapsed filter: nothing logged at ERROR level')
  call s:teardown()
endfunction
call s:test_log_elapsed_level_filtering()
