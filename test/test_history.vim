" test/test_history.vim — Tests for the history backend
"
" Uses a temp directory to avoid polluting real history.

let s:tmpdir = '/tmp/skyrg_test_history_' . getpid()

"==============================================================================
" Helpers
"==============================================================================

function! s:setup() abort
  " Override XDG_DATA_HOME so history goes to temp dir
  let $XDG_DATA_HOME = s:tmpdir
  if isdirectory(s:tmpdir)
    call system('rm -rf ' . shellescape(s:tmpdir))
  endif
endfunction

function! s:teardown() abort
  call system('rm -rf ' . shellescape(s:tmpdir))
  unlet $XDG_DATA_HOME
endfunction

"==============================================================================
" Tests
"==============================================================================

function! s:test_history_save_and_load()
  call s:setup()
  let l:entry = {'query': 'hello', 'types': 'py', 'dirs': '',
    \ 'preset': '', 'gitignore': 1, 'timestamp': 1000}
  call skyrg#backend#history#save(l:entry)
  let l:all = skyrg#backend#history#load_all()
  call AssertEqual(1, len(l:all), 'history: 1 entry after save')
  call AssertEqual('hello', l:all[0].query, 'history: query matches')
  call AssertEqual(1000, l:all[0].timestamp, 'history: timestamp matches')
  call s:teardown()
endfunction
call s:test_history_save_and_load()

function! s:test_history_load_last()
  call s:setup()
  call skyrg#backend#history#save({'query': 'first', 'timestamp': 100})
  call skyrg#backend#history#save({'query': 'second', 'timestamp': 200})
  call skyrg#backend#history#save({'query': 'third', 'timestamp': 300})
  let l:last = skyrg#backend#history#load_last()
  call AssertEqual('third', l:last.query, 'history load_last: returns most recent')
  call s:teardown()
endfunction
call s:test_history_load_last()

function! s:test_history_load_all_order()
  call s:setup()
  call skyrg#backend#history#save({'query': 'a', 'timestamp': 100})
  call skyrg#backend#history#save({'query': 'b', 'timestamp': 200})
  call skyrg#backend#history#save({'query': 'c', 'timestamp': 300})
  let l:all = skyrg#backend#history#load_all()
  call AssertEqual(3, len(l:all), 'history order: 3 entries')
  call AssertEqual('c', l:all[0].query, 'history order: newest first')
  call AssertEqual('a', l:all[2].query, 'history order: oldest last')
  call s:teardown()
endfunction
call s:test_history_load_all_order()

function! s:test_history_dedup()
  call s:setup()
  let l:e = {'query': 'same', 'types': 'py', 'dirs': '', 'preset': '', 'gitignore': 1}
  call skyrg#backend#history#save(extend(copy(l:e), {'timestamp': 100}))
  call skyrg#backend#history#save(extend(copy(l:e), {'timestamp': 200}))
  let l:all = skyrg#backend#history#load_all()
  call AssertEqual(1, len(l:all), 'history dedup: duplicate not saved')
  call s:teardown()
endfunction
call s:test_history_dedup()

function! s:test_history_dedup_different()
  call s:setup()
  call skyrg#backend#history#save({'query': 'a', 'types': '', 'dirs': '', 'preset': '', 'gitignore': 1, 'timestamp': 100})
  call skyrg#backend#history#save({'query': 'b', 'types': '', 'dirs': '', 'preset': '', 'gitignore': 1, 'timestamp': 200})
  let l:all = skyrg#backend#history#load_all()
  call AssertEqual(2, len(l:all), 'history dedup diff: different queries both saved')
  call s:teardown()
endfunction
call s:test_history_dedup_different()

function! s:test_history_empty_query_not_saved()
  call s:setup()
  call skyrg#backend#history#save({'query': '', 'timestamp': 100})
  let l:all = skyrg#backend#history#load_all()
  call AssertEqual(0, len(l:all), 'history empty: not saved')
  call s:teardown()
endfunction
call s:test_history_empty_query_not_saved()

function! s:test_history_search()
  call s:setup()
  call skyrg#backend#history#save({'query': 'hello world', 'timestamp': 100})
  call skyrg#backend#history#save({'query': 'foo bar', 'timestamp': 200})
  call skyrg#backend#history#save({'query': 'hello vim', 'timestamp': 300})
  let l:r = skyrg#backend#history#search('hello')
  call AssertEqual(2, len(l:r), 'history search: found 2 matches')
  call AssertEqual('hello vim', l:r[0].query, 'history search: newest match first')
  call s:teardown()
endfunction
call s:test_history_search()

function! s:test_history_delete()
  call s:setup()
  call skyrg#backend#history#save({'query': 'keep', 'timestamp': 100})
  call skyrg#backend#history#save({'query': 'delete_me', 'timestamp': 200})
  call skyrg#backend#history#save({'query': 'also_keep', 'timestamp': 300})
  call skyrg#backend#history#delete(200)
  let l:all = skyrg#backend#history#load_all()
  call AssertEqual(2, len(l:all), 'history delete: 2 entries remain')
  let l:queries = map(copy(l:all), {_, e -> e.query})
  call Assert(index(l:queries, 'delete_me') == -1, 'history delete: deleted entry gone')
  call s:teardown()
endfunction
call s:test_history_delete()

function! s:test_history_load_empty()
  call s:setup()
  let l:all = skyrg#backend#history#load_all()
  call AssertEqual([], l:all, 'history empty: load_all returns []')
  let l:last = skyrg#backend#history#load_last()
  call AssertEqual({}, l:last, 'history empty: load_last returns {}')
  call s:teardown()
endfunction
call s:test_history_load_empty()

function! s:test_history_project_root()
  let l:root = skyrg#backend#history#project_root()
  call Assert(!empty(l:root), 'history: project_root not empty')
endfunction
call s:test_history_project_root()
