" autoload/skyrg/panel.vim — Multi-pane search UI (entry point + shared state)
"
" Architecture:
"   panel.vim owns the shared state dict (s:state) and popup lifecycle.
"   Submodules access state via skyrg#panel#state() and constants via
"   skyrg#panel#const().  Each submodule owns a namespaced sub-dict:
"
"     s:state.popups   — popup window IDs (form_id, results_id, etc.)
"     s:state.tree     — tree panel state (idx, nodes, expanded, filter, etc.)
"     s:state.results  — search results (matches, result_idx, res_scroll)
"     s:state.form     — form state (field index, fields array)
"     s:state.search   — rg job state (search_gen, pending, job, timer)
"
"   This namespacing prevents key collisions and makes ownership explicit.
"
" Design patterns:
"   1. Prep/Render separation: panels split data preparation (file I/O,
"      filtering, syntax analysis) from rendering (building popup lines).
"      Swap the prep step to add features without touching rendering.
"   2. Line builders: util#line() and util#hl_line() standardize popup
"      line dict construction across all panels.
"   3. State accessors: submodules never access s:state directly; they
"      call skyrg#panel#state() to get a reference. This makes
"      dependencies explicit and keeps the door open for validation.
"
" Submodules under panel/:
"   tree.vim      — directory tree (owns state.tree)
"   form.vim      — form rendering + keys (owns state.form)
"   results.vim   — results list (owns state.results)
"   preview.vim   — file preview with syntax highlighting
"   search.vim    — async rg job (owns state.search)
"   preset.vim    — preset management
"   complete.vim  — dir/type tab-completion
"   util.vim      — shared line builders + helpers

"==============================================================================
" Constants (shared via skyrg#panel#const())
"==============================================================================
let s:const = {
  \ 'QUERY': 0, 'DIRS': 1, 'TYPES': 2, 'PRESET': 3, 'GITIGN': 4,
  \ 'NFIELDS': 5,
  \ 'PANE_FORM': 0, 'PANE_RESULTS': 1, 'PANE_TREE': 2,
  \ 'MODE_SEARCH': 'search', 'MODE_BROWSE': 'browse',
  \ }

highlight SkyRGSel cterm=bold ctermfg=Yellow ctermbg=DarkBlue gui=bold guifg=#FFD700 guibg=#1C3A5F

"==============================================================================
" State accessors (used by all submodules)
"==============================================================================
function! skyrg#panel#state() abort
  return s:state
endfunction

function! skyrg#panel#const() abort
  return s:const
endfunction

function! skyrg#panel#get_layout() abort
  return s:layout()
endfunction

function! skyrg#panel#close() abort
  call s:close()
endfunction

function! skyrg#panel#set_pane(p) abort
  call s:set_pane(a:p)
endfunction

function! skyrg#panel#reposition_popups() abort
  call s:reposition_popups()
endfunction

"==============================================================================
" Open
"==============================================================================
function! skyrg#panel#open() abort
  if !exists('*popup_create') || !exists('*job_start')
    echohl ErrorMsg | echo '[SkyRG] Requires Vim 8.2+ with +popupwin +job' | echohl None
    return
  endif
  let l:c = s:const
  let s:state = {
    \ 'mode': l:c.MODE_SEARCH, 'pane': l:c.PANE_FORM, 'closing': 0,
    \ 'popups': {'form': 0, 'results': 0, 'preview': 0, 'tree': 0},
    \ 'form': {
    \   'field': l:c.QUERY,
    \   'fields': [
    \     {'label': 'Query',  'value': '', 'pos': 0},
    \     {'label': 'Dirs',   'value': '', 'pos': 0},
    \     {'label': 'Types',  'value': '', 'pos': 0},
    \     {'label': 'Preset', 'value': '', 'pos': 0},
    \     {'label': '.gitignore', 'value': 'on', 'pos': 0},
    \   ],
    \ },
    \ 'results': {'matches': [], 'idx': 0, 'scroll': 0},
    \ 'search': {'gen': 0},
    \ 'tree': {
    \   'open': 0, 'idx': 0, 'nodes': [], 'expanded': {},
    \   'filter': '', 'tab_mode': 0, 'tab_base': '', 'no_matches': 0,
    \ },
    \ }
  call s:init_prop_types()
  let l:L = s:layout()
  let l:bch = ['─','│','─','│','╭','╮','╯','╰']
  let s:state.popups.form = popup_create(skyrg#panel#form#render(), {
    \ 'title': ' SkyRG ', 'border': [], 'borderchars': l:bch,
    \ 'borderhighlight': ['Title'], 'padding': [0,1,0,1],
    \ 'line': l:L.fr, 'col': l:L.fc, 'minwidth': l:L.fw, 'maxwidth': l:L.fw,
    \ 'minheight': l:L.fh, 'maxheight': l:L.fh,
    \ 'filter': function('s:on_key'), 'mapping': 0, 'zindex': 200,
    \ 'callback': function('s:on_close'),
    \ })
  let s:state.popups.results = popup_create([{'text': '  No results'}], {
    \ 'title': ' Results ', 'border': [], 'borderchars': l:bch,
    \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1], 'scrollbar': 1,
    \ 'wrap': 0,
    \ 'line': l:L.rr, 'col': l:L.rc, 'minwidth': l:L.rw, 'maxwidth': l:L.rw,
    \ 'minheight': l:L.rh, 'maxheight': l:L.rh, 'zindex': 100,
    \ })
  let s:state.popups.preview = popup_create([{'text': ''}], {
    \ 'title': ' Preview ', 'border': [], 'borderchars': l:bch,
    \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1], 'scrollbar': 1,
    \ 'line': l:L.pr, 'col': l:L.pc, 'minwidth': l:L.pw, 'maxwidth': l:L.pw,
    \ 'minheight': l:L.ph, 'maxheight': l:L.ph, 'zindex': 100,
    \ })
  let s:state.popups.tree = popup_create([{'text': '  (Ctrl+Left to open)'}], {
    \ 'title': ' Tree ', 'border': [], 'borderchars': l:bch,
    \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1], 'scrollbar': 1,
    \ 'line': l:L.tr, 'col': l:L.tc, 'minwidth': l:L.tw, 'maxwidth': l:L.tw,
    \ 'minheight': l:L.th, 'maxheight': l:L.th, 'zindex': 100,
    \ 'hidden': 1,
    \ })
endfunction

"==============================================================================
" Browse mode
"==============================================================================
function! skyrg#panel#browse(matches, title) abort
  if !exists('*popup_create')
    echohl ErrorMsg | echo '[SkyRG] Requires Vim 8.2+ with +popupwin' | echohl None
    return
  endif
  let l:c = s:const
  let s:state = {
    \ 'mode': l:c.MODE_BROWSE,
    \ 'pane': l:c.PANE_RESULTS, 'closing': 0,
    \ 'popups': {'form': 0, 'results': 0, 'preview': 0},
    \ 'form': {'field': 0, 'fields': []},
    \ 'results': {'matches': a:matches, 'idx': 0, 'scroll': 0},
    \ 'search': {'gen': 0},
    \ }
  call s:init_prop_types()
  let l:L = s:layout()
  let l:bch = ['─','│','─','│','╭','╮','╯','╰']
  let s:state.popups.results = popup_create([{'text': '  Loading...'}], {
    \ 'title': ' '.a:title.' ', 'border': [], 'borderchars': l:bch,
    \ 'borderhighlight': ['Title'], 'padding': [0,1,0,1], 'scrollbar': 1,
    \ 'wrap': 0,
    \ 'line': l:L.rr, 'col': l:L.rc, 'minwidth': l:L.rw, 'maxwidth': l:L.rw,
    \ 'minheight': l:L.rh, 'maxheight': l:L.rh,
    \ 'filter': function('s:on_key'), 'mapping': 0, 'zindex': 200,
    \ 'callback': function('s:on_close'),
    \ })
  let s:state.popups.preview = popup_create([{'text': ''}], {
    \ 'title': ' Preview ', 'border': [], 'borderchars': l:bch,
    \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1], 'scrollbar': 1,
    \ 'line': l:L.pr, 'col': l:L.pc, 'minwidth': l:L.pw, 'maxwidth': l:L.pw,
    \ 'minheight': l:L.ph, 'maxheight': l:L.ph, 'zindex': 100,
    \ })
  call skyrg#panel#results#redraw()
  call skyrg#panel#preview#update()
endfunction

function! skyrg#panel#ycm_refs() abort
  try | execute 'YcmCompleter GoToReferences' | catch
    echohl ErrorMsg | echo '[SkyRG] GoToReferences failed: '.v:exception | echohl None | return
  endtry
  cclose
  let l:qf = getqflist()
  if empty(l:qf) | echohl WarningMsg | echo '[SkyRG] No references found' | echohl None | return | endif
  let l:matches = []
  for l:item in l:qf
    let l:file = bufname(l:item.bufnr)
    if empty(l:file) | continue | endif
    call add(l:matches, {'file': fnamemodify(l:file, ':p'), 'line': l:item.lnum,
      \ 'col': l:item.col, 'text': trim(get(l:item, 'text', ''))})
  endfor
  if empty(l:matches) | echohl WarningMsg | echo '[SkyRG] No references found' | echohl None | return | endif
  call skyrg#panel#browse(l:matches, 'References ('.len(l:matches).')')
endfunction

"==============================================================================
" Layout
"==============================================================================
function! s:layout() abort
  let l:W = &columns | let l:H = &lines
  let l:fw = max([l:W - 6, 40])
  let l:c = s:const
  if s:state.mode ==# l:c.MODE_BROWSE
    let l:bh = max([l:H - 4, 6])
    let l:rw = max([float2nr(l:fw * 0.45), 20])
    let l:pw = max([l:fw - l:rw - 2, 20])
    return {'fw':l:fw, 'fh':0, 'fr':0, 'fc':0,
      \ 'rw':l:rw, 'rh':l:bh, 'rr':2, 'rc':3,
      \ 'pw':l:pw, 'ph':l:bh, 'pr':2, 'pc':l:rw+5}
  endif
  let l:fh = 7 | let l:tw = 30
  let l:tree_vis = get(s:state.tree, 'open', 0)
  let l:toff = l:tree_vis ? l:tw + 2 : 0
  let l:fw2 = max([l:fw - l:toff, 40])
  let l:bh = max([l:H - l:fh - 6, 6])
  let l:rw = max([float2nr(l:fw2 * 0.45), 20])
  let l:pw = max([l:fw2 - l:rw - 2, 20])
  let l:fc = 3 + l:toff
  return {'fw':l:fw2, 'fh':l:fh, 'fr':2, 'fc':l:fc,
    \ 'rw':l:rw, 'rh':l:bh, 'rr':l:fh+4, 'rc':l:fc,
    \ 'pw':l:pw, 'ph':l:bh, 'pr':l:fh+4, 'pc':l:fc+l:rw+2,
    \ 'tw':l:tw, 'th':l:H-4, 'tr':2, 'tc':3}
endfunction

"==============================================================================
" Close / prop types
"==============================================================================
let s:syn_groups = ['Comment', 'Constant', 'String', 'Identifier',
  \ 'Function', 'Statement', 'PreProc', 'Type', 'Special', 'Underlined',
  \ 'Error', 'Todo', 'Number', 'Boolean', 'Keyword', 'Operator']

function! s:init_prop_types() abort
  for l:n in ['skyrg_cursor', 'skyrg_sel', 'skyrg_match']
    silent! call prop_type_delete(l:n)
  endfor
  for l:g in s:syn_groups
    silent! call prop_type_delete('skyrg_syn_' . l:g)
  endfor
  let l:hl = hlexists('TermCursor') ? 'TermCursor' : 'Visual'
  call prop_type_add('skyrg_cursor', {'highlight': l:hl})
  call prop_type_add('skyrg_sel',    {'highlight': 'SkyRGSel'})
  call prop_type_add('skyrg_match',  {'highlight': 'Search'})
  for l:g in s:syn_groups
    call prop_type_add('skyrg_syn_' . l:g, {'highlight': l:g})
  endfor
endfunction

function! s:close() abort
  if s:state.closing | return | endif
  let s:state.closing = 1
  if has_key(s:state.search, 'job') && job_status(s:state.search.job) ==# 'run'
    call job_stop(s:state.search.job)
  endif
  if has_key(s:state.search, 'timer') | call timer_stop(s:state.search.timer) | endif
  for l:id in [s:state.popups.form, s:state.popups.results, s:state.popups.preview, get(s:state.popups, 'tree', 0)]
    silent! call popup_close(l:id)
  endfor
  for l:n in ['skyrg_cursor', 'skyrg_sel', 'skyrg_match']
    silent! call prop_type_delete(l:n)
  endfor
  for l:g in s:syn_groups
    silent! call prop_type_delete('skyrg_syn_' . l:g)
  endfor
  " Clean up syntax preview hidden window
  call skyrg#panel#preview#cleanup()
endfunction

function! s:on_close(id, result) abort
  call s:close()
endfunction

"==============================================================================
" Pane management
"==============================================================================
function! s:set_pane(p) abort
  let l:c = s:const
  let s:state.pane = a:p
  if s:state.popups.form
    call popup_setoptions(s:state.popups.form, {'borderhighlight': [a:p == l:c.PANE_FORM ? 'Title' : 'Comment']})
  endif
  call popup_setoptions(s:state.popups.results, {'borderhighlight': [a:p == l:c.PANE_RESULTS ? 'Title' : 'Comment']})
  if get(s:state.popups, 'tree', 0)
    call popup_setoptions(s:state.popups.tree, {'borderhighlight': [a:p == l:c.PANE_TREE ? 'Title' : 'Comment']})
  endif
  if s:state.popups.form | call skyrg#panel#form#redraw() | endif
endfunction

function! s:reposition_popups() abort
  let l:L = s:layout()
  if s:state.popups.form
    call popup_move(s:state.popups.form, {'line': l:L.fr, 'col': l:L.fc, 'minwidth': l:L.fw, 'maxwidth': l:L.fw})
  endif
  call popup_move(s:state.popups.results, {'line': l:L.rr, 'col': l:L.rc, 'minwidth': l:L.rw, 'maxwidth': l:L.rw})
  call popup_move(s:state.popups.preview, {'line': l:L.pr, 'col': l:L.pc, 'minwidth': l:L.pw, 'maxwidth': l:L.pw})
  if get(s:state.popups, 'tree', 0)
    call popup_move(s:state.popups.tree, {'line': l:L.tr, 'col': l:L.tc,
      \ 'minwidth': l:L.tw, 'maxwidth': l:L.tw, 'minheight': l:L.th, 'maxheight': l:L.th})
  endif
endfunction

"==============================================================================
" Key dispatch
"==============================================================================
function! s:on_key(winid, key) abort
  let l:c = s:const
  if a:key ==# "\<Esc>"
    call s:close() | return 1
  endif
  " Ctrl+Left/Right: tree toggle / pane switching
  if a:key ==# "\<C-Left>" || a:key ==# "\<C-Right>"
    if a:key ==# "\<C-Left>" && !s:state.tree.open
      call skyrg#panel#tree#toggle(1)
    elseif a:key ==# "\<C-Left>" && s:state.tree.open && s:state.pane != l:c.PANE_TREE
      call s:set_pane(l:c.PANE_TREE)
    elseif a:key ==# "\<C-Right>" && s:state.tree.open && s:state.pane == l:c.PANE_TREE
      call skyrg#panel#tree#toggle(0)
    elseif a:key ==# "\<C-Right>" && s:state.pane != l:c.PANE_FORM
      call s:set_pane(l:c.PANE_FORM)
    endif
    return 1
  endif
  " Tree mode: all keys go to tree
  if s:state.pane == l:c.PANE_TREE
    return skyrg#panel#tree#on_key(a:key)
  endif
  " Browse mode: results nav + Enter
  if s:state.mode ==# l:c.MODE_BROWSE
    if a:key ==# "\<Up>" || a:key ==# "\<Down>"
      call skyrg#panel#results#move(a:key ==# "\<Up>" ? -1 : 1)
    elseif a:key ==# "\<PageUp>" || a:key ==# "\<PageDown>"
      call skyrg#panel#results#move(a:key ==# "\<PageUp>" ? -(s:layout().rh - 2) : (s:layout().rh - 2))
    elseif a:key ==# "\<CR>"
      call skyrg#panel#results#jump()
    endif
    return 1
  endif
  " Search mode: Up/Down = results
  if a:key ==# "\<Up>" || a:key ==# "\<Down>"
    call skyrg#panel#results#move(a:key ==# "\<Up>" ? -1 : 1)
    return 1
  endif
  if a:key ==# "\<PageUp>" || a:key ==# "\<PageDown>"
    call skyrg#panel#results#move(a:key ==# "\<PageUp>" ? -(s:layout().rh - 2) : (s:layout().rh - 2))
    return 1
  endif
  " Tab/S-Tab: completion or preset cycling
  if a:key ==# "\<Tab>" || a:key ==# "\<S-Tab>"
    if s:state.form.field == l:c.DIRS || s:state.form.field == l:c.TYPES
      call skyrg#panel#complete#field(a:key ==# "\<S-Tab>" ? -1 : 1)
      call skyrg#panel#form#redraw()
    elseif s:state.form.field == l:c.QUERY
      call skyrg#panel#preset#cycle(a:key ==# "\<Tab>" ? 1 : -1)
      call skyrg#panel#form#redraw()
      call skyrg#panel#search#schedule()
    endif
    return 1
  endif
  " Ctrl+Shift+Left/Right: jump letter in completion
  if (a:key ==# "\<C-S-Left>" || a:key ==# "\<C-S-Right>") && s:state.pane == l:c.PANE_FORM
    if s:state.form.field == l:c.DIRS || s:state.form.field == l:c.TYPES
      call skyrg#panel#complete#jump_letter(a:key ==# "\<C-S-Left>" ? -1 : 1)
      call skyrg#panel#form#redraw()
    endif
    return 1
  endif
  return skyrg#panel#form#on_key(a:key)
endfunction
