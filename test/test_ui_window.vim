" test/test_ui_window.vim — Tests for ui/window.vim layout engine
"
" Tests layout computation without creating actual popups.
" The layout engine is the core of the window system.

"==============================================================================
" Layout computation tests (via internal function access pattern)
"==============================================================================

" We test indirectly by creating a minimal window and checking the layout.
" Since open() requires popup support, we test the pane wiring logic here.

function! s:test_list_pane_on_select_callback()
  let s:selected_items = []
  function! s:on_sel(item, idx) abort
    call add(s:selected_items, a:item)
  endfunction
  let l:p = skyrg#ui#panes#list#new({
    \ 'on_select': function('s:on_sel'),
    \ })
  call l:p.set_items(['a', 'b', 'c'])
  call l:p.move(1)
  call AssertEqual(1, len(s:selected_items), 'list callback: on_select called once')
  call AssertEqual('b', s:selected_items[0], 'list callback: on_select received correct item')
  call l:p.move(1)
  call AssertEqual(2, len(s:selected_items), 'list callback: on_select called again')
  call AssertEqual('c', s:selected_items[1], 'list callback: second select correct')
endfunction
call s:test_list_pane_on_select_callback()

function! s:test_list_pane_on_accept_callback()
  let s:accepted = []
  function! s:on_acc(item, idx) abort
    call add(s:accepted, {'item': a:item, 'idx': a:idx})
  endfunction
  let l:p = skyrg#ui#panes#list#new({
    \ 'on_accept': function('s:on_acc'),
    \ 'actions': {'accept': 'results_open'},
    \ })
  call l:p.set_items(['x', 'y', 'z'])
  call l:p.move(2)
  " Simulate Enter key
  let l:consumed = l:p.on_key("\<CR>", function('skyrg#ui#keymap#is'))
  call Assert(l:consumed, 'list accept: key consumed')
  call AssertEqual(1, len(s:accepted), 'list accept: callback called')
  call AssertEqual('z', s:accepted[0].item, 'list accept: correct item')
  call AssertEqual(2, s:accepted[0].idx, 'list accept: correct idx')
endfunction
call s:test_list_pane_on_accept_callback()

function! s:test_list_scroll_management()
  let l:p = skyrg#ui#panes#list#new({})
  let l:p._geo = {'height': 7, 'width': 40}
  let l:items = []
  for l:i in range(20)
    call add(l:items, 'item_' . l:i)
  endfor
  call l:p.set_items(l:items)
  " Move to item 10 (beyond visible area of height-2=5)
  call l:p.move(10)
  let l:r = l:p.render()
  " Should have rendered ~5 lines (the visible window)
  call Assert(len(l:r) <= 6, 'list scroll: rendered lines within visible area')
  call Assert(l:p.state.scroll > 0, 'list scroll: scroll offset > 0')
endfunction
call s:test_list_scroll_management()

function! s:test_form_field_navigation()
  let l:p = skyrg#ui#panes#form#new({
    \ 'fields': [
    \   {'label': 'A', 'value': ''},
    \   {'label': 'B', 'value': ''},
    \   {'label': 'C', 'value': ''},
    \ ],
    \ })
  let l:K = function('skyrg#ui#keymap#is')
  " Down → field 1
  call l:p.on_key("\<Down>", l:K)
  call AssertEqual(1, l:p.state.field_idx, 'form nav: Down to field 1')
  " Down → field 2
  call l:p.on_key("\<Down>", l:K)
  call AssertEqual(2, l:p.state.field_idx, 'form nav: Down to field 2')
  " Down wraps to 0
  call l:p.on_key("\<Down>", l:K)
  call AssertEqual(0, l:p.state.field_idx, 'form nav: Down wraps to 0')
  " Up wraps to 2
  call l:p.on_key("\<Up>", l:K)
  call AssertEqual(2, l:p.state.field_idx, 'form nav: Up wraps to 2')
endfunction
call s:test_form_field_navigation()

function! s:test_form_text_editing()
  let l:p = skyrg#ui#panes#form#new({
    \ 'fields': [{'label': 'Q', 'type': 'text', 'value': ''}],
    \ })
  let l:K = function('skyrg#ui#keymap#is')
  let l:p._focused = 1
  " Type 'abc'
  call l:p.on_key('a', l:K)
  call l:p.on_key('b', l:K)
  call l:p.on_key('c', l:K)
  call AssertEqual('abc', l:p.state.fields[0].value, 'form edit: typed abc')
  call AssertEqual(3, l:p.state.fields[0].pos, 'form edit: cursor at 3')
  " Backspace
  call l:p.on_key("\<BS>", l:K)
  call AssertEqual('ab', l:p.state.fields[0].value, 'form edit: BS removes c')
  " Move left, type 'x'
  call l:p.on_key("\<Left>", l:K)
  call AssertEqual(1, l:p.state.fields[0].pos, 'form edit: cursor at 1')
  call l:p.on_key('x', l:K)
  call AssertEqual('axb', l:p.state.fields[0].value, 'form edit: insert x')
  " Home then End
  call l:p.on_key("\<Home>", l:K)
  call AssertEqual(0, l:p.state.fields[0].pos, 'form edit: Home')
  call l:p.on_key("\<End>", l:K)
  call AssertEqual(3, l:p.state.fields[0].pos, 'form edit: End')
  " Ctrl-U clears
  call l:p.on_key("\<C-u>", l:K)
  call AssertEqual('', l:p.state.fields[0].value, 'form edit: C-u clears')
endfunction
call s:test_form_text_editing()

function! s:test_form_toggle()
  let l:p = skyrg#ui#panes#form#new({
    \ 'fields': [{'label': 'On', 'type': 'toggle', 'value': 'on'}],
    \ })
  let l:K = function('skyrg#ui#keymap#is')
  call l:p.on_key(' ', l:K)
  call AssertEqual('off', l:p.state.fields[0].value, 'form toggle: on→off')
  call l:p.on_key(' ', l:K)
  call AssertEqual('on', l:p.state.fields[0].value, 'form toggle: off→on')
endfunction
call s:test_form_toggle()

function! s:test_info_pane_protocol()
  let l:p = skyrg#ui#panes#info#new({})
  " Verify pane protocol methods exist
  call Assert(has_key(l:p, 'render'), 'info protocol: has render')
  call Assert(has_key(l:p, 'on_key'), 'info protocol: has on_key')
  call Assert(has_key(l:p, 'on_focus'), 'info protocol: has on_focus')
  call Assert(has_key(l:p, 'on_blur'), 'info protocol: has on_blur')
  call Assert(has_key(l:p, 'on_resize'), 'info protocol: has on_resize')
  call Assert(has_key(l:p, 'cleanup'), 'info protocol: has cleanup')
  " on_key returns 0 (info pane doesn't handle keys)
  let l:K = function('skyrg#ui#keymap#is')
  call AssertEqual(0, l:p.on_key('a', l:K), 'info protocol: on_key returns 0')
endfunction
call s:test_info_pane_protocol()

function! s:test_preview_pane_protocol()
  let l:p = skyrg#ui#panes#preview#new({'syntax_enabled': 0})
  call Assert(has_key(l:p, 'render'), 'preview protocol: has render')
  call Assert(has_key(l:p, 'show_file'), 'preview protocol: has show_file')
  call Assert(has_key(l:p, 'clear'), 'preview protocol: has clear')
  call Assert(has_key(l:p, 'toggle_syntax'), 'preview protocol: has toggle_syntax')
  call AssertEqual('', l:p.state.file, 'preview: starts with empty file')
endfunction
call s:test_preview_pane_protocol()

function! s:test_tree_pane_protocol()
  let l:p = skyrg#ui#panes#tree#new({'root': getcwd()})
  call Assert(has_key(l:p, 'render'), 'tree protocol: has render')
  call Assert(has_key(l:p, 'on_key'), 'tree protocol: has on_key')
  call Assert(has_key(l:p, 'init'), 'tree protocol: has init')
  call Assert(has_key(l:p, 'selected_node'), 'tree protocol: has selected_node')
  " Starts with empty nodes
  call AssertEqual([], l:p.state.nodes, 'tree: starts empty')
endfunction
call s:test_tree_pane_protocol()
