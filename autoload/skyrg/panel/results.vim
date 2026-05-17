" autoload/skyrg/panel/results.vim — Results list rendering and navigation
"
" Follows prep/render separation:
"   s:prepare()  — computes visible window into matches list
"   s:render()   — builds popup line dicts from prepared data
"   redraw()     — orchestrates prepare → render → popup_settext

"==============================================================================
" Public API
"==============================================================================
function! skyrg#panel#results#redraw() abort
  let l:s = skyrg#panel#state()
  let l:r = l:s.results
  if empty(l:r.matches)
    let l:msg = !empty(get(l:s.search, 'rg_error', ''))
      \ ? '  Error: '.l:s.search.rg_error : '  No results'
    call popup_settext(l:s.popups.results, [skyrg#panel#util#line(l:msg)])
    call popup_setoptions(l:s.popups.results, {'title': ' Results '})
    return
  endif
  let l:data = s:prepare(l:r)
  let l:lines = s:render(l:data, l:r.idx)
  call popup_settext(l:s.popups.results, l:lines)
  call popup_setoptions(l:s.popups.results, {
    \ 'title': printf(' Results (%d/%d) ', l:r.idx+1, len(l:r.matches))})
endfunction

function! skyrg#panel#results#move(dir) abort
  let l:r = skyrg#panel#state().results
  if empty(l:r.matches) | return | endif
  let l:r.idx = max([0, min([len(l:r.matches)-1, l:r.idx + a:dir])])
  call skyrg#panel#results#redraw() | call skyrg#panel#preview#update()
endfunction

function! skyrg#panel#results#jump() abort
  let l:r = skyrg#panel#state().results
  if empty(l:r.matches) | return | endif
  let l:m = l:r.matches[l:r.idx]
  call skyrg#panel#close()
  execute 'edit +'.l:m.line.' '.fnameescape(l:m.file)
  call cursor(l:m.line, l:m.col)
  normal! zz
endfunction

"==============================================================================
" Prep / Render (private)
"==============================================================================

" Compute the visible slice of matches (scroll management).
" Returns: {'first': int, 'last': int}
function! s:prepare(r) abort
  let l:L = skyrg#panel#get_layout()
  let l:vis = l:L.rh - 2
  let l:first = a:r.scroll
  if a:r.idx < l:first
    let l:first = a:r.idx
  elseif a:r.idx >= l:first + l:vis
    let l:first = a:r.idx - l:vis + 1
  endif
  let a:r.scroll = l:first
  return {'first': l:first, 'last': min([l:first + l:vis - 1, len(a:r.matches)-1])}
endfunction

" Build popup line dicts from the visible slice.
function! s:render(data, sel_idx) abort
  let l:r = skyrg#panel#state().results
  let l:lines = []
  for l:i in range(a:data.first, a:data.last)
    let l:m = l:r.matches[l:i]
    let l:mk = l:i == a:sel_idx ? '> ' : '  '
    let l:text = printf('%s%s:%d: %s', l:mk, skyrg#panel#util#short(l:m.file), l:m.line, l:m.text)
    call add(l:lines, l:i == a:sel_idx
      \ ? skyrg#panel#util#hl_line(l:text, 'skyrg_sel')
      \ : skyrg#panel#util#line(l:text))
  endfor
  return l:lines
endfunction
