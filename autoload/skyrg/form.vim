" skyrg/form.vim - Interactive popup search form
"
" Opens a multi-field popup for building SkyRG searches interactively.
" Fields: Query, Types, Dirs, Preset
"
" Navigation:
"   Tab / S-Tab / Down / Up    move between fields
"   Left / Right / Home / End  cursor within a field
"   Ctrl-N / Ctrl-P            cycle presets (in Preset field)
"   Ctrl-U                     clear field
"   Ctrl-W                     delete word back (comma/slash/space aware)
"   Enter                      run search
"   Esc                        cancel

let s:LABEL_PAD = 9

" Field order matters — index used for preset auto-populate
let s:QUERY  = 0
let s:TYPES  = 1
let s:DIRS   = 2
let s:PRESET = 3

let s:state = {}

"==============================================================================
" Public API
"==============================================================================

function! skyrg#form#open() abort
  if !exists('*popup_create')
    call skyrg#log#error('[SkyRG] Form requires Vim 8.2+ with +popupwin')
    return
  endif

  let s:state = {
    \ 'id': 0,
    \ 'active': s:QUERY,
    \ 'fields': [
    \   {'label': 'Query',  'value': '', 'pos': 0},
    \   {'label': 'Types',  'value': '', 'pos': 0},
    \   {'label': 'Dirs',   'value': '', 'pos': 0},
    \   {'label': 'Preset', 'value': '', 'pos': 0},
    \ ],
    \ }

  silent! call prop_type_delete('skyrg_cursor')
  call prop_type_add('skyrg_cursor', {'highlight': 'TermCursor'})

  let s:state.id = popup_create(s:render(), {
    \ 'title': ' SkyRG ',
    \ 'border': [],
    \ 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    \ 'padding': [0, 1, 0, 1],
    \ 'filter': function('s:on_key'),
    \ 'mapping': 0,
    \ 'pos': 'center',
    \ 'minwidth': 55,
    \ 'maxwidth': 80,
    \ })
endfunction

"==============================================================================
" Key handler
"==============================================================================

function! s:on_key(id, key) abort
  let l:f = s:state.fields[s:state.active]

  " ── Navigation ──────────────────────────────────────────────────────────
  if a:key == "\<Tab>" || a:key == "\<C-j>" || a:key == "\<Down>"
    call s:on_leave_field()
    let s:state.active = (s:state.active + 1) % len(s:state.fields)

  elseif a:key == "\<S-Tab>" || a:key == "\<C-k>" || a:key == "\<Up>"
    call s:on_leave_field()
    let s:state.active = (s:state.active - 1 + len(s:state.fields)) % len(s:state.fields)

  " ── Submit / Cancel ─────────────────────────────────────────────────────
  elseif a:key == "\<CR>"
    call s:submit()
    return 1

  elseif a:key == "\<Esc>"
    call popup_close(a:id)
    return 1

  " ── Cursor movement ─────────────────────────────────────────────────────
  elseif a:key == "\<Left>"
    let l:f.pos = max([0, l:f.pos - 1])

  elseif a:key == "\<Right>"
    let l:f.pos = min([len(l:f.value), l:f.pos + 1])

  elseif a:key == "\<Home>" || a:key == "\<C-a>"
    let l:f.pos = 0

  elseif a:key == "\<End>" || a:key == "\<C-e>"
    let l:f.pos = len(l:f.value)

  " ── Editing ─────────────────────────────────────────────────────────────
  elseif a:key == "\<BS>" || a:key == "\<C-h>"
    if l:f.pos > 0
      let l:before = l:f.pos >= 2 ? l:f.value[:l:f.pos - 2] : ''
      let l:f.value = l:before . l:f.value[l:f.pos:]
      let l:f.pos -= 1
    endif

  elseif a:key == "\<Del>"
    if l:f.pos < len(l:f.value)
      let l:before = l:f.pos > 0 ? l:f.value[:l:f.pos - 1] : ''
      let l:after = l:f.pos + 1 < len(l:f.value) ? l:f.value[l:f.pos + 1:] : ''
      let l:f.value = l:before . l:after
    endif

  elseif a:key == "\<C-u>"
    let l:f.value = ''
    let l:f.pos = 0

  elseif a:key == "\<C-w>"
    call s:delete_word_back(l:f)

  " ── Preset cycling (only in Preset field) ───────────────────────────────
  elseif (a:key == "\<C-n>" || a:key == "\<C-p>") && s:state.active == s:PRESET
    call s:cycle_preset(a:key == "\<C-n>" ? 1 : -1)

  " ── Character input ─────────────────────────────────────────────────────
  elseif len(a:key) == 1 && char2nr(a:key) >= 32
    let l:before = l:f.pos > 0 ? l:f.value[:l:f.pos - 1] : ''
    let l:f.value = l:before . a:key . l:f.value[l:f.pos:]
    let l:f.pos += 1

  endif

  call s:redraw()
  return 1
endfunction

"==============================================================================
" Rendering
"==============================================================================

function! s:render() abort
  let l:lines = []

  for l:i in range(len(s:state.fields))
    let l:f = s:state.fields[l:i]
    let l:is_active = l:i == s:state.active
    let l:ind = l:is_active ? '>' : ' '
    let l:label = printf('%-' . s:LABEL_PAD . 's', l:f.label . ':')
    " Trailing space on active field gives the cursor somewhere to land at EOL
    let l:val = l:f.value . (l:is_active ? ' ' : '')
    let l:prefix = printf(' %s %s ', l:ind, l:label)
    let l:text = l:prefix . l:val

    if l:is_active
      let l:cursor_col = len(l:prefix) + l:f.pos + 1
      call add(l:lines, {'text': l:text, 'props': [
        \ {'col': l:cursor_col, 'length': 1, 'type': 'skyrg_cursor'}
        \ ]})
    else
      call add(l:lines, l:text)
    endif
  endfor

  " Context-sensitive hint
  let l:hint = s:get_hint()
  call add(l:lines, '')
  if l:hint !=# ''
    call add(l:lines, l:hint)
  endif
  call add(l:lines, ' Tab: next  Enter: search  Esc: cancel')

  return l:lines
endfunction

function! s:redraw() abort
  call popup_settext(s:state.id, s:render())
endfunction

function! s:get_hint() abort
  let l:label = s:state.fields[s:state.active].label
  if l:label ==# 'Types'
    return ' Comma-separated extensions (e.g. cc,h,py)'
  elseif l:label ==# 'Dirs'
    return ' Comma-separated paths relative to cwd'
  elseif l:label ==# 'Preset'
    let l:names = s:available_presets()
    if empty(l:names)
      return ' No presets registered'
    endif
    return ' Ctrl-N/P to cycle: ' . join(l:names, ', ')
  endif
  return ''
endfunction

"==============================================================================
" Submit
"==============================================================================

function! s:submit() abort
  let l:query  = s:field_value(s:QUERY)
  let l:types  = s:field_value(s:TYPES)
  let l:dirs   = s:field_value(s:DIRS)
  let l:preset = s:field_value(s:PRESET)

  call popup_close(s:state.id)

  let l:args = []
  if l:preset !=# ''
    call extend(l:args, ['-p', l:preset])
  endif
  if l:types !=# ''
    call extend(l:args, ['-f', l:types])
  endif
  if l:dirs !=# ''
    call extend(l:args, ['-d', l:dirs])
  endif
  if l:query !=# ''
    call extend(l:args, split(l:query))
  endif

  if empty(l:args)
    call skyrg#log#error('[SkyRG] Nothing to search')
    return
  endif

  call call('skyrg#search', l:args)
endfunction

"==============================================================================
" Preset interaction
"==============================================================================

" When leaving Preset field, auto-populate Types/Dirs if they're empty.
function! s:on_leave_field() abort
  if s:state.active == s:PRESET
    call s:apply_preset()
  endif
endfunction

" Populate Types/Dirs from the named preset (only fills empty fields).
function! s:apply_preset() abort
  let l:name = s:field_value(s:PRESET)
  if l:name ==# '' || !exists('g:SkyFilter') || !has_key(g:SkyFilter.presets, l:name)
    return
  endif

  let l:preset = g:SkyFilter.presets[l:name]

  " Auto-fill Types if empty
  if s:field_value(s:TYPES) ==# '' && has_key(l:preset, 'type')
    let l:inc = sort(filter(keys(l:preset.type), {_, k -> l:preset.type[k] == 1}))
    if !empty(l:inc)
      let s:state.fields[s:TYPES].value = join(l:inc, ',')
      let s:state.fields[s:TYPES].pos = len(s:state.fields[s:TYPES].value)
    endif
  endif

  " Auto-fill Dirs if empty
  if s:field_value(s:DIRS) ==# '' && has_key(l:preset, 'dir')
    let l:inc = sort(filter(keys(l:preset.dir), {_, k -> l:preset.dir[k] == 1}))
    if !empty(l:inc)
      let s:state.fields[s:DIRS].value = join(l:inc, ',')
      let s:state.fields[s:DIRS].pos = len(s:state.fields[s:DIRS].value)
    endif
  endif
endfunction

" Cycle through available presets with Ctrl-N / Ctrl-P.
function! s:cycle_preset(direction) abort
  let l:names = s:available_presets()
  if empty(l:names)
    return
  endif

  let l:f = s:state.fields[s:PRESET]
  let l:idx = index(l:names, l:f.value)

  if l:idx < 0
    let l:idx = a:direction > 0 ? 0 : len(l:names) - 1
  else
    let l:idx = (l:idx + a:direction + len(l:names)) % len(l:names)
  endif

  let l:f.value = l:names[l:idx]
  let l:f.pos = len(l:f.value)

  " Clear Types/Dirs so apply_preset can refill for the new preset
  let s:state.fields[s:TYPES].value = ''
  let s:state.fields[s:TYPES].pos = 0
  let s:state.fields[s:DIRS].value = ''
  let s:state.fields[s:DIRS].pos = 0
  call s:apply_preset()
endfunction

function! s:available_presets() abort
  if !exists('g:SkyFilter') || !has_key(g:SkyFilter, 'presets')
    return []
  endif
  " Filter out internal/ephemeral presets
  return sort(filter(keys(g:SkyFilter.presets),
    \ {_, v -> v !~# '^\(ACTIVE\|DEFAULT\)'}))
endfunction

"==============================================================================
" Editing helpers
"==============================================================================

" Delete backward to the nearest comma, slash, or space.
function! s:delete_word_back(field) abort
  if a:field.pos == 0
    return
  endif
  let l:before = a:field.value[:a:field.pos - 1]
  " Strip trailing separators first so repeated Ctrl-W makes progress
  let l:trimmed = substitute(l:before, '[,/ ]*$', '', '')
  if l:trimmed ==# ''
    let l:new_pos = 0
  else
    let l:stop = max([strridx(l:trimmed, ','), strridx(l:trimmed, '/'), strridx(l:trimmed, ' ')])
    let l:new_pos = l:stop < 0 ? 0 : l:stop + 1
  endif
  let a:field.value = (l:new_pos > 0 ? a:field.value[:l:new_pos - 1] : '') . a:field.value[a:field.pos:]
  let a:field.pos = l:new_pos
endfunction

function! s:field_value(index) abort
  return trim(s:state.fields[a:index].value)
endfunction
