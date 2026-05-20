" autoload/skyrg/panel/keymap.vim — Configurable key bindings
"
" Provides a default keymap and merges user overrides from g:skyrg_keymap.
" Each action maps to a list of key sequences (Vim key notation strings).
"
" Usage (in .vimrc):
"   let g:skyrg_keymap = {
"     \ 'query_to_tree':   ["\<C-Left>"],
"     \ 'query_to_results': ["\<C-Down>"],
"     \ ...
"   \ }
"
" Actions are grouped by pane context:
"   Global:    close
"   Query:     query_to_tree, query_to_results, query_field_up, query_field_down,
"              query_search, query_cursor_left, query_cursor_right
"   Tree:      tree_to_query, tree_up, tree_down, tree_page_up, tree_page_down,
"              tree_expand, tree_collapse, tree_select
"   Results:   results_to_query, results_up, results_down, results_page_up,
"              results_page_down, results_open

let s:defaults = {
  \ 'close':              ["\<Esc>"],
  \
  \ 'query_to_tree':      ["\<C-Left>"],
  \ 'query_to_results':   ["\<C-Down>"],
  \ 'query_field_up':     ["\<Up>"],
  \ 'query_field_down':   ["\<Down>"],
  \ 'query_search':       ["\<CR>"],
  \ 'query_cursor_left':  ["\<Left>"],
  \ 'query_cursor_right': ["\<Right>"],
  \ 'query_home':         ["\<Home>"],
  \ 'query_end':          ["\<End>"],
  \ 'query_del_char':     ["\<BS>"],
  \ 'query_del_forward':  ["\<Del>"],
  \ 'query_del_line':     ["\<C-u>"],
  \ 'query_del_word':     ["\<C-w>", "\<S-BS>"],
  \ 'query_complete':     ["\<Tab>"],
  \ 'query_complete_rev': ["\<S-Tab>"],
  \ 'query_jump_letter':  ["\<C-S-Left>"],
  \ 'query_jump_letter_r': ["\<C-S-Right>"],
  \
  \ 'tree_to_query':      ["\<C-Right>"],
  \ 'tree_up':            ["\<Up>"],
  \ 'tree_down':          ["\<Down>"],
  \ 'tree_page_up':       ["\<PageUp>"],
  \ 'tree_page_down':     ["\<PageDown>"],
  \ 'tree_expand':        ["\<Right>"],
  \ 'tree_collapse':      ["\<Left>"],
  \ 'tree_toggle':        [" "],
  \ 'tree_select':        ["\<CR>"],
  \ 'tree_del_char':      ["\<BS>", "\<Del>"],
  \ 'tree_clear':         ["\<C-u>"],
  \ 'tree_complete':      ["\<Tab>"],
  \ 'tree_complete_rev':  ["\<S-Tab>"],
  \
  \ 'results_to_query':   ["\<C-Up>"],
  \ 'results_up':         ["\<Up>"],
  \ 'results_down':       ["\<Down>"],
  \ 'results_page_up':    ["\<PageUp>"],
  \ 'results_page_down':  ["\<PageDown>"],
  \ 'results_open':       ["\<CR>"],
  \ 'results_toggle_syntax': ["s"],
  \ }

" Merged map (computed once on first call)
let s:merged = {}

function! skyrg#panel#keymap#get() abort
  if !empty(s:merged)
    return s:merged
  endif
  let s:merged = deepcopy(s:defaults)
  if exists('g:skyrg_keymap') && type(g:skyrg_keymap) == v:t_dict
    for [l:action, l:keys] in items(g:skyrg_keymap)
      if has_key(s:merged, l:action) && type(l:keys) == v:t_list
        let s:merged[l:action] = l:keys
      endif
    endfor
  endif
  return s:merged
endfunction

" Check if a key matches an action. Returns 1 if matched.
function! skyrg#panel#keymap#is(key, action) abort
  let l:km = skyrg#panel#keymap#get()
  return has_key(l:km, a:action) && index(l:km[a:action], a:key) >= 0
endfunction

" Force re-merge (e.g. after user changes g:skyrg_keymap at runtime)
function! skyrg#panel#keymap#reset() abort
  let s:merged = {}
endfunction
