" autoload/skyrg/backend/rg.vim — Async ripgrep search backend
"
" Headless data producer: accepts query parameters, runs rg asynchronously,
" delivers results via callbacks. No UI knowledge.
"
" Conforms to the backend protocol (see docs/architecture/backends.md).
"
" Usage:
"   let backend = skyrg#backend#rg#new()
"   call backend.run({
"     \ 'query': 'search term', 'types': 'py,cpp', 'dirs': 'src/',
"     \ 'preset': 'my_preset', 'gitignore': 1,
"   \ }, {
"     \ 'on_result': function('s:on_item'),
"     \ 'on_done':   function('s:on_done'),
"     \ 'on_error':  function('s:on_error'),
"   \ })
"   call backend.cancel()

let s:MAX_RESULTS = 500

"==============================================================================
" Constructor
"==============================================================================

function! skyrg#backend#rg#new() abort
  let l:backend = {
    \ '_job':     0,
    \ '_gen':     0,
    \ '_pending': [],
    \ '_cbs':     {},
    \ '_error':   '',
    \ }

  function! l:backend.run(params, callbacks) dict abort
    call self.cancel()
    let self._gen += 1
    let self._error = ''
    let self._pending = []
    let self._cbs = a:callbacks

    let l:query = get(a:params, 'query', '')
    if empty(l:query)
      if has_key(a:callbacks, 'on_done')
        call a:callbacks.on_done([])
      endif
      return
    endif

    let l:cmd = s:build_cmd(a:params)
    let self._timer = skyrg#log#timer()
    call skyrg#log#info('backend/rg', 'run gen=%d query="%s"', self._gen, l:query)
    call skyrg#log#debug('backend/rg', 'cmd: %s', join(l:cmd, ' '))
    let l:gen = self._gen
    let l:be = self

    let self._job = job_start(l:cmd, {
      \ 'out_cb': function('s:on_out', [l:be, l:gen]),
      \ 'err_cb': function('s:on_err', [l:be, l:gen]),
      \ 'close_cb': function('s:on_done', [l:be, l:gen]),
      \ 'out_mode': 'nl',
      \ })
  endfunction

  function! l:backend.cancel() dict abort
    if type(self._job) != v:t_number && job_status(self._job) ==# 'run'
      call skyrg#log#debug('backend/rg', 'cancel gen=%d', self._gen)
      call job_stop(self._job)
    endif
  endfunction

  " Schedule a debounced search (convenience wrapper).
  function! l:backend.schedule(params, callbacks, ...) dict abort
    let l:delay = a:0 > 0 ? a:1 : 300
    if has_key(self, '_timer') && self._timer
      call timer_stop(self._timer)
    endif
    let self._timer = timer_start(l:delay,
      \ function('s:do_scheduled', [self, a:params, a:callbacks]))
  endfunction

  return l:backend
endfunction

"==============================================================================
" Command builder
"==============================================================================

function! s:build_cmd(params) abort
  let l:cmd = ['rg', '--column', '--line-number', '--no-heading',
    \ '--color=never', '--smart-case',
    \ '--max-count=' . s:MAX_RESULTS]

  " Gitignore
  if !get(a:params, 'gitignore', 1)
    call add(l:cmd, '--no-ignore')
  endif

  " File types
  for l:t in split(get(a:params, 'types', ''), ',')
    let l:t = trim(l:t)
    if empty(l:t) | continue | endif
    if l:t[0] ==# '.'
      call extend(l:cmd, ['-g', '*' . l:t])
    else
      call extend(l:cmd, ['-t', l:t])
    endif
  endfor

  " Preset globs
  let l:preset_name = trim(get(a:params, 'preset', ''))
  if !empty(l:preset_name)
    let l:filter = skyrg#panel#preset#get_sky_filter(l:preset_name)
    if !empty(l:filter)
      call extend(l:cmd, l:filter.get_globbing_args())
    endif
  endif

  " Query pattern
  call extend(l:cmd, ['--', a:params.query])

  " Directories
  let l:has_dir = 0
  for l:d in split(get(a:params, 'dirs', ''), ',')
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

  return l:cmd
endfunction

"==============================================================================
" Job callbacks
"==============================================================================

function! s:on_out(be, gen, ch, msg) abort
  if a:gen != a:be._gen || len(a:be._pending) >= s:MAX_RESULTS | return | endif
  let l:p = matchlist(a:msg, '^\(.\{-}\):\(\d\+\):\(\d\+\):\(.*\)$')
  if !empty(l:p)
    let l:item = {
      \ 'file': l:p[1], 'line': str2nr(l:p[2]),
      \ 'col': str2nr(l:p[3]), 'text': trim(l:p[4])}
    call add(a:be._pending, l:item)
    if has_key(a:be._cbs, 'on_result')
      call a:be._cbs.on_result(l:item)
    endif
  endif
endfunction

function! s:on_err(be, gen, ch, msg) abort
  if a:gen != a:be._gen | return | endif
  let a:be._error = a:msg
  call skyrg#log#warn('backend/rg', 'error gen=%d: %s', a:gen, a:msg)
  if has_key(a:be._cbs, 'on_error')
    call a:be._cbs.on_error(a:msg)
  endif
endfunction

function! s:on_done(be, gen, ch) abort
  if a:gen != a:be._gen | return | endif
  if has_key(a:be, '_timer') && !empty(a:be._timer)
    call skyrg#log#elapsed(a:be._timer, 'backend/rg', 'done gen=%d results=%d', a:gen, len(a:be._pending))
    let a:be._timer = []
  else
    call skyrg#log#info('backend/rg', 'done gen=%d results=%d', a:gen, len(a:be._pending))
  endif
  if has_key(a:be._cbs, 'on_done')
    call a:be._cbs.on_done(a:be._pending)
  endif
endfunction

function! s:do_scheduled(be, params, callbacks, timer) abort
  call a:be.run(a:params, a:callbacks)
endfunction
