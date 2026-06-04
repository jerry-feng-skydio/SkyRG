" autoload/skyrg/instabug.vim — Annotated screen dumps to log
"
" Captures the full Vim screen as text, window/buffer metadata, layout tree,
" and a user-provided annotation, then appends everything to the SkyRG log.
"
" Usage:
"   :SkyRGInstabug          " prompt for annotation, dump to log
"   call skyrg#instabug#dump()

function! skyrg#instabug#dump() abort
  " Prompt for annotation
  let l:note = input('[SkyRG Instabug] Describe what you see: ')
  redraw

  call skyrg#log#info('instabug', '=== INSTABUG DUMP ===')
  call skyrg#log#info('instabug', 'note: "%s"', l:note)

  " Screen dimensions
  let l:rows = &lines
  let l:cols = &columns
  call skyrg#log#info('instabug', 'screen: %dx%d', l:rows, l:cols)

  " Capture screen text
  call skyrg#log#info('instabug', '--- SCREEN ---')
  for l:r in range(1, l:rows)
    let l:line = ''
    for l:c in range(1, l:cols)
      let l:line .= screenstring(l:r, l:c)
    endfor
    call skyrg#log#info('instabug', '%s', l:line)
  endfor

  " Vim :messages — capture recent messages (errors, warnings, echom output).
  " Bounded to the last 50 lines to keep dump size reasonable.
  call skyrg#log#info('instabug', '--- MESSAGES ---')
  let l:msgs = split(execute('messages'), "\n")
  let l:msg_limit = 50
  if len(l:msgs) > l:msg_limit
    call skyrg#log#info('instabug', '... (%d lines truncated)', len(l:msgs) - l:msg_limit)
    let l:msgs = l:msgs[-l:msg_limit :]
  endif
  for l:msg in l:msgs
    call skyrg#log#info('instabug', '%s', l:msg)
  endfor

  " Window metadata
  call skyrg#log#info('instabug', '--- WINDOWS ---')
  let l:wins = []
  for l:w in getwininfo()
    let l:entry = {
      \ 'id': l:w.winid,
      \ 'bufname': bufname(l:w.bufnr),
      \ 'filetype': getbufvar(l:w.bufnr, '&filetype'),
      \ 'buftype': getbufvar(l:w.bufnr, '&buftype'),
      \ 'width': l:w.width,
      \ 'height': l:w.height,
      \ 'winrow': l:w.winrow,
      \ 'wincol': l:w.wincol,
      \ 'terminal': l:w.terminal,
      \ }
    if l:w.terminal
      let l:job = term_getjob(l:w.bufnr)
      let l:entry.job_status = l:job isnot v:null ? job_status(l:job) : 'none'
    endif
    call add(l:wins, l:entry)
  endfor
  call skyrg#log#data('instabug', 'windows', l:wins)

  " Layout tree
  call skyrg#log#info('instabug', '--- LAYOUT ---')
  call skyrg#log#data('instabug', 'layout', winlayout())

  call skyrg#log#info('instabug', '=== END INSTABUG ===')

  echo printf('[SkyRG] Instabug dump saved to %s', skyrg#log#file())
endfunction
