" autoload/skyrg/views/history.vim — History browser view
"
" Full-screen popup listing past search queries. Uses the generic list pane
" for rendering and navigation, with a preview pane showing query details.
"
" Usage:
"   call skyrg#views#history#open()
"   " (with filter)
"   call skyrg#views#history#open({'filter': 'TODO'})

let s:handle = {}
let s:entries = []
let s:filter = ''

"==============================================================================
" Open
"==============================================================================

function! skyrg#views#history#open(...) abort
  let l:params = a:0 > 0 && type(a:1) == v:t_dict ? a:1 : {}
  let s:filter = get(l:params, 'filter', '')

  " Load entries
  let s:entries = empty(s:filter)
    \ ? skyrg#backend#history#load_all()
    \ : skyrg#backend#history#search(s:filter)

  if empty(s:entries)
    echo '[SkyRG] No history entries'
    return
  endif

  " Build as a browse-mode panel with search results
  let l:matches = []
  for l:e in s:entries
    " Convert history entry to match format for browse mode
    let l:text = printf('[%s] %s', s:format_time(get(l:e, 'timestamp', 0)), l:e.query)
    if !empty(get(l:e, 'types', ''))
      let l:text .= printf(' (types: %s)', l:e.types)
    endif
    if !empty(get(l:e, 'dirs', ''))
      let l:text .= printf(' (dirs: %s)', l:e.dirs)
    endif
    if !empty(get(l:e, 'preset', ''))
      let l:text .= printf(' (preset: %s)', l:e.preset)
    endif
    " Use a fake match format that browse mode can display
    call add(l:matches, {
      \ 'file': get(l:e, 'query', ''),
      \ 'line': get(l:e, 'result_count', 0),
      \ 'col': 0,
      \ 'text': l:text,
      \ '_history_entry': l:e,
      \ })
  endfor

  call skyrg#panel#browse(l:matches, printf('History (%d)', len(l:matches)))
endfunction

"==============================================================================
" Time formatting
"==============================================================================

function! s:format_time(ts) abort
  if a:ts == 0 | return '?' | endif
  let l:now = localtime()
  let l:diff = l:now - a:ts
  if l:diff < 60
    return 'just now'
  elseif l:diff < 3600
    return printf('%dm ago', l:diff / 60)
  elseif l:diff < 86400
    return printf('%dh ago', l:diff / 3600)
  elseif l:diff < 604800
    return printf('%dd ago', l:diff / 86400)
  else
    return strftime('%Y-%m-%d', a:ts)
  endif
endfunction
