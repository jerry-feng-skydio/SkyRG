" skyrg.vim - Main search function
"
" Parses command-line flags, applies a base filter preset, builds an rg
" command, and launches an fzf interactive grep window with live reload.
"
" Requires: ripgrep, fzf.vim

let s:RG_BASE = 'rg --column --line-number --no-heading --color=always --smart-case'
let s:plugin_root = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')

"==============================================================================
" Public API
"==============================================================================

" Main entry point. Designed to be called via a user-defined command, e.g.:
"   command! -nargs=* -bang RG call skyrg#search(<f-args>)
"
" See :help skyrg-function for full flag documentation.
function! skyrg#search(...) abort
  let [l:filter, l:preset_name, l:query] = s:parse_args(a:000)

  " Resolve and apply base preset
  let l:base = s:resolve_base(l:preset_name)
  call l:filter.apply_base(l:base)

  " Build rg commands
  let l:flags = l:filter.get_globbing_flags()
  let l:dirs  = l:filter.get_search_directories()
  let l:fmt   = s:RG_BASE . ' %s -- %s %s || true'

  let l:initial = printf(l:fmt, l:flags, shellescape(l:query), l:dirs)
  let l:reload  = printf(l:fmt, l:flags, '{q}', l:dirs)

  call skyrg#log#debug('[SkyRG] initial: %s', l:initial)
  call skyrg#log#debug('[SkyRG] reload:  %s', l:reload)

  " Launch fzf with live-reload
  let l:spec = {
    \ 'options': [
    \   '--phony',
    \   '--query', l:query,
    \   '--bind', 'change:reload:' . l:reload,
    \ ]}
  call fzf#vim#grep(l:initial, 1, fzf#vim#with_preview(l:spec), 0)
endfunction

"==============================================================================
" Argument parsing
"==============================================================================

" Parse the variadic args into [filter, preset_name, query_string].
function! s:parse_args(args) abort
  let l:filter   = skyrg#filter#new('ACTIVE_QUERY')
  let l:preset   = ''
  let l:query    = ''
  let l:in_query = 0
  let l:i        = 0

  while l:i < len(a:args)
    let l:arg = a:args[l:i]

    if !l:in_query
      " -- : stop parsing flags, rest is query
      if l:arg ==# '--'
        let l:in_query = 1
        let l:i += 1
        continue

      " -f / -Nf / -d / -Nd : list flags (consume next arg)
      elseif s:is_list_flag(l:arg)
        if l:i + 1 >= len(a:args)
          call skyrg#log#error('[SkyRG] Missing argument for %s', l:arg)
          let l:i += 1
          continue
        endif
        let l:i += 1
        call s:apply_list_flag(l:filter, l:arg, split(a:args[l:i], ','))

      " -p : preset name (consume next arg)
      elseif l:arg ==# '-p'
        if l:i + 1 >= len(a:args)
          call skyrg#log#error('[SkyRG] Missing argument for -p')
          let l:i += 1
          continue
        endif
        let l:i += 1
        let l:preset = a:args[l:i]
        call skyrg#log#debug('[SkyRG] Using preset: %s', l:preset)

      " Not a flag — start of query
      else
        let l:in_query = 1
      endif
    endif

    if l:in_query
      let l:query = l:query ==# '' ? l:arg : l:query . ' ' . l:arg
    endif

    let l:i += 1
  endwhile

  return [l:filter, l:preset, l:query]
endfunction

function! s:is_list_flag(arg) abort
  return a:arg ==# '-f' || a:arg ==# '-Nf' || a:arg ==# '-d' || a:arg ==# '-Nd'
endfunction

function! s:apply_list_flag(filter, flag, values) abort
  if a:flag ==# '-f'
    call a:filter.include_filetypes(a:values)
  elseif a:flag ==# '-Nf'
    call a:filter.ignore_filetypes(a:values)
  elseif a:flag ==# '-d'
    call a:filter.include_dirs(a:values)
  elseif a:flag ==# '-Nd'
    call a:filter.ignore_dirs(a:values)
  endif
endfunction

"==============================================================================
" Preset resolution
"==============================================================================

" Look up the named preset, falling back to g:SkyFilter.default.
function! s:resolve_base(name) abort
  if a:name !=# '' && has_key(g:SkyFilter.presets, a:name)
    return g:SkyFilter.presets[a:name]
  endif

  " Ensure the default preset exists (create empty one if needed)
  if !has_key(g:SkyFilter.presets, g:SkyFilter.default)
    call skyrg#filter#new(g:SkyFilter.default)
  endif

  return g:SkyFilter.presets[g:SkyFilter.default]
endfunction

"==============================================================================
" Hot-reload: re-source all autoload files and plugin entry point
"==============================================================================
function! skyrg#reload() abort
  " Defer actual reload to avoid "function in use" error when called
  " from within action#dispatch (which is on the call stack)
  call timer_start(0, function('s:do_reload'))
endfunction

function! s:do_reload(timer) abort
  " Snapshot state that will be lost when s: vars reinitialize
  let l:had_tasks = !empty(skyrg#backend#tasks#running())

  " Stop USB watcher before re-source to prevent duplicates
  " (global.vim calls watch_usb() which starts a new one)
  call skyrg#backend#device#unwatch_usb()

  let l:root = s:plugin_root
  " Re-source all autoload files (order doesn't matter for autoload)
  " Skip skyrg.vim itself to avoid redefining s:do_reload while it's running
  for l:f in glob(l:root . '/autoload/skyrg/**/*.vim', 0, 1)
    if l:f !=# l:root . '/autoload/skyrg.vim'
      execute 'source' fnameescape(l:f)
    endif
  endfor
  " Re-source plugin entry point (bypass load guard)
  let g:skyrg_reloading = 1
  execute 'source' fnameescape(l:root . '/plugin/skyrg.vim')
  unlet g:skyrg_reloading
  " Re-source global.vim so page config and user overrides take effect
  let l:global = expand('~/.dotfiles/skyrg/global.vim')
  if filereadable(l:global)
    execute 'source' fnameescape(l:global)
  endif
  " Reset context action registry so builtins re-register cleanly
  call skyrg#backend#context#reset()
  " Reset keymap cache in case user changed g:skyrg_keymap
  call skyrg#panel#keymap#reset()

  echom '[SkyRG] Reloaded (device cache + action history cleared)'
  if l:had_tasks
    echohl WarningMsg
    echom '[SkyRG] Warning: in-flight tasks lost tracking — jobs still run but completion callbacks may not fire'
    echohl None
  endif
endfunction
