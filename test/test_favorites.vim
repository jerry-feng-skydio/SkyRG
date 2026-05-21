" test/test_favorites.vim — Tests for the favorites backend

let s:tmpdir = '/tmp/skyrg_test_favorites_' . getpid()

function! s:setup() abort
  let $XDG_DATA_HOME = s:tmpdir
  if isdirectory(s:tmpdir)
    call system('rm -rf ' . shellescape(s:tmpdir))
  endif
endfunction

function! s:teardown() abort
  call system('rm -rf ' . shellescape(s:tmpdir))
  unlet $XDG_DATA_HOME
endfunction

function! s:test_fav_add_and_load()
  call s:setup()
  call skyrg#backend#favorites#add({'query': 'TODO', 'types': 'py', 'timestamp': 1000})
  let l:all = skyrg#backend#favorites#load_all()
  call AssertEqual(1, len(l:all), 'fav: 1 entry after add')
  call AssertEqual('TODO', l:all[0].query, 'fav: query matches')
  call s:teardown()
endfunction
call s:test_fav_add_and_load()

function! s:test_fav_remove()
  call s:setup()
  call skyrg#backend#favorites#add({'query': 'a', 'timestamp': 100})
  call skyrg#backend#favorites#add({'query': 'b', 'timestamp': 200})
  call skyrg#backend#favorites#remove(0)
  let l:all = skyrg#backend#favorites#load_all()
  call AssertEqual(1, len(l:all), 'fav remove: 1 entry remains')
  call AssertEqual('b', l:all[0].query, 'fav remove: correct entry remains')
  call s:teardown()
endfunction
call s:test_fav_remove()

function! s:test_fav_update_label()
  call s:setup()
  call skyrg#backend#favorites#add({'query': 'test', 'timestamp': 100})
  call skyrg#backend#favorites#update_label(0, 'My Label')
  let l:all = skyrg#backend#favorites#load_all()
  call AssertEqual('My Label', l:all[0].label, 'fav label: updated')
  call s:teardown()
endfunction
call s:test_fav_update_label()

function! s:test_fav_is_favorited()
  call s:setup()
  call skyrg#backend#favorites#add({'query': 'hello', 'timestamp': 100})
  call Assert(skyrg#backend#favorites#is_favorited('hello'), 'fav: hello is favorited')
  call Assert(!skyrg#backend#favorites#is_favorited('world'), 'fav: world is not favorited')
  call s:teardown()
endfunction
call s:test_fav_is_favorited()

function! s:test_fav_empty()
  call s:setup()
  let l:all = skyrg#backend#favorites#load_all()
  call AssertEqual([], l:all, 'fav empty: returns []')
  call s:teardown()
endfunction
call s:test_fav_empty()

function! s:test_fav_default_label()
  call s:setup()
  call skyrg#backend#favorites#add({'query': 'myquery', 'timestamp': 100})
  let l:all = skyrg#backend#favorites#load_all()
  call AssertEqual('myquery', l:all[0].label, 'fav default label: uses query')
  call s:teardown()
endfunction
call s:test_fav_default_label()
