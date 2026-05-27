" autoload/skyrg/revup.vim — Revup topic chain viewer
"
" Shows a popup with the current branch's revup topic chain.
" Select a topic to insert Topic: or Relative: tags at cursor.
"
" Keybindings:
"   Up/Down   — navigate topics
"   Enter     — insert 'Topic: <name>' at cursor
"   r         — insert 'Relative: <name>' at cursor
"   Esc       — close

let s:script_dir = expand('<sfile>:p:h')
let s:py_script = s:script_dir . '/revup_topics.py'

" Popup state
let s:popup_id = 0
let s:topics = []
let s:tree_nodes = []
let s:sel_idx = 0

"==============================================================================
" Public API
"==============================================================================
function! skyrg#revup#show() abort
  if !exists('*popup_create')
    echohl ErrorMsg | echo '[SkyRG] Requires Vim 8.2+ with +popupwin' | echohl None
    return
  endif

  " Run the Python helper to get topic data
  let l:cmd = 'python3 ' . shellescape(s:py_script)
  let l:raw = system(l:cmd)
  if v:shell_error
    echohl ErrorMsg | echo '[SkyRG Revup] Failed to run topic parser: ' . l:raw | echohl None
    return
  endif

  let l:data = json_decode(l:raw)
  if type(l:data) != v:t_dict
    echohl ErrorMsg | echo '[SkyRG Revup] Invalid JSON from topic parser' | echohl None
    return
  endif

  if !empty(get(l:data, 'error', ''))
    echohl ErrorMsg | echo '[SkyRG Revup] ' . l:data.error | echohl None
    return
  endif

  let s:topics = get(l:data, 'topics', [])
  if empty(s:topics)
    echohl WarningMsg | echo '[SkyRG Revup] No revup topics found in current branch' | echohl None
    return
  endif

  " Build tree nodes (flatten with depth for display)
  let s:tree_nodes = s:build_tree()
  let s:sel_idx = 0

  " Ensure highlight group and prop types exist
  if !hlexists('SkyRGSel') || empty(execute('hi SkyRGSel'))
    highlight SkyRGSel cterm=bold ctermfg=Yellow ctermbg=DarkBlue gui=bold guifg=#FFD700 guibg=#1C3A5F
  endif
  silent! call prop_type_delete('skyrg_revup_sel')
  silent! call prop_type_delete('skyrg_revup_dim')
  call prop_type_add('skyrg_revup_sel', {'highlight': 'SkyRGSel'})
  call prop_type_add('skyrg_revup_dim', {'highlight': 'Comment'})

  " Calculate popup size
  let l:W = &columns | let l:H = &lines
  let l:pw = min([max([s:max_line_width() + 6, 40]), l:W - 6])
  let l:ph = min([len(s:tree_nodes) + 2, l:H - 6])

  let l:bch = ['─','│','─','│','╭','╮','╯','╰']
  let l:base = get(l:data, 'base_branch', '')
  let l:title = ' Revup Topics (' . l:base . ') '

  let s:popup_id = popup_create(s:render(), {
    \ 'title': l:title,
    \ 'border': [], 'borderchars': l:bch,
    \ 'highlight': 'Normal',
    \ 'borderhighlight': ['Title'],
    \ 'padding': [0,1,0,1],
    \ 'line': 3,
    \ 'col': max([(l:W - l:pw) / 2, 1]),
    \ 'minwidth': l:pw, 'maxwidth': l:pw,
    \ 'minheight': l:ph, 'maxheight': l:ph,
    \ 'filter': function('s:on_key'),
    \ 'mapping': 0,
    \ 'callback': function('s:on_close'),
    \ 'zindex': 300,
    \ })
endfunction

"==============================================================================
" Tree building
"==============================================================================

" Build a flat list of {name, depth, commits, title, relative} for display.
" Root topics (no relative) are at depth 0; children are nested.
function! s:build_tree() abort
  " Index topics by name
  let l:by_name = {}
  for l:t in s:topics
    let l:by_name[l:t.name] = l:t
  endfor

  " Find children for each topic
  let l:children = {}
  let l:roots = []
  for l:t in s:topics
    let l:rel = get(l:t, 'relative', v:null)
    if l:rel is v:null || l:rel ==# '' || !has_key(l:by_name, l:rel)
      call add(l:roots, l:t.name)
    else
      if !has_key(l:children, l:rel)
        let l:children[l:rel] = []
      endif
      call add(l:children[l:rel], l:t.name)
    endif
  endfor

  " DFS to build flat node list
  let l:nodes = []
  for l:root in l:roots
    call s:walk_tree(l:root, 0, l:by_name, l:children, l:nodes)
  endfor

  return l:nodes
endfunction

function! s:walk_tree(name, depth, by_name, children, nodes) abort
  let l:t = a:by_name[a:name]
  let l:rel = get(l:t, 'relative', v:null)
  call add(a:nodes, {
    \ 'name': a:name,
    \ 'depth': a:depth,
    \ 'commits': l:t.commits,
    \ 'title': l:t.title,
    \ 'relative': (l:rel is v:null || l:rel ==# '') ? '' : l:rel,
    \ })
  if has_key(a:children, a:name)
    for l:child in a:children[a:name]
      call s:walk_tree(l:child, a:depth + 1, a:by_name, a:children, a:nodes)
    endfor
  endif
endfunction

"==============================================================================
" Rendering
"==============================================================================
function! s:render() abort
  let l:lines = []
  " Header line
  call add(l:lines, {'text': '  Enter=Topic  r=Relative  Esc=Close', 'props': [
    \ {'col': 1, 'length': 37, 'type': 'skyrg_revup_dim'}]})

  for l:i in range(len(s:tree_nodes))
    let l:node = s:tree_nodes[l:i]
    let l:indent = repeat('  ', l:node.depth)
    let l:marker = l:i == s:sel_idx ? '▸ ' : '  '
    let l:commits_str = l:node.commits == 1 ? '1 commit' : l:node.commits . ' commits'
    let l:text = l:indent . l:marker . l:node.name
    let l:meta = '  (' . l:commits_str . ')'
    let l:full = l:text . l:meta

    if l:i == s:sel_idx
      call add(l:lines, {'text': l:full, 'props': [
        \ {'col': 1, 'length': len(l:full), 'type': 'skyrg_revup_sel'}]})
    else
      call add(l:lines, {'text': l:full, 'props': [
        \ {'col': len(l:text) + 1, 'length': len(l:meta), 'type': 'skyrg_revup_dim'}]})
    endif
  endfor

  return l:lines
endfunction

function! s:max_line_width() abort
  let l:max = 20
  for l:node in s:tree_nodes
    let l:w = l:node.depth * 2 + 2 + len(l:node.name) + len(string(l:node.commits)) + 12
    if l:w > l:max | let l:max = l:w | endif
  endfor
  return l:max
endfunction

function! s:redraw() abort
  if s:popup_id
    call popup_settext(s:popup_id, s:render())
  endif
endfunction

"==============================================================================
" Key handling
"==============================================================================
function! s:on_key(winid, key) abort
  if a:key ==# "\<Esc>"
    call popup_close(a:winid)
    return 1
  endif

  if a:key ==# "\<Up>" || a:key ==# 'k'
    let s:sel_idx = max([0, s:sel_idx - 1])
    call s:redraw()
    return 1
  endif

  if a:key ==# "\<Down>" || a:key ==# 'j'
    let s:sel_idx = min([len(s:tree_nodes) - 1, s:sel_idx + 1])
    call s:redraw()
    return 1
  endif

  " Enter: insert Topic: tag at cursor
  if a:key ==# "\<CR>"
    let l:name = s:tree_nodes[s:sel_idx].name
    call popup_close(a:winid)
    call s:insert_or_replace('Topic: ' . l:name)
    return 1
  endif

  " r: insert Relative: tag at cursor
  if a:key ==# 'r'
    let l:name = s:tree_nodes[s:sel_idx].name
    call popup_close(a:winid)
    call s:insert_or_replace('Relative: ' . l:name)
    return 1
  endif

  return 1
endfunction

function! s:on_close(id, result) abort
  silent! call prop_type_delete('skyrg_revup_sel')
  silent! call prop_type_delete('skyrg_revup_dim')
  let s:popup_id = 0
endfunction

"==============================================================================
" Text insertion
"==============================================================================

" Extract the tag name (e.g. 'Topic' or 'Relative') from a tag line.
function! s:tag_name(text) abort
  return matchstr(a:text, '^\S\+\ze:')
endfunction

function! s:insert_or_replace(text) abort
  let l:tag = s:tag_name(a:text)
  let l:pattern = '^\c' . l:tag . ':.*$'

  " Scan the entire buffer for an existing line with this tag
  for l:i in range(1, line('$'))
    if getline(l:i) =~# l:pattern
      call setline(l:i, a:text)
      call cursor(l:i, len(a:text))
      return
    endif
  endfor

  " No existing tag found — insert at cursor
  let l:line = line('.')
  let l:cur = getline(l:line)
  if l:cur =~# '^\s*$'
    call setline(l:line, a:text)
    call cursor(l:line, len(a:text))
  else
    call append(l:line, a:text)
    call cursor(l:line + 1, len(a:text))
  endif
endfunction
