" test/run.vim — Minimal test runner for SkyRG
"
" Usage:  vim -u NONE -N --cmd 'set rtp+=.' -S test/run.vim
"
" Exits with code 1 if any test fails.

let s:pass = 0
let s:fail = 0
let s:errors = []

function! Assert(cond, msg) abort
  if a:cond
    let s:pass += 1
  else
    let s:fail += 1
    call add(s:errors, a:msg)
    echom 'FAIL: ' . a:msg
  endif
endfunction

function! AssertEqual(expected, actual, msg) abort
  if a:expected ==# a:actual
    let s:pass += 1
  else
    let s:fail += 1
    let l:detail = a:msg . '  expected=' . string(a:expected) . '  actual=' . string(a:actual)
    call add(s:errors, l:detail)
    echom 'FAIL: ' . l:detail
  endif
endfunction

" Source the plugin (initializes g:SkyFilter)
runtime plugin/skyrg.vim

" Source test files
runtime test/test_filter.vim
runtime test/test_search_cmd.vim
runtime test/test_keymap.vim
runtime test/test_ui_panes.vim
runtime test/test_ui_window.vim
runtime test/test_backend_rg.vim
runtime test/test_history.vim

" Summary
echom ''
echom '========================================'
echom printf('  %d passed, %d failed', s:pass, s:fail)
echom '========================================'
if !empty(s:errors)
  echom ''
  for l:e in s:errors
    echom '  ✗ ' . l:e
  endfor
endif

" Write results to file for inspection
let s:log = [printf('%d passed, %d failed', s:pass, s:fail)]
for l:e in s:errors
  call add(s:log, '  FAIL: ' . l:e)
endfor
call writefile(s:log, '/tmp/skyrg_test.log')

if s:fail > 0
  cquit!
else
  qall!
endif
