" autoload/skyrg/panel/form.vim — Form rendering and key handling
"
" Owns state.form: {field, fields}

"==============================================================================
" Key handling
"==============================================================================
function! skyrg#panel#form#on_key(key) abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  let l:fm = l:s.form
  let l:f = l:fm.fields[l:fm.field]
  let l:changed = 0
  " Any non-Tab key resets the tab-cycle state
  if a:key !=# "\<Tab>" | call skyrg#panel#complete#reset_tab_cycle() | endif
  if a:key ==# "\<C-Up>"
    let l:fm.field = (l:fm.field - 1 + l:c.NFIELDS) % l:c.NFIELDS
  elseif a:key ==# "\<C-Down>"
    let l:fm.field = (l:fm.field + 1) % l:c.NFIELDS
  elseif l:fm.field == l:c.PRESET && (a:key ==# "\<Left>" || a:key ==# "\<Right>")
    call skyrg#panel#preset#cycle(a:key ==# "\<Right>" ? 1 : -1)
    let l:changed = 1
  elseif l:fm.field == l:c.PRESET && (a:key ==# "\<BS>" || a:key ==# "\<Del>" || a:key ==# nr2char(127))
    let l:f.value = '' | let l:f.pos = 0
    let l:fm.fields[l:c.TYPES].value = ''
    let l:fm.fields[l:c.TYPES].pos = 0
    let l:fm.fields[l:c.DIRS].value = ''
    let l:fm.fields[l:c.DIRS].pos = 0
    let l:changed = 1
  elseif l:fm.field == l:c.PRESET
    " Block all other input on Preset field
    call skyrg#panel#form#redraw()
    return 1
  elseif l:fm.field == l:c.GITIGN && a:key ==# ' '
    let l:f.value = l:f.value ==# 'on' ? 'off' : 'on'
    let l:changed = 1
  elseif a:key ==# "\<CR>"
    call skyrg#panel#results#jump()
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
    call skyrg#panel#util#del_word(l:f) | let l:changed = 1
  elseif (a:key ==# "\<C-n>" || a:key ==# "\<C-p>") && l:fm.field == l:c.PRESET
    call skyrg#panel#preset#cycle(a:key ==# "\<C-n>" ? 1 : -1) | let l:changed = 1
  elseif len(a:key) == 1 && char2nr(a:key) >= 32 && l:fm.field != l:c.GITIGN
    let l:b = l:f.pos > 0 ? l:f.value[:l:f.pos-1] : ''
    let l:f.value = l:b . a:key . l:f.value[l:f.pos:]
    let l:f.pos += 1 | let l:changed = 1
  endif
  call skyrg#panel#form#redraw()
  if l:changed | call skyrg#panel#search#schedule() | endif
  return 1
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
    return skyrg#panel#util#hl_line('  e.g. py,cpp,java  (Tab to complete, comma-separated)', 'skyrg_dim')
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
  return skyrg#panel#util#hl_line('  C-Up/C-Down: fields  Up/Down: matches  Tab: presets  Enter: open', 'skyrg_dim')
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
