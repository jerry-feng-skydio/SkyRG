" autoload/skyrg/ui/panes/list.vim — Generic scrollable list pane
"
" A reusable list pane that displays items with selection, scrolling,
" and configurable formatting. Conforms to the pane protocol.
"
" Usage:
"   let pane = skyrg#ui#panes#list#new({
"     \ 'format_item': function('s:fmt'),    " (item, idx, is_sel) → line_dict
"     \ 'on_select':   function('s:on_sel'), " (item, idx) — cursor moved
"     \ 'on_accept':   function('s:on_acc'), " (item, idx) — Enter pressed
"     \ 'empty_text':  'No items',
"     \ 'actions':     {'up': 'results_up', 'down': 'results_down', ...},
"     \ })

"==============================================================================
" Constructor
"==============================================================================

function! skyrg#ui#panes#list#new(config) abort
  let l:pane = {
    \ 'name':   '',
    \ 'config': a:config,
    \ 'state':  {'items': [], 'idx': 0, 'scroll': 0},
    \ '_geo':   {'height': 20, 'width': 40},
    \ }

  " --- Pane protocol methods ---

  function! l:pane.render() dict abort
    let l:items = self.state.items
    if empty(l:items)
      let l:msg = get(self.config, 'empty_text', 'No items')
      return [skyrg#ui#util#hl_line('  ' . l:msg, 'skyrg_dim')]
    endif
    let l:data = s:prepare(self)
    return s:render(self, l:data)
  endfunction

  function! l:pane.on_key(key, K) dict abort
    let l:act = get(self.config, 'actions', s:default_actions())
    if a:K(a:key, get(l:act, 'up', 'results_up'))
      call self.move(-1) | return 1
    endif
    if a:K(a:key, get(l:act, 'down', 'results_down'))
      call self.move(1) | return 1
    endif
    if a:K(a:key, get(l:act, 'page_up', 'results_page_up'))
      call self.move(-(self._geo.height - 2)) | return 1
    endif
    if a:K(a:key, get(l:act, 'page_down', 'results_page_down'))
      call self.move(self._geo.height - 2) | return 1
    endif
    if a:K(a:key, get(l:act, 'accept', 'results_open'))
      if !empty(self.state.items)
        let l:item = self.state.items[self.state.idx]
        if has_key(self.config, 'on_accept')
          call self.config.on_accept(l:item, self.state.idx)
        endif
      endif
      return 1
    endif
    return 0
  endfunction

  function! l:pane.on_focus() dict abort
  endfunction

  function! l:pane.on_blur() dict abort
  endfunction

  function! l:pane.on_resize(geo) dict abort
    let self._geo = a:geo
  endfunction

  function! l:pane.cleanup() dict abort
  endfunction

  " --- Public helpers ---

  function! l:pane.set_items(items) dict abort
    let self.state.items = a:items
    let self.state.idx = 0
    let self.state.scroll = 0
  endfunction

  function! l:pane.move(delta) dict abort
    if empty(self.state.items) | return | endif
    let self.state.idx = max([0, min([
      \ len(self.state.items) - 1, self.state.idx + a:delta])])
    if has_key(self.config, 'on_select')
      call self.config.on_select(self.state.items[self.state.idx], self.state.idx)
    endif
  endfunction

  function! l:pane.selected() dict abort
    if empty(self.state.items) | return {} | endif
    return self.state.items[self.state.idx]
  endfunction

  return l:pane
endfunction

"==============================================================================
" Private helpers
"==============================================================================

function! s:default_actions() abort
  return {
    \ 'up':        'results_up',
    \ 'down':      'results_down',
    \ 'page_up':   'results_page_up',
    \ 'page_down': 'results_page_down',
    \ 'accept':    'results_open',
    \ }
endfunction

" Compute visible window into items list (scroll management).
function! s:prepare(pane) abort
  let l:vis = max([a:pane._geo.height - 2, 1])
  let l:s = a:pane.state
  let l:first = l:s.scroll
  if l:s.idx < l:first
    let l:first = l:s.idx
  elseif l:s.idx >= l:first + l:vis
    let l:first = l:s.idx - l:vis + 1
  endif
  let l:s.scroll = l:first
  return {'first': l:first, 'last': min([l:first + l:vis - 1, len(l:s.items) - 1])}
endfunction

" Build popup line dicts from prepared data.
function! s:render(pane, data) abort
  let l:lines = []
  let l:has_fmt = has_key(a:pane.config, 'format_item')
  for l:i in range(a:data.first, a:data.last)
    let l:item = a:pane.state.items[l:i]
    let l:is_sel = l:i == a:pane.state.idx
    if l:has_fmt
      call add(l:lines, a:pane.config.format_item(l:item, l:i, l:is_sel))
    else
      " Default formatting: show string representation
      let l:text = (l:is_sel ? '> ' : '  ') . string(l:item)
      if l:is_sel
        call add(l:lines, skyrg#ui#util#hl_line(l:text, 'skyrg_sel'))
      else
        call add(l:lines, {'text': l:text})
      endif
    endif
  endfor
  return l:lines
endfunction
