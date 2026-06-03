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
let s:plugin_dir = expand('<sfile>:p:h:h')
let s:commit = 'unknown'
if isdirectory(s:plugin_dir . '/.git') || filereadable(s:plugin_dir . '/.git')
  let s:commit = trim(system('git -C ' . shellescape(s:plugin_dir) . ' rev-parse --short HEAD'))
  if v:shell_error | let s:commit = 'unknown' | endif
endif
call skyrg#log#info('plugin', 'loaded commit=%s level=%s file=%s',
  \ s:commit, toupper(get(g:, 'skyrg_log_level', 'INFO')), skyrg#log#file())

" Commands
command! -nargs=* SkyRG              call skyrg#views#search#open(<args>)
command! -nargs=0 SkyRGHistory       call skyrg#views#history#open()
command! -nargs=0 SkyRGLog           execute 'split' skyrg#log#file()
command! -nargs=0 SkyRGLogClear      call skyrg#log#clear() | echo '[SkyRG] Log cleared'
command! -nargs=0 SkyRGDebugHistory  call skyrg#views#debug#history()
command! -nargs=0 SkyRGTasks         call skyrg#views#tasks#open()
command! -nargs=0 SkyRGFollowup      call skyrg#backend#action#show_latest_followup()
command! -nargs=0 SkyRGActionLog     call skyrg#views#tasks#open_last_log()
command! -nargs=0 YRefs              call skyrg#panel#ycm_refs()
command! -nargs=0 SkyRGReload        call skyrg#reload()
command! -nargs=0 RevupTopics        call skyrg#revup#show()
command! -nargs=0 SkyRGDevice         call skyrg#views#device#refresh({})

" Context popup key mapping (user sets g:skyrg_context_key in .vimrc)
if exists('g:skyrg_context_key') && !empty(g:skyrg_context_key)
  execute 'nnoremap <silent>' g:skyrg_context_key ':call skyrg#views#context#open("n")<CR>'
  execute 'vnoremap <silent>' g:skyrg_context_key ':<C-u>call skyrg#views#context#open("v")<CR>'
endif

