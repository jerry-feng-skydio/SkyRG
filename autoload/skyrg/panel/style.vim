" autoload/skyrg/panel/style.vim — COMPAT SHIM
" Delegates to skyrg#ui#style#*. Use skyrg#ui#style#* directly in new code.

let skyrg#panel#style#CURSOR = 'skyrg_cursor'
let skyrg#panel#style#SEL    = 'skyrg_sel'
let skyrg#panel#style#MATCH  = 'skyrg_match'
let skyrg#panel#style#DIM    = 'skyrg_dim'

function! skyrg#panel#style#init() abort
  call skyrg#ui#style#init()
endfunction

function! skyrg#panel#style#cleanup() abort
  call skyrg#ui#style#cleanup()
endfunction

function! skyrg#panel#style#syn_groups() abort
  return skyrg#ui#style#syn_groups()
endfunction
