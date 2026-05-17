" autoload/skyrg/panel/tree.vim — Directory tree panel
"
" Owns state.tree: {open, idx, nodes, expanded, filter, tab_mode, tab_base,
"                   no_matches, scroll}
"
" Provides a navigable directory tree for selecting search directories.
" Features: expand/collapse, prefix search, tab completion, pinned ancestors.

let s:TREE_SHOW_FILES = 0
let s:TREE_SEARCH_NORMAL = 0 | let s:TREE_SEARCH_FUZZY = 1
let s:TREE_SEARCH_MODE = s:TREE_SEARCH_NORMAL

"==============================================================================
" Toggle / init
"==============================================================================
function! skyrg#panel#tree#toggle(open) abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  let l:t = l:s.tree
  let l:t.open = a:open
  if a:open
    if empty(l:t.nodes)
      call skyrg#panel#tree#init()
    else
      call skyrg#panel#tree#redraw()
    endif
    call popup_show(l:s.popups.tree)
    call skyrg#panel#set_pane(l:c.PANE_TREE)
  else
    call popup_hide(l:s.popups.tree)
    call skyrg#panel#set_pane(l:c.PANE_FORM)
  endif
  call skyrg#panel#reposition_popups()
endfunction

function! skyrg#panel#tree#init() abort
  let l:t = skyrg#panel#state().tree
  let l:t.expanded = {}
  let l:t.idx = 0
  call s:rebuild()
endfunction

"==============================================================================
" Directory listing
"==============================================================================
function! s:tree_ls(dir) abort
  let l:raw = globpath(a:dir, '*', 0, 1) + globpath(a:dir, '.*', 0, 1)
  let l:dirs = []
  let l:files = []
  for l:p in l:raw
    let l:name = fnamemodify(l:p, ':t')
    if l:name ==# '.' || l:name ==# '..' | continue | endif
    if l:name ==# '.git' | continue | endif
    if isdirectory(l:p)
      call add(l:dirs, l:p)
    else
      call add(l:files, l:p)
    endif
  endfor
  call sort(l:dirs) | call sort(l:files)
  return s:TREE_SHOW_FILES ? l:dirs + l:files : l:dirs
endfunction

"==============================================================================
" Tree data model — build flat node list from expanded state
"==============================================================================
" Each node: {'path': abs_path, 'depth': int, 'is_dir': bool, 'name': str}
function! s:rebuild() abort
  let l:t = skyrg#panel#state().tree
  let l:root = getcwd()
  let l:t.nodes = []
  call s:walk(l:root, 0)
  if l:t.idx >= len(l:t.nodes)
    let l:t.idx = max([0, len(l:t.nodes) - 1])
  endif
  call skyrg#panel#tree#redraw()
endfunction

function! s:walk(dir, depth) abort
  let l:t = skyrg#panel#state().tree
  let l:children = s:tree_ls(a:dir)
  let l:expanded_child = ''
  for l:p in l:children
    if has_key(l:t.expanded, l:p)
      let l:expanded_child = l:p
      break
    endif
  endfor
  if !empty(l:expanded_child)
    let l:is_dir = isdirectory(l:expanded_child)
    call add(l:t.nodes, {
      \ 'path': l:expanded_child, 'depth': a:depth,
      \ 'is_dir': l:is_dir, 'name': fnamemodify(l:expanded_child, ':t')})
    if l:is_dir
      call s:walk(l:expanded_child, a:depth + 1)
    endif
  else
    let l:filt = l:t.filter
    let l:matched = 0
    for l:p in l:children
      let l:name = fnamemodify(l:p, ':t')
      if !empty(l:filt) && !s:match(l:name, l:filt)
        continue
      endif
      let l:is_dir = isdirectory(l:p)
      call add(l:t.nodes, {
        \ 'path': l:p, 'depth': a:depth,
        \ 'is_dir': l:is_dir, 'name': l:name})
      let l:matched += 1
    endfor
    let l:t.no_matches = (!empty(l:filt) && l:matched == 0)
  endif
endfunction

"==============================================================================
" Helpers
"==============================================================================
function! s:deepest_parent() abort
  let l:t = skyrg#panel#state().tree
  let l:best = -1
  for l:i in range(len(l:t.nodes))
    if has_key(l:t.expanded, l:t.nodes[l:i].path)
      let l:best = l:i
    endif
  endfor
  return l:best
endfunction

function! s:matching_indices() abort
  let l:t = skyrg#panel#state().tree
  let l:result = []
  let l:leaf_depth = -1
  for l:n in l:t.nodes
    if !has_key(l:t.expanded, l:n.path)
      let l:leaf_depth = l:n.depth
      break
    endif
  endfor
  if l:leaf_depth < 0 | return l:result | endif
  for l:i in range(len(l:t.nodes))
    let l:n = l:t.nodes[l:i]
    if l:n.depth == l:leaf_depth && !has_key(l:t.expanded, l:n.path)
      call add(l:result, l:i)
    endif
  endfor
  return l:result
endfunction

function! s:match(name, filt) abort
  if s:TREE_SEARCH_MODE == s:TREE_SEARCH_NORMAL
    return a:name[:len(a:filt)-1] ==? a:filt
  else
    return a:name =~? a:filt
  endif
endfunction

function! s:rebuild_and_select_first() abort
  let l:t = skyrg#panel#state().tree
  call s:rebuild()
  let l:matches = s:matching_indices()
  if !empty(l:matches)
    let l:t.idx = l:matches[0]
  else
    let l:pi = s:deepest_parent()
    if l:pi >= 0
      let l:t.idx = l:pi
    endif
  endif
  call skyrg#panel#tree#redraw()
endfunction

" Expand a directory node and move cursor to first child
function! s:expand_node(node) abort
  let l:t = skyrg#panel#state().tree
  let l:t.filter = ''
  let l:t.tab_mode = 0
  let l:t.expanded[a:node.path] = 1
  call s:rebuild()
  for l:i in range(len(l:t.nodes))
    if l:t.nodes[l:i].path ==# a:node.path
      let l:t.idx = l:i
      if l:i + 1 < len(l:t.nodes)
            \ && l:t.nodes[l:i + 1].depth > l:t.nodes[l:i].depth
        let l:t.idx = l:i + 1
      endif
      break
    endif
  endfor
  call skyrg#panel#tree#redraw()
endfunction

" Collapse a directory node and keep cursor on it
function! s:collapse_node(node) abort
  let l:t = skyrg#panel#state().tree
  let l:t.filter = ''
  let l:t.tab_mode = 0
  call remove(l:t.expanded, a:node.path)
  call s:rebuild()
  for l:i in range(len(l:t.nodes))
    if l:t.nodes[l:i].path ==# a:node.path
      let l:t.idx = l:i
      break
    endif
  endfor
  call skyrg#panel#tree#redraw()
endfunction

"==============================================================================
" Rendering
"==============================================================================
function! s:add_line(lines, idx) abort
  let l:t = skyrg#panel#state().tree
  let l:n = l:t.nodes[a:idx]
  let l:indent = repeat('  ', l:n.depth)
  let l:icon = l:n.is_dir ? (has_key(l:t.expanded, l:n.path) ? '▼ ' : '▶ ') : '  '
  let l:text = l:indent . l:icon . l:n.name . (l:n.is_dir ? '/' : '')
  call add(a:lines, a:idx == l:t.idx
    \ ? skyrg#panel#util#hl_line(l:text, 'skyrg_sel')
    \ : skyrg#panel#util#line(l:text))
endfunction

function! s:render_searchbar(lines, L) abort
  let l:t = skyrg#panel#state().tree
  let l:filt = l:t.filter
  if l:t.tab_mode
    let l:bar = ' >' . l:filt
    call add(a:lines, {'text': l:bar, 'props': [
      \ {'col': 1, 'length': 2, 'type': 'skyrg_dim'}]})
  else
    let l:bar = ' >' . l:filt
    let l:cpos = len(l:bar) + 1
    call add(a:lines, {'text': l:bar . ' ', 'props': [
      \ {'col': 1, 'length': 2, 'type': 'skyrg_dim'},
      \ {'col': l:cpos, 'length': 1, 'type': 'skyrg_cursor'}]})
  endif
  call add(a:lines, skyrg#panel#util#hl_line(repeat('─', a:L.tw - 2), 'skyrg_dim'))
endfunction

function! skyrg#panel#tree#redraw() abort
  let l:s = skyrg#panel#state()
  let l:t = l:s.tree
  if !l:s.popups.tree | return | endif
  let l:L = skyrg#panel#get_layout()
  let l:vis = l:L.th - 4
  let l:lines = []
  call s:render_searchbar(l:lines, l:L)
  call add(l:lines, skyrg#panel#util#hl_line(' ' . getcwd(), 'skyrg_dim'))
  if l:t.no_matches || empty(l:t.nodes)
    for l:i in range(len(l:t.nodes))
      call s:add_line(l:lines, l:i)
    endfor
    call add(l:lines, skyrg#panel#util#hl_line('     (no matches)', 'skyrg_dim'))
    call popup_settext(l:s.popups.tree, l:lines)
    let l:pi = s:deepest_parent()
    if l:pi >= 0
      let l:t.idx = l:pi
      let l:rel = fnamemodify(l:t.nodes[l:pi].path, ':.')
      call popup_setoptions(l:s.popups.tree, {'title': ' '.l:rel.' '})
    else
      call popup_setoptions(l:s.popups.tree, {'title': ' Tree '})
    endif
    return
  endif
  let l:sel_depth = l:t.nodes[l:t.idx].depth
  let l:ancestors = []
  if l:sel_depth > 0
    let l:d = l:sel_depth
    for l:j in range(l:t.idx - 1, 0, -1)
      if l:t.nodes[l:j].depth < l:d
        call insert(l:ancestors, l:j)
        let l:d = l:t.nodes[l:j].depth
      endif
      if l:d == 0 | break | endif
    endfor
  endif
  let l:sib_start = -1
  let l:sib_end = -1
  if empty(l:ancestors)
    let l:sib_start = 0
    let l:sib_end = len(l:t.nodes) - 1
  else
    let l:parent_idx = l:ancestors[-1]
    let l:sib_start = l:parent_idx + 1
    let l:sib_end = len(l:t.nodes) - 1
    for l:j in range(l:sib_start, len(l:t.nodes) - 1)
      if l:t.nodes[l:j].depth < l:sel_depth
        let l:sib_end = l:j - 1
        break
      endif
    endfor
  endif
  for l:ai in l:ancestors
    call s:add_line(l:lines, l:ai)
  endfor
  let l:sib_vis = l:vis - len(l:ancestors)
  let l:sib_scroll = get(l:t, 'scroll', l:sib_start)
  let l:sib_scroll = max([l:sib_start, min([l:sib_scroll, l:sib_end])])
  if l:t.idx < l:sib_scroll
    let l:sib_scroll = l:t.idx
  elseif l:t.idx >= l:sib_scroll + l:sib_vis
    let l:sib_scroll = l:t.idx - l:sib_vis + 1
  endif
  let l:sib_scroll = max([l:sib_start, l:sib_scroll])
  let l:t.scroll = l:sib_scroll
  for l:i in range(l:sib_scroll, min([l:sib_scroll + l:sib_vis - 1, l:sib_end]))
    call s:add_line(l:lines, l:i)
  endfor
  call popup_settext(l:s.popups.tree, l:lines)
  let l:node = l:t.nodes[l:t.idx]
  let l:rel = fnamemodify(l:node.path, ':.')
  call popup_setoptions(l:s.popups.tree, {'title': ' '.l:rel.' '})
endfunction

"==============================================================================
" Key handling
"==============================================================================
function! skyrg#panel#tree#on_key(key) abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  let l:t = l:s.tree
  " --- Backspace ---
  if a:key ==# "\<BS>" || a:key ==# "\<Del>" || a:key ==# nr2char(127)
    if l:t.tab_mode
      let l:t.tab_mode = 0
      let l:t.filter = l:t.tab_base
      call s:rebuild_and_select_first()
    elseif !empty(l:t.filter)
      let l:t.filter = l:t.filter[:-2]
      call s:rebuild_and_select_first()
    endif
    return 1
  endif
  " --- Ctrl+U: clear filter ---
  if a:key ==# "\<C-u>"
    let l:t.filter = ''
    let l:t.tab_mode = 0
    call s:rebuild_and_select_first()
    return 1
  endif
  " --- Tab / S-Tab: tab completion mode ---
  if a:key ==# "\<Tab>" || a:key ==# "\<S-Tab>"
    let l:matches = s:matching_indices()
    if empty(l:matches) | return 1 | endif
    if !l:t.tab_mode
      let l:t.tab_mode = 1
      let l:t.tab_base = l:t.filter
    endif
    let l:cur = index(l:matches, l:t.idx)
    if a:key ==# "\<Tab>"
      let l:next = l:cur < 0 ? 0 : (l:cur + 1) % len(l:matches)
    else
      let l:next = l:cur <= 0 ? len(l:matches) - 1 : l:cur - 1
    endif
    let l:t.idx = l:matches[l:next]
    let l:t.filter = l:t.nodes[l:t.idx].name
    call skyrg#panel#tree#redraw()
    return 1
  endif
  " --- Right: expand selected folder ---
  if a:key ==# "\<Right>"
    if !empty(l:t.nodes)
      let l:node = l:t.nodes[l:t.idx]
      if l:node.is_dir && !has_key(l:t.expanded, l:node.path)
        call s:expand_node(l:node)
      endif
    endif
    return 1
  endif
  " --- Left: jump to parent ---
  if a:key ==# "\<Left>"
    let l:pi = s:deepest_parent()
    if l:pi >= 0
      let l:t.idx = l:pi
      let l:t.tab_mode = 0
      let l:t.filter = ''
      call skyrg#panel#tree#redraw()
    endif
    return 1
  endif
  " Allow typing even when tree is empty (no matches)
  if empty(l:t.nodes) || l:t.no_matches
    if len(a:key) == 1 && char2nr(a:key) >= 32
      let l:t.tab_mode = 0
      let l:t.filter .= a:key
      call s:rebuild_and_select_first()
    endif
    return 1
  endif
  let l:node = l:t.nodes[l:t.idx]
  " --- Up/Down: navigate ---
  if a:key ==# "\<Up>" || a:key ==# "\<C-Up>"
    let l:t.idx = max([0, l:t.idx - 1])
    let l:t.tab_mode = 0
    call skyrg#panel#tree#redraw()
  elseif a:key ==# "\<Down>" || a:key ==# "\<C-Down>"
    let l:t.idx = min([len(l:t.nodes) - 1, l:t.idx + 1])
    let l:t.tab_mode = 0
    call skyrg#panel#tree#redraw()
  " --- Space: expand or collapse directory ---
  elseif a:key ==# ' '
    if l:node.is_dir
      if has_key(l:t.expanded, l:node.path)
        call s:collapse_node(l:node)
      else
        call s:expand_node(l:node)
      endif
    endif
  " --- Typing: search mode ---
  elseif len(a:key) == 1 && char2nr(a:key) >= 33
    let l:t.tab_mode = 0
    let l:t.filter .= a:key
    call s:rebuild_and_select_first()
  " --- Enter: paste path into Dirs and close tree ---
  elseif a:key ==# "\<CR>"
    let l:rel = fnamemodify(l:node.path, ':.')
    if l:node.is_dir
      let l:rel = l:rel . '/'
    endif
    let l:f = l:s.form.fields[l:c.DIRS]
    let l:f.value = l:rel
    let l:f.pos = len(l:f.value)
    let l:s.form.field = l:c.DIRS
    call skyrg#panel#tree#toggle(0)
    call skyrg#panel#form#redraw()
    call skyrg#panel#search#schedule()
  endif
  return 1
endfunction
