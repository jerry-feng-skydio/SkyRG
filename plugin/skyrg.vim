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
call skyrg#log#info('plugin', 'loaded level=%s file=%s',
  \ toupper(get(g:, 'skyrg_log_level', 'INFO')), skyrg#log#file())

" Commands
command! -nargs=* SkyRG              call skyrg#views#search#open(<args>)
command! -nargs=0 SkyRGHistory       call skyrg#views#history#open()
command! -nargs=0 SkyRGLog           execute 'split' skyrg#log#file()
command! -nargs=0 SkyRGLogClear      call skyrg#log#clear() | echo '[SkyRG] Log cleared'
command! -nargs=0 SkyRGDebugHistory  call skyrg#views#debug#history()
command! -nargs=0 SkyRGTasks         call skyrg#views#tasks#open()
command! -nargs=0 SkyRGActionLog     call skyrg#views#tasks#open_last_log()
command! -nargs=0 YRefs              call skyrg#panel#ycm_refs()
command! -nargs=0 SkyRGReload        call skyrg#reload()

" Context popup key mapping (user sets g:skyrg_context_key in .vimrc)
if exists('g:skyrg_context_key') && !empty(g:skyrg_context_key)
  execute 'nnoremap <silent>' g:skyrg_context_key ':call skyrg#views#context#open("n")<CR>'
  execute 'vnoremap <silent>' g:skyrg_context_key ':<C-u>call skyrg#views#context#open("v")<CR>'
endif
