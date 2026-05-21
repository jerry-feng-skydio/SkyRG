" autoload/skyrg/ui/panes/form.vim — Generic multi-field editor pane
"
" A reusable form pane with configurable fields, cursor editing, and
" field navigation. Conforms to the pane protocol.
"
" Usage:
"   let pane = skyrg#ui#panes#form#new({
"     \ 'fields': [
"     \   {'label': 'Query', 'type': 'text',   'value': ''},
"     \   {'label': 'Preset','type': 'select', 'value': '', 'options_fn': ...},
"     \   {'label': '.gitignore', 'type': 'toggle', 'value': 'on'},
"     \ ],
"     \ 'on_change':  function('s:on_field_change'),
"     \ 'on_submit':  function('s:on_submit'),
"     \ 'hint_fn':    function('s:hint'),
"     \ 'is_active_fn': function('s:is_form_active'),
"     \ })
"
" Field types:
"   'text'    — free-text input with cursor
"   'toggle'  — space toggles between 'on'/'off'
"   'select'  — left/right cycles through options, letters jump
"   'readonly'— display only, no editing

"==============================================================================
" Constructor
"==============================================================================

function! skyrg#ui#panes#form#new(config) abort
  " Initialize field state from config
  let l:fields = []
  for l:f in a:config.fields
    call add(l:fields, {
      \ 'label':  l:f.label,
      \ 'type':   get(l:f, 'type', 'text'),
      \ 'value':  get(l:f, 'value', ''),
      \ 'pos':    len(get(l:f, 'value', '')),
      \ })
  endfor

  let l:pane = {
    \ 'name':   '',
    \ 'config': a:config,
    \ 'state':  {'fields': l:fields, 'field_idx': 0},
    \ '_geo':   {'height': 7, 'width': 40},
    \ '_focused': 0,
    \ }

  " --- Pane protocol methods ---

  function! l:pane.render() dict abort
    return s:render_form(self)
  endfunction

  function! l:pane.on_key(key, K) dict abort
    return s:handle_key(self, a:key, a:K)
  endfunction

  function! l:pane.on_focus() dict abort
    let self._focused = 1
  endfunction

  function! l:pane.on_blur() dict abort
    let self._focused = 0
  endfunction

  function! l:pane.on_resize(geo) dict abort
    let self._geo = a:geo
  endfunction

  function! l:pane.cleanup() dict abort
  endfunction

  " --- Public helpers ---

  " Get a snapshot of all field values as a dict {label: value}
  function! l:pane.get_values() dict abort
    let l:d = {}
    for l:f in self.state.fields
      let l:d[l:f.label] = l:f.value
    endfor
    return l:d
  endfunction

  " Set field values from a dict {label: value}
  function! l:pane.set_values(d) dict abort
    for l:f in self.state.fields
      if has_key(a:d, l:f.label)
        let l:f.value = a:d[l:f.label]
        let l:f.pos = len(l:f.value)
      endif
    endfor
  endfunction

  " Get the currently focused field dict
  function! l:pane.current_field() dict abort
    return self.state.fields[self.state.field_idx]
  endfunction

  return l:pane
endfunction

"==============================================================================
" Key handling
"==============================================================================

function! s:handle_key(pane, key, K) abort
  let l:fm = a:pane.state
  let l:f = l:fm.fields[l:fm.field_idx]
  let l:old_val = l:f.value
  let l:changed = 0

  " Up/Down: navigate fields
  if a:K(a:key, 'query_field_up')
    let l:fm.field_idx = (l:fm.field_idx - 1 + len(l:fm.fields)) % len(l:fm.fields)
    return 1
  elseif a:K(a:key, 'query_field_down')
    let l:fm.field_idx = (l:fm.field_idx + 1) % len(l:fm.fields)
    return 1
  endif

  " Type-specific handling
  if l:f.type ==# 'toggle'
    if a:key ==# ' '
      let l:f.value = l:f.value ==# 'on' ? 'off' : 'on'
      let l:changed = 1
    endif
    return l:changed

  elseif l:f.type ==# 'select'
    " Left/Right cycle through options
    if a:K(a:key, 'query_cursor_left') || a:K(a:key, 'query_cursor_right')
      if has_key(a:pane.config, 'on_select_cycle')
        let l:dir = a:K(a:key, 'query_cursor_right') ? 1 : -1
        call a:pane.config.on_select_cycle(l:fm.field_idx, l:dir)
        let l:changed = 1
      endif
      return 1
    " Delete clears
    elseif a:K(a:key, 'query_del_char') || a:K(a:key, 'query_del_forward')
      if has_key(a:pane.config, 'on_select_clear')
        call a:pane.config.on_select_clear(l:fm.field_idx)
        let l:changed = 1
      endif
      return 1
    " Letters jump
    elseif len(a:key) == 1 && a:key =~# '[a-zA-Z]'
      if has_key(a:pane.config, 'on_select_letter')
        call a:pane.config.on_select_letter(l:fm.field_idx, a:key)
        let l:changed = 1
      endif
      return 1
    endif
    " Block other input on select fields
    return 1

  elseif l:f.type ==# 'readonly'
    return 0
  endif

  " --- Text field handling ---

  " Enter: submit
  if a:K(a:key, 'query_search')
    if has_key(a:pane.config, 'on_submit')
      call a:pane.config.on_submit(a:pane.get_values())
    endif
    return 1
  endif

  " Cursor movement
  if a:K(a:key, 'query_cursor_left')
    let l:f.pos = max([0, l:f.pos - 1])
    return 1
  elseif a:K(a:key, 'query_cursor_right')
    let l:f.pos = min([len(l:f.value), l:f.pos + 1])
    return 1
  elseif a:K(a:key, 'query_home')
    let l:f.pos = 0
    return 1
  elseif a:K(a:key, 'query_end')
    let l:f.pos = len(l:f.value)
    return 1
  endif

  " Editing
  if a:K(a:key, 'query_del_char')
    if l:f.pos > 0
      let l:f.value = (l:f.pos > 1 ? l:f.value[:l:f.pos-2] : '') . l:f.value[l:f.pos:]
      let l:f.pos -= 1
      let l:changed = 1
    endif
    return 1
  elseif a:K(a:key, 'query_del_forward')
    if l:f.pos < len(l:f.value)
      let l:b = l:f.pos > 0 ? l:f.value[:l:f.pos-1] : ''
      let l:f.value = l:b . (l:f.pos+1 < len(l:f.value) ? l:f.value[l:f.pos+1:] : '')
      let l:changed = 1
    endif
    return 1
  elseif a:K(a:key, 'query_del_line')
    let l:f.value = '' | let l:f.pos = 0
    let l:changed = 1
    return 1
  elseif a:K(a:key, 'query_del_word')
    call skyrg#ui#util#del_word(l:f)
    let l:changed = 1
    return 1
  endif

  " Printable character input
  if len(a:key) == 1 && char2nr(a:key) >= 32
    let l:b = l:f.pos > 0 ? l:f.value[:l:f.pos-1] : ''
    let l:f.value = l:b . a:key . l:f.value[l:f.pos:]
    let l:f.pos += 1
    let l:changed = 1
    return 1
  endif

  " Notify on change
  if l:changed && has_key(a:pane.config, 'on_change')
    call a:pane.config.on_change(l:fm.field_idx, l:old_val, l:f.value)
  endif

  return 0
endfunction

"==============================================================================
" Rendering
"==============================================================================

function! s:render_form(pane) abort
  let l:fm = a:pane.state
  let l:act_fn = get(a:pane.config, 'is_active_fn', 0)
  let l:is_active = l:act_fn isnot 0 ? l:act_fn() : a:pane._focused
  let l:lines = []

  for l:i in range(len(l:fm.fields))
    let l:f = l:fm.fields[l:i]
    let l:act = l:i == l:fm.field_idx && l:is_active

    if l:f.type ==# 'toggle'
      let l:chk = l:f.value ==# 'on' ? 'x' : ' '
      let l:text = printf(' %s [%s] %s', l:act ? '>' : ' ', l:chk, l:f.label)
      let l:props = [{'col': 1, 'length': len(l:text), 'type': 'skyrg_dim'}]
      if l:act
        call add(l:props, {'col': 4, 'length': 3, 'type': 'skyrg_cursor'})
      endif
      call add(l:lines, {'text': l:text, 'props': l:props})

    elseif l:f.type ==# 'select'
      let l:val = empty(l:f.value) ? '(None)' : l:f.value
      let l:pfx = printf(' %s %-8s ', l:act ? '>' : ' ', l:f.label . ':')
      let l:text = l:pfx . "\u25C0 " . l:val . " \u25B6"
      let l:props = [{'col': 1, 'length': len(l:pfx), 'type': 'skyrg_dim'}]
      if l:act
        call add(l:props, {'col': len(l:pfx)+1, 'length': len(l:text)-len(l:pfx), 'type': 'skyrg_cursor'})
      endif
      call add(l:lines, {'text': l:text, 'props': l:props})

    else " text / readonly
      let l:pfx = printf(' %s %-8s ', l:act ? '>' : ' ', l:f.label . ':')
      let l:text = l:pfx . l:f.value . (l:act ? ' ' : '')
      let l:props = [{'col': 1, 'length': len(l:pfx), 'type': 'skyrg_dim'}]
      if l:act && l:f.type !=# 'readonly'
        call add(l:props, {'col': len(l:pfx)+l:f.pos+1, 'length': 1, 'type': 'skyrg_cursor'})
      endif
      call add(l:lines, {'text': l:text, 'props': l:props})
    endif
  endfor

  " Hint line
  if has_key(a:pane.config, 'hint_fn')
    call add(l:lines, a:pane.config.hint_fn(l:fm.field_idx))
  endif

  return l:lines
endfunction
