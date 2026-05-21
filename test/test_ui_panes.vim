" test/test_ui_panes.vim — Tests for generic UI pane implementations
"
" Tests the list, form, info, preview, and tree panes in isolation
" (no popups required — we test the data model and rendering).

"==============================================================================
" List pane tests
"==============================================================================

function! s:test_list_new()
  let l:p = skyrg#ui#panes#list#new({'empty_text': 'Nothing here'})
  call AssertEqual([], l:p.state.items, 'list: starts with empty items')
  call AssertEqual(0, l:p.state.idx, 'list: starts at idx 0')
  let l:r = l:p.render()
  call Assert(l:r[0].text =~# 'Nothing here', 'list: renders empty_text')
endfunction
call s:test_list_new()

function! s:test_list_set_items()
  let l:p = skyrg#ui#panes#list#new({})
  call l:p.set_items(['alpha', 'beta', 'gamma'])
  call AssertEqual(3, len(l:p.state.items), 'list: set_items count')
  call AssertEqual(0, l:p.state.idx, 'list: set_items resets idx')
  call AssertEqual('alpha', l:p.selected(), 'list: selected() returns first')
endfunction
call s:test_list_set_items()

function! s:test_list_move()
  let l:p = skyrg#ui#panes#list#new({})
  call l:p.set_items(['a', 'b', 'c', 'd', 'e'])
  call l:p.move(2)
  call AssertEqual(2, l:p.state.idx, 'list: move(2) from 0')
  call AssertEqual('c', l:p.selected(), 'list: selected after move')
  call l:p.move(-1)
  call AssertEqual(1, l:p.state.idx, 'list: move(-1)')
  call l:p.move(-5)
  call AssertEqual(0, l:p.state.idx, 'list: move clamps at 0')
  call l:p.move(100)
  call AssertEqual(4, l:p.state.idx, 'list: move clamps at end')
endfunction
call s:test_list_move()

function! s:test_list_render_default()
  let l:p = skyrg#ui#panes#list#new({})
  call l:p.set_items(['foo', 'bar'])
  let l:r = l:p.render()
  call Assert(len(l:r) >= 2, 'list: renders 2 items')
  call Assert(l:r[0].text =~# 'foo', 'list: first item contains foo')
endfunction
call s:test_list_render_default()

function! s:test_list_render_custom()
  function! s:fmt(item, idx, sel) abort
    return skyrg#ui#util#line((a:sel ? '* ' : '  ') . a:item)
  endfunction
  let l:p = skyrg#ui#panes#list#new({'format_item': function('s:fmt')})
  call l:p.set_items(['one', 'two'])
  let l:r = l:p.render()
  call Assert(l:r[0].text =~# '^\*.*one', 'list: custom fmt selected')
  call Assert(l:r[1].text =~# '^  two', 'list: custom fmt non-selected')
endfunction
call s:test_list_render_custom()

"==============================================================================
" Form pane tests
"==============================================================================

function! s:test_form_new()
  let l:p = skyrg#ui#panes#form#new({
    \ 'fields': [
    \   {'label': 'Name', 'type': 'text', 'value': 'hello'},
    \   {'label': 'Active', 'type': 'toggle', 'value': 'on'},
    \ ],
    \ })
  call AssertEqual(2, len(l:p.state.fields), 'form: 2 fields')
  call AssertEqual('hello', l:p.state.fields[0].value, 'form: initial value')
  call AssertEqual(0, l:p.state.field_idx, 'form: starts on field 0')
endfunction
call s:test_form_new()

function! s:test_form_get_set_values()
  let l:p = skyrg#ui#panes#form#new({
    \ 'fields': [
    \   {'label': 'A', 'value': 'x'},
    \   {'label': 'B', 'value': 'y'},
    \ ],
    \ })
  let l:v = l:p.get_values()
  call AssertEqual('x', l:v.A, 'form: get_values A')
  call AssertEqual('y', l:v.B, 'form: get_values B')
  call l:p.set_values({'A': 'new', 'B': 'val'})
  call AssertEqual('new', l:p.state.fields[0].value, 'form: set_values A')
  call AssertEqual('val', l:p.state.fields[1].value, 'form: set_values B')
endfunction
call s:test_form_get_set_values()

function! s:test_form_render()
  let l:p = skyrg#ui#panes#form#new({
    \ 'fields': [
    \   {'label': 'Query', 'type': 'text', 'value': 'test'},
    \   {'label': 'Enabled', 'type': 'toggle', 'value': 'on'},
    \   {'label': 'Mode', 'type': 'select', 'value': 'fast'},
    \ ],
    \ })
  let l:p._focused = 1
  let l:r = l:p.render()
  call Assert(len(l:r) >= 3, 'form: renders at least 3 lines')
  call Assert(l:r[0].text =~# 'Query', 'form: first line has Query label')
  call Assert(l:r[1].text =~# 'Enabled', 'form: second line has toggle label')
  call Assert(l:r[2].text =~# 'Mode', 'form: third line has select label')
endfunction
call s:test_form_render()

"==============================================================================
" Info pane tests
"==============================================================================

function! s:test_info_new()
  let l:p = skyrg#ui#panes#info#new({})
  call AssertEqual(1, len(l:p.state.lines), 'info: starts with 1 empty line')
  call l:p.set_lines([
    \ skyrg#ui#util#line('Hello'),
    \ skyrg#ui#util#hl_line('World', 'skyrg_dim'),
    \ ])
  let l:r = l:p.render()
  call AssertEqual(2, len(l:r), 'info: renders 2 lines after set')
  call AssertEqual('Hello', l:r[0].text, 'info: first line text')
  call l:p.clear()
  let l:r = l:p.render()
  call AssertEqual(1, len(l:r), 'info: clear resets to 1 line')
endfunction
call s:test_info_new()

"==============================================================================
" Util tests (verifying ui/ path works)
"==============================================================================

function! s:test_ui_util()
  let l:line = skyrg#ui#util#line('hello')
  call AssertEqual('hello', l:line.text, 'ui util: line text')
  call Assert(!has_key(l:line, 'props'), 'ui util: line no props')

  let l:hl = skyrg#ui#util#hl_line('world', 'skyrg_dim')
  call AssertEqual('world', l:hl.text, 'ui util: hl_line text')
  call AssertEqual(1, len(l:hl.props), 'ui util: hl_line has 1 prop')
  call AssertEqual('skyrg_dim', l:hl.props[0].type, 'ui util: hl_line prop type')
endfunction
call s:test_ui_util()
