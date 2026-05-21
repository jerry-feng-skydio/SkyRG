" skyrg/log.vim — Structured logging for SkyRG
"
" Levels: DEBUG < INFO < WARN < ERROR < OFF
" Output: file (append) + optional echom
"
" Configuration (in .vimrc):
"   let g:skyrg_log_level = 'INFO'   " DEBUG|INFO|WARN|ERROR|OFF
"   let g:skyrg_log_file  = '...'    " default: ~/.local/share/skyrg/skyrg.log
"   let g:skyrg_log_echo  = 0        " also echom (for live debugging)
"   let g:skyrg_log_max   = 5000     " max lines before rotation
"
" Usage:
"   call skyrg#log#debug('module', 'message %s', arg)
"   call skyrg#log#info('module', 'message')
"   call skyrg#log#warn('module', 'message')
"   call skyrg#log#error('module', 'message')
"   call skyrg#log#data('module', 'label', dict_or_list)

let s:levels = {'DEBUG': 0, 'INFO': 1, 'WARN': 2, 'ERROR': 3, 'OFF': 4}
let s:rotated = 0

"==============================================================================
" Public API
"==============================================================================

function! skyrg#log#debug(src, msg, ...) abort
  call s:log('DEBUG', a:src, a:msg, a:000)
endfunction

function! skyrg#log#info(src, msg, ...) abort
  call s:log('INFO', a:src, a:msg, a:000)
endfunction

function! skyrg#log#warn(src, msg, ...) abort
  call s:log('WARN', a:src, a:msg, a:000)
endfunction

function! skyrg#log#error(src, msg, ...) abort
  call s:log('ERROR', a:src, a:msg, a:000)
endfunction

" Log structured data (dict/list) as JSON on a separate line.
function! skyrg#log#data(src, label, data) abort
  if !s:should_log('DEBUG') | return | endif
  let l:json = json_encode(a:data)
  let l:line = s:timestamp() . ' [DEBUG] [' . a:src . '] ' . a:label . ': ' . l:json
  call s:write(l:line)
  if s:echo_enabled()
    echom '[SkyRG] ' . a:label . ': ' . l:json
  endif
endfunction

" Backward compat: status() maps to INFO
function! skyrg#log#status(msg, ...) abort
  call s:log('INFO', 'status', a:msg, a:000)
endfunction

"==============================================================================
" Timing traces
"==============================================================================

" Start a timer. Returns an opaque value to pass to elapsed().
function! skyrg#log#timer() abort
  return reltime()
endfunction

" Log elapsed time since timer was started.
" Automatically picks ms or s formatting. Logs at INFO level.
"   let t = skyrg#log#timer()
"   ... slow work ...
"   call skyrg#log#elapsed(t, 'module', 'description')
function! skyrg#log#elapsed(timer, src, msg, ...) abort
  if !s:should_log('INFO') | return | endif
  let l:ms = s:elapsed_ms(a:timer)
  let l:text = empty(a:000) ? a:msg : call('printf', [a:msg] + a:000)
  let l:fmt = l:ms >= 1000.0
    \ ? printf('%s (%.2fs)', l:text, l:ms / 1000.0)
    \ : printf('%s (%.1fms)', l:text, l:ms)
  call s:log('INFO', a:src, l:fmt, [])
endfunction

" Log elapsed time at DEBUG level (for less critical timings).
function! skyrg#log#elapsed_debug(timer, src, msg, ...) abort
  if !s:should_log('DEBUG') | return | endif
  let l:ms = s:elapsed_ms(a:timer)
  let l:text = empty(a:000) ? a:msg : call('printf', [a:msg] + a:000)
  let l:fmt = l:ms >= 1000.0
    \ ? printf('%s (%.2fs)', l:text, l:ms / 1000.0)
    \ : printf('%s (%.1fms)', l:text, l:ms)
  call s:log('DEBUG', a:src, l:fmt, [])
endfunction

" Return elapsed milliseconds as a float (for programmatic use).
function! skyrg#log#elapsed_ms(timer) abort
  return s:elapsed_ms(a:timer)
endfunction

"==============================================================================
" Log file management
"==============================================================================

function! skyrg#log#file() abort
  return s:log_file()
endfunction

" Rotate the log file (called on plugin load or manually).
function! skyrg#log#rotate() abort
  let l:file = s:log_file()
  if !filereadable(l:file) | return | endif
  let l:lines = readfile(l:file)
  let l:max = get(g:, 'skyrg_log_max', 5000)
  if len(l:lines) > l:max
    " Keep the last max/2 lines
    let l:keep = l:lines[len(l:lines) - l:max/2 :]
    call insert(l:keep, '--- log rotated at ' . strftime('%Y-%m-%d %H:%M:%S') . ' ---')
    call writefile(l:keep, l:file)
  endif
endfunction

" Clear the log file.
function! skyrg#log#clear() abort
  let l:file = s:log_file()
  call writefile([], l:file)
endfunction

"==============================================================================
" Private
"==============================================================================

function! s:log(level, src, msg, args) abort
  if !s:should_log(a:level) | return | endif
  let l:text = empty(a:args) ? a:msg : call('printf', [a:msg] + a:args)
  let l:line = s:timestamp() . ' [' . a:level . '] [' . a:src . '] ' . l:text
  call s:write(l:line)
  if s:echo_enabled() || a:level ==# 'ERROR'
    if a:level ==# 'ERROR'
      echohl ErrorMsg
    elseif a:level ==# 'WARN'
      echohl WarningMsg
    endif
    echom '[SkyRG] ' . l:text
    if a:level ==# 'ERROR' || a:level ==# 'WARN'
      echohl None
    endif
  endif
endfunction

function! s:should_log(level) abort
  let l:cfg = toupper(get(g:, 'skyrg_log_level', 'INFO'))
  return get(s:levels, a:level, 1) >= get(s:levels, l:cfg, 1)
endfunction

function! s:echo_enabled() abort
  return get(g:, 'skyrg_log_echo', 0)
endfunction

function! s:elapsed_ms(timer) abort
  let l:elapsed = reltime(a:timer)
  return str2float(reltimestr(l:elapsed)) * 1000.0
endfunction

function! s:timestamp() abort
  return strftime('%Y-%m-%d %H:%M:%S')
endfunction

function! s:log_file() abort
  if exists('g:skyrg_log_file') && !empty(g:skyrg_log_file)
    return g:skyrg_log_file
  endif
  let l:base = exists('$XDG_DATA_HOME') && !empty($XDG_DATA_HOME)
    \ ? $XDG_DATA_HOME : expand('~/.local/share')
  return l:base . '/skyrg/skyrg.log'
endfunction

function! s:write(line) abort
  let l:file = s:log_file()
  let l:dir = fnamemodify(l:file, ':h')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  " Rotate once per session
  if !s:rotated
    let s:rotated = 1
    call skyrg#log#rotate()
  endif
  call writefile([a:line], l:file, 'a')
endfunction
