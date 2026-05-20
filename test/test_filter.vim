" test/test_filter.vim — Tests for skyrg#filter (filter creation, composition, query building)

"==============================================================================
" Basic filter creation
"==============================================================================
call skyrg#filter#new('test_empty')
call Assert(has_key(g:SkyFilter.presets, 'test_empty'), 'new filter registered in presets')

"==============================================================================
" Include filetypes → glob flags
"==============================================================================
let s:f1 = skyrg#filter#new('test_inc_types')
      \ .include_filetypes(['cc', 'h', 'py'])
let s:flags = s:f1.get_globbing_flags()
call Assert(s:flags =~# "\\*\\.{.*cc.*}", 'glob flags contain cc')
call Assert(s:flags =~# "\\*\\.{.*h.*}",  'glob flags contain h')
call Assert(s:flags =~# "\\*\\.{.*py.*}", 'glob flags contain py')

"==============================================================================
" get_globbing_args — list form (no shell quotes)
"==============================================================================
let s:args = s:f1.get_globbing_args()
call Assert(type(s:args) == v:t_list, 'get_globbing_args returns a list')
call Assert(index(s:args, '-g') >= 0, 'args contain -g flag')
" Verify no single quotes in any argument
for s:a in s:args
  call Assert(stridx(s:a, "'") < 0, 'no shell quotes in arg: ' . s:a)
endfor

"==============================================================================
" Ignore filetypes
"==============================================================================
let s:f2 = skyrg#filter#new('test_ign_types')
      \ .ignore_filetypes(['vim', 'sh'])
let s:args2 = s:f2.get_globbing_args()
let s:has_ignore = 0
for s:i in range(len(s:args2) - 1)
  if s:args2[s:i] ==# '-g' && s:args2[s:i+1] =~# '^!.*vim'
    let s:has_ignore = 1
  endif
endfor
call Assert(s:has_ignore, 'glob args contain ignore for vim')

"==============================================================================
" Include dirs → search directories
"==============================================================================
let s:f3 = skyrg#filter#new('test_inc_dirs')
      \ .include_dirs(['src', 'lib'])
call AssertEqual('src lib', s:f3.get_search_directories(), 'search dirs string')
call Assert(index(s:f3.get_search_dirs_list(), 'src') >= 0, 'search dirs list contains src')
call Assert(index(s:f3.get_search_dirs_list(), 'lib') >= 0, 'search dirs list contains lib')

"==============================================================================
" Ignore dirs → glob args
"==============================================================================
let s:f4 = skyrg#filter#new('test_ign_dirs')
      \ .ignore_dirs(['build', '**/node_modules'])
let s:args4 = s:f4.get_globbing_args()
let s:has_build_ign = 0
let s:has_nm_ign = 0
for s:i in range(len(s:args4) - 1)
  if s:args4[s:i] ==# '-g' && s:args4[s:i+1] ==# '!build/**'
    let s:has_build_ign = 1
  endif
  if s:args4[s:i] ==# '-g' && s:args4[s:i+1] ==# '!**/node_modules/**'
    let s:has_nm_ign = 1
  endif
endfor
call Assert(s:has_build_ign, 'glob args contain build ignore')
call Assert(s:has_nm_ign, 'glob args contain node_modules ignore')

"==============================================================================
" apply_base — specificity rules
"==============================================================================
" When self has includes, base includes are skipped
let s:base = skyrg#filter#new('test_base')
      \ .include_filetypes(['cc', 'h'])
      \ .include_dirs(['base_dir'])
      \ .ignore_dirs(['build'])

let s:over = skyrg#filter#new('test_override')
      \ .include_filetypes(['py'])
call s:over.apply_base(s:base)
let s:over_args = s:over.get_globbing_args()
" Should have py but NOT cc/h (self includes override base includes)
let s:has_py = 0
let s:has_cc = 0
for s:i in range(len(s:over_args) - 1)
  if s:over_args[s:i] ==# '-g' && s:over_args[s:i+1] =~# 'py'
    let s:has_py = 1
  endif
  if s:over_args[s:i] ==# '-g' && s:over_args[s:i+1] =~# '\\bcc\\b'
    let s:has_cc = 1
  endif
endfor
call Assert(s:has_py, 'override keeps own include types')
" Base dirs should be applied (self has no dir includes)
call Assert(index(s:over.get_search_dirs_list(), 'base_dir') >= 0, 'base dirs applied when self has none')
" Base ignores always applied
let s:has_build = 0
for s:i in range(len(s:over_args) - 1)
  if s:over_args[s:i] ==# '-g' && s:over_args[s:i+1] ==# '!build/**'
    let s:has_build = 1
  endif
endfor
call Assert(s:has_build, 'base ignore dirs always applied')

"==============================================================================
" Chainable API
"==============================================================================
let s:f5 = skyrg#filter#new('test_chain')
      \ .include_filetypes(['cc'])
      \ .ignore_dirs(['build'])
      \ .include_dirs(['src'])
call Assert(s:f5.name ==# 'test_chain', 'chaining preserves filter identity')
let s:a5 = s:f5.get_globbing_args()
call Assert(!empty(s:a5), 'chained filter produces non-empty args')
