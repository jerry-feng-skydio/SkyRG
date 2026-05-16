" autoload/skyrg/panel.vim — Multi-pane search UI (form + results + preview)

let s:QUERY = 0 | let s:TYPES = 1 | let s:DIRS = 2 | let s:PRESET = 3 | let s:GITIGN = 4
let s:NFIELDS = 5
let s:PANE_FORM = 0 | let s:PANE_RESULTS = 1
let s:MODE_SEARCH = 'search' | let s:MODE_BROWSE = 'browse'
let s:MAX_RESULTS = 500 | let s:PREVIEW_CTX = 10 | let s:SEARCH_DELAY = 300

function! skyrg#panel#open() abort
  if !exists('*popup_create') || !exists('*job_start')
    echohl ErrorMsg | echo '[SkyRG] Requires Vim 8.2+ with +popupwin +job' | echohl None
    return
  endif
  let s:state = {
    \ 'mode': s:MODE_SEARCH,
    \ 'pane': s:PANE_FORM, 'field': s:QUERY, 'closing': 0, 'search_gen': 0, 
    \ 'fields': [
    \   {'label': 'Query',  'value': '', 'pos': 0},
    \   {'label': 'Types',  'value': '', 'pos': 0},
    \   {'label': 'Dirs',   'value': '', 'pos': 0},
    \   {'label': 'Preset', 'value': '', 'pos': 0},
    \   {'label': '.gitignore', 'value': 'on', 'pos': 0},
    \ ],
    \ 'matches': [], 'result_idx': 0, 'res_scroll': 0,
    \ 'form_id': 0, 'results_id': 0, 'preview_id': 0,
    \ }
  for l:n in ['skyrg_cursor', 'skyrg_sel', 'skyrg_match']
    silent! call prop_type_delete(l:n)
  endfor
  let l:hl = hlexists('TermCursor') ? 'TermCursor' : 'Visual'
  call prop_type_add('skyrg_cursor', {'highlight': l:hl})
  call prop_type_add('skyrg_sel',    {'highlight': 'CursorLine'})
  call prop_type_add('skyrg_match',  {'highlight': 'Search'})
  let l:L = s:layout()
  let l:bch = ['─','│','─','│','╭','╮','╯','╰']
  let s:state.form_id = popup_create(s:render_form(), {
    \ 'title': ' SkyRG ', 'border': [], 'borderchars': l:bch,
    \ 'borderhighlight': ['Title'], 'padding': [0,1,0,1],
    \ 'line': l:L.fr, 'col': l:L.fc, 'minwidth': l:L.fw, 'maxwidth': l:L.fw,
    \ 'minheight': l:L.fh, 'maxheight': l:L.fh,
    \ 'filter': function('s:on_key'), 'mapping': 0, 'zindex': 200,
    \ 'callback': function('s:on_close'),
    \ })
  let s:state.results_id = popup_create([{'text': '  No results'}], {
    \ 'title': ' Results ', 'border': [], 'borderchars': l:bch,
    \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1], 'scrollbar': 1,
    \ 'wrap': 0,
    \ 'line': l:L.rr, 'col': l:L.rc, 'minwidth': l:L.rw, 'maxwidth': l:L.rw,
    \ 'minheight': l:L.rh, 'maxheight': l:L.rh, 'zindex': 100,
    \ })
  let s:state.preview_id = popup_create([{'text': ''}], {
    \ 'title': ' Preview ', 'border': [], 'borderchars': l:bch,
    \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1], 'scrollbar': 1,
    \ 'line': l:L.pr, 'col': l:L.pc, 'minwidth': l:L.pw, 'maxwidth': l:L.pw,
    \ 'minheight': l:L.ph, 'maxheight': l:L.ph, 'zindex': 100,
    \ })
endfunction

"==============================================================================
" Browse mode — display external results (e.g. YCM references)
"==============================================================================
" matches: list of {'file': path, 'line': nr, 'col': nr, 'text': str}
" title: string shown in the results popup title
function! skyrg#panel#browse(matches, title) abort
  if !exists('*popup_create')
    echohl ErrorMsg | echo '[SkyRG] Requires Vim 8.2+ with +popupwin' | echohl None
    return
  endif
  let s:state = {
    \ 'mode': s:MODE_BROWSE,
    \ 'pane': s:PANE_RESULTS, 'field': 0, 'closing': 0, 'search_gen': 0,
    \ 'fields': [],
    \ 'matches': a:matches, 'result_idx': 0, 'res_scroll': 0,
    \ 'form_id': 0, 'results_id': 0, 'preview_id': 0,
    \ }
  for l:n in ['skyrg_cursor', 'skyrg_sel', 'skyrg_match']
    silent! call prop_type_delete(l:n)
  endfor
  let l:hl = hlexists('TermCursor') ? 'TermCursor' : 'Visual'
  call prop_type_add('skyrg_cursor', {'highlight': l:hl})
  call prop_type_add('skyrg_sel',    {'highlight': 'CursorLine'})
  call prop_type_add('skyrg_match',  {'highlight': 'Search'})
  let l:L = s:layout()
  let l:bch = ['─','│','─','│','╭','╮','╯','╰']
  let s:state.results_id = popup_create([{'text': '  Loading...'}], {
    \ 'title': ' '.a:title.' ', 'border': [], 'borderchars': l:bch,
    \ 'borderhighlight': ['Title'], 'padding': [0,1,0,1], 'scrollbar': 1,
    \ 'wrap': 0,
    \ 'line': l:L.rr, 'col': l:L.rc, 'minwidth': l:L.rw, 'maxwidth': l:L.rw,
    \ 'minheight': l:L.rh, 'maxheight': l:L.rh,
    \ 'filter': function('s:on_key'), 'mapping': 0, 'zindex': 200,
    \ 'callback': function('s:on_close'),
    \ })
  let s:state.preview_id = popup_create([{'text': ''}], {
    \ 'title': ' Preview ', 'border': [], 'borderchars': l:bch,
    \ 'borderhighlight': ['Comment'], 'padding': [0,1,0,1], 'scrollbar': 1,
    \ 'line': l:L.pr, 'col': l:L.pc, 'minwidth': l:L.pw, 'maxwidth': l:L.pw,
    \ 'minheight': l:L.ph, 'maxheight': l:L.ph, 'zindex': 100,
    \ })
  call s:redraw_results()
  call s:update_preview()
endfunction

" Grab YCM GoToReferences results and display in browse mode
function! skyrg#panel#ycm_refs() abort
  " Run GoToReferences — YCM populates the quickfix list
  try
    execute 'YcmCompleter GoToReferences'
  catch
    echohl ErrorMsg | echo '[SkyRG] YcmCompleter GoToReferences failed: '.v:exception | echohl None
    return
  endtry
  cclose
  let l:qf = getqflist()
  if empty(l:qf)
    echohl WarningMsg | echo '[SkyRG] No references found' | echohl None
    return
  endif
  let l:matches = []
  for l:item in l:qf
    let l:file = bufname(l:item.bufnr)
    if empty(l:file) | continue | endif
    call add(l:matches, {
      \ 'file': fnamemodify(l:file, ':p'),
      \ 'line': l:item.lnum,
      \ 'col': l:item.col,
      \ 'text': trim(get(l:item, 'text', '')),
      \ })
  endfor
  if empty(l:matches)
    echohl WarningMsg | echo '[SkyRG] No references found' | echohl None
    return
  endif
  call skyrg#panel#browse(l:matches, 'References ('.len(l:matches).')')
endfunction

function! s:layout() abort
  let l:W = &columns | let l:H = &lines
  let l:fw = max([l:W - 6, 40])
  if s:state.mode ==# s:MODE_BROWSE
    let l:fh = 0
    let l:bh = max([l:H - 4, 6])
    let l:rw = max([float2nr(l:fw * 0.45), 20])
    let l:pw = max([l:fw - l:rw - 2, 20])
    return {'fw':l:fw, 'fh':0, 'fr':0, 'fc':0,
      \ 'rw':l:rw, 'rh':l:bh, 'rr':2, 'rc':3,
      \ 'pw':l:pw, 'ph':l:bh, 'pr':2, 'pc':l:rw+5}
  endif
  let l:fh = 7
  let l:bh = max([l:H - l:fh - 6, 6])
  let l:rw = max([float2nr(l:fw * 0.45), 20])
  let l:pw = max([l:fw - l:rw - 2, 20])
  return {'fw':l:fw, 'fh':l:fh, 'fr':2, 'fc':3,
    \ 'rw':l:rw, 'rh':l:bh, 'rr':l:fh+4, 'rc':3,
    \ 'pw':l:pw, 'ph':l:bh, 'pr':l:fh+4, 'pc':l:rw+5}
endfunction

function! s:close() abort
  if s:state.closing | return | endif
  let s:state.closing = 1
  if has_key(s:state, 'job') && job_status(s:state.job) ==# 'run'
    call job_stop(s:state.job)
  endif
  if has_key(s:state, 'timer') | call timer_stop(s:state.timer) | endif
  for l:id in [s:state.form_id, s:state.results_id, s:state.preview_id]
    silent! call popup_close(l:id)
  endfor
  for l:n in ['skyrg_cursor', 'skyrg_sel', 'skyrg_match']
    silent! call prop_type_delete(l:n)
  endfor
endfunction

function! s:on_close(id, result) abort
  call s:close()
endfunction

function! s:on_key(winid, key) abort
  if a:key ==# "\<Esc>"
    call s:close() | return 1
  endif
  " Up/Down: move match selection
  if a:key ==# "\<Up>" || a:key ==# "\<Down>"
    call s:move_result(a:key ==# "\<Up>" ? -1 : 1)
    return 1
  endif
  " PageUp/PageDown: jump by a page
  if a:key ==# "\<PageUp>" || a:key ==# "\<PageDown>"
    let l:page = s:layout().rh - 2
    call s:move_result(a:key ==# "\<PageUp>" ? -l:page : l:page)
    return 1
  endif
  " Browse mode: only results navigation + Enter
  if s:state.mode ==# s:MODE_BROWSE
    if a:key ==# "\<CR>"
      call s:jump_to_match()
    endif
    return 1
  endif
  " Tab / S-Tab: field completion (Types/Dirs)
  if a:key ==# "\<Tab>" || a:key ==# "\<S-Tab>"
    if s:state.field == s:DIRS || s:state.field == s:TYPES
      call s:complete_field(a:key ==# "\<S-Tab>" ? -1 : 1)
      call s:redraw_form()
    endif
    return 1
  endif
  " Ctrl+Left/Right: prev/next completion selection
  if a:key ==# "\<C-Left>" || a:key ==# "\<C-Right>"
    if s:state.field == s:DIRS || s:state.field == s:TYPES
      call s:complete_field(a:key ==# "\<C-Left>" ? -1 : 1)
      call s:redraw_form()
    endif
    return 1
  endif
  " Ctrl+Shift+Left/Right: jump to next selection with different first letter
  if a:key ==# "\<C-S-Left>" || a:key ==# "\<C-S-Right>"
    if s:state.field == s:DIRS || s:state.field == s:TYPES
      call s:complete_field_jump_letter(a:key ==# "\<C-S-Left>" ? -1 : 1)
      call s:redraw_form()
    endif
    return 1
  endif
  return s:form_key(a:key)
endfunction

function! s:move_result(dir) abort
  if empty(s:state.matches) | return | endif
  let s:state.result_idx = max([0, min([len(s:state.matches)-1, s:state.result_idx + a:dir])])
  call s:redraw_results() | call s:update_preview()
endfunction

function! s:complete_field_jump_letter(dir) abort
  if !get(s:state, 'tab_cycling', 0) || empty(get(s:state, 'tab_candidates', []))
    call s:complete_field(a:dir)
    return
  endif
  let l:cands = s:state.tab_candidates
  let l:n = len(l:cands)
  let l:cur_letter = l:cands[s:state.tab_idx][0]
  let l:idx = s:state.tab_idx
  while 1
    let l:idx = (l:idx + a:dir + l:n) % l:n
    if l:cands[l:idx][0] !=# l:cur_letter || l:idx == s:state.tab_idx
      break
    endif
  endwhile
  let s:state.tab_idx = l:idx
  " Update the field value with the new candidate
  let l:f = s:state.fields[s:state.field]
  if s:state.field == s:DIRS
    let l:parts = split(l:f.value, ',', 1)
    let l:prev_len = 0
    for l:i in range(len(l:parts) - 1)
      let l:prev_len += len(l:parts[l:i]) + 1
    endfor
    let l:parts[-1] = l:cands[l:idx]
    let s:state.dir_candidates = l:cands
    let l:f.value = join(l:parts, ',')
    let l:f.pos = l:prev_len + len(l:parts[-1]) - 1
  elseif s:state.field == s:TYPES
    let l:val = l:f.value
    if len(l:val) > 0 && l:val[-1:] ==# ',' | let l:val = l:val[:-2] | endif
    let l:parts = split(l:val, ',', 1)
    let l:parts[-1] = l:cands[l:idx]
    let s:state.type_candidates = l:cands
    let l:f.value = join(l:parts, ',') . ','
    let l:f.pos = len(l:f.value)
  endif
endfunction

function! s:set_pane(p) abort
  let s:state.pane = a:p
  if s:state.form_id
    call popup_setoptions(s:state.form_id,    {'borderhighlight': [a:p == s:PANE_FORM ? 'Title' : 'Comment']})
  endif
  call popup_setoptions(s:state.results_id, {'borderhighlight': [a:p == s:PANE_RESULTS ? 'Title' : 'Comment']})
  if s:state.form_id | call s:redraw_form() | endif
endfunction

"==============================================================================
" Form key handling (Up/Down = fields, typing = edit, Enter = search)
"==============================================================================
function! s:form_key(key) abort
  let l:f = s:state.fields[s:state.field]
  let l:changed = 0
  " Any non-Tab key resets the tab-cycle state
  if a:key !=# "\<Tab>" | call s:reset_tab_cycle() | endif
  if a:key ==# "\<C-Up>"
    let s:state.field = (s:state.field - 1 + s:NFIELDS) % s:NFIELDS
  elseif a:key ==# "\<C-Down>"
    let s:state.field = (s:state.field + 1) % s:NFIELDS
  elseif s:state.field == s:GITIGN && a:key ==# ' '
    let l:f.value = l:f.value ==# 'on' ? 'off' : 'on'
    let l:changed = 1
  elseif a:key ==# "\<CR>"
    call s:jump_to_match()
    return 1
  elseif a:key ==# "\<Left>"
    let l:f.pos = max([0, l:f.pos - 1])
  elseif a:key ==# "\<Right>"
    let l:f.pos = min([len(l:f.value), l:f.pos + 1])
  elseif a:key ==# "\<Home>"
    let l:f.pos = 0
  elseif a:key ==# "\<End>"
    let l:f.pos = len(l:f.value)
  elseif a:key ==# "\<BS>"
    if l:f.pos > 0
      let l:f.value = (l:f.pos > 1 ? l:f.value[:l:f.pos-2] : '') . l:f.value[l:f.pos:]
      let l:f.pos -= 1 | let l:changed = 1
    endif
  elseif a:key ==# "\<Del>"
    if l:f.pos < len(l:f.value)
      let l:b = l:f.pos > 0 ? l:f.value[:l:f.pos-1] : ''
      let l:f.value = l:b . (l:f.pos+1 < len(l:f.value) ? l:f.value[l:f.pos+1:] : '')
      let l:changed = 1
    endif
  elseif a:key ==# "\<C-u>"
    let l:f.value = '' | let l:f.pos = 0 | let l:changed = 1
  elseif a:key ==# "\<C-w>" || a:key ==# "\<S-BS>"
    call s:del_word(l:f) | let l:changed = 1
  elseif (a:key ==# "\<C-n>" || a:key ==# "\<C-p>") && s:state.field == s:PRESET
    call s:cycle_preset(a:key ==# "\<C-n>" ? 1 : -1) | let l:changed = 1
  elseif len(a:key) == 1 && char2nr(a:key) >= 32 && s:state.field != s:GITIGN
    let l:b = l:f.pos > 0 ? l:f.value[:l:f.pos-1] : ''
    let l:f.value = l:b . a:key . l:f.value[l:f.pos:]
    let l:f.pos += 1 | let l:changed = 1
  endif
  call s:redraw_form()
  if l:changed | call s:schedule_search() | endif
  return 1
endfunction


"==============================================================================
" Form rendering
"==============================================================================
function! s:render_form() abort
  let l:lines = []
  for l:i in range(s:NFIELDS)
    let l:f = s:state.fields[l:i]
    let l:act = l:i == s:state.field && s:state.pane == s:PANE_FORM
    if l:i == s:GITIGN
      let l:chk = l:f.value ==# 'on' ? 'x' : ' '
      let l:text = printf(' %s [%s] %s', l:act ? '>' : ' ', l:chk, l:f.label)
      if l:act
        call add(l:lines, {'text': l:text, 'props': [
          \ {'col': 4, 'length': 3, 'type': 'skyrg_cursor'}]})
      else
        call add(l:lines, {'text': l:text})
      endif
    else
      let l:pfx = printf(' %s %-8s ', l:act ? '>' : ' ', l:f.label . ':')
      let l:text = l:pfx . l:f.value . (l:act ? ' ' : '')
      if l:act
        call add(l:lines, {'text': l:text, 'props': [
          \ {'col': len(l:pfx)+l:f.pos+1, 'length': 1, 'type': 'skyrg_cursor'}]})
      else
        call add(l:lines, {'text': l:text})
      endif
    endif
  endfor
  call add(l:lines, s:hint())
  return l:lines
endfunction

function! s:redraw_form() abort
  call popup_settext(s:state.form_id, s:render_form())
endfunction

function! s:hint() abort
  let l:lab = s:state.fields[s:state.field].label
  if l:lab ==# 'Preset'
    let l:n = s:preset_names()
    let l:t = empty(l:n) ? '  No presets' : '  Presets: '.join(l:n,', ').'  (C-n/C-p)'
    return {'text': l:t}
  elseif l:lab ==# 'Types'
    let l:cands = get(s:state, 'type_candidates', [])
    if !empty(l:cands)
      return s:hint_with_hl(l:cands, 20)
    endif
    return {'text': '  e.g. py,cpp,java  (Tab to complete, comma-separated)'}
  elseif l:lab ==# 'Dirs'
    let l:cands = get(s:state, 'dir_candidates', [])
    if !empty(l:cands)
      return s:hint_with_hl(map(copy(l:cands), 'fnamemodify(v:val, ":.")'), 10)
    endif
    return {'text': '  e.g. src/,lib/  (Tab to complete, comma-separated)'}
  endif
  if l:lab ==# '.gitignore'
    return {'text': '  Space: toggle  (rg respects .gitignore by default)'}
  endif
  return {'text': '  C-Up/C-Down: fields  Up/Down: matches  Enter: open  Esc: close'}
endfunction

function! s:hint_with_hl(cands, max_show) abort
  let l:sel = get(s:state, 'tab_idx', -1)
  let l:n = len(a:cands)
  let l:show = min([a:max_show, l:n])

  " Center the window on the selected item
  let l:half = l:show / 2
  if l:sel >= 0 && l:n > l:show
    let l:start = max([0, min([l:sel - l:half, l:n - l:show])])
  else
    let l:start = 0
  endif
  let l:end = l:start + l:show - 1

  let l:text = '  '
  let l:props = []
  if l:start > 0
    let l:text .= '... '
  endif
  for l:i in range(l:start, l:end)
    let l:col = len(l:text) + 1
    let l:text .= a:cands[l:i]
    if l:i == l:sel
      call add(l:props, {'col': l:col, 'length': len(a:cands[l:i]), 'type': 'skyrg_sel'})
    endif
    let l:text .= '  '
  endfor
  if l:end < l:n - 1
    let l:text .= '...'
  endif
  return empty(l:props) ? {'text': l:text} : {'text': l:text, 'props': l:props}
endfunction

"==============================================================================
" Results rendering
"==============================================================================
function! s:redraw_results() abort
  if empty(s:state.matches)
    let l:msg = !empty(get(s:state, 'rg_error', '')) ? '  Error: '.s:state.rg_error : '  No results'
    call popup_settext(s:state.results_id, [{'text': l:msg}])
    call popup_setoptions(s:state.results_id, {'title': ' Results '})
    return
  endif
  let l:L = s:layout()
  let l:vis = l:L.rh - 2
  let l:first = s:state.res_scroll
  if s:state.result_idx < l:first
    let l:first = s:state.result_idx
  elseif s:state.result_idx >= l:first + l:vis
    let l:first = s:state.result_idx - l:vis + 1
  endif
  let s:state.res_scroll = l:first
  let l:lines = []
  for l:i in range(l:first, min([l:first + l:vis - 1, len(s:state.matches)-1]))
    let l:m = s:state.matches[l:i]
    let l:mk = l:i == s:state.result_idx ? '> ' : '  '
    let l:text = printf('%s%s:%d: %s', l:mk, s:short(l:m.file), l:m.line, l:m.text)
    if l:i == s:state.result_idx
      call add(l:lines, {'text': l:text, 'props': [
        \ {'col': 1, 'length': len(l:text), 'type': 'skyrg_sel'}]})
    else
      call add(l:lines, {'text': l:text})
    endif
  endfor
  call popup_settext(s:state.results_id, l:lines)
  call popup_setoptions(s:state.results_id, {
    \ 'title': printf(' Results (%d/%d) ', s:state.result_idx+1, len(s:state.matches))})
endfunction

"==============================================================================
" Preview rendering
"==============================================================================
function! s:update_preview() abort
  if empty(s:state.matches)
    call popup_settext(s:state.preview_id, [{'text': ''}])
    call popup_setoptions(s:state.preview_id, {'title': ' Preview '})
    return
  endif
  let l:m = s:state.matches[s:state.result_idx]
  call popup_setoptions(s:state.preview_id, {'title': ' '.s:short(l:m.file).' '})
  if !filereadable(l:m.file)
    call popup_settext(s:state.preview_id, [{'text': '  (not readable)'}])
    return
  endif
  let l:all = readfile(l:m.file)
  let l:s = max([0, l:m.line - s:PREVIEW_CTX - 1])
  let l:e = min([len(l:all)-1, l:m.line + s:PREVIEW_CTX - 1])
  let l:lines = []
  for l:i in range(l:s, l:e)
    let l:ln = l:i + 1
    let l:text = printf('%s%4d  %s', l:ln == l:m.line ? '>' : ' ', l:ln, l:all[l:i])
    if l:ln == l:m.line
      call add(l:lines, {'text': l:text, 'props': [
        \ {'col': 1, 'length': len(l:text), 'type': 'skyrg_match'}]})
    else
      call add(l:lines, {'text': l:text})
    endif
  endfor
  call popup_settext(s:state.preview_id, l:lines)
endfunction

"==============================================================================
" Async ripgrep search
"==============================================================================
function! s:schedule_search() abort
  if has_key(s:state, 'timer') | call timer_stop(s:state.timer) | endif
  let s:state.timer = timer_start(s:SEARCH_DELAY, function('s:do_search'))
endfunction

function! s:do_search(timer) abort
  call s:run_search()
endfunction

function! s:run_search() abort
  if has_key(s:state, 'job') && job_status(s:state.job) ==# 'run'
    call job_stop(s:state.job)
  endif
  let s:state.search_gen += 1
  let s:state.rg_error = ''
  let l:q = s:state.fields[s:QUERY].value
  if empty(l:q)
    let s:state.matches = [] | let s:state.result_idx = 0
    call s:redraw_results() | call s:update_preview()
    return
  endif
  let l:cmd = ['rg', '--column', '--line-number', '--no-heading',
    \ '--color=never', '--smart-case', '--max-count=500']
  " Apply .gitignore setting
  if s:state.fields[s:GITIGN].value !=# 'on'
    call add(l:cmd, '--no-ignore')
  endif
  " Apply Types field
  for l:t in split(s:state.fields[s:TYPES].value, ',')
    let l:t = trim(l:t)
    if !empty(l:t) | call extend(l:cmd, ['-t', l:t]) | endif
  endfor
  " Apply SkyFilter preset if selected
  let l:preset_name = trim(s:state.fields[s:PRESET].value)
  if !empty(l:preset_name)
    let l:filter = s:get_sky_filter(l:preset_name)
    if !empty(l:filter)
      let l:glob_flags = l:filter.get_globbing_flags()
      if !empty(l:glob_flags)
        call extend(l:cmd, split(l:glob_flags))
      endif
    endif
  endif
  call extend(l:cmd, ['--', l:q])
  " Apply Dirs field
  let l:has_dir = 0
  for l:d in split(s:state.fields[s:DIRS].value, ',')
    let l:d = trim(l:d)
    if !empty(l:d) | call add(l:cmd, l:d) | let l:has_dir = 1 | endif
  endfor
  " Apply SkyFilter search directories if no explicit dirs
  if !l:has_dir && !empty(l:preset_name)
    let l:filter = s:get_sky_filter(l:preset_name)
    if !empty(l:filter)
      let l:sdirs = l:filter.get_search_directories()
      if !empty(l:sdirs)
        call extend(l:cmd, split(l:sdirs))
        let l:has_dir = 1
      endif
    endif
  endif
  if !l:has_dir | call add(l:cmd, '.') | endif
  let l:gen = s:state.search_gen
  let s:state.pending = []
  let s:state.job = job_start(l:cmd, {
    \ 'out_cb': function('s:on_out', [l:gen]),
    \ 'err_cb': function('s:on_err', [l:gen]),
    \ 'close_cb': function('s:on_done', [l:gen]),
    \ 'out_mode': 'nl',
    \ })
endfunction

function! s:on_err(gen, ch, msg) abort
  if a:gen != s:state.search_gen | return | endif
  " Show rg errors (e.g. bad type, bad regex) in results pane
  let s:state.rg_error = a:msg
endfunction

function! s:on_out(gen, ch, msg) abort
  if a:gen != s:state.search_gen || len(s:state.pending) >= s:MAX_RESULTS | return | endif
  let l:p = matchlist(a:msg, '^\(.\{-}\):\(\d\+\):\(\d\+\):\(.*\)$')
  if !empty(l:p)
    call add(s:state.pending, {
      \ 'file': l:p[1], 'line': str2nr(l:p[2]),
      \ 'col': str2nr(l:p[3]), 'text': trim(l:p[4])})
  endif
endfunction

function! s:on_done(gen, ch) abort
  if a:gen != s:state.search_gen | return | endif
  let s:state.matches = s:state.pending
  let s:state.result_idx = 0 | let s:state.res_scroll = 0
  call s:redraw_results() | call s:update_preview()
  redraw
endfunction

"==============================================================================
" Jump to match
"==============================================================================
function! s:jump_to_match() abort
  if empty(s:state.matches) | return | endif
  let l:m = s:state.matches[s:state.result_idx]
  call s:close()
  execute 'edit +'.l:m.line.' '.fnameescape(l:m.file)
  call cursor(l:m.line, l:m.col)
  normal! zz
endfunction

"==============================================================================
" Preset helpers
"==============================================================================
function! s:preset_names() abort
  let l:names = {}
  if exists('g:skyrg_presets')
    for l:k in keys(g:skyrg_presets) | let l:names[l:k] = 1 | endfor
  endif
  if exists('g:SkyFilter') && has_key(g:SkyFilter, 'presets')
    for l:k in keys(g:SkyFilter.presets) | let l:names[l:k] = 1 | endfor
  endif
  return sort(keys(l:names))
endfunction

function! s:get_sky_filter(name) abort
  if exists('g:SkyFilter') && has_key(g:SkyFilter, 'presets') && has_key(g:SkyFilter.presets, a:name)
    return g:SkyFilter.presets[a:name]
  endif
  return {}
endfunction

function! s:cycle_preset(dir) abort
  let l:n = s:preset_names()
  if empty(l:n) | return | endif
  let l:idx = index(l:n, s:state.fields[s:PRESET].value)
  let l:idx = l:idx < 0 ? 0 : (l:idx + a:dir + len(l:n)) % len(l:n)
  let l:name = l:n[l:idx]
  let s:state.fields[s:PRESET].value = l:name
  let s:state.fields[s:PRESET].pos = len(l:name)
  call s:apply_preset(l:name)
endfunction

function! s:apply_preset(name) abort
  if !exists('g:skyrg_presets') || !has_key(g:skyrg_presets, a:name) | return | endif
  let l:p = g:skyrg_presets[a:name]
  if empty(s:state.fields[s:TYPES].value) && has_key(l:p, 'desired_types')
    let l:v = join(l:p.desired_types, ',')
    let s:state.fields[s:TYPES].value = l:v | let s:state.fields[s:TYPES].pos = len(l:v)
  endif
  if empty(s:state.fields[s:DIRS].value) && has_key(l:p, 'desired_dirs')
    let l:v = join(l:p.desired_dirs, ',')
    let s:state.fields[s:DIRS].value = l:v | let s:state.fields[s:DIRS].pos = len(l:v)
  endif
endfunction

"==============================================================================
" Utilities
"==============================================================================
function! s:del_word(f) abort
  if a:f.pos == 0 | return | endif
  let l:b = a:f.value[:a:f.pos-1]
  let l:a = a:f.value[a:f.pos:]
  let l:b = substitute(l:b, '[^,/ ]*[,/ ]*$', '', '')
  let a:f.value = l:b . l:a | let a:f.pos = len(l:b)
endfunction

function! s:short(path) abort
  let l:cwd = getcwd() . '/'
  return a:path[:len(l:cwd)-1] ==# l:cwd ? a:path[len(l:cwd):] : a:path
endfunction

"==============================================================================
" Directory tab-completion (relative to cwd)
"==============================================================================
" Unified Tab completion dispatcher
function! s:complete_field(...) abort
  let l:dir = get(a:, 1, 1)
  if s:state.field == s:DIRS
    call s:complete_dirs(l:dir)
  elseif s:state.field == s:TYPES
    call s:complete_types(l:dir)
  endif
endfunction

"==============================================================================
" Dirs completion — cursor-aware (sibling vs drill-in)
"==============================================================================
function! s:complete_dirs(dir) abort
  let l:f = s:state.fields[s:DIRS]
  let l:parts = split(l:f.value, ',', 1)

  " Compute offset of last comma-part and cursor pos within it
  let l:prev_len = 0
  for l:i in range(len(l:parts) - 1)
    let l:prev_len += len(l:parts[l:i]) + 1
  endfor
  let l:cur = l:parts[-1]
  let l:cpos = l:f.pos - l:prev_len          " cursor within this part
  let l:n_cands = len(get(s:state, 'tab_candidates', []))

  " --- Cycling ---------------------------------------------------------
  if get(s:state, 'tab_cycling', 0) && l:n_cands > 0
    let l:cands = s:state.tab_candidates
    let s:state.tab_idx = (s:state.tab_idx + a:dir + l:n_cands) % l:n_cands
    let l:parts[-1] = l:cands[s:state.tab_idx]
    let s:state.dir_candidates = l:cands
    let l:f.value = join(l:parts, ',')
    let l:f.pos = l:prev_len + len(l:parts[-1]) - 1
    return
  endif

  " --- Determine mode: drill-in vs sibling ----------------------------
  " Drill-in:  cursor is past the trailing '/' (ready to type inside)
  " Sibling:   cursor is on or before '/' (still on the segment name)
  let l:drill = (l:cpos >= len(l:cur)) && l:cur[-1:] ==# '/'

  if l:drill
    let l:prefix = l:cur
    let l:candidates = s:glob_entries(l:prefix)
  else
    let l:stripped = l:cur
    if l:stripped[-1:] ==# '/'
      let l:stripped = l:stripped[:-2]
    endif
    let l:slash = strridx(l:stripped, '/')
    let l:parent = l:slash >= 0 ? l:stripped[:l:slash] : ''
    let l:candidates = s:glob_entries(l:parent)
  endif

  if empty(l:candidates)
    let s:state.dir_candidates = []
    call s:reset_tab_cycle()
    return
  endif

  let l:exact = index(l:candidates, l:cur)
  if l:exact >= 0
    let l:next = (l:exact + a:dir + len(l:candidates)) % len(l:candidates)
    let l:parts[-1] = l:candidates[l:next]
    call s:dir_start_cycle(l:candidates, l:next)
  elseif len(l:candidates) == 1
    let l:parts[-1] = l:candidates[0]
    call s:dir_start_cycle(l:candidates, 0)
  else
    let l:pick = a:dir >= 0 ? 0 : len(l:candidates) - 1
    let l:parts[-1] = l:candidates[l:pick]
    call s:dir_start_cycle(l:candidates, l:pick)
  endif

  let l:f.value = join(l:parts, ',')
  let l:f.pos = l:prev_len + len(l:parts[-1]) - 1
endfunction

function! s:dir_start_cycle(cands, idx) abort
  let s:state.dir_candidates = a:cands
  let s:state.tab_cycling = 1
  let s:state.tab_candidates = a:cands
  let s:state.tab_idx = a:idx
  let s:state.tab_suffix = ''
endfunction

" Glob directories only; trailing '/'
function! s:glob_entries(prefix) abort
  let l:entries = filter(glob(a:prefix . '*', 0, 1), 'isdirectory(v:val)')
  return map(l:entries, 'v:val . "/"')
endfunction

"==============================================================================
" Types completion — cursor-aware (sibling vs drill-in, ',' = separator)
"==============================================================================
function! s:complete_types(dir) abort
  let l:f = s:state.fields[s:TYPES]
  let l:parts = split(l:f.value, ',', 1)

  " Compute offset of last comma-part and cursor pos within it
  let l:prev_len = 0
  for l:i in range(len(l:parts) - 1)
    let l:prev_len += len(l:parts[l:i]) + 1
  endfor
  let l:cur = trim(l:parts[-1])
  let l:cpos = l:f.pos - l:prev_len
  let l:n_cands = len(get(s:state, 'tab_candidates', []))

  " --- Cycling ---------------------------------------------------------
  if get(s:state, 'tab_cycling', 0) && l:n_cands > 0
    let l:cands = s:state.tab_candidates
    let s:state.tab_idx = (s:state.tab_idx + a:dir + l:n_cands) % l:n_cands
    let l:parts[-1] = l:cands[s:state.tab_idx]
    let s:state.type_candidates = l:cands
    let l:f.value = join(l:parts, ',')
    let l:f.pos = l:prev_len + len(l:parts[-1]) - 1
    return
  endif

  " --- Determine mode: drill-in vs sibling ----------------------------
  " Drill-in:  cursor is past the trailing ',' (empty new part → all types)
  " Sibling:   cursor is on or before ',' (still on the type name)
  let l:drill = (l:cpos >= len(l:parts[-1])) && !empty(l:cur)

  if l:drill
    " Start fresh completion for a new type after the comma
    let l:parts = l:parts + ['']
    let l:prev_len += len(l:cur) + 1
    let l:cur = ''
    let l:candidates = s:match_types('')
  else
    " Cycle/replace the current partial type
    let l:candidates = s:match_types(l:cur)
  endif

  if empty(l:candidates)
    let s:state.type_candidates = []
    call s:reset_tab_cycle()
    return
  endif

  let l:exact = index(l:candidates, l:cur)
  if l:exact >= 0
    let l:next = (l:exact + a:dir + len(l:candidates)) % len(l:candidates)
    let l:parts[-1] = l:candidates[l:next]
    call s:type_start_cycle(l:candidates, l:next)
  elseif len(l:candidates) == 1
    let l:parts[-1] = l:candidates[0]
    call s:type_start_cycle(l:candidates, 0)
  else
    let l:pick = a:dir >= 0 ? 0 : len(l:candidates) - 1
    let l:parts[-1] = l:candidates[l:pick]
    call s:type_start_cycle(l:candidates, l:pick)
  endif

  let l:f.value = join(l:parts, ',')
  let l:f.pos = l:prev_len + len(l:parts[-1]) - 1
endfunction

function! s:type_start_cycle(cands, idx) abort
  let s:state.type_candidates = a:cands
  let s:state.tab_cycling = 1
  let s:state.tab_candidates = a:cands
  let s:state.tab_idx = a:idx
  let s:state.tab_suffix = ''
endfunction

function! s:match_types(partial) abort
  let l:all = s:rg_type_names()
  " Exclude types already selected in earlier comma-separated parts
  let l:val = s:state.fields[s:TYPES].value
  if l:val[-1:] ==# ',' | let l:val = l:val[:-2] | endif
  let l:chosen = map(split(l:val, ','), 'trim(v:val)')
  if !empty(l:chosen)
    call remove(l:chosen, -1)
    let l:all = filter(copy(l:all), 'index(l:chosen, v:val) < 0')
  endif
  " When .gitignore is respected, hide types whose extensions are all ignored
  if s:state.fields[s:GITIGN].value ==# 'on'
    let l:gi_exts = s:gitignore_extensions()
    if !empty(l:gi_exts)
      let l:type_exts = s:rg_type_extensions()
      let l:all = filter(l:all, '!s:type_fully_ignored(v:val, l:type_exts, l:gi_exts)')
    endif
  endif
  if empty(a:partial)
    return l:all
  endif
  return filter(l:all, 'v:val[:len(a:partial)-1] ==# a:partial')
endfunction

" Cache rg --type-list output (parsed once per session)
let s:rg_types_cache = []
function! s:rg_type_names() abort
  if !empty(s:rg_types_cache)
    return s:rg_types_cache
  endif
  call s:parse_rg_type_list()
  return s:rg_types_cache
endfunction

" Cache rg type → extensions mapping (parsed once per session)
let s:rg_type_ext_cache = {}
function! s:rg_type_extensions() abort
  if !empty(s:rg_type_ext_cache)
    return s:rg_type_ext_cache
  endif
  call s:parse_rg_type_list()
  return s:rg_type_ext_cache
endfunction

function! s:parse_rg_type_list() abort
  if !empty(s:rg_types_cache) | return | endif
  let l:raw = systemlist('rg --type-list 2>/dev/null')
  for l:line in l:raw
    let l:name = matchstr(l:line, '^[^:]*')
    if empty(l:name) | continue | endif
    call add(s:rg_types_cache, l:name)
    let l:ext_str = matchstr(l:line, ':\s*\zs.*')
    let s:rg_type_ext_cache[l:name] = map(split(l:ext_str, ',\s*'), 'substitute(v:val, "^\\*\\.", "", "")')
  endfor
endfunction

" Parse .gitignore for extension-based ignore patterns (e.g. *.pyc → pyc)
let s:gitignore_ext_cache = v:null
function! s:gitignore_extensions() abort
  if s:gitignore_ext_cache isnot v:null
    return s:gitignore_ext_cache
  endif
  let s:gitignore_ext_cache = {}
  let l:gi = findfile('.gitignore', '.;')
  if empty(l:gi) | return s:gitignore_ext_cache | endif
  for l:line in readfile(l:gi)
    let l:line = trim(l:line)
    if empty(l:line) || l:line[0] ==# '#' | continue | endif
    " Match patterns like *.ext or **/*.ext (not negated)
    if l:line[0] ==# '!' | continue | endif
    let l:ext = matchstr(l:line, '^\%(\*\*/\)\?\*\.\zs[a-zA-Z0-9_+]\+$')
    if !empty(l:ext)
      let s:gitignore_ext_cache[l:ext] = 1
    endif
  endfor
  return s:gitignore_ext_cache
endfunction

" Check if ALL extensions of a type are gitignored
function! s:type_fully_ignored(type_name, type_exts, gi_exts) abort
  let l:exts = get(a:type_exts, a:type_name, [])
  if empty(l:exts) | return 0 | endif
  for l:ext in l:exts
    if !has_key(a:gi_exts, l:ext) | return 0 | endif
  endfor
  return 1
endfunction

function! s:reset_tab_cycle() abort
  let s:state.tab_cycling = 0
  let s:state.tab_candidates = []
  let s:state.tab_suffix = ''
  " Keep tab_idx so the hint highlight persists on the last selection
endfunction
