" autoload/skyrg/ui/panes/preview.vim — Generic file preview pane
"
" Displays a file with line numbers, optional syntax highlighting, and
" a highlighted target line. Conforms to the pane protocol.
"
" Usage:
"   let pane = skyrg#ui#panes#preview#new({
"     \ 'syntax_enabled': 1,
"     \ })
"   call pane.show_file('/path/to/file.py', 42)

" Hidden window state for syntax analysis
let s:syn_winid = 0
let s:syn_file = ''

" Syntax group → prop type mapping
let s:hl_map = {}

"==============================================================================
" Constructor
"==============================================================================

function! skyrg#ui#panes#preview#new(config) abort
  " Build hl_map on first use
  if empty(s:hl_map)
    for l:g in skyrg#ui#style#syn_groups()
      let s:hl_map[l:g] = 'skyrg_syn_' . l:g
    endfor
  endif

  let l:pane = {
    \ 'name':   '',
    \ 'config': a:config,
    \ 'state':  {'file': '', 'line': 0, 'col': 0, 'text': '',
    \            'syn_mode': 0, 'syn_spans': []},
    \ '_geo':   {'height': 20, 'width': 40},
    \ '_lines': [],
    \ }

  function! l:pane.render() dict abort
    return empty(self._lines) ? [{'text': ''}] : self._lines
  endfunction

  function! l:pane.on_key(key, K) dict abort
    return 0
  endfunction

  function! l:pane.on_focus() dict abort
  endfunction

  function! l:pane.on_blur() dict abort
  endfunction

  function! l:pane.on_resize(geo) dict abort
    let self._geo = a:geo
    " Re-render with new visible lines count
    if !empty(self.state.file)
      call self.show_file(self.state.file, self.state.line)
    endif
  endfunction

  function! l:pane.cleanup() dict abort
    call skyrg#ui#panes#preview#cleanup_syn()
  endfunction

  " --- Public API ---

  " Show a file at a given line, centered in the pane.
  function! l:pane.show_file(file, line, ...) dict abort
    let self.state.file = a:file
    let self.state.line = a:line
    let l:syn_spans = a:0 > 0 ? a:1 : []
    if !filereadable(a:file)
      let self._lines = [skyrg#ui#util#hl_line('  File not found: ' . a:file, 'skyrg_dim')]
      return
    endif
    let l:visible = max([self._geo.height - 2, 6])
    let l:all = readfile(a:file)
    let l:data = s:prepare(l:all, a:line, l:syn_spans, l:visible)
    let self._lines = s:render(l:data, a:line)
  endfunction

  " Show a file with on-demand syntax highlighting.
  function! l:pane.show_file_with_syntax(file, line) dict abort
    if !filereadable(a:file)
      let self._lines = [skyrg#ui#util#hl_line('  File not found: ' . a:file, 'skyrg_dim')]
      return
    endif
    let l:all = readfile(a:file)
    let l:spans = s:get_syntax_spans(a:file, 1, len(l:all))
    call self.show_file(a:file, a:line, l:spans)
  endfunction

  " Toggle syntax highlighting on/off.
  function! l:pane.toggle_syntax() dict abort
    let self.state.syn_mode = !self.state.syn_mode
    if !empty(self.state.file)
      if self.state.syn_mode
        call self.show_file_with_syntax(self.state.file, self.state.line)
      else
        call self.show_file(self.state.file, self.state.line)
      endif
    endif
  endfunction

  " Clear the preview.
  function! l:pane.clear() dict abort
    let self.state.file = ''
    let self.state.line = 0
    let self._lines = [{'text': ''}]
  endfunction

  return l:pane
endfunction

"==============================================================================
" Cleanup
"==============================================================================

function! skyrg#ui#panes#preview#cleanup_syn() abort
  if s:syn_winid && win_id2win(s:syn_winid)
    silent! execute win_id2win(s:syn_winid) . 'close!'
  endif
  let s:syn_winid = 0
  let s:syn_file = ''
endfunction

"==============================================================================
" Prep / Render (private)
"==============================================================================

" Center the target line in the visible window.
function! s:prepare(all_lines, match_line, syn_spans, visible) abort
  let l:total = len(a:all_lines)
  let l:half = a:visible / 2
  let l:s_line = max([0, a:match_line - 1 - l:half])
  let l:e_line = l:s_line + a:visible - 1
  if l:e_line >= l:total
    let l:e_line = l:total - 1
    let l:s_line = max([0, l:e_line - a:visible + 1])
  endif
  return {'file_lines': a:all_lines, 'syn_spans': a:syn_spans,
    \ 'start': l:s_line, 'end': l:e_line}
endfunction

" Build popup line dicts with line numbers, optional syntax, and match highlight.
function! s:render(data, match_line) abort
  let l:lines = []
  for l:i in range(a:data.start, a:data.end)
    let l:ln = l:i + 1
    let l:prefix = printf('%s%4d  ', l:ln == a:match_line ? '>' : ' ', l:ln)
    let l:text = l:prefix . a:data.file_lines[l:i]
    let l:plen = len(l:prefix)

    " Dim line number prefix
    let l:props = [{'col': 1, 'length': l:plen, 'type': 'skyrg_dim'}]
    " Apply syntax spans if available
    if !empty(a:data.syn_spans) && l:i < len(a:data.syn_spans)
      for l:sp in a:data.syn_spans[l:i]
        call add(l:props, {
          \ 'col': l:sp.col + l:plen,
          \ 'length': l:sp.length,
          \ 'type': l:sp.type})
      endfor
    endif
    " Highlight target line
    if l:ln == a:match_line
      call add(l:props, {'col': 1, 'length': len(l:text), 'type': 'skyrg_match'})
    endif

    call add(l:lines, skyrg#ui#util#line(l:text, l:props))
  endfor
  return l:lines
endfunction

"==============================================================================
" Syntax analysis via hidden window
"==============================================================================

function! s:map_hl(name) abort
  return get(s:hl_map, a:name, '')
endfunction

function! s:get_syntax_spans(file, start_lnum, end_lnum) abort
  call s:ensure_syn_window(a:file)

  let l:result = []
  if !s:syn_winid || !win_id2win(s:syn_winid)
    for l:lnum in range(a:start_lnum, a:end_lnum)
      call add(l:result, [])
    endfor
    return l:result
  endif

  let l:save_win = win_getid()
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
      if !empty(l:prev_prop)
        call add(l:spans, {
          \ 'col': l:span_start,
          \ 'length': l:line_len - l:span_start + 1,
          \ 'type': l:prev_prop})
      endif
    endif

    call add(l:result, l:spans)
  endfor

  noautocmd call win_gotoid(l:save_win)
  return l:result
endfunction

function! s:ensure_syn_window(file) abort
  if s:syn_winid && win_id2win(s:syn_winid) && s:syn_file ==# a:file
    return
  endif

  let l:save_win = win_getid()

  if !s:syn_winid || !win_id2win(s:syn_winid)
    noautocmd silent! botright 1split
    let s:syn_winid = win_getid()
    setlocal noswapfile bufhidden=hide nobuflisted
    setlocal nonumber norelativenumber signcolumn=no
  else
    noautocmd call win_gotoid(s:syn_winid)
  endif

  noautocmd silent! execute 'edit ' . fnameescape(a:file)
  let s:syn_file = a:file

  if !exists('b:current_syntax') || empty(b:current_syntax)
    filetype detect
    syntax enable
  endif

  noautocmd call win_gotoid(l:save_win)
endfunction
