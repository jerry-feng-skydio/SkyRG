" autoload/skyrg/panel/preview.vim — File preview rendering

let s:PREVIEW_CTX = 10

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
  let l:lines = []
  for l:i in range(l:s_line, l:e_line)
    let l:ln = l:i + 1
    let l:text = printf('%s%4d  %s', l:ln == l:m.line ? '>' : ' ', l:ln, l:all[l:i])
    if l:ln == l:m.line
      call add(l:lines, {'text': l:text, 'props': [
        \ {'col': 1, 'length': len(l:text), 'type': 'skyrg_match'}]})
    else
      call add(l:lines, {'text': l:text})
    endif
  endfor
  call popup_settext(l:s.preview_id, l:lines)
endfunction
