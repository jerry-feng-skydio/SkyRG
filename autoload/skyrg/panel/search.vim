" autoload/skyrg/panel/search.vim — Async ripgrep search job management

let s:SEARCH_DELAY = 300
let s:MAX_RESULTS = 500

function! skyrg#panel#search#schedule() abort
  let l:s = skyrg#panel#state()
  if has_key(l:s, 'timer') | call timer_stop(l:s.timer) | endif
  let l:s.timer = timer_start(s:SEARCH_DELAY, function('s:do_search'))
endfunction

function! s:do_search(timer) abort
  call skyrg#panel#search#run()
endfunction

function! skyrg#panel#search#run() abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  if has_key(l:s, 'job') && job_status(l:s.job) ==# 'run'
    call job_stop(l:s.job)
  endif
  let l:s.search_gen += 1
  let l:s.rg_error = ''
  let l:q = l:s.fields[l:c.QUERY].value
  if empty(l:q)
    let l:s.matches = [] | let l:s.result_idx = 0
    call skyrg#panel#results#redraw() | call skyrg#panel#preview#update()
    return
  endif
  let l:cmd = ['rg', '--column', '--line-number', '--no-heading',
    \ '--color=never', '--smart-case', '--max-count=500']
  " Apply .gitignore setting
  if l:s.fields[l:c.GITIGN].value !=# 'on'
    call add(l:cmd, '--no-ignore')
  endif
  " Apply Types field
  for l:t in split(l:s.fields[l:c.TYPES].value, ',')
    let l:t = trim(l:t)
    if !empty(l:t) | call extend(l:cmd, ['-t', l:t]) | endif
  endfor
  " Apply SkyFilter preset if selected
  let l:preset_name = trim(l:s.fields[l:c.PRESET].value)
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
  " Apply Dirs field
  let l:has_dir = 0
  for l:d in split(l:s.fields[l:c.DIRS].value, ',')
    let l:d = trim(l:d)
    if !empty(l:d) | call add(l:cmd, l:d) | let l:has_dir = 1 | endif
  endfor
  " Apply SkyFilter search directories if no explicit dirs
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
  let l:gen = l:s.search_gen
  let l:s.pending = []
  let l:s.job = job_start(l:cmd, {
    \ 'out_cb': function('s:on_out', [l:gen]),
    \ 'err_cb': function('s:on_err', [l:gen]),
    \ 'close_cb': function('s:on_done', [l:gen]),
    \ 'out_mode': 'nl',
    \ })
endfunction

function! s:on_err(gen, ch, msg) abort
  let l:s = skyrg#panel#state()
  if a:gen != l:s.search_gen | return | endif
  let l:s.rg_error = a:msg
endfunction

function! s:on_out(gen, ch, msg) abort
  let l:s = skyrg#panel#state()
  if a:gen != l:s.search_gen || len(l:s.pending) >= s:MAX_RESULTS | return | endif
  let l:p = matchlist(a:msg, '^\(.\{-}\):\(\d\+\):\(\d\+\):\(.*\)$')
  if !empty(l:p)
    call add(l:s.pending, {
      \ 'file': l:p[1], 'line': str2nr(l:p[2]),
      \ 'col': str2nr(l:p[3]), 'text': trim(l:p[4])})
  endif
endfunction

function! s:on_done(gen, ch) abort
  let l:s = skyrg#panel#state()
  if a:gen != l:s.search_gen | return | endif
  let l:s.matches = l:s.pending
  let l:s.result_idx = 0 | let l:s.res_scroll = 0
  call skyrg#panel#results#redraw() | call skyrg#panel#preview#update()
  redraw
endfunction
