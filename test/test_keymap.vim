" test/test_keymap.vim — Tests for configurable keymap system

"==============================================================================
" Default keymap
"==============================================================================
call skyrg#panel#keymap#reset()
let s:km = skyrg#panel#keymap#get()

call Assert(type(s:km) == v:t_dict, 'keymap returns a dict')
call Assert(has_key(s:km, 'close'), 'default has close action')
call Assert(has_key(s:km, 'query_to_tree'), 'default has query_to_tree')
call Assert(has_key(s:km, 'query_to_results'), 'default has query_to_results')
call Assert(has_key(s:km, 'query_field_up'), 'default has query_field_up')
call Assert(has_key(s:km, 'query_field_down'), 'default has query_field_down')
call Assert(has_key(s:km, 'query_search'), 'default has query_search')
call Assert(has_key(s:km, 'results_to_query'), 'default has results_to_query')
call Assert(has_key(s:km, 'results_up'), 'default has results_up')
call Assert(has_key(s:km, 'results_down'), 'default has results_down')
call Assert(has_key(s:km, 'results_open'), 'default has results_open')
call Assert(has_key(s:km, 'tree_to_query'), 'default has tree_to_query')

"==============================================================================
" Key matching
"==============================================================================
call Assert(skyrg#panel#keymap#is("\<Esc>", 'close'), 'Esc matches close')
call Assert(skyrg#panel#keymap#is("\<CR>", 'query_search'), 'CR matches query_search')
call Assert(skyrg#panel#keymap#is("\<Up>", 'query_field_up'), 'Up matches query_field_up')
call Assert(skyrg#panel#keymap#is("\<Down>", 'query_field_down'), 'Down matches query_field_down')
call Assert(skyrg#panel#keymap#is("\<C-Left>", 'query_to_tree'), 'C-Left matches query_to_tree')
call Assert(skyrg#panel#keymap#is("\<C-Down>", 'query_to_results'), 'C-Down matches query_to_results')
call Assert(skyrg#panel#keymap#is("\<C-Up>", 'results_to_query'), 'C-Up matches results_to_query')
call Assert(skyrg#panel#keymap#is("\<C-Right>", 'tree_to_query'), 'C-Right matches tree_to_query')

" Non-matching
call Assert(!skyrg#panel#keymap#is("\<CR>", 'close'), 'CR does not match close')
call Assert(!skyrg#panel#keymap#is("\<Esc>", 'query_search'), 'Esc does not match query_search')

"==============================================================================
" User override
"==============================================================================
let g:skyrg_keymap = {'close': ["\<C-q>"], 'query_search': ["\<CR>", "\<C-s>"]}
call skyrg#panel#keymap#reset()

call Assert(skyrg#panel#keymap#is("\<C-q>", 'close'), 'user override: C-q matches close')
call Assert(!skyrg#panel#keymap#is("\<Esc>", 'close'), 'user override: Esc no longer matches close')
call Assert(skyrg#panel#keymap#is("\<CR>", 'query_search'), 'user override: CR still matches query_search')
call Assert(skyrg#panel#keymap#is("\<C-s>", 'query_search'), 'user override: C-s matches query_search')

" Non-overridden actions still work
call Assert(skyrg#panel#keymap#is("\<Up>", 'query_field_up'), 'non-overridden: Up matches query_field_up')

" Cleanup
unlet g:skyrg_keymap
call skyrg#panel#keymap#reset()

"==============================================================================
" Invalid user override (wrong type) is ignored
"==============================================================================
let g:skyrg_keymap = {'close': 'not_a_list'}
call skyrg#panel#keymap#reset()
call Assert(skyrg#panel#keymap#is("\<Esc>", 'close'), 'invalid override ignored: Esc still matches close')
unlet g:skyrg_keymap
call skyrg#panel#keymap#reset()

"==============================================================================
" Unknown action in user override is ignored
"==============================================================================
let g:skyrg_keymap = {'nonexistent_action': ["\<F12>"]}
call skyrg#panel#keymap#reset()
call Assert(!skyrg#panel#keymap#is("\<F12>", 'nonexistent_action'), 'unknown action not added')
unlet g:skyrg_keymap
call skyrg#panel#keymap#reset()
