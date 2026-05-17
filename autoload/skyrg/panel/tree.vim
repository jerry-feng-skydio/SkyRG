" autoload/skyrg/panel/tree.vim — Directory tree panel
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
  let l:s.tree_open = a:open
  if a:open
    if empty(l:s.tree_nodes)
      call skyrg#panel#tree#init()
    else
      call skyrg#panel#tree#redraw()
    endif
    call popup_show(l:s.tree_id)
    call skyrg#panel#set_pane(l:c.PANE_TREE)
  else
    call popup_hide(l:s.tree_id)
    call skyrg#panel#set_pane(l:c.PANE_FORM)
  endif
  call skyrg#panel#reposition_popups()
endfunction

function! skyrg#panel#tree#init() abort
  let l:s = skyrg#panel#state()
  let l:s.tree_expanded = {}
  let l:s.tree_idx = 0
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
  let l:s = skyrg#panel#state()
  let l:root = getcwd()
  let l:s.tree_nodes = []
  call s:walk(l:root, 0)
  if l:s.tree_idx >= len(l:s.tree_nodes)
    let l:s.tree_idx = max([0, len(l:s.tree_nodes) - 1])
  endif
  call skyrg#panel#tree#redraw()
endfunction

function! s:walk(dir, depth) abort
  let l:s = skyrg#panel#state()
  let l:children = s:tree_ls(a:dir)
  let l:expanded_child = ''
  for l:p in l:children
    if has_key(l:s.tree_expanded, l:p)
      let l:expanded_child = l:p
      break
    endif
  endfor
  if !empty(l:expanded_child)
    " Only show the expanded child (siblings hidden)
    let l:is_dir = isdirectory(l:expanded_child)
    call add(l:s.tree_nodes, {
      \ 'path': l:expanded_child, 'depth': a:depth,
      \ 'is_dir': l:is_dir, 'name': fnamemodify(l:expanded_child, ':t')})
    if l:is_dir
      call s:walk(l:expanded_child, a:depth + 1)
    endif
  else
    " Leaf level: filter children by tree_filter
    let l:filt = get(l:s, 'tree_filter', '')
    let l:matched = 0
    for l:p in l:children
      let l:name = fnamemodify(l:p, ':t')
      if !empty(l:filt) && !s:match(l:name, l:filt)
        continue
      endif
      let l:is_dir = isdirectory(l:p)
      call add(l:s.tree_nodes, {
        \ 'path': l:p, 'depth': a:depth,
        \ 'is_dir': l:is_dir, 'name': l:name})
      let l:matched += 1
    endfor
    let l:s.tree_no_matches = (!empty(l:filt) && l:matched == 0)
  endif
endfunction

"==============================================================================
" Helpers
"==============================================================================
function! s:deepest_parent() abort
  let l:s = skyrg#panel#state()
  let l:best = -1
  for l:i in range(len(l:s.tree_nodes))
    if has_key(l:s.tree_expanded, l:s.tree_nodes[l:i].path)
      let l:best = l:i
    endif
  endfor
  return l:best
endfunction

function! s:matching_indices() abort
  let l:s = skyrg#panel#state()
  let l:result = []
  let l:leaf_depth = -1
  for l:n in l:s.tree_nodes
    if !has_key(l:s.tree_expanded, l:n.path)
      let l:leaf_depth = l:n.depth
      break
    endif
  endfor
  if l:leaf_depth < 0 | return l:result | endif
  for l:i in range(len(l:s.tree_nodes))
    let l:n = l:s.tree_nodes[l:i]
    if l:n.depth == l:leaf_depth && !has_key(l:s.tree_expanded, l:n.path)
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
  let l:s = skyrg#panel#state()
  call s:rebuild()
  let l:matches = s:matching_indices()
  if !empty(l:matches)
    let l:s.tree_idx = l:matches[0]
  else
    let l:pi = s:deepest_parent()
    if l:pi >= 0
      let l:s.tree_idx = l:pi
    endif
  endif
  call skyrg#panel#tree#redraw()
endfunction

" Expand a directory node and move cursor to first child
function! s:expand_node(node) abort
  let l:s = skyrg#panel#state()
  let l:s.tree_filter = ''
  let l:s.tree_tab_mode = 0
  let l:s.tree_expanded[a:node.path] = 1
  call s:rebuild()
  for l:i in range(len(l:s.tree_nodes))
    if l:s.tree_nodes[l:i].path ==# a:node.path
      let l:s.tree_idx = l:i
      if l:i + 1 < len(l:s.tree_nodes)
            \ && l:s.tree_nodes[l:i + 1].depth > l:s.tree_nodes[l:i].depth
        let l:s.tree_idx = l:i + 1
      endif
      break
    endif
  endfor
  call skyrg#panel#tree#redraw()
endfunction

" Collapse a directory node and keep cursor on it
function! s:collapse_node(node) abort
  let l:s = skyrg#panel#state()
  let l:s.tree_filter = ''
  let l:s.tree_tab_mode = 0
  call remove(l:s.tree_expanded, a:node.path)
  call s:rebuild()
  for l:i in range(len(l:s.tree_nodes))
    if l:s.tree_nodes[l:i].path ==# a:node.path
      let l:s.tree_idx = l:i
      break
    endif
  endfor
  call skyrg#panel#tree#redraw()
endfunction

"==============================================================================
" Rendering
"==============================================================================
function! s:add_line(lines, idx) abort
  let l:s = skyrg#panel#state()
  let l:n = l:s.tree_nodes[a:idx]
  let l:indent = repeat('  ', l:n.depth)
  let l:icon = l:n.is_dir ? (has_key(l:s.tree_expanded, l:n.path) ? '▼ ' : '▶ ') : '  '
  let l:text = l:indent . l:icon . l:n.name . (l:n.is_dir ? '/' : '')
  if a:idx == l:s.tree_idx
    call add(a:lines, {'text': l:text, 'props': [
      \ {'col': 1, 'length': len(l:text), 'type': 'skyrg_sel'}]})
  else
    call add(a:lines, {'text': l:text})
  endif
endfunction

function! s:render_searchbar(lines, L) abort
  let l:s = skyrg#panel#state()
  let l:filt = get(l:s, 'tree_filter', '')
  if l:s.tree_tab_mode
    let l:bar = ' >' . l:filt
    call add(a:lines, {'text': l:bar})
  else
    let l:bar = ' >' . l:filt
    let l:cpos = len(l:bar) + 1
    call add(a:lines, {'text': l:bar . ' ', 'props': [
      \ {'col': l:cpos, 'length': 1, 'type': 'skyrg_cursor'}]})
  endif
  call add(a:lines, {'text': repeat('─', a:L.tw - 2)})
endfunction

function! skyrg#panel#tree#redraw() abort
  let l:s = skyrg#panel#state()
  if !l:s.tree_id | return | endif
  let l:L = skyrg#panel#get_layout()
  " Search bar (2 lines) + project root (1 line) at top = 3 fixed lines
  let l:vis = l:L.th - 4
  let l:lines = []
  " 1. Search bar at top
  call s:render_searchbar(l:lines, l:L)
  " 2. Project root
  call add(l:lines, {'text': ' ' . getcwd()})
  " Handle no-matches: show parent selected + "(no matches)" hint
  if l:s.tree_no_matches || empty(l:s.tree_nodes)
    for l:i in range(len(l:s.tree_nodes))
      call s:add_line(l:lines, l:i)
    endfor
    call add(l:lines, {'text': '     (no matches)'})
    call popup_settext(l:s.tree_id, l:lines)
    let l:pi = s:deepest_parent()
    if l:pi >= 0
      let l:s.tree_idx = l:pi
      let l:rel = fnamemodify(l:s.tree_nodes[l:pi].path, ':.')
      call popup_setoptions(l:s.tree_id, {'title': ' '.l:rel.' '})
    else
      call popup_setoptions(l:s.tree_id, {'title': ' Tree '})
    endif
    return
  endif
  " Split rendering: pinned ancestors + scrollable siblings
  let l:sel_depth = l:s.tree_nodes[l:s.tree_idx].depth
  let l:ancestors = []
  if l:sel_depth > 0
    let l:d = l:sel_depth
    for l:j in range(l:s.tree_idx - 1, 0, -1)
      if l:s.tree_nodes[l:j].depth < l:d
        call insert(l:ancestors, l:j)
        let l:d = l:s.tree_nodes[l:j].depth
      endif
      if l:d == 0 | break | endif
    endfor
  endif
  let l:sib_start = -1
  let l:sib_end = -1
  if empty(l:ancestors)
    let l:sib_start = 0
    let l:sib_end = len(l:s.tree_nodes) - 1
  else
    let l:parent_idx = l:ancestors[-1]
    let l:sib_start = l:parent_idx + 1
    let l:sib_end = len(l:s.tree_nodes) - 1
    for l:j in range(l:sib_start, len(l:s.tree_nodes) - 1)
      if l:s.tree_nodes[l:j].depth < l:sel_depth
        let l:sib_end = l:j - 1
        break
      endif
    endfor
  endif
  for l:ai in l:ancestors
    call s:add_line(l:lines, l:ai)
  endfor
  let l:sib_vis = l:vis - len(l:ancestors)
  let l:sib_scroll = get(l:s, 'tree_scroll', l:sib_start)
  let l:sib_scroll = max([l:sib_start, min([l:sib_scroll, l:sib_end])])
  if l:s.tree_idx < l:sib_scroll
    let l:sib_scroll = l:s.tree_idx
  elseif l:s.tree_idx >= l:sib_scroll + l:sib_vis
    let l:sib_scroll = l:s.tree_idx - l:sib_vis + 1
  endif
  let l:sib_scroll = max([l:sib_start, l:sib_scroll])
  let l:s.tree_scroll = l:sib_scroll
  for l:i in range(l:sib_scroll, min([l:sib_scroll + l:sib_vis - 1, l:sib_end]))
    call s:add_line(l:lines, l:i)
  endfor
  call popup_settext(l:s.tree_id, l:lines)
  let l:node = l:s.tree_nodes[l:s.tree_idx]
  let l:rel = fnamemodify(l:node.path, ':.')
  call popup_setoptions(l:s.tree_id, {'title': ' '.l:rel.' '})
endfunction

"==============================================================================
" Key handling
"==============================================================================
function! skyrg#panel#tree#on_key(key) abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  " --- Backspace ---
  if a:key ==# "\<BS>" || a:key ==# "\<Del>" || a:key ==# nr2char(127)
    if l:s.tree_tab_mode
      let l:s.tree_tab_mode = 0
      let l:s.tree_filter = l:s.tree_tab_base
      call s:rebuild_and_select_first()
    elseif !empty(l:s.tree_filter)
      let l:s.tree_filter = l:s.tree_filter[:-2]
      call s:rebuild_and_select_first()
    endif
    return 1
  endif
  " --- Ctrl+U: clear filter ---
  if a:key ==# "\<C-u>"
    let l:s.tree_filter = ''
    let l:s.tree_tab_mode = 0
    call s:rebuild_and_select_first()
    return 1
  endif
  " --- Tab / S-Tab: tab completion mode ---
  if a:key ==# "\<Tab>" || a:key ==# "\<S-Tab>"
    let l:matches = s:matching_indices()
    if empty(l:matches) | return 1 | endif
    if !l:s.tree_tab_mode
      let l:s.tree_tab_mode = 1
      let l:s.tree_tab_base = l:s.tree_filter
    endif
    let l:cur = index(l:matches, l:s.tree_idx)
    if a:key ==# "\<Tab>"
      let l:next = l:cur < 0 ? 0 : (l:cur + 1) % len(l:matches)
    else
      let l:next = l:cur <= 0 ? len(l:matches) - 1 : l:cur - 1
    endif
    let l:s.tree_idx = l:matches[l:next]
    let l:s.tree_filter = l:s.tree_nodes[l:s.tree_idx].name
    call skyrg#panel#tree#redraw()
    return 1
  endif
  " --- Right: expand selected folder ---
  if a:key ==# "\<Right>"
    let l:nodes = l:s.tree_nodes
    if !empty(l:nodes)
      let l:node = l:nodes[l:s.tree_idx]
      if l:node.is_dir && !has_key(l:s.tree_expanded, l:node.path)
        call s:expand_node(l:node)
      endif
    endif
    return 1
  endif
  " --- Left: jump to parent ---
  if a:key ==# "\<Left>"
    let l:pi = s:deepest_parent()
    if l:pi >= 0
      let l:s.tree_idx = l:pi
      let l:s.tree_tab_mode = 0
      let l:s.tree_filter = ''
      call skyrg#panel#tree#redraw()
    endif
    return 1
  endif
  let l:nodes = l:s.tree_nodes
  " Allow typing even when tree is empty (no matches)
  if empty(l:nodes) || l:s.tree_no_matches
    if len(a:key) == 1 && char2nr(a:key) >= 32
      let l:s.tree_tab_mode = 0
      let l:s.tree_filter .= a:key
      call s:rebuild_and_select_first()
    endif
    return 1
  endif
  let l:node = l:nodes[l:s.tree_idx]
  " --- Up/Down: navigate ---
  if a:key ==# "\<Up>" || a:key ==# "\<C-Up>"
    let l:s.tree_idx = max([0, l:s.tree_idx - 1])
    let l:s.tree_tab_mode = 0
    call skyrg#panel#tree#redraw()
  elseif a:key ==# "\<Down>" || a:key ==# "\<C-Down>"
    let l:s.tree_idx = min([len(l:nodes) - 1, l:s.tree_idx + 1])
    let l:s.tree_tab_mode = 0
    call skyrg#panel#tree#redraw()
  " --- Space: expand or collapse directory ---
  elseif a:key ==# ' '
    if l:node.is_dir
      if has_key(l:s.tree_expanded, l:node.path)
        call s:collapse_node(l:node)
      else
        call s:expand_node(l:node)
      endif
    endif
  " --- Typing: search mode ---
  elseif len(a:key) == 1 && char2nr(a:key) >= 33
    let l:s.tree_tab_mode = 0
    let l:s.tree_filter .= a:key
    call s:rebuild_and_select_first()
  " --- Enter: paste path into Dirs and close tree ---
  elseif a:key ==# "\<CR>"
    let l:rel = fnamemodify(l:node.path, ':.')
    if l:node.is_dir
      let l:rel = l:rel . '/'
    endif
    let l:f = l:s.fields[l:c.DIRS]
    let l:f.value = l:rel
    let l:f.pos = len(l:f.value)
    let l:s.field = l:c.DIRS
    call skyrg#panel#tree#toggle(0)
    call skyrg#panel#form#redraw()
    call skyrg#panel#search#schedule()
  endif
  return 1
endfunction
