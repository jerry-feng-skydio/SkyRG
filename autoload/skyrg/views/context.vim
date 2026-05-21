" autoload/skyrg/views/context.vim — Context popup view
"
" Shows a cursor-relative action menu with context-aware filtering.
" Actions are provided by the context backend. Users trigger this
" via a key mapping (g:skyrg_context_key).
"
" See docs/architecture/context-popup.md for the full spec.
"
" Usage:
"   call skyrg#views#context#open('n')   " normal mode
"   call skyrg#views#context#open('v')   " visual mode

let s:popup_id = 0
let s:actions = []
let s:ctx = {}
let s:selected = 0

"==============================================================================
" Open
"==============================================================================

function! skyrg#views#context#open(mode) abort
  " Build context from cursor position
  let s:ctx = s:build_context(a:mode)

  " Get filtered actions
  let s:actions = skyrg#backend#context#get(s:ctx)
  if empty(s:actions)
    echo '[SkyRG] No actions available'
    return
  endif

  let s:selected = 0
  call skyrg#log#info('views/context', 'open mode=%s actions=%d word="%s"',
    \ a:mode, len(s:actions), s:ctx.word)

  " Build popup content
  let l:lines = s:render()

  " Calculate position (cursor-relative)
  let l:pos = screenpos(win_getid(), line('.'), col('.'))
  let l:line = l:pos.row + 1
  let l:col = l:pos.col

  " Determine width from longest action label
  let l:max_w = 0
  for l:a in s:actions
    let l:label = has_key(l:a, 'label_fn') ? l:a.label_fn(s:ctx) : l:a.name
    let l:w = len(l:label) + 6
    if l:w > l:max_w | let l:max_w = l:w | endif
  endfor

  " Close any existing popup
  if s:popup_id | silent! call popup_close(s:popup_id) | endif

  " Create popup
  call skyrg#ui#style#init()
  let s:popup_id = popup_create(l:lines, {
    \ 'line': l:line,
    \ 'col': l:col,
    \ 'pos': 'topleft',
    \ 'width': l:max_w,
    \ 'padding': [0, 1, 0, 1],
    \ 'border': [1, 1, 1, 1],
    \ 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    \ 'borderhighlight': ['Title'],
    \ 'highlight': 'Normal',
    \ 'title': ' Actions ',
    \ 'filter': function('s:on_key'),
    \ 'mapping': 0,
    \ 'callback': function('s:on_close'),
    \ 'zindex': 300,
    \ })
endfunction

"==============================================================================
" Context builder
"==============================================================================

function! s:build_context(mode) abort
  let l:ctx = {
    \ 'word':     expand('<cword>'),
    \ 'WORD':     expand('<cWORD>'),
    \ 'line':     getline('.'),
    \ 'col':      col('.'),
    \ 'filetype': &filetype,
    \ 'mode':     a:mode,
    \ 'file':     expand('%:p'),
    \ 'dir':      expand('%:p:h'),
    \ 'visual':   '',
    \ }
  " Get visual selection if in visual mode
  if a:mode ==# 'v'
    let [l:l1, l:c1] = getpos("'<")[1:2]
    let [l:l2, l:c2] = getpos("'>")[1:2]
    if l:l1 == l:l2
      let l:ctx.visual = getline(l:l1)[l:c1-1 : l:c2-1]
    else
      let l:lines = getline(l:l1, l:l2)
      let l:lines[0] = l:lines[0][l:c1-1:]
      let l:lines[-1] = l:lines[-1][:l:c2-1]
      let l:ctx.visual = join(l:lines, "\n")
    endif
  endif
  return l:ctx
endfunction

"==============================================================================
" Key handling
"==============================================================================

function! s:on_key(winid, key) abort
  " Escape: close
  if a:key ==# "\<Esc>" || a:key ==# "\<C-c>"
    call popup_close(a:winid)
    return 1
  endif

  " Up/Down: navigate
  if a:key ==# "\<Up>" || a:key ==# 'k'
    let s:selected = max([0, s:selected - 1])
    call popup_settext(a:winid, s:render())
    return 1
  endif
  if a:key ==# "\<Down>" || a:key ==# 'j'
    let s:selected = min([len(s:actions) - 1, s:selected + 1])
    call popup_settext(a:winid, s:render())
    return 1
  endif

  " Enter: execute selected action
  if a:key ==# "\<CR>"
    let l:action = s:actions[s:selected]
    call skyrg#log#info('views/context', 'execute "%s"', l:action.name)
    call popup_close(a:winid)
    call skyrg#backend#context#execute(l:action, s:ctx)
    return 1
  endif

  " Letter shortcut: find action by key
  if len(a:key) == 1 && a:key =~# '[a-zA-Z]'
    for l:i in range(len(s:actions))
      if get(s:actions[l:i], 'key', '') ==# a:key
        let l:action = s:actions[l:i]
        call skyrg#log#info('views/context', 'execute "%s" (key=%s)', l:action.name, a:key)
        call popup_close(a:winid)
        call skyrg#backend#context#execute(l:action, s:ctx)
        return 1
      endif
    endfor
  endif

  return 1
endfunction

function! s:on_close(id, result) abort
  let s:popup_id = 0
  call skyrg#ui#style#cleanup()
endfunction

"==============================================================================
" Rendering
"==============================================================================

function! s:render() abort
  let l:lines = []
  let l:prev_group = ''
  for l:i in range(len(s:actions))
    let l:a = s:actions[l:i]
    let l:group = get(l:a, 'group', '')
    " Group separator
    if !empty(l:group) && l:group !=# l:prev_group && l:i > 0
      call add(l:lines, {'text': ''})
    endif
    let l:prev_group = l:group
    " Format: [key] Action name (label_fn overrides static name)
    let l:key_str = has_key(l:a, 'key') ? '['.l:a.key.'] ' : '    '
    let l:label = has_key(l:a, 'label_fn') ? l:a.label_fn(s:ctx) : l:a.name
    let l:text = '  ' . l:key_str . l:label
    if l:i == s:selected
      call add(l:lines, skyrg#ui#util#hl_line(l:text, 'skyrg_sel'))
    else
      let l:props = []
      if has_key(l:a, 'key')
        call add(l:props, {'col': 3, 'length': len(l:key_str), 'type': 'skyrg_dim'})
      endif
      call add(l:lines, empty(l:props) ? {'text': l:text} : {'text': l:text, 'props': l:props})
    endif
  endfor
  return l:lines
endfunction
