" autoload/skyrg/panel.vim — Multi-pane search UI (entry point + shared state)
"
" Architecture:
"   panel.vim owns the shared state dict (s:state) and popup lifecycle.
"   Submodules access state via skyrg#panel#state() and constants via
"   skyrg#panel#const().  Each submodule owns a namespaced sub-dict:
"
"     s:state.popups   — popup window IDs (form, results, preview, tree)
"     s:state.tree     — tree panel state (idx, nodes, expanded, filter, etc.)
"     s:state.results  — search results (matches, idx, scroll)
"     s:state.form     — form state (field index, fields array)
"     s:state.search   — rg job state (gen, pending, job, timer)
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
"      call skyrg#panel#state() to get a reference.  In debug mode
"      (g:skyrg_debug), the accessor validates against s:schema.
"   4. Style registry: style.vim is the single source of truth for all
"      highlight groups and text property types.
"   5. Popup factory: popup.vim provides create/move with shared defaults
"      (Normal highlight, rounded borders, padding).
"   6. Event bus: events.vim decouples cross-panel updates.  Emitters
"      don't know who listens; listeners register in s:register_events().
"   7. Layout geometry: s:layout() returns a flat dict plus a .geo
"      sub-dict with per-popup {line, col, width, height} for clean
"      popup factory calls.
"
" Submodules under panel/:
"   style.vim     — highlight groups + prop type registry
"   popup.vim     — popup factory (create/move with defaults)
"   events.vim    — event bus (on/emit/reset)
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
  \ 'PREVIEW_MATCH_ONLY': 0, 'PREVIEW_SYNTAX': 1,
  \ }

"==============================================================================
" State accessors (used by all submodules)
"==============================================================================
function! skyrg#panel#state() abort
  if get(g:, 'skyrg_debug', 0) | call s:validate_state() | endif
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
function! skyrg#panel#open(...) abort
  if !exists('*popup_create') || !exists('*job_start')
    echohl ErrorMsg | echo '[SkyRG] Requires Vim 8.2+ with +popupwin +job' | echohl None
    return
  endif
  let l:params = a:0 > 0 && type(a:1) == v:t_dict ? a:1 : {}
  let l:open_timer = skyrg#log#timer()
  call skyrg#log#info('panel', 'open mode=search')
  if !empty(l:params)
    call skyrg#log#data('panel', 'open params', l:params)
  endif
  let l:c = s:const
  let s:state = {
    \ 'mode': l:c.MODE_SEARCH, 'pane': l:c.PANE_FORM, 'closing': 0,
    \ 'popups': {'form': 0, 'results': 0, 'preview': 0, 'tree': 0, 'info': 0},
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
    \ '_search_dirty': 1,
    \ 'preview_mode': 0,
    \ '_syn_cache': {}, '_syn_cache_gen': -1,
    \ 'tree': {
    \   'open': 0, 'idx': 0, 'nodes': [], 'expanded': {},
    \   'filter': '', 'tab_mode': 0, 'tab_base': '', 'no_matches': 0,
    \ },
    \ }
  " Pre-fill fields from params (for query loading from history, context, etc.)
  if !empty(l:params)
    call s:apply_params(l:params)
  endif
  call skyrg#panel#style#init()
  call s:register_events()
  let l:g = s:layout().geo
  let s:state.popups.form = skyrg#panel#popup#create(skyrg#panel#form#render(),
    \ extend(copy(l:g.form), {'title': ' SkyRG ', 'borderhighlight': ['Title'],
    \   'filter': function('s:on_key'), 'mapping': 0, 'zindex': 200,
    \   'callback': function('s:on_close')}))
  let s:state.popups.results = skyrg#panel#popup#create([{'text': '  No results'}],
    \ extend(copy(l:g.results), {'title': ' Results ', 'wrap': 0}))
  let s:state.popups.preview = skyrg#panel#popup#create([{'text': ''}],
    \ extend(copy(l:g.preview), {'title': ' Preview '}))
  let s:state.popups.tree = skyrg#panel#popup#create([{'text': '  (Ctrl+Left to open)'}],
    \ extend(copy(l:g.tree), {'title': ' Tree ', 'hidden': 1}))
  let s:state.popups.info = skyrg#panel#popup#create([{'text': ''}],
    \ extend(copy(l:g.info), {'title': ' Info '}))
  call skyrg#panel#preview#show_preset(s:state.form.fields[l:c.PRESET].value)
  augroup SkyRGResize
    autocmd!
    autocmd VimResized * call skyrg#panel#reposition_popups()
  augroup END
  call skyrg#log#elapsed(l:open_timer, 'panel', 'open complete (5 popups created)')
endfunction

"==============================================================================
" Params application (query pre-loading)
"==============================================================================
function! s:apply_params(params) abort
  let l:c = s:const
  let l:f = s:state.form.fields
  if has_key(a:params, 'query')
    let l:f[l:c.QUERY].value = a:params.query
    let l:f[l:c.QUERY].pos = len(a:params.query)
  endif
  if has_key(a:params, 'dirs')
    let l:f[l:c.DIRS].value = a:params.dirs
    let l:f[l:c.DIRS].pos = len(a:params.dirs)
  endif
  if has_key(a:params, 'types')
    let l:f[l:c.TYPES].value = a:params.types
    let l:f[l:c.TYPES].pos = len(a:params.types)
  endif
  if has_key(a:params, 'preset')
    let l:f[l:c.PRESET].value = a:params.preset
    let l:f[l:c.PRESET].pos = len(a:params.preset)
    if !empty(a:params.preset)
      call skyrg#panel#preset#apply(a:params.preset)
    endif
  endif
  if has_key(a:params, 'gitignore')
    let l:f[l:c.GITIGN].value = a:params.gitignore ? 'on' : 'off'
  endif
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
  call skyrg#panel#style#init()
  call s:register_events()
  let l:g = s:layout().geo
  let s:state.popups.results = skyrg#panel#popup#create([{'text': '  Loading...'}],
    \ extend(copy(l:g.results), {'title': ' '.a:title.' ', 'borderhighlight': ['Title'],
    \   'wrap': 0, 'filter': function('s:on_key'), 'mapping': 0, 'zindex': 200,
    \   'callback': function('s:on_close')}))
  let s:state.popups.preview = skyrg#panel#popup#create([{'text': ''}],
    \ extend(copy(l:g.preview), {'title': ' Preview '}))
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
    let l:flat = {'fw':l:fw, 'fh':0, 'fr':0, 'fc':0,
      \ 'rw':l:rw, 'rh':l:bh, 'rr':2, 'rc':3,
      \ 'pw':l:pw, 'ph':l:bh, 'pr':2, 'pc':l:rw+5,
      \ 'tw':0, 'th':0, 'tr':0, 'tc':0,
      \ 'iw':0, 'ih':0, 'ir':0, 'ic':0}
  else
    let l:fh = 7 | let l:tw = 30
    let l:tree_vis = get(s:state.tree, 'open', 0)
    let l:toff = l:tree_vis ? l:tw + 2 : 0
    let l:total_w = max([l:fw - l:toff, 40])
    " Split top row: form ~55%, info pane ~45%
    let l:form_w = max([float2nr(l:total_w * 0.55), 30])
    let l:info_w = max([l:total_w - l:form_w - 2, 15])
    let l:bh = max([l:H - l:fh - 6, 6])
    let l:rw = max([float2nr(l:total_w * 0.45), 20])
    let l:pw = max([l:total_w - l:rw - 2, 20])
    let l:fc = 3 + l:toff
    let l:flat = {'fw':l:form_w, 'fh':l:fh, 'fr':2, 'fc':l:fc,
      \ 'rw':l:rw, 'rh':l:bh, 'rr':l:fh+4, 'rc':l:fc,
      \ 'pw':l:pw, 'ph':l:bh, 'pr':l:fh+4, 'pc':l:fc+l:rw+2,
      \ 'tw':l:tw, 'th':l:H-4, 'tr':2, 'tc':3,
      \ 'iw':l:info_w, 'ih':l:fh, 'ir':2, 'ic':l:fc+l:form_w+2}
  endif
  " Per-popup geometry (used by popup factory for create/move)
  let l:flat.geo = {
    \ 'form':    {'line': l:flat.fr, 'col': l:flat.fc, 'width': l:flat.fw, 'height': l:flat.fh},
    \ 'results': {'line': l:flat.rr, 'col': l:flat.rc, 'width': l:flat.rw, 'height': l:flat.rh},
    \ 'preview': {'line': l:flat.pr, 'col': l:flat.pc, 'width': l:flat.pw, 'height': l:flat.ph},
    \ 'tree':    {'line': l:flat.tr, 'col': l:flat.tc, 'width': l:flat.tw, 'height': l:flat.th},
    \ 'info':    {'line': l:flat.ir, 'col': l:flat.ic, 'width': l:flat.iw, 'height': l:flat.ih},
    \ }
  return l:flat
endfunction

"==============================================================================
" State schema validation (enabled by :let g:skyrg_debug = 1)
"==============================================================================
let s:schema = {
  \ 'popups': ['form', 'results', 'preview'],
  \ 'form':    ['field', 'fields'],
  \ 'results': ['matches', 'idx', 'scroll'],
  \ 'search':  ['gen'],
  \ }

function! s:validate_state() abort
  if !exists('s:state') | return | endif
  for [l:ns, l:keys] in items(s:schema)
    if !has_key(s:state, l:ns)
      echohl ErrorMsg | echom '[SkyRG] state missing namespace: '.l:ns | echohl None
      continue
    endif
    for l:k in l:keys
      if !has_key(s:state[l:ns], l:k)
        echohl ErrorMsg | echom '[SkyRG] state.'.l:ns.' missing key: '.l:k | echohl None
      endif
    endfor
  endfor
endfunction

"==============================================================================
" Event wiring
"==============================================================================
function! s:register_events() abort
  call skyrg#panel#events#reset()
  call skyrg#panel#events#on('results_changed', function('skyrg#panel#results#redraw'))
  call skyrg#panel#events#on('results_changed', function('skyrg#panel#preview#update'))
endfunction

"==============================================================================
" Close
"==============================================================================
function! s:close() abort
  if s:state.closing | return | endif
  call skyrg#log#info('panel', 'close')
  let s:state.closing = 1
  if has_key(s:state.search, 'job') && job_status(s:state.search.job) ==# 'run'
    call job_stop(s:state.search.job)
  endif
  if has_key(s:state.search, 'timer') | call timer_stop(s:state.search.timer) | endif
  for l:id in [s:state.popups.form, s:state.popups.results, s:state.popups.preview, get(s:state.popups, 'tree', 0), get(s:state.popups, 'info', 0)]
    silent! call popup_close(l:id)
  endfor
  call skyrg#panel#events#reset()
  call skyrg#panel#style#cleanup()
  call skyrg#panel#preview#cleanup()
  silent! autocmd! SkyRGResize
endfunction

function! s:on_close(id, result) abort
  call s:close()
endfunction

"==============================================================================
" Pane management
"==============================================================================
function! s:set_pane(p) abort
  let l:c = s:const
  let l:names = {l:c.PANE_FORM: 'form', l:c.PANE_RESULTS: 'results', l:c.PANE_TREE: 'tree'}
  call skyrg#log#debug('panel', 'set_pane → %s', get(l:names, a:p, string(a:p)))
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
  if s:state.closing | return | endif
  let l:reposition_timer = skyrg#log#timer()
  let l:g = s:layout().geo
  if s:state.popups.form
    call skyrg#panel#popup#move(s:state.popups.form, l:g.form)
  endif
  call skyrg#panel#popup#move(s:state.popups.results, l:g.results)
  call skyrg#panel#popup#move(s:state.popups.preview, l:g.preview)
  if get(s:state.popups, 'tree', 0)
    call skyrg#panel#popup#move(s:state.popups.tree, l:g.tree)
  endif
  if get(s:state.popups, 'info', 0)
    call skyrg#panel#popup#move(s:state.popups.info, l:g.info)
  endif
  " Re-render content to fill new dimensions
  if s:state.popups.form | call skyrg#panel#form#redraw() | endif
  call skyrg#panel#results#redraw()
  call skyrg#panel#preview#update()
  call skyrg#log#elapsed_debug(l:reposition_timer, 'panel', 'reposition complete')
endfunction

"==============================================================================
" Key dispatch
"==============================================================================
function! s:on_key(winid, key) abort
  let l:c = s:const
  let l:K = function('skyrg#panel#keymap#is')
  call skyrg#log#debug('panel/key', 'key=%s pane=%d', strtrans(a:key), s:state.pane)

  " --- Global: close ---
  if l:K(a:key, 'close')
    call s:close() | return 1
  endif

  " --- Route by active pane ---
  if s:state.pane == l:c.PANE_TREE
    return s:on_key_tree(a:key, l:K)
  elseif s:state.pane == l:c.PANE_RESULTS
    return s:on_key_results(a:key, l:K)
  else
    return s:on_key_query(a:key, l:K)
  endif
endfunction

" --- Query pane keys ---
function! s:on_key_query(key, K) abort
  let l:c = s:const

  " Ctrl+Left → open/activate tree
  if a:K(a:key, 'query_to_tree')
    if !s:state.tree.open
      call skyrg#panel#tree#toggle(1)
    else
      call s:set_pane(l:c.PANE_TREE)
    endif
    return 1
  endif

  " Ctrl+Down → activate results pane
  if a:K(a:key, 'query_to_results')
    call s:set_pane(l:c.PANE_RESULTS)
    return 1
  endif

  " Tab/S-Tab: completion or preset cycling
  if a:K(a:key, 'query_complete') || a:K(a:key, 'query_complete_rev')
    let l:rev = a:K(a:key, 'query_complete_rev')
    if s:state.form.field == l:c.DIRS || s:state.form.field == l:c.TYPES
      call skyrg#panel#complete#field(l:rev ? -1 : 1)
      call skyrg#panel#form#redraw()
    elseif s:state.form.field == l:c.QUERY
      call skyrg#panel#preset#cycle(l:rev ? -1 : 1)
      call skyrg#panel#form#redraw()
    endif
    return 1
  endif

  " Ctrl+Shift+Left/Right: jump letter in completion
  if a:K(a:key, 'query_jump_letter') || a:K(a:key, 'query_jump_letter_r')
    if s:state.form.field == l:c.DIRS || s:state.form.field == l:c.TYPES
      call skyrg#panel#complete#jump_letter(a:K(a:key, 'query_jump_letter') ? -1 : 1)
      call skyrg#panel#form#redraw()
    endif
    return 1
  endif

  " PageUp/PageDown: history navigation
  if a:K(a:key, 'query_history_prev')
    call skyrg#views#search#history_prev()
    return 1
  endif
  if a:K(a:key, 'query_history_next')
    call skyrg#views#search#history_next()
    return 1
  endif

  " Ctrl+Backspace: clear all fields
  if a:K(a:key, 'query_clear_all')
    call skyrg#views#search#clear_all()
    return 1
  endif

  " Delegate remaining keys to form handler
  return skyrg#panel#form#on_key(a:key)
endfunction

" --- Results pane keys ---
function! s:on_key_results(key, K) abort
  let l:c = s:const

  " Ctrl+Up → activate query pane (not available in browse mode)
  if a:K(a:key, 'results_to_query') && s:state.mode !=# l:c.MODE_BROWSE
    call s:set_pane(l:c.PANE_FORM)
    return 1
  endif

  " Up/Down: navigate matches
  if a:K(a:key, 'results_up')
    call skyrg#panel#results#move(-1) | return 1
  endif
  if a:K(a:key, 'results_down')
    call skyrg#panel#results#move(1) | return 1
  endif

  " PageUp/PageDown: page scroll
  if a:K(a:key, 'results_page_up')
    call skyrg#panel#results#move(-(s:layout().rh - 2)) | return 1
  endif
  if a:K(a:key, 'results_page_down')
    call skyrg#panel#results#move(s:layout().rh - 2) | return 1
  endif

  " Enter: open match
  if a:K(a:key, 'results_open')
    call skyrg#panel#results#jump() | return 1
  endif

  " s: toggle syntax highlighting in preview
  if a:K(a:key, 'results_toggle_syntax')
    call skyrg#panel#preview#toggle_syntax()
    return 1
  endif

  return 1
endfunction

" --- Tree pane keys ---
function! s:on_key_tree(key, K) abort
  let l:c = s:const

  " Ctrl+Right → activate query pane
  if a:K(a:key, 'tree_to_query')
    if s:state.tree.open
      call skyrg#panel#tree#toggle(0)
    endif
    call s:set_pane(l:c.PANE_FORM)
    return 1
  endif

  " Delegate remaining keys to tree handler
  return skyrg#panel#tree#on_key(a:key)
endfunction
