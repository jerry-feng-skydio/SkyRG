" autoload/skyrg/panel/util.vim — Shared utilities

" Delete backward to the nearest comma, slash, or space
function! skyrg#panel#util#del_word(f) abort
  if a:f.pos == 0 | return | endif
  let l:b = a:f.value[:a:f.pos-1]
  let l:a = a:f.value[a:f.pos:]
  let l:b = substitute(l:b, '[^,/ ]*[,/ ]*$', '', '')
  let a:f.value = l:b . l:a | let a:f.pos = len(l:b)
endfunction

" Shorten a path relative to cwd
function! skyrg#panel#util#short(path) abort
  let l:cwd = getcwd() . '/'
  return a:path[:len(l:cwd)-1] ==# l:cwd ? a:path[len(l:cwd):] : a:path
endfunction
