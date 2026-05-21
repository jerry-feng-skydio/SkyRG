" test/test_backend_rg.vim — Tests for the rg backend

"==============================================================================
" Backend constructor
"==============================================================================

function! s:test_rg_new()
  let l:be = skyrg#backend#rg#new()
  call Assert(has_key(l:be, 'run'), 'rg backend: has run')
  call Assert(has_key(l:be, 'cancel'), 'rg backend: has cancel')
  call Assert(has_key(l:be, 'schedule'), 'rg backend: has schedule')
  call AssertEqual(0, l:be._gen, 'rg backend: gen starts at 0')
endfunction
call s:test_rg_new()

"==============================================================================
" Empty query returns immediately
"==============================================================================

function! s:test_rg_empty_query()
  let s:done_results = v:null
  function! s:on_done(results) abort
    let s:done_results = a:results
  endfunction
  let l:be = skyrg#backend#rg#new()
  call l:be.run({'query': ''}, {'on_done': function('s:on_done')})
  call AssertEqual([], s:done_results, 'rg empty query: on_done called with []')
endfunction
call s:test_rg_empty_query()

"==============================================================================
" Generation counter increments
"==============================================================================

function! s:test_rg_gen_counter()
  let l:be = skyrg#backend#rg#new()
  call AssertEqual(0, l:be._gen, 'rg gen: starts at 0')
  call l:be.run({'query': ''}, {})
  call AssertEqual(1, l:be._gen, 'rg gen: increments to 1')
  call l:be.run({'query': ''}, {})
  call AssertEqual(2, l:be._gen, 'rg gen: increments to 2')
endfunction
call s:test_rg_gen_counter()

"==============================================================================
" Views search query snapshot
"==============================================================================

function! s:test_views_search_get_query()
  " Verify the function exists and returns a dict (even if panel isn't open)
  let l:q = skyrg#views#search#get_query()
  call Assert(type(l:q) == v:t_dict, 'views search: get_query returns dict')
endfunction
call s:test_views_search_get_query()
