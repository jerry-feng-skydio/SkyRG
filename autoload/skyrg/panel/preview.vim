" autoload/skyrg/panel/preview.vim — File preview with syntax highlighting

let s:PREVIEW_CTX = 10

" Persistent hidden window for syntax analysis
let s:syn_winid = 0
let s:syn_file = ''

"==============================================================================
" Public API
"==============================================================================
function! skyrg#panel#preview#update() abort
  let l:s = skyrg#panel#state()
  if empty(l:s.matches)
    call popup_settext(l:s.preview_id, [{'text': ''}])
    call popup_setoptions(l:s.preview_id, {'title': ' Preview '})
    return
  endif
  let l:m = l:s.matches[l:s.result_idx]
  call popup_setoptions(l:s.preview_id, {'title': ' '.skyrg#panel#util#short(l:m.file).' '})
  if !filereadable(l:m.file)
    call popup_settext(l:s.preview_id, [{'text': '  (not readable)'}])
    return
  endif
  let l:all = readfile(l:m.file)
  let l:s_line = max([0, l:m.line - s:PREVIEW_CTX - 1])
  let l:e_line = min([len(l:all)-1, l:m.line + s:PREVIEW_CTX - 1])

  " Get syntax spans from a hidden buffer
  let l:syn_spans = s:get_syntax_spans(l:m.file, l:s_line + 1, l:e_line + 1)

  let l:lines = []
  for l:i in range(l:s_line, l:e_line)
    let l:ln = l:i + 1
    let l:prefix = printf('%s%4d  ', l:ln == l:m.line ? '>' : ' ', l:ln)
    let l:text = l:prefix . l:all[l:i]
    let l:plen = len(l:prefix)

    " Collect props: syntax spans first, match highlight on top
    let l:props = []
    let l:span_idx = l:i - l:s_line
    if l:span_idx < len(l:syn_spans)
      for l:sp in l:syn_spans[l:span_idx]
        call add(l:props, {
          \ 'col': l:sp.col + l:plen,
          \ 'length': l:sp.length,
          \ 'type': l:sp.type})
      endfor
    endif
    if l:ln == l:m.line
      call add(l:props, {'col': 1, 'length': len(l:text), 'type': 'skyrg_match'})
    endif

    if empty(l:props)
      call add(l:lines, {'text': l:text})
    else
      call add(l:lines, {'text': l:text, 'props': l:props})
    endif
  endfor
  call popup_settext(l:s.preview_id, l:lines)
endfunction

function! skyrg#panel#preview#cleanup() abort
  if s:syn_winid && win_id2win(s:syn_winid)
    silent! execute win_id2win(s:syn_winid) . 'close!'
  endif
  let s:syn_winid = 0
  let s:syn_file = ''
endfunction

"==============================================================================
" Syntax analysis via hidden window
"==============================================================================

" Map synIDtrans name → prop type name. Returns '' for unmapped groups.
let s:hl_map = {}
for s:g in ['Comment', 'Constant', 'String', 'Identifier', 'Function',
  \ 'Statement', 'PreProc', 'Type', 'Special', 'Underlined',
  \ 'Error', 'Todo', 'Number', 'Boolean', 'Keyword', 'Operator']
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
