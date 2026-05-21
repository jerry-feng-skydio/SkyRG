" autoload/skyrg/ui/panes/tree.vim — Generic tree browser pane
"
" A reusable expandable tree pane. Conforms to the pane protocol.
" The existing panel/tree.vim is much more complex (search, tab-completion,
" pinned ancestors, etc.); this provides the core tree infrastructure that
" panel/tree.vim can be migrated onto in Phase 3.
"
" Usage:
"   let pane = skyrg#ui#panes#tree#new({
"     \ 'root':        getcwd(),
"     \ 'list_fn':     function('s:list_children'),  " (path) → [{name, path, is_dir}, ...]
"     \ 'on_select':   function('s:on_node_selected'),
"     \ 'show_files':  0,
"     \ })

"==============================================================================
" Constructor
"==============================================================================

function! skyrg#ui#panes#tree#new(config) abort
  let l:pane = {
    \ 'name':   '',
    \ 'config': a:config,
    \ 'state':  {
    \   'nodes': [],
    \   'idx': 0,
    \   'scroll': 0,
    \   'expanded': {},
    \   'filter': '',
    \ },
    \ '_geo':   {'height': 30, 'width': 30},
    \ }

  function! l:pane.render() dict abort
    return s:render_tree(self)
  endfunction

  function! l:pane.on_key(key, K) dict abort
    return s:handle_key(self, a:key, a:K)
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

  function! l:pane.init() dict abort
    let self.state.expanded = {}
    let self.state.idx = 0
    call s:rebuild(self)
  endfunction

  function! l:pane.selected_node() dict abort
    if self.state.idx < len(self.state.nodes)
      return self.state.nodes[self.state.idx]
    endif
    return {}
  endfunction

  return l:pane
endfunction

"==============================================================================
" Tree building
"==============================================================================

function! s:rebuild(pane) abort
  let l:root = get(a:pane.config, 'root', getcwd())
  let a:pane.state.nodes = []
  call s:build_level(a:pane, l:root, 0)
endfunction

function! s:build_level(pane, dir, depth) abort
  let l:list_fn = get(a:pane.config, 'list_fn', function('s:default_list'))
  let l:children = l:list_fn(a:dir)
  for l:child in l:children
    if !l:child.is_dir && !get(a:pane.config, 'show_files', 0)
      continue
    endif
    call add(a:pane.state.nodes, {
      \ 'name': l:child.name,
      \ 'path': l:child.path,
      \ 'is_dir': l:child.is_dir,
      \ 'depth': a:depth,
      \ })
    if l:child.is_dir && has_key(a:pane.state.expanded, l:child.path)
      call s:build_level(a:pane, l:child.path, a:depth + 1)
    endif
  endfor
endfunction

function! s:default_list(dir) abort
  let l:raw = globpath(a:dir, '*', 0, 1) + globpath(a:dir, '.*', 0, 1)
  let l:result = []
  for l:p in l:raw
    let l:name = fnamemodify(l:p, ':t')
    if l:name ==# '.' || l:name ==# '..' || l:name ==# '.git'
      continue
    endif
    call add(l:result, {'name': l:name, 'path': l:p, 'is_dir': isdirectory(l:p)})
  endfor
  call sort(l:result, {a, b -> a.name < b.name ? -1 : a.name > b.name ? 1 : 0})
  return l:result
endfunction

"==============================================================================
" Key handling
"==============================================================================

function! s:handle_key(pane, key, K) abort
  let l:t = a:pane.state
  if empty(l:t.nodes) | return 0 | endif

  " Navigation
  if a:K(a:key, 'tree_up')
    let l:t.idx = max([0, l:t.idx - 1])
    return 1
  endif
  if a:K(a:key, 'tree_down')
    let l:t.idx = min([len(l:t.nodes) - 1, l:t.idx + 1])
    return 1
  endif
  if a:K(a:key, 'tree_page_up')
    let l:t.idx = max([0, l:t.idx - (a:pane._geo.height - 4)])
    return 1
  endif
  if a:K(a:key, 'tree_page_down')
    let l:t.idx = min([len(l:t.nodes) - 1, l:t.idx + (a:pane._geo.height - 4)])
    return 1
  endif

  " Expand / collapse
  if a:K(a:key, 'tree_expand')
    let l:node = l:t.nodes[l:t.idx]
    if l:node.is_dir && !has_key(l:t.expanded, l:node.path)
      let l:t.expanded[l:node.path] = 1
      call s:rebuild(a:pane)
    endif
    return 1
  endif
  if a:K(a:key, 'tree_collapse')
    let l:node = l:t.nodes[l:t.idx]
    if l:node.is_dir && has_key(l:t.expanded, l:node.path)
      call remove(l:t.expanded, l:node.path)
      call s:rebuild(a:pane)
    elseif l:node.depth > 0
      " Collapse to parent
      for l:i in range(l:t.idx - 1, 0, -1)
        if l:t.nodes[l:i].depth < l:node.depth
          let l:t.idx = l:i
          break
        endif
      endfor
    endif
    return 1
  endif
  if a:K(a:key, 'tree_toggle')
    let l:node = l:t.nodes[l:t.idx]
    if l:node.is_dir
      if has_key(l:t.expanded, l:node.path)
        call remove(l:t.expanded, l:node.path)
      else
        let l:t.expanded[l:node.path] = 1
      endif
      call s:rebuild(a:pane)
    endif
    return 1
  endif

  " Select (Enter)
  if a:K(a:key, 'tree_select')
    let l:node = l:t.nodes[l:t.idx]
    if has_key(a:pane.config, 'on_select')
      call a:pane.config.on_select(l:node)
    endif
    return 1
  endif

  return 0
endfunction

"==============================================================================
" Rendering
"==============================================================================

function! s:render_tree(pane) abort
  let l:t = a:pane.state
  let l:lines = []

  " Header: current directory
  call add(l:lines, skyrg#ui#util#hl_line(' ' . getcwd(), 'skyrg_dim'))

  if empty(l:t.nodes)
    call add(l:lines, skyrg#ui#util#hl_line('  (empty)', 'skyrg_dim'))
    return l:lines
  endif

  " Scroll management
  let l:vis = max([a:pane._geo.height - 4, 1])
  let l:first = l:t.scroll
  if l:t.idx < l:first
    let l:first = l:t.idx
  elseif l:t.idx >= l:first + l:vis
    let l:first = l:t.idx - l:vis + 1
  endif
  let l:t.scroll = l:first
  let l:last = min([l:first + l:vis - 1, len(l:t.nodes) - 1])

  for l:i in range(l:first, l:last)
    let l:node = l:t.nodes[l:i]
    let l:is_sel = l:i == l:t.idx
    let l:indent = repeat('  ', l:node.depth)
    let l:icon = l:node.is_dir
      \ ? (has_key(l:t.expanded, l:node.path) ? '▼ ' : '▶ ')
      \ : '  '
    let l:mk = l:is_sel ? '>' : ' '
    let l:text = ' ' . l:mk . l:indent . l:icon . l:node.name
    if l:is_sel
      call add(l:lines, skyrg#ui#util#hl_line(l:text, 'skyrg_sel'))
    else
      call add(l:lines, {'text': l:text})
    endif
  endfor

  return l:lines
endfunction
