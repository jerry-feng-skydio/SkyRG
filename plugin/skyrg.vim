" skyrg.vim - Search wrapper for ripgrep + fzf
" Maintainer: Jerry Feng <jerry.feng@skydio.com>
" License: MIT

if exists('g:loaded_skyrg') && !get(g:, 'skyrg_reloading', 0)
  finish
endif
let g:loaded_skyrg = 1

" User configuration
if !exists('g:skyrg_verbose')
  let g:skyrg_verbose = 0
endif

" Initialize the filter system
call skyrg#filter#init()

" Commands
command! -nargs=0 YRefs call skyrg#panel#ycm_refs()
command! -nargs=0 SkyRGReload call skyrg#reload()
