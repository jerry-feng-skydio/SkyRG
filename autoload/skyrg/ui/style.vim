" autoload/skyrg/ui/style.vim — Centralized highlight & prop type registry
"
" Single source of truth for all highlight groups and text property types.
" Adding a new style = one entry here. Init and cleanup are symmetric.
"
" Usage:
"   call skyrg#ui#style#init()     " register all prop types
"   call skyrg#ui#style#cleanup()  " remove all prop types
"   skyrg#ui#style#CURSOR          " prop type name constants

"==============================================================================
" Highlight group definitions
"==============================================================================
highlight SkyRGSel cterm=bold ctermfg=Yellow ctermbg=DarkBlue gui=bold guifg=#FFD700 guibg=#1C3A5F
highlight SkyRGLog ctermbg=Black ctermfg=Gray guibg=#0A0A0A guifg=#A0A0A0
highlight SkyRGLogStderr ctermbg=Black ctermfg=Red guibg=#0A0A0A guifg=#CC6666

"==============================================================================
" Prop type name constants — use these instead of string literals
"==============================================================================
let skyrg#ui#style#CURSOR = 'skyrg_cursor'
let skyrg#ui#style#SEL    = 'skyrg_sel'
let skyrg#ui#style#MATCH  = 'skyrg_match'
let skyrg#ui#style#DIM    = 'skyrg_dim'

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
function! skyrg#ui#style#init() abort
  call skyrg#ui#style#cleanup()
  " Cursor needs runtime check for best highlight
  let s:core_props['skyrg_cursor'] = hlexists('TermCursor') ? 'TermCursor' : 'Visual'
  for [l:name, l:hl] in items(s:core_props)
    call prop_type_add(l:name, {'highlight': l:hl})
  endfor
  for l:g in s:syn_groups
    call prop_type_add('skyrg_syn_' . l:g, {'highlight': l:g})
  endfor
endfunction

function! skyrg#ui#style#cleanup() abort
  for l:name in keys(s:core_props)
    silent! call prop_type_delete(l:name)
  endfor
  for l:g in s:syn_groups
    silent! call prop_type_delete('skyrg_syn_' . l:g)
  endfor
endfunction

" Return the list of syntax group names (used by preview.vim)
function! skyrg#ui#style#syn_groups() abort
  return s:syn_groups
endfunction

" Apply log-viewer styling to the current buffer.
function! skyrg#ui#style#apply_log() abort
  setlocal nonumber norelativenumber signcolumn=no
  setlocal winfixheight
  setlocal statusline=\ ⟳\ SkyRG\ Log\ %=%l/%L
  " Syntax-based styling (Vim doesn't support per-window backgrounds)
  syntax match SkyRGLogStdout /^\[stdout\].*/
  syntax match SkyRGLogStderrLine /^\[stderr\].*/
  syntax match SkyRGLogHeader /^===.*===$\|^Task ID:.*\|^Action:.*\|^Command:.*\|^CWD:.*\|^Started:.*\|^Context:.*/
  highlight link SkyRGLogStdout Comment
  highlight link SkyRGLogStderrLine SkyRGLogStderr
  highlight link SkyRGLogHeader Title
endfunction
