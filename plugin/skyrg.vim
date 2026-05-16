" skyrg.vim - Search wrapper for ripgrep + fzf
" Maintainer: Jerry Feng <jerry.feng@skydio.com>
" License: MIT

if exists('g:loaded_skyrg')
  finish
endif
let g:loaded_skyrg = 1

" User configuration
if !exists('g:skyrg_verbose')
  let g:skyrg_verbose = 0
endif

" Initialize the filter system
call skyrg#filter#init()

