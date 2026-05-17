" autoload/skyrg/panel/style.vim — Centralized highlight & prop type registry
"
" Single source of truth for all highlight groups and text property types.
" Adding a new style = one entry here. Init and cleanup are symmetric.
"
" Usage:
"   call skyrg#panel#style#init()     " register all prop types
"   call skyrg#panel#style#cleanup()  " remove all prop types
"   skyrg#panel#style#CURSOR          " prop type name constants

"==============================================================================
" Highlight group definitions
"==============================================================================
highlight SkyRGSel cterm=bold ctermfg=Yellow ctermbg=DarkBlue gui=bold guifg=#FFD700 guibg=#1C3A5F

"==============================================================================
" Prop type name constants — use these instead of string literals
"==============================================================================
let skyrg#panel#style#CURSOR = 'skyrg_cursor'
let skyrg#panel#style#SEL    = 'skyrg_sel'
let skyrg#panel#style#MATCH  = 'skyrg_match'
let skyrg#panel#style#DIM    = 'skyrg_dim'

"==============================================================================
" Syntax groups used for preview highlighting
"==============================================================================
let s:syn_groups = ['Comment', 'Constant', 'String', 'Identifier',
  \ 'Function', 'Statement', 'PreProc', 'Type', 'Special', 'Underlined',
  \ 'Error', 'Todo', 'Number', 'Boolean', 'Keyword', 'Operator']

" Core prop types: name → highlight group
let s:core_props = {
  \ 'skyrg_cursor': '',
  \ 'skyrg_sel':    'SkyRGSel',
  \ 'skyrg_match':  'Search',
  \ 'skyrg_dim':    'Comment',
  \ }

"==============================================================================
" Init / cleanup
"==============================================================================
function! skyrg#panel#style#init() abort
  call skyrg#panel#style#cleanup()
  " Cursor needs runtime check for best highlight
  let s:core_props['skyrg_cursor'] = hlexists('TermCursor') ? 'TermCursor' : 'Visual'
  for [l:name, l:hl] in items(s:core_props)
    call prop_type_add(l:name, {'highlight': l:hl})
  endfor
  for l:g in s:syn_groups
    call prop_type_add('skyrg_syn_' . l:g, {'highlight': l:g})
  endfor
endfunction

function! skyrg#panel#style#cleanup() abort
  for l:name in keys(s:core_props)
    silent! call prop_type_delete(l:name)
  endfor
  for l:g in s:syn_groups
    silent! call prop_type_delete('skyrg_syn_' . l:g)
  endfor
endfunction

" Return the list of syntax group names (used by preview.vim)
function! skyrg#panel#style#syn_groups() abort
  return s:syn_groups
endfunction
