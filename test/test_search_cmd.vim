" test/test_search_cmd.vim — Tests for rg command building from form state
"
" These tests verify that the search module builds correct rg commands
" from the form fields, without actually running rg.

"==============================================================================
" Helper: build an rg command list from form-like inputs
"==============================================================================
" Simulates the command-building logic from search.vim without job_start.
function! s:build_cmd(query, types, dirs, preset, gitignore) abort
  let l:cmd = ['rg', '--column', '--line-number', '--no-heading',
    \ '--color=never', '--smart-case', '--max-count=500']
  if a:gitignore !=# 'on'
    call add(l:cmd, '--no-ignore')
  endif
  for l:t in split(a:types, ',')
    let l:t = trim(l:t)
    if empty(l:t) | continue | endif
    if l:t[0] ==# '.'
      call extend(l:cmd, ['-g', '*' . l:t])
    else
      call extend(l:cmd, ['-t', l:t])
    endif
  endfor
  if !empty(a:preset)
    let l:filter = skyrg#panel#preset#get_sky_filter(a:preset)
    if !empty(l:filter)
      call extend(l:cmd, l:filter.get_globbing_args())
    endif
  endif
  call extend(l:cmd, ['--', a:query])
  let l:has_dir = 0
  for l:d in split(a:dirs, ',')
    let l:d = trim(l:d)
    if !empty(l:d) | call add(l:cmd, l:d) | let l:has_dir = 1 | endif
  endfor
  if !l:has_dir && !empty(a:preset)
    let l:filter = skyrg#panel#preset#get_sky_filter(a:preset)
    if !empty(l:filter)
      let l:sdirs = l:filter.get_search_dirs_list()
      if !empty(l:sdirs)
        call extend(l:cmd, l:sdirs)
        let l:has_dir = 1
      endif
    endif
  endif
  if !l:has_dir | call add(l:cmd, '.') | endif
  return l:cmd
endfunction

"==============================================================================
" Test: basic query with no filters
"==============================================================================
let s:cmd1 = s:build_cmd('hello', '', '', '', 'on')
call Assert(index(s:cmd1, '--') >= 0, 'cmd contains -- separator')
call Assert(index(s:cmd1, 'hello') >= 0, 'cmd contains query')
call Assert(index(s:cmd1, '.') >= 0, 'cmd defaults to . search dir')
call Assert(index(s:cmd1, '--no-ignore') < 0, 'gitignore on: no --no-ignore')

"==============================================================================
" Test: gitignore off
"==============================================================================
let s:cmd2 = s:build_cmd('hello', '', '', '', 'off')
call Assert(index(s:cmd2, '--no-ignore') >= 0, 'gitignore off: has --no-ignore')

"==============================================================================
" Test: rg type names
"==============================================================================
let s:cmd3 = s:build_cmd('hello', 'py,cpp', '', '', 'on')
let s:t_idx = index(s:cmd3, '-t')
call Assert(s:t_idx >= 0, 'cmd has -t flag for type names')
call Assert(index(s:cmd3, 'py') >= 0, 'cmd has py type')
call Assert(index(s:cmd3, 'cpp') >= 0, 'cmd has cpp type')

"==============================================================================
" Test: raw extension with .ext syntax
"==============================================================================
let s:cmd4 = s:build_cmd('hello', '.proto,.lcm', '', '', 'on')
call Assert(index(s:cmd4, '-t') < 0, 'no -t flag for raw extensions')
let s:has_proto_glob = 0
let s:has_lcm_glob = 0
for s:i in range(len(s:cmd4) - 1)
  if s:cmd4[s:i] ==# '-g' && s:cmd4[s:i+1] ==# '*.proto'
    let s:has_proto_glob = 1
  endif
  if s:cmd4[s:i] ==# '-g' && s:cmd4[s:i+1] ==# '*.lcm'
    let s:has_lcm_glob = 1
  endif
endfor
call Assert(s:has_proto_glob, '.proto becomes -g *.proto')
call Assert(s:has_lcm_glob, '.lcm becomes -g *.lcm')

"==============================================================================
" Test: mixed type names and raw extensions
"==============================================================================
let s:cmd5 = s:build_cmd('hello', 'py,.proto', '', '', 'on')
call Assert(index(s:cmd5, 'py') >= 0, 'mixed: has py type')
let s:has_proto5 = 0
for s:i in range(len(s:cmd5) - 1)
  if s:cmd5[s:i] ==# '-g' && s:cmd5[s:i+1] ==# '*.proto'
    let s:has_proto5 = 1
  endif
endfor
call Assert(s:has_proto5, 'mixed: .proto becomes glob')

"==============================================================================
" Test: explicit dirs
"==============================================================================
let s:cmd6 = s:build_cmd('hello', '', 'src/,lib/', '', 'on')
call Assert(index(s:cmd6, 'src/') >= 0, 'cmd has src/ dir')
call Assert(index(s:cmd6, 'lib/') >= 0, 'cmd has lib/ dir')
call Assert(index(s:cmd6, '.') < 0, 'explicit dirs: no . fallback')

"==============================================================================
" Test: preset with SkyFilter
"==============================================================================
call skyrg#filter#new('test_preset_cmd')
      \ .include_filetypes(['cc', 'h'])
      \ .include_dirs(['mydir'])
      \ .ignore_dirs(['build'])
let s:cmd7 = s:build_cmd('hello', '', '', 'test_preset_cmd', 'on')
" Should have glob args from filter, no shell quotes
for s:a in s:cmd7
  call Assert(stridx(s:a, "'") < 0, 'preset cmd: no shell quotes in arg: ' . s:a)
endfor
" Should have the preset's search dir
call Assert(index(s:cmd7, 'mydir') >= 0, 'preset cmd: search dir from filter')
call Assert(index(s:cmd7, '.') < 0, 'preset cmd: no . fallback with preset dirs')
" Should have build ignore glob
let s:has_build7 = 0
for s:i in range(len(s:cmd7) - 1)
  if s:cmd7[s:i] ==# '-g' && s:cmd7[s:i+1] ==# '!build/**'
    let s:has_build7 = 1
  endif
endfor
call Assert(s:has_build7, 'preset cmd: has build ignore glob')

"==============================================================================
" Test: explicit dirs override preset dirs
"==============================================================================
let s:cmd8 = s:build_cmd('hello', '', 'other/', 'test_preset_cmd', 'on')
call Assert(index(s:cmd8, 'other/') >= 0, 'explicit dir overrides preset dir')
call Assert(index(s:cmd8, 'mydir') < 0, 'preset dir not used when explicit dir given')
