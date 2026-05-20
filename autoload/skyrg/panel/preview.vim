" autoload/skyrg/panel/preview.vim — File preview with syntax highlighting
"
" Follows prep/render separation:
"   s:prepare()  — reads file lines + extracts syntax spans for the range
"   s:render()   — builds popup line dicts with syntax + match highlight
"   update()     — orchestrates prepare → render → popup_settext

let s:PREVIEW_CTX = 10

" Persistent hidden window for syntax analysis
let s:syn_winid = 0
let s:syn_file = ''

"==============================================================================
" Public API
"==============================================================================
function! skyrg#panel#preview#update() abort
  let l:s = skyrg#panel#state()
  let l:r = l:s.results
  if empty(l:r.matches)
    call popup_settext(l:s.popups.preview, [skyrg#panel#util#line('')])
    call popup_setoptions(l:s.popups.preview, {'title': ' Preview '})
    return
  endif
  let l:m = l:r.matches[l:r.idx]
  call popup_setoptions(l:s.popups.preview, {'title': ' '.skyrg#panel#util#short(l:m.file).' '})
  if !filereadable(l:m.file)
    call popup_settext(l:s.popups.preview, [skyrg#panel#util#hl_line('  (not readable)', 'skyrg_dim')])
    return
  endif
  let l:data = s:prepare(l:m.file, l:m.line)
  let l:lines = s:render(l:data, l:m.line)
  call popup_settext(l:s.popups.preview, l:lines)
endfunction

" Show preset details in the preview pane
function! skyrg#panel#preview#show_preset(name) abort
  let l:s = skyrg#panel#state()
  if empty(a:name)
    call popup_settext(l:s.popups.preview, [skyrg#panel#util#hl_line('  No preset selected', 'skyrg_dim')])
    call popup_setoptions(l:s.popups.preview, {'title': ' Preset '})
    return
  endif
  let l:sum = skyrg#panel#preset#get_summary(a:name)
  let l:lines = []
  call add(l:lines, skyrg#panel#util#hl_line('  Preset: ' . a:name, 'skyrg_sel'))
  call add(l:lines, skyrg#panel#util#line(''))
  call add(l:lines, skyrg#panel#util#hl_line('  Include types:', 'skyrg_dim'))
  if empty(l:sum.inc_types)
    call add(l:lines, skyrg#panel#util#line('    (all)'))
  else
    call add(l:lines, skyrg#panel#util#line('    ' . join(l:sum.inc_types, ', ')))
  endif
  call add(l:lines, skyrg#panel#util#line(''))
  call add(l:lines, skyrg#panel#util#hl_line('  Ignore types:', 'skyrg_dim'))
  if empty(l:sum.ign_types)
    call add(l:lines, skyrg#panel#util#line('    (none)'))
  else
    call add(l:lines, skyrg#panel#util#line('    ' . join(l:sum.ign_types, ', ')))
  endif
  call add(l:lines, skyrg#panel#util#line(''))
  call add(l:lines, skyrg#panel#util#hl_line('  Include dirs:', 'skyrg_dim'))
  if empty(l:sum.inc_dirs)
    call add(l:lines, skyrg#panel#util#line('    (cwd)'))
  else
    for l:d in l:sum.inc_dirs
      call add(l:lines, skyrg#panel#util#line('    ' . l:d))
    endfor
  endif
  call add(l:lines, skyrg#panel#util#line(''))
  call add(l:lines, skyrg#panel#util#hl_line('  Ignore dirs:', 'skyrg_dim'))
  if empty(l:sum.ign_dirs)
    call add(l:lines, skyrg#panel#util#line('    (none)'))
  else
    for l:d in l:sum.ign_dirs
      call add(l:lines, skyrg#panel#util#line('    ' . l:d))
    endfor
  endif
  call popup_settext(l:s.popups.preview, l:lines)
  call popup_setoptions(l:s.popups.preview, {'title': ' Preset: ' . a:name . ' '})
endfunction

function! skyrg#panel#preview#cleanup() abort
  if s:syn_winid && win_id2win(s:syn_winid)
    silent! execute win_id2win(s:syn_winid) . 'close!'
  endif
  let s:syn_winid = 0
  let s:syn_file = ''
endfunction

"==============================================================================
" Prep / Render (private)
"==============================================================================

" Read file lines and syntax spans for the preview range.
" Returns: {'file_lines': [...], 'syn_spans': [...], 'start': int, 'end': int}
function! s:prepare(file, match_line) abort
  let l:all = readfile(a:file)
  let l:s_line = max([0, a:match_line - s:PREVIEW_CTX - 1])
  let l:e_line = min([len(l:all)-1, a:match_line + s:PREVIEW_CTX - 1])
  let l:syn_spans = s:get_syntax_spans(a:file, l:s_line + 1, l:e_line + 1)
  return {'file_lines': l:all, 'syn_spans': l:syn_spans,
    \ 'start': l:s_line, 'end': l:e_line}
endfunction

" Build popup line dicts with syntax props + match highlight.
function! s:render(data, match_line) abort
  let l:lines = []
  for l:i in range(a:data.start, a:data.end)
    let l:ln = l:i + 1
    let l:prefix = printf('%s%4d  ', l:ln == a:match_line ? '>' : ' ', l:ln)
    let l:text = l:prefix . a:data.file_lines[l:i]
    let l:plen = len(l:prefix)

    " Dim line number prefix
    let l:props = [{'col': 1, 'length': l:plen, 'type': 'skyrg_dim'}]
    let l:span_idx = l:i - a:data.start
    if l:span_idx < len(a:data.syn_spans)
      for l:sp in a:data.syn_spans[l:span_idx]
        call add(l:props, {
          \ 'col': l:sp.col + l:plen,
          \ 'length': l:sp.length,
          \ 'type': l:sp.type})
      endfor
    endif
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
  " If the hidden window already has this file, nothing to do
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
