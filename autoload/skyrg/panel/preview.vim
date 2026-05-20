" autoload/skyrg/panel/preview.vim — File preview with syntax highlighting
"
" Two preview modes:
"   MATCH_ONLY  (0) — lightweight: line numbers + match highlight only
"   PREVIEW_SYNTAX (1) — full syntax highlighting + match highlight
"
" Syntax computation strategy (g:skyrg_syntax_mode):
"   'lazy'      — compute spans for a file on first display (default)
"   'cache_all' — compute spans for ALL result files at once on toggle
"
" Syntax spans are cached per search generation and file. Mashing 's'
" while the query hasn't changed is a no-op.

" Preview context is now dynamic based on popup height (see s:visible_lines())

" Persistent hidden window for syntax analysis
let s:syn_winid = 0
let s:syn_file = ''

" Timer ID for batch cache_all computation
let s:batch_timer = 0
let s:batch_gen = -1

"==============================================================================
" Public API
"==============================================================================

" Main update — called when the selected match changes or results arrive.
function! skyrg#panel#preview#update() abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  let l:r = l:s.results
  if empty(l:r.matches)
    call popup_settext(l:s.popups.preview, [skyrg#panel#util#line('')])
    call popup_setoptions(l:s.popups.preview, {'title': ' Preview '})
    return
  endif
  let l:m = l:r.matches[l:r.idx]
  let l:mode_tag = l:s.preview_mode == l:c.PREVIEW_SYNTAX ? ' [syn] ' : ' '
  call popup_setoptions(l:s.popups.preview, {
    \ 'title': l:mode_tag . skyrg#panel#util#short(l:m.file) . ' '})
  if !filereadable(l:m.file)
    call popup_settext(l:s.popups.preview, [skyrg#panel#util#hl_line('  (not readable)', 'skyrg_dim')])
    return
  endif
  let l:want_syn = l:s.preview_mode == l:c.PREVIEW_SYNTAX
  let l:syn_spans = []
  if l:want_syn
    let l:syn_spans = s:get_cached_or_compute(l:m.file, l:m.line)
  endif
  let l:vis = s:visible_lines(l:s)
  let l:data = s:prepare(l:m.file, l:m.line, l:syn_spans, l:vis)
  let l:lines = s:render(l:data, l:m.line)
  call popup_settext(l:s.popups.preview, l:lines)
endfunction

" Toggle between MATCH_ONLY and MATCH_SYNTAX_HIGHLIGHTED.
" Robust: pressing 's' repeatedly with unchanged query is a no-op.
function! skyrg#panel#preview#toggle_syntax() abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  if l:s.preview_mode == l:c.PREVIEW_MATCH_ONLY
    let l:s.preview_mode = l:c.PREVIEW_SYNTAX
    " If cache_all mode, start batch computation
    if s:syntax_mode() ==# 'cache_all' && !empty(l:s.results.matches)
      call s:start_batch_cache(l:s)
    endif
  else
    let l:s.preview_mode = l:c.PREVIEW_MATCH_ONLY
  endif
  call skyrg#panel#preview#update()
endfunction

" Reset preview mode to MATCH_ONLY (called after each new search).
function! skyrg#panel#preview#reset_mode() abort
  let l:s = skyrg#panel#state()
  let l:s.preview_mode = 0
  " Stop any running batch computation
  if s:batch_timer | call timer_stop(s:batch_timer) | let s:batch_timer = 0 | endif
endfunction

" Invalidate syntax cache (called when search gen changes).
function! skyrg#panel#preview#invalidate_cache() abort
  let l:s = skyrg#panel#state()
  let l:s._syn_cache = {}
  let l:s._syn_cache_gen = -1
  if s:batch_timer | call timer_stop(s:batch_timer) | let s:batch_timer = 0 | endif
endfunction

" Show preset details in the info pane (right of query form).
" Includes a carousel of all preset names at the bottom.
function! skyrg#panel#preview#show_preset(name) abort
  let l:s = skyrg#panel#state()
  let l:info = get(l:s.popups, 'info', 0)
  if !l:info | return | endif
  let l:lines = []
  if empty(a:name)
    call add(l:lines, skyrg#panel#util#hl_line(' No preset selected', 'skyrg_dim'))
  else
    let l:sum = skyrg#panel#preset#get_summary(a:name)
    call add(l:lines, skyrg#panel#util#hl_line(' Preset: ' . a:name, 'skyrg_sel'))
    if !empty(l:sum.inc_types)
      call add(l:lines, skyrg#panel#util#hl_line(' +types: ' . join(l:sum.inc_types, ', '), 'skyrg_dim'))
    endif
    if !empty(l:sum.ign_types)
      call add(l:lines, skyrg#panel#util#hl_line(' -types: ' . join(l:sum.ign_types, ', '), 'skyrg_dim'))
    endif
    if !empty(l:sum.inc_dirs)
      call add(l:lines, skyrg#panel#util#hl_line(' +dirs:  ' . join(l:sum.inc_dirs, ', '), 'skyrg_dim'))
    endif
    if !empty(l:sum.ign_dirs)
      call add(l:lines, skyrg#panel#util#hl_line(' -dirs:  ' . join(l:sum.ign_dirs, ', '), 'skyrg_dim'))
    endif
  endif
  " Build carousel line with all preset names
  let l:carousel = s:build_carousel(a:name)
  if !empty(l:carousel)
    " Pad to push carousel to the bottom of the info pane
    let l:geo = skyrg#panel#get_layout().geo.info
    let l:avail = get(l:geo, 'height', 7)
    while len(l:lines) < l:avail - 1
      call add(l:lines, skyrg#panel#util#line(''))
    endwhile
    call add(l:lines, l:carousel)
  endif
  call popup_settext(l:info, l:lines)
  let l:title = empty(a:name) ? ' Info ' : ' Preset: ' . a:name . ' '
  call popup_setoptions(l:info, {'title': l:title})
endfunction

" Build a carousel line: " name1 | [name2] | name3 "
" Active preset is highlighted with skyrg_sel prop.
function! s:build_carousel(active) abort
  let l:names = skyrg#panel#preset#names()
  if empty(l:names)
    return {}
  endif
  let l:sep = ' | '
  let l:text = ' '
  let l:props = []
  for l:i in range(len(l:names))
    let l:n = l:names[l:i]
    let l:is_active = l:n ==# a:active
    if l:is_active
      let l:start = len(l:text)
      let l:label = '[' . l:n . ']'
      let l:text .= l:label
      call add(l:props, {'col': l:start + 1, 'length': len(l:label), 'type': 'skyrg_sel'})
    else
      let l:text .= l:n
    endif
    if l:i < len(l:names) - 1
      let l:text .= l:sep
    endif
  endfor
  return skyrg#panel#util#line(l:text, l:props)
endfunction

" Clear the info pane.
function! skyrg#panel#preview#clear_info() abort
  let l:s = skyrg#panel#state()
  let l:info = get(l:s.popups, 'info', 0)
  if !l:info | return | endif
  call popup_settext(l:info, [skyrg#panel#util#line('')])
  call popup_setoptions(l:info, {'title': ' Info '})
endfunction

function! skyrg#panel#preview#cleanup() abort
  if s:syn_winid && win_id2win(s:syn_winid)
    silent! execute win_id2win(s:syn_winid) . 'close!'
  endif
  let s:syn_winid = 0
  let s:syn_file = ''
  if s:batch_timer | call timer_stop(s:batch_timer) | let s:batch_timer = 0 | endif
endfunction

"==============================================================================
" Configuration helper
"==============================================================================
function! s:syntax_mode() abort
  return get(g:, 'skyrg_syntax_mode', 'lazy')
endfunction

"==============================================================================
" Syntax cache
"==============================================================================

" Return cached spans or compute them (lazy mode: only this file).
function! s:get_cached_or_compute(file, match_line) abort
  let l:s = skyrg#panel#state()
  let l:gen = l:s.search.gen
  " Invalidate cache on generation change
  if l:s._syn_cache_gen != l:gen
    let l:s._syn_cache = {}
    let l:s._syn_cache_gen = l:gen
  endif
  " Return from cache if available
  if has_key(l:s._syn_cache, a:file)
    return l:s._syn_cache[a:file]
  endif
  " Compute and cache
  let l:all = readfile(a:file)
  let l:spans = s:get_syntax_spans(a:file, 1, len(l:all))
  let l:s._syn_cache[a:file] = l:spans
  return l:spans
endfunction

"==============================================================================
" Batch cache_all computation (incremental via timer)
"==============================================================================
function! s:start_batch_cache(state) abort
  let l:gen = a:state.search.gen
  " Already cached for this gen — no-op (robust against 's' mashing)
  if a:state._syn_cache_gen == l:gen && !empty(a:state._syn_cache)
    return
  endif
  let a:state._syn_cache = {}
  let a:state._syn_cache_gen = l:gen
  " Collect unique files
  let l:files = {}
  for l:m in a:state.results.matches
    let l:files[l:m.file] = 1
  endfor
  let s:batch_queue = keys(l:files)
  let s:batch_gen = l:gen
  if s:batch_timer | call timer_stop(s:batch_timer) | endif
  let s:batch_timer = timer_start(10, function('s:batch_step'), {'repeat': -1})
endfunction

function! s:batch_step(timer) abort
  let l:s = skyrg#panel#state()
  " Abort if generation has changed (new search started)
  if l:s.search.gen != s:batch_gen || empty(s:batch_queue)
    call timer_stop(a:timer)
    let s:batch_timer = 0
    return
  endif
  let l:file = remove(s:batch_queue, 0)
  if has_key(l:s._syn_cache, l:file) || !filereadable(l:file)
    return
  endif
  let l:all = readfile(l:file)
  let l:spans = s:get_syntax_spans(l:file, 1, len(l:all))
  let l:s._syn_cache[l:file] = l:spans
  " Refresh preview if this is the currently-displayed file
  let l:r = l:s.results
  if !empty(l:r.matches) && l:r.matches[l:r.idx].file ==# l:file
    call skyrg#panel#preview#update()
  endif
endfunction

"==============================================================================
" Prep / Render (private)
"==============================================================================

" Compute how many lines the preview popup can display.
function! s:visible_lines(state) abort
  let l:geo = skyrg#panel#get_layout().geo.preview
  return max([get(l:geo, 'height', 20), 6])
endfunction

" Read file lines and build data dict for rendering.
" Centers the match line in the visible window, using all available space.
function! s:prepare(file, match_line, syn_spans, visible) abort
  let l:all = readfile(a:file)
  let l:total = len(l:all)
  let l:half = a:visible / 2
  " Center the match line; clamp to file boundaries
  let l:s_line = max([0, a:match_line - 1 - l:half])
  let l:e_line = l:s_line + a:visible - 1
  if l:e_line >= l:total
    let l:e_line = l:total - 1
    let l:s_line = max([0, l:e_line - a:visible + 1])
  endif
  return {'file_lines': l:all, 'syn_spans': a:syn_spans,
    \ 'start': l:s_line, 'end': l:e_line}
endfunction

" Build popup line dicts with optional syntax props + match highlight.
function! s:render(data, match_line) abort
  let l:lines = []
  for l:i in range(a:data.start, a:data.end)
    let l:ln = l:i + 1
    let l:prefix = printf('%s%4d  ', l:ln == a:match_line ? '>' : ' ', l:ln)
    let l:text = l:prefix . a:data.file_lines[l:i]
    let l:plen = len(l:prefix)

    " Dim line number prefix
    let l:props = [{'col': 1, 'length': l:plen, 'type': 'skyrg_dim'}]
    " Apply syntax spans if available (indexed by 0-based line number)
    if !empty(a:data.syn_spans) && l:i < len(a:data.syn_spans)
      for l:sp in a:data.syn_spans[l:i]
        call add(l:props, {
          \ 'col': l:sp.col + l:plen,
          \ 'length': l:sp.length,
          \ 'type': l:sp.type})
      endfor
    endif
    " Highlight match line
    if l:ln == a:match_line
      call add(l:props, {'col': 1, 'length': len(l:text), 'type': 'skyrg_match'})
    endif

    call add(l:lines, skyrg#panel#util#line(l:text, l:props))
  endfor
  return l:lines
endfunction

"==============================================================================
" Syntax analysis via hidden window
"==============================================================================

" Map synIDtrans name → prop type name. Returns '' for unmapped groups.
let s:hl_map = {}
for s:g in skyrg#panel#style#syn_groups()
  let s:hl_map[s:g] = 'skyrg_syn_' . s:g
endfor

function! s:map_hl(name) abort
  return get(s:hl_map, a:name, '')
endfunction

function! s:get_syntax_spans(file, start_lnum, end_lnum) abort
  " Ensure hidden window has the right file loaded with syntax
  call s:ensure_syn_window(a:file)

  let l:result = []
  if !s:syn_winid || !win_id2win(s:syn_winid)
    " Fallback: no syntax, return empty spans
    for l:lnum in range(a:start_lnum, a:end_lnum)
      call add(l:result, [])
    endfor
    return l:result
  endif

  let l:save_win = win_getid()

  " Switch to the syntax window to query synID
  noautocmd call win_gotoid(s:syn_winid)

  for l:lnum in range(a:start_lnum, a:end_lnum)
    let l:line = getline(l:lnum)
    let l:line_len = len(l:line)
    let l:spans = []

    if l:line_len > 0
      let l:prev_prop = ''
      let l:span_start = 1

      for l:col in range(1, l:line_len)
        let l:id = synIDtrans(synID(l:lnum, l:col, 1))
        let l:hl_name = synIDattr(l:id, 'name')
        let l:prop = s:map_hl(l:hl_name)

        if l:prop !=# l:prev_prop
          " Close previous span
          if !empty(l:prev_prop)
            call add(l:spans, {
              \ 'col': l:span_start,
              \ 'length': l:col - l:span_start,
              \ 'type': l:prev_prop})
          endif
          let l:prev_prop = l:prop
          let l:span_start = l:col
        endif
      endfor
      " Close final span
      if !empty(l:prev_prop)
        call add(l:spans, {
          \ 'col': l:span_start,
          \ 'length': l:line_len - l:span_start + 1,
          \ 'type': l:prev_prop})
      endif
    endif

    call add(l:result, l:spans)
  endfor

  " Switch back
  noautocmd call win_gotoid(l:save_win)
  return l:result
endfunction

function! s:ensure_syn_window(file) abort
  " If the hidden window already has this file loaded with syntax
  if s:syn_winid && win_id2win(s:syn_winid) && s:syn_file ==# a:file
    return
  endif

  let l:save_win = win_getid()

  " Create or reuse the hidden 1-line split
  if !s:syn_winid || !win_id2win(s:syn_winid)
    noautocmd silent! botright 1split
    let s:syn_winid = win_getid()
    setlocal noswapfile bufhidden=hide nobuflisted
    setlocal nonumber norelativenumber signcolumn=no
  else
    noautocmd call win_gotoid(s:syn_winid)
  endif

  " Load the file
  noautocmd silent! execute 'edit ' . fnameescape(a:file)
  let s:syn_file = a:file

  " Ensure syntax is enabled
  if !exists('b:current_syntax') || empty(b:current_syntax)
    filetype detect
    syntax enable
  endif

  " Go back to the original window
  noautocmd call win_gotoid(l:save_win)
endfunction
