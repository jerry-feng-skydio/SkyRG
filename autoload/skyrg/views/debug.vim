" autoload/skyrg/views/debug.vim — Debug views for SkyRG internals
"
" Usage:
"   call skyrg#views#debug#history()    " raw history popup
"
" Keys inside the popup:
"   j/k or Down/Up  — scroll
"   q / Esc         — close

let s:popup = 0

"==============================================================================
" History debug view
"==============================================================================

function! skyrg#views#debug#history() abort
  let l:t = skyrg#log#timer()
  let l:root = skyrg#backend#history#project_root()
  let l:entries = skyrg#backend#history#load_all()
  let l:file = skyrg#backend#history#file_path()

  let l:lines = []
  call add(l:lines, {'text': ' Project: ' . l:root, 'props': []})
  call add(l:lines, {'text': ' File:    ' . l:file, 'props': []})
  call add(l:lines, {'text': ' Entries: ' . len(l:entries), 'props': []})
  call add(l:lines, {'text': repeat('─', 60), 'props': []})

  if empty(l:entries)
    call add(l:lines, {'text': '  (no history entries)', 'props': []})
  else
    let l:idx = 0
    for l:e in l:entries
      let l:idx += 1
      " Header line: index + query + timestamp
      let l:ts = s:format_ts(get(l:e, 'timestamp', 0))
      let l:header = printf(' #%-4d  %s  "%s"', l:idx, l:ts, get(l:e, 'query', ''))
      call add(l:lines, {'text': l:header, 'props': []})

      " Detail lines: all fields
      for l:key in sort(keys(l:e))
        if l:key ==# 'query' || l:key ==# 'timestamp'
          continue
        endif
        let l:val = l:e[l:key]
        let l:display = type(l:val) == v:t_dict || type(l:val) == v:t_list
          \ ? json_encode(l:val) : string(l:val)
        call add(l:lines, {'text': printf('         %-14s %s', l:key . ':', l:display), 'props': []})
      endfor

      " Separator
      call add(l:lines, {'text': '', 'props': []})
    endfor
  endif

  " Create popup
  let l:width = min([&columns - 4, 90])
  let l:height = min([&lines - 4, len(l:lines) + 2])

  if s:popup && popup_getpos(s:popup) != {}
    call popup_close(s:popup)
  endif

  let s:popup = popup_create(l:lines, {
    \ 'title': ' Debug: History (' . len(l:entries) . ' entries) ',
    \ 'border': [1,1,1,1],
    \ 'borderchars': ['─','│','─','│','┌','┐','┘','└'],
    \ 'padding': [0,1,0,1],
    \ 'maxwidth': l:width,
    \ 'minwidth': l:width,
    \ 'maxheight': l:height,
    \ 'minheight': l:height,
    \ 'scrollbar': 1,
    \ 'mapping': 0,
    \ 'filter': function('s:on_key'),
    \ 'zindex': 300,
    \ })

  call skyrg#log#elapsed(l:t, 'debug', 'history popup %d entries', len(l:entries))
endfunction

"==============================================================================
" Key handler
"==============================================================================

function! s:on_key(winid, key) abort
  if a:key ==# 'q' || a:key ==# "\<Esc>"
    call popup_close(a:winid)
    return 1
  endif
  if a:key ==# 'j' || a:key ==# "\<Down>"
    call win_execute(a:winid, 'normal! j')
    return 1
  endif
  if a:key ==# 'k' || a:key ==# "\<Up>"
    call win_execute(a:winid, 'normal! k')
    return 1
  endif
  if a:key ==# "\<C-d>"
    call win_execute(a:winid, 'normal! 10j')
    return 1
  endif
  if a:key ==# "\<C-u>"
    call win_execute(a:winid, 'normal! 10k')
    return 1
  endif
  if a:key ==# 'g'
    call win_execute(a:winid, 'normal! gg')
    return 1
  endif
  if a:key ==# 'G'
    call win_execute(a:winid, 'normal! G')
    return 1
  endif
  return 1
endfunction

"==============================================================================
" Helpers
"==============================================================================

function! s:format_ts(ts) abort
  if a:ts == 0
    return '(no timestamp)     '
  endif
  return strftime('%Y-%m-%d %H:%M:%S', a:ts)
endfunction
