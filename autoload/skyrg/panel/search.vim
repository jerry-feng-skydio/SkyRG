" autoload/skyrg/panel/search.vim — Async ripgrep search job management
"
" Owns state.search: {gen, pending, job, timer, rg_error}
"
" NOTE: The rg command builder and async job logic have been extracted into
" skyrg#backend#rg (autoload/skyrg/backend/rg.vim). This module still
" manages the panel-specific wiring (state.results mutation, event emission).
" In a future phase, this module will delegate fully to the backend.

let s:SEARCH_DELAY = 300
let s:MAX_RESULTS = 500
let s:search_timer = []

function! skyrg#panel#search#schedule() abort
  let l:se = skyrg#panel#state().search
  if has_key(l:se, 'timer') | call timer_stop(l:se.timer) | endif
  let l:se.timer = timer_start(s:SEARCH_DELAY, function('s:do_search'))
endfunction

function! s:do_search(timer) abort
  call skyrg#panel#search#run()
endfunction

function! skyrg#panel#search#run() abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  let l:se = l:s.search
  let l:f = l:s.form
  if has_key(l:se, 'job') && job_status(l:se.job) ==# 'run'
    call job_stop(l:se.job)
  endif
  let l:se.gen += 1
  let l:se.rg_error = ''
  let l:q = l:f.fields[l:c.QUERY].value
  if empty(l:q)
    let l:s.results.matches = [] | let l:s.results.idx = 0
    call skyrg#panel#events#emit('results_changed')
    return
  endif
  let l:cmd = ['rg', '--column', '--line-number', '--no-heading',
    \ '--color=never', '--smart-case', '--max-count=500']
  if l:f.fields[l:c.GITIGN].value !=# 'on'
    call add(l:cmd, '--no-ignore')
  endif
  for l:t in split(l:f.fields[l:c.TYPES].value, ',')
    let l:t = trim(l:t)
    if empty(l:t) | continue | endif
    if l:t[0] ==# '.'
      call extend(l:cmd, ['-g', '*' . l:t])
    else
      call extend(l:cmd, ['-t', l:t])
    endif
  endfor
  let l:preset_name = trim(l:f.fields[l:c.PRESET].value)
  if !empty(l:preset_name)
    let l:filter = skyrg#panel#preset#get_sky_filter(l:preset_name)
    if !empty(l:filter)
      call extend(l:cmd, l:filter.get_globbing_args())
    endif
  endif
  call extend(l:cmd, ['--', l:q])
  let l:has_dir = 0
  for l:d in split(l:f.fields[l:c.DIRS].value, ',')
    let l:d = trim(l:d)
    if !empty(l:d) | call add(l:cmd, l:d) | let l:has_dir = 1 | endif
  endfor
  if !l:has_dir && !empty(l:preset_name)
    let l:filter = skyrg#panel#preset#get_sky_filter(l:preset_name)
    if !empty(l:filter)
      let l:sdirs = l:filter.get_search_dirs_list()
      if !empty(l:sdirs)
        call extend(l:cmd, l:sdirs)
        let l:has_dir = 1
      endif
    endif
  endif
  if !l:has_dir | call add(l:cmd, '.') | endif
  let s:search_timer = skyrg#log#timer()
  call skyrg#log#info('search', 'run gen=%d query="%s"', l:se.gen, l:q)
  call skyrg#log#debug('search', 'cmd: %s', join(l:cmd, ' '))
  let l:gen = l:se.gen
  let l:se.pending = []
  let l:se.job = job_start(l:cmd, {
    \ 'out_cb': function('s:on_out', [l:gen]),
    \ 'err_cb': function('s:on_err', [l:gen]),
    \ 'close_cb': function('s:on_done', [l:gen]),
    \ 'out_mode': 'nl',
    \ })
endfunction

function! s:on_err(gen, ch, msg) abort
  let l:se = skyrg#panel#state().search
  if a:gen != l:se.gen | return | endif
  let l:se.rg_error = a:msg
  call skyrg#log#warn('search', 'rg error gen=%d: %s', a:gen, a:msg)
endfunction

function! s:on_out(gen, ch, msg) abort
  let l:se = skyrg#panel#state().search
  if a:gen != l:se.gen || len(l:se.pending) >= s:MAX_RESULTS | return | endif
  let l:p = matchlist(a:msg, '^\(.\{-}\):\(\d\+\):\(\d\+\):\(.*\)$')
  if !empty(l:p)
    call add(l:se.pending, {
      \ 'file': l:p[1], 'line': str2nr(l:p[2]),
      \ 'col': str2nr(l:p[3]), 'text': trim(l:p[4])})
  endif
endfunction

function! s:on_done(gen, ch) abort
  let l:s = skyrg#panel#state()
  let l:se = l:s.search
  if a:gen != l:se.gen | return | endif
  if !empty(s:search_timer)
    call skyrg#log#elapsed(s:search_timer, 'search', 'done gen=%d results=%d', a:gen, len(l:se.pending))
    let s:search_timer = []
  else
    call skyrg#log#info('search', 'done gen=%d results=%d', a:gen, len(l:se.pending))
  endif
  let l:s.results.matches = l:se.pending
  let l:s.results.idx = 0 | let l:s.results.scroll = 0
  call skyrg#panel#preview#reset_mode()
  call skyrg#panel#preview#invalidate_cache()
  call skyrg#panel#events#emit('results_changed')
  redraw
endfunction
