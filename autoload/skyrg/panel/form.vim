" autoload/skyrg/panel/form.vim — Form rendering and key handling
"
" Owns state.form: {field, fields}

"==============================================================================
" Key handling
"==============================================================================
function! skyrg#panel#form#on_key(key) abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  let l:K = function('skyrg#panel#keymap#is')
  let l:fm = l:s.form
  let l:f = l:fm.fields[l:fm.field]
  let l:field_before = l:fm.field
  let l:dirty = 0
  " Any non-Tab key resets the tab-cycle state
  if !l:K(a:key, 'query_complete') | call skyrg#panel#complete#reset_tab_cycle() | endif

  " Up/Down: navigate form fields
  if l:K(a:key, 'query_field_up')
    let l:fm.field = (l:fm.field - 1 + l:c.NFIELDS) % l:c.NFIELDS
  elseif l:K(a:key, 'query_field_down')
    let l:fm.field = (l:fm.field + 1) % l:c.NFIELDS

  " Preset field: Left/Right cycles, BS clears
  elseif l:fm.field == l:c.PRESET && (l:K(a:key, 'query_cursor_left') || l:K(a:key, 'query_cursor_right'))
    call skyrg#panel#preset#cycle(l:K(a:key, 'query_cursor_right') ? 1 : -1)
    let l:dirty = 1
  elseif l:fm.field == l:c.PRESET && (l:K(a:key, 'query_del_char') || l:K(a:key, 'query_del_forward'))
    let l:f.value = '' | let l:f.pos = 0
    let l:fm.fields[l:c.TYPES].value = ''
    let l:fm.fields[l:c.TYPES].pos = 0
    let l:fm.fields[l:c.DIRS].value = ''
    let l:fm.fields[l:c.DIRS].pos = 0
    let l:dirty = 1
  elseif l:fm.field == l:c.PRESET
    " Block all other input on Preset field
    call skyrg#panel#form#redraw()
    return 1

  " Gitignore toggle
  elseif l:fm.field == l:c.GITIGN && a:key ==# ' '
    let l:f.value = l:f.value ==# 'on' ? 'off' : 'on'
    let l:dirty = 1

  " Enter: behaviour depends on g:skyrg_user_must_initiate_search
  elseif l:K(a:key, 'query_search')
    if s:must_initiate()
      " Manual mode: first Enter runs search, second Enter activates results
      if get(l:s, '_search_dirty', 1)
        let l:s._search_dirty = 0
        call skyrg#panel#search#run()
      elseif !empty(l:s.results.matches)
        call skyrg#panel#set_pane(l:c.PANE_RESULTS)
      endif
    else
      " Auto mode: search already running/done, Enter activates results
      if !empty(l:s.results.matches)
        call skyrg#panel#set_pane(l:c.PANE_RESULTS)
      endif
    endif
    call skyrg#panel#form#redraw()
    return 1

  " Cursor movement
  elseif l:K(a:key, 'query_cursor_left')
    let l:f.pos = max([0, l:f.pos - 1])
  elseif l:K(a:key, 'query_cursor_right')
    let l:f.pos = min([len(l:f.value), l:f.pos + 1])
  elseif l:K(a:key, 'query_home')
    let l:f.pos = 0
  elseif l:K(a:key, 'query_end')
    let l:f.pos = len(l:f.value)

  " Editing
  elseif l:K(a:key, 'query_del_char')
    if l:f.pos > 0
      let l:f.value = (l:f.pos > 1 ? l:f.value[:l:f.pos-2] : '') . l:f.value[l:f.pos:]
      let l:f.pos -= 1
      let l:dirty = 1
    endif
  elseif l:K(a:key, 'query_del_forward')
    if l:f.pos < len(l:f.value)
      let l:b = l:f.pos > 0 ? l:f.value[:l:f.pos-1] : ''
      let l:f.value = l:b . (l:f.pos+1 < len(l:f.value) ? l:f.value[l:f.pos+1:] : '')
      let l:dirty = 1
    endif
  elseif l:K(a:key, 'query_del_line')
    let l:f.value = '' | let l:f.pos = 0
    let l:dirty = 1
  elseif l:K(a:key, 'query_del_word')
    call skyrg#panel#util#del_word(l:f)
    let l:dirty = 1

  " C-n/C-p: preset cycling (alternate binding)
  elseif (a:key ==# "\<C-n>" || a:key ==# "\<C-p>") && l:fm.field == l:c.PRESET
    call skyrg#panel#preset#cycle(a:key ==# "\<C-n>" ? 1 : -1)
    let l:dirty = 1

  " Printable character input
  elseif len(a:key) == 1 && char2nr(a:key) >= 32 && l:fm.field != l:c.GITIGN
    let l:b = l:f.pos > 0 ? l:f.value[:l:f.pos-1] : ''
    let l:f.value = l:b . a:key . l:f.value[l:f.pos:]
    let l:f.pos += 1
    let l:dirty = 1
  endif

  " Schedule auto-search or mark dirty depending on config
  if l:dirty
    let l:s._search_dirty = 1
    if !s:must_initiate()
      call skyrg#panel#search#schedule()
    endif
  endif

  call skyrg#panel#form#redraw()
  " Show preset details when Preset field is active; restore match preview otherwise
  if l:fm.field == l:c.PRESET
    call skyrg#panel#preview#show_preset(l:fm.fields[l:c.PRESET].value)
  elseif l:field_before != l:fm.field
    call skyrg#panel#preview#update()
  endif
  return 1
endfunction

function! s:must_initiate() abort
  return get(g:, 'skyrg_user_must_initiate_search', 0)
endfunction

"==============================================================================
" Rendering
"==============================================================================
function! skyrg#panel#form#render() abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  let l:fm = l:s.form
  let l:lines = []
  for l:i in range(l:c.NFIELDS)
    let l:f = l:fm.fields[l:i]
    let l:act = l:i == l:fm.field && l:s.pane == l:c.PANE_FORM
    if l:i == l:c.GITIGN
      let l:chk = l:f.value ==# 'on' ? 'x' : ' '
      let l:text = printf(' %s [%s] %s', l:act ? '>' : ' ', l:chk, l:f.label)
      let l:props = [{'col': 1, 'length': len(l:text), 'type': 'skyrg_dim'}]
      if l:act
        call add(l:props, {'col': 4, 'length': 3, 'type': 'skyrg_cursor'})
      endif
      call add(l:lines, {'text': l:text, 'props': l:props})
    elseif l:i == l:c.PRESET
      let l:val = empty(l:f.value) ? '(None)' : l:f.value
      let l:pfx = printf(' %s %-8s ', l:act ? '>' : ' ', l:f.label . ':')
      let l:text = l:pfx . '◀ ' . l:val . ' ▶'
      let l:props = [{'col': 1, 'length': len(l:pfx), 'type': 'skyrg_dim'}]
      if l:act
        call add(l:props, {'col': len(l:pfx)+1, 'length': len(l:text)-len(l:pfx), 'type': 'skyrg_cursor'})
      endif
      call add(l:lines, {'text': l:text, 'props': l:props})
    else
      let l:pfx = printf(' %s %-8s ', l:act ? '>' : ' ', l:f.label . ':')
      let l:text = l:pfx . l:f.value . (l:act ? ' ' : '')
      let l:props = [{'col': 1, 'length': len(l:pfx), 'type': 'skyrg_dim'}]
      if l:act
        call add(l:props, {'col': len(l:pfx)+l:f.pos+1, 'length': 1, 'type': 'skyrg_cursor'})
      endif
      call add(l:lines, {'text': l:text, 'props': l:props})
    endif
  endfor
  call add(l:lines, s:hint())
  return l:lines
endfunction

function! skyrg#panel#form#redraw() abort
  let l:s = skyrg#panel#state()
  call popup_settext(l:s.popups.form, skyrg#panel#form#render())
endfunction

"==============================================================================
" Hint line
"==============================================================================
function! s:hint() abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  let l:fm = l:s.form
  let l:lab = l:fm.fields[l:fm.field].label
  if l:lab ==# 'Preset'
    let l:n = skyrg#panel#preset#names()
    let l:t = empty(l:n) ? '  No presets' : '  Left/Right: cycle  Backspace: reset'
    return skyrg#panel#util#hl_line(l:t, 'skyrg_dim')
  elseif l:lab ==# 'Types'
    let l:cands = get(l:s, 'type_candidates', [])
    if !empty(l:cands)
      return skyrg#panel#form#hint_with_hl(l:cands, 20)
    endif
    return skyrg#panel#util#hl_line('  e.g. py,cpp,.proto  (Tab: complete types  .ext: raw extension)', 'skyrg_dim')
  elseif l:lab ==# 'Dirs'
    let l:cands = get(l:s, 'dir_candidates', [])
    if !empty(l:cands)
      return skyrg#panel#form#hint_with_hl(map(copy(l:cands), 'fnamemodify(v:val, ":t")'), 10)
    endif
    return skyrg#panel#util#hl_line('  e.g. src/,lib/  (Tab to complete, comma-separated)', 'skyrg_dim')
  endif
  if l:lab ==# '.gitignore'
    return skyrg#panel#util#hl_line('  Space: toggle  (rg respects .gitignore by default)', 'skyrg_dim')
  endif
  if s:must_initiate()
    return skyrg#panel#util#hl_line('  Up/Down: fields  Enter: search  Tab: presets  C-Down: results', 'skyrg_dim')
  endif
  return skyrg#panel#util#hl_line('  Up/Down: fields  Enter: results  Tab: presets  C-Down: results', 'skyrg_dim')
endfunction

function! skyrg#panel#form#hint_with_hl(cands, max_show) abort
  let l:s = skyrg#panel#state()
  let l:sel = get(l:s, 'tab_idx', -1)
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
  call insert(l:props, {'col': 1, 'length': len(l:text), 'type': 'skyrg_dim'})
  return {'text': l:text, 'props': l:props}
endfunction
