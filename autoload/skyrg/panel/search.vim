" autoload/skyrg/panel/search.vim — Async ripgrep search job management
"
" Owns state.search: {gen, pending, job, timer, rg_error}

let s:SEARCH_DELAY = 300
let s:MAX_RESULTS = 500

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
    if !empty(l:t) | call extend(l:cmd, ['-t', l:t]) | endif
  endfor
  let l:preset_name = trim(l:f.fields[l:c.PRESET].value)
  if !empty(l:preset_name)
    let l:filter = skyrg#panel#preset#get_sky_filter(l:preset_name)
    if !empty(l:filter)
      let l:glob_flags = l:filter.get_globbing_flags()
      if !empty(l:glob_flags)
        call extend(l:cmd, split(l:glob_flags))
      endif
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
      let l:sdirs = l:filter.get_search_directories()
      if !empty(l:sdirs)
        call extend(l:cmd, split(l:sdirs))
        let l:has_dir = 1
      endif
    endif
  endif
  if !l:has_dir | call add(l:cmd, '.') | endif
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
  let l:s.results.matches = l:se.pending
  let l:s.results.idx = 0 | let l:s.results.scroll = 0
  call skyrg#panel#events#emit('results_changed')
  redraw
endfunction
