" skyrg/complete.vim - Tab completion for SkyRG commands
"
" Provides context-aware completion for the :RG command:
"   - Flags (-f, -Nf, -d, -Nd, -p, --)
"   - Preset names after -p
"   - File extensions after -f / -Nf  (comma-separated aware)
"   - Directories after -d / -Nd      (comma-separated aware, relative to cwd)
"
" Usage in your command definition:
"   command! -nargs=* -bang -complete=customlist,skyrg#complete#rg RG
"         \ call skyrg#search(<f-args>)

" Flags that consume the next argument
let s:ARG_FLAGS = ['-f', '-Nf', '-d', '-Nd', '-p']
let s:ALL_FLAGS = ['-f', '-Nf', '-d', '-Nd', '-p', '--']

" Fallback extensions when no presets are registered yet
let s:FALLBACK_EXTS = [
      \ 'py', 'cc', 'cpp', 'h', 'hpp', 'java', 'kt', 'swift', 'mm', 'm',
      \ 'js', 'ts', 'vim', 'sh', 'proto', 'lcm', 'djinni',
      \ 'yaml', 'json', 'md', 'cmake', 'bazel',
      \ ]

"==============================================================================
" Entry point
"==============================================================================

function! skyrg#complete#rg(ArgLead, CmdLine, CursorPos) abort
  " If -- already appeared, everything after is query — no completion
  if s:past_double_dash(a:CmdLine, a:CursorPos)
    return []
  endif

  let l:parts = split(a:CmdLine[:a:CursorPos - 1], '\s\+', 1)
  let l:ctx = s:get_context(l:parts)

  if l:ctx ==# '-p'
    return s:complete_presets(a:ArgLead)
  elseif l:ctx ==# '-f' || l:ctx ==# '-Nf'
    return s:complete_filetypes(a:ArgLead)
  elseif l:ctx ==# '-d' || l:ctx ==# '-Nd'
    return s:complete_dirs(a:ArgLead)
  endif

  " Default: offer flags (only if we haven't drifted into query territory)
  return s:complete_flags(a:ArgLead)
endfunction

"==============================================================================
" Context detection
"==============================================================================

" Returns the flag whose argument we're currently completing, or ''.
function! s:get_context(parts) abort
  if len(a:parts) < 2
    return ''
  endif
  let l:prev = a:parts[-2]
  return index(s:ARG_FLAGS, l:prev) >= 0 ? l:prev : ''
endfunction

" Check whether -- has already been typed (everything after is raw query).
function! s:past_double_dash(cmdline, cursorpos) abort
  let l:before_cursor = a:cmdline[:a:cursorpos - 1]
  " Match standalone -- (not part of another word)
  return l:before_cursor =~# '\(^\|\s\)--\s'
endfunction

"==============================================================================
" Completers
"==============================================================================

function! s:complete_flags(lead) abort
  return filter(copy(s:ALL_FLAGS), {_, v -> s:prefix_match(v, a:lead)})
endfunction

function! s:complete_presets(lead) abort
  if !exists('g:SkyFilter') || !has_key(g:SkyFilter, 'presets')
    return []
  endif
  let l:names = sort(keys(g:SkyFilter.presets))
  return filter(l:names, {_, v -> s:prefix_match(v, a:lead)})
endfunction

function! s:complete_filetypes(lead) abort
  let [l:prefix, l:segment] = s:split_csv(a:lead)
  let l:exts = s:collect_known_extensions()
  let l:matches = filter(l:exts, {_, v -> s:prefix_match(v, l:segment)})
  return map(l:matches, {_, v -> l:prefix . v})
endfunction

function! s:complete_dirs(lead) abort
  let [l:prefix, l:segment] = s:split_csv(a:lead)

  " Glob for directories matching the segment
  let l:pattern = l:segment ==# '' ? '*' : l:segment . '*'
  let l:candidates = glob(l:pattern, 0, 1)
  let l:dirs = filter(l:candidates, {_, v -> isdirectory(v)})

  " Append / so the user can keep drilling down
  let l:dirs = map(l:dirs, {_, v -> l:prefix . v . '/'})
  return l:dirs
endfunction

"==============================================================================
" Helpers
"==============================================================================

" Case-insensitive prefix match.
function! s:prefix_match(str, prefix) abort
  if a:prefix ==# ''
    return 1
  endif
  return a:str[:len(a:prefix) - 1] ==? a:prefix
endfunction

" Split 'foo,bar,baz' → ['foo,bar,', 'baz'] for comma-separated completion.
" If no comma, returns ['', lead].
function! s:split_csv(lead) abort
  let l:idx = strridx(a:lead, ',')
  if l:idx < 0
    return ['', a:lead]
  endif
  return [a:lead[:l:idx], a:lead[l:idx + 1:]]
endfunction

" Gather unique file extensions from all registered filter presets.
" Falls back to a built-in list if no presets exist.
function! s:collect_known_extensions() abort
  let l:exts = {}

  if exists('g:SkyFilter') && has_key(g:SkyFilter, 'presets')
    for l:preset in values(g:SkyFilter.presets)
      if has_key(l:preset, 'type')
        for l:ext in keys(l:preset.type)
          let l:exts[l:ext] = 1
        endfor
      endif
    endfor
  endif

  " If no presets have been set up yet, offer sensible defaults
  if empty(l:exts)
    for l:ext in s:FALLBACK_EXTS
      let l:exts[l:ext] = 1
    endfor
  endif

  return sort(keys(l:exts))
endfunction
