" autoload/skyrg/panel/results.vim — Results list rendering and navigation

function! skyrg#panel#results#redraw() abort
  let l:s = skyrg#panel#state()
  if empty(l:s.matches)
    let l:msg = !empty(get(l:s, 'rg_error', '')) ? '  Error: '.l:s.rg_error : '  No results'
    call popup_settext(l:s.results_id, [{'text': l:msg}])
    call popup_setoptions(l:s.results_id, {'title': ' Results '})
    return
  endif
  let l:L = skyrg#panel#get_layout()
  let l:vis = l:L.rh - 2
  let l:first = l:s.res_scroll
  if l:s.result_idx < l:first
    let l:first = l:s.result_idx
  elseif l:s.result_idx >= l:first + l:vis
    let l:first = l:s.result_idx - l:vis + 1
  endif
  let l:s.res_scroll = l:first
  let l:lines = []
  for l:i in range(l:first, min([l:first + l:vis - 1, len(l:s.matches)-1]))
    let l:m = l:s.matches[l:i]
    let l:mk = l:i == l:s.result_idx ? '> ' : '  '
    let l:text = printf('%s%s:%d: %s', l:mk, skyrg#panel#util#short(l:m.file), l:m.line, l:m.text)
    if l:i == l:s.result_idx
      call add(l:lines, {'text': l:text, 'props': [
        \ {'col': 1, 'length': len(l:text), 'type': 'skyrg_sel'}]})
    else
      call add(l:lines, {'text': l:text})
    endif
  endfor
  call popup_settext(l:s.results_id, l:lines)
  call popup_setoptions(l:s.results_id, {
    \ 'title': printf(' Results (%d/%d) ', l:s.result_idx+1, len(l:s.matches))})
endfunction

function! skyrg#panel#results#move(dir) abort
  let l:s = skyrg#panel#state()
  if empty(l:s.matches) | return | endif
  let l:s.result_idx = max([0, min([len(l:s.matches)-1, l:s.result_idx + a:dir])])
  call skyrg#panel#results#redraw() | call skyrg#panel#preview#update()
endfunction

function! skyrg#panel#results#jump() abort
  let l:s = skyrg#panel#state()
  if empty(l:s.matches) | return | endif
  let l:m = l:s.matches[l:s.result_idx]
  call skyrg#panel#close()
  execute 'edit +'.l:m.line.' '.fnameescape(l:m.file)
  call cursor(l:m.line, l:m.col)
  normal! zz
endfunction
