" autoload/skyrg/ui/live_split.vim — Reusable tailing scratch split
"
" Shared infrastructure for styled, auto-scrolling scratch splits. Supports
" two data sources:
"   - 'file': re-reads a file on a timer (for task log files)
"   - 'job':  streams stdout from a shell command (for ssh tail, logcat, etc.)
"
" Usage:
"   let id = skyrg#ui#live_split#open({
"     \ 'title': 'My Log',
"     \ 'source': 'file',        " 'file' or 'job'
"     \ 'path': '/path/to/log',  " required for source=file
"     \ 'cmd': 'ssh host tail -f /var/log/syslog',  " required for source=job
"     \ 'cwd': '/some/dir',      " optional, for source=job
"     \ 'height': 10,            " optional, default g:skyrg_log_height
"     \ })
"
"   call skyrg#ui#live_split#close(id)       " close split + stop source
"   call skyrg#ui#live_split#stop(id)        " stop source, keep split open
"   call skyrg#ui#live_split#close_all()     " close everything
"
" Buffer keymaps (set automatically):
"   w   — save buffer contents to a timestamped file in /tmp
"   q   — close the split

" { id: { bufnr, source, timer, job, path, ... } }
let s:splits = {}
let s:next_id = 1

"==============================================================================
" Open
"==============================================================================

function! skyrg#ui#live_split#open(opts) abort
  let l:id = s:next_id
  let s:next_id += 1

  let l:height = get(a:opts, 'height', get(g:, 'skyrg_log_height', 10))
  let l:title = get(a:opts, 'title', 'SkyRG')
  let l:source = get(a:opts, 'source', 'file')

  execute 'botright ' . l:height . 'new'
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  execute 'file' fnameescape('[SkyRG #' . l:id . '] ' . l:title)
  call skyrg#ui#style#apply_log()
  nnoremap <buffer> <silent> q :call skyrg#ui#live_split#close_current()<CR>
  nnoremap <buffer> <silent> w :call skyrg#ui#live_split#save_current()<CR>
  nnoremap <buffer> <silent> y :call skyrg#ui#live_split#yank_current()<CR>

  let l:bufnr = bufnr('%')
  let l:entry = {
    \ 'id': l:id,
    \ 'bufnr': l:bufnr,
    \ 'source': l:source,
    \ 'title': l:title,
    \ 'timer': 0,
    \ 'job': v:null,
    \ 'path': get(a:opts, 'path', ''),
    \ }

  if l:source ==# 'file'
    " Populate from file, start timer
    let l:path = a:opts.path
    if filereadable(l:path)
      call setline(1, readfile(l:path))
      normal! G
    endif
    let l:entry.timer = timer_start(1000,
      \ function('s:file_tick', [l:id]), {'repeat': -1})
  elseif l:source ==# 'job'
    " Start a job, stream stdout into buffer
    let l:cmd = a:opts.cmd
    let l:job_opts = {
      \ 'out_cb': function('s:job_out', [l:id]),
      \ 'err_cb': function('s:job_out', [l:id]),
      \ 'exit_cb': function('s:job_exit', [l:id]),
      \ 'out_mode': 'nl',
      \ 'err_mode': 'nl',
      \ }
    let l:cwd = get(a:opts, 'cwd', '')
    if !empty(l:cwd) && isdirectory(l:cwd)
      let l:job_opts.cwd = l:cwd
    endif
    let l:entry.job = job_start(['/bin/sh', '-c', l:cmd], l:job_opts)
    " Auto-scroll timer (job appends async, scroll needs periodic check)
    let l:entry.timer = timer_start(500,
      \ function('s:scroll_tick', [l:id]), {'repeat': -1})
  endif

  let s:splits[l:id] = l:entry
  call skyrg#log#info('ui/live_split', 'open #%d "%s" source=%s', l:id, l:title, l:source)
  return l:id
endfunction

"==============================================================================
" Close / Stop
"==============================================================================

" Close the split entirely (stop source + wipe buffer).
function! skyrg#ui#live_split#close(id) abort
  let l:s = get(s:splits, a:id, {})
  if empty(l:s) | return | endif
  call s:cleanup_source(l:s)
  if bufexists(l:s.bufnr)
    let l:win = bufwinnr(l:s.bufnr)
    if l:win != -1
      execute l:win . 'wincmd w'
      silent! close
    endif
    silent! execute 'bwipeout' l:s.bufnr
  endif
  if has_key(s:splits, a:id)
    call remove(s:splits, a:id)
  endif
  call skyrg#log#info('ui/live_split', 'close #%d', a:id)
endfunction

" Stop the data source but keep the split open with final content.
function! skyrg#ui#live_split#stop(id) abort
  let l:s = get(s:splits, a:id, {})
  if empty(l:s) | return | endif
  call s:cleanup_source(l:s)
  " Final refresh for file source
  if l:s.source ==# 'file' && filereadable(l:s.path)
    call s:refresh_buffer(l:s.bufnr, readfile(l:s.path))
  endif
  if has_key(s:splits, a:id)
    call remove(s:splits, a:id)
  endif
  call skyrg#log#info('ui/live_split', 'stop #%d (split kept)', a:id)
endfunction

" Close all live splits.
function! skyrg#ui#live_split#close_all() abort
  for l:id in keys(s:splits)
    call skyrg#ui#live_split#close(l:id)
  endfor
endfunction

" Get the buffer number for a live split (for external tracking).
function! skyrg#ui#live_split#bufnr(id) abort
  let l:s = get(s:splits, a:id, {})
  return empty(l:s) ? -1 : l:s.bufnr
endfunction

" Return 1 if the given buffer number belongs to an active live split.
function! skyrg#ui#live_split#is_live_split(bufnr) abort
  return s:id_for_bufnr(a:bufnr) != -1
endfunction

"==============================================================================
" File source — timer-based re-read
"==============================================================================

function! s:file_tick(id, timer) abort
  let l:s = get(s:splits, a:id, {})
  if empty(l:s) || !bufexists(l:s.bufnr) || !filereadable(l:s.path)
    call skyrg#ui#live_split#close(a:id)
    return
  endif
  let l:win = bufwinnr(l:s.bufnr)
  if l:win == -1
    call skyrg#ui#live_split#close(a:id)
    return
  endif
  let l:cur_win = winnr()
  execute l:win . 'wincmd w'
  let l:prev_line = line('.')
  let l:was_at_end = (l:prev_line >= line('$') - 1)
  let l:lines = readfile(l:s.path)
  silent! %delete _
  call setline(1, l:lines)
  if l:was_at_end
    normal! G
  else
    execute 'keepjumps normal!' min([l:prev_line, len(l:lines)]) . 'G'
  endif
  execute l:cur_win . 'wincmd w'
endfunction

"==============================================================================
" Job source — stdout callback + scroll timer
"==============================================================================

function! s:job_out(id, ch, msg) abort
  let l:s = get(s:splits, a:id, {})
  if empty(l:s) || !bufexists(l:s.bufnr) | return | endif
  " Append line to buffer
  call appendbufline(l:s.bufnr, '$', a:msg)
endfunction

function! s:job_exit(id, job, exit_code) abort
  let l:s = get(s:splits, a:id, {})
  if empty(l:s) | return | endif
  " Stop the scroll timer but keep the split open
  if l:s.timer
    call timer_stop(l:s.timer)
    let l:s.timer = 0
  endif
  let l:s.job = v:null
  " Append exit status line
  if bufexists(l:s.bufnr)
    let l:msg = a:exit_code == 0
      \ ? printf('--- exited cleanly ---')
      \ : printf('--- exited with code %d ---', a:exit_code)
    call appendbufline(l:s.bufnr, '$', l:msg)
  endif
  call skyrg#log#info('ui/live_split', '#%d job exited (%d)', a:id, a:exit_code)
  if has_key(s:splits, a:id)
    call remove(s:splits, a:id)
  endif
endfunction

" Periodic scroll-to-bottom for job source (if cursor at end).
function! s:scroll_tick(id, timer) abort
  let l:s = get(s:splits, a:id, {})
  if empty(l:s) || !bufexists(l:s.bufnr)
    call timer_stop(a:timer)
    return
  endif
  let l:win = bufwinnr(l:s.bufnr)
  if l:win == -1
    call timer_stop(a:timer)
    return
  endif
  let l:cur_win = winnr()
  execute l:win . 'wincmd w'
  if line('.') >= line('$') - 2
    normal! G
  endif
  execute l:cur_win . 'wincmd w'
endfunction

"==============================================================================
" Save buffer to file
"==============================================================================

" Save the current buffer's live_split contents to a timestamped file.
function! skyrg#ui#live_split#save_current() abort
  let l:id = s:id_for_bufnr(bufnr('%'))
  if l:id == -1
    echohl WarningMsg | echo '[SkyRG] Not a live split buffer' | echohl None
    return
  endif
  let l:s = s:splits[l:id]
  let l:dir = s:save_dir()
  let l:slug = substitute(tolower(l:s.title), '[^a-z0-9]\+', '-', 'g')
  let l:slug = substitute(l:slug, '-\+$', '', '')
  let l:fname = l:dir . '/' . printf('%s-%s.log', l:slug, strftime('%Y%m%d-%H%M%S'))
  let l:lines = getbufline(l:s.bufnr, 1, '$')
  call writefile(l:lines, l:fname)

  " Register as a task so it appears in the task viewer
  let l:task_id = skyrg#backend#tasks#add({
    \ 'title': 'Saved: ' . l:s.title,
    \ 'cmd': 'save ' . l:fname,
    \ })
  call skyrg#backend#tasks#append_output(l:task_id, 'stdout',
    \ printf('Saved %d lines from "%s"', len(l:lines), l:s.title))
  call skyrg#backend#tasks#append_output(l:task_id, 'stdout', l:fname)
  call skyrg#backend#tasks#complete(l:task_id, 0)

  echo printf('[SkyRG] Saved %d lines → %s', len(l:lines), l:fname)
endfunction

" Copy the current buffer's live_split contents to the system clipboard.
function! skyrg#ui#live_split#yank_current() abort
  let l:id = s:id_for_bufnr(bufnr('%'))
  if l:id == -1
    echohl WarningMsg | echo '[SkyRG] Not a live split buffer' | echohl None
    return
  endif
  let l:s = s:splits[l:id]
  let l:lines = getbufline(l:s.bufnr, 1, '$')
  let @+ = join(l:lines, "\n")
  echo printf('[SkyRG] Copied %d lines to clipboard', len(l:lines))
endfunction

" Close the live_split under the cursor.
function! skyrg#ui#live_split#close_current() abort
  let l:id = s:id_for_bufnr(bufnr('%'))
  if l:id == -1 | return | endif
  call skyrg#ui#live_split#close(l:id)
endfunction

" Find split id by buffer number.
function! s:id_for_bufnr(bufnr) abort
  for [l:id, l:s] in items(s:splits)
    if l:s.bufnr == a:bufnr
      return l:id
    endif
  endfor
  return -1
endfunction

"==============================================================================
" Internal helpers
"==============================================================================

function! s:save_dir() abort
  let l:base = exists('$XDG_DATA_HOME') && !empty($XDG_DATA_HOME)
    \ ? $XDG_DATA_HOME : expand('~/.local/share')
  let l:dir = l:base . '/skyrg/saved'
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  return l:dir
endfunction

function! s:cleanup_source(entry) abort
  if a:entry.timer
    call timer_stop(a:entry.timer)
    let a:entry.timer = 0
  endif
  if a:entry.job != v:null && job_status(a:entry.job) ==# 'run'
    call job_stop(a:entry.job)
    let a:entry.job = v:null
  endif
endfunction

" Replace buffer contents and optionally scroll to bottom.
function! s:refresh_buffer(bufnr, lines) abort
  let l:win = bufwinnr(a:bufnr)
  if l:win == -1 | return | endif
  let l:cur_win = winnr()
  execute l:win . 'wincmd w'
  silent! %delete _
  call setline(1, a:lines)
  normal! G
  execute l:cur_win . 'wincmd w'
endfunction
