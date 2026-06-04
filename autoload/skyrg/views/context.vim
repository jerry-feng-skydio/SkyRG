" autoload/skyrg/views/context.vim — Paginated context popup view
"
" Shows a cursor-relative action menu organized into pages (domains).
" Pages are navigated via Left/Right arrows or number keys 0-9.
" Actions within a page are selected via Up/Down or shortcut keys.
"
" Page configuration lives in g:skyrg_pages and g:skyrg_group_pages.
" See backend/context_pages.vim for the page management engine.
"
" Usage:
"   call skyrg#views#context#open('n')   " normal mode
"   call skyrg#views#context#open('v')   " visual mode

let s:popup_id = 0
let s:all_actions = []   " all registered actions (unfiltered)
let s:page_actions = []  " actions for the current page (filtered)
let s:ctx = {}
let s:selected = 0
let s:history_mode = 0   " 1 when showing the history page

"==============================================================================
" Open
"==============================================================================

function! skyrg#views#context#open(mode) abort
  " Build context from cursor position
  let s:ctx = s:build_context(a:mode)

  " Get all actions that pass their predicates
  let s:all_actions = skyrg#backend#context#get_all()

  " Determine which page to open
  let l:page = skyrg#backend#context_pages#resolve_open_page(s:all_actions, s:ctx)
  if l:page < 0
    echo '[SkyRG] No actions available'
    return
  endif
  call skyrg#backend#context_pages#set_current(l:page)
  let s:history_mode = 0
  call s:load_page()

  call skyrg#log#info('views/context', 'open mode=%s page=%d actions=%d',
    \ a:mode, l:page, len(s:page_actions))

  " Calculate position — smart: open below cursor in upper half,
  " above cursor in lower half, so the popup doesn't cover the
  " code the user is referencing or the command-line input zone.
  let l:pos = screenpos(win_getid(), line('.'), col('.'))
  let l:col = l:pos.col
  if l:pos.row > (&lines / 2)
    " Cursor in lower half — open above
    let l:line = l:pos.row - 1
    let l:anchor = 'botleft'
  else
    " Cursor in upper half — open below
    let l:line = l:pos.row + 1
    let l:anchor = 'topleft'
  endif

  " Close any existing popup
  if s:popup_id | silent! call popup_close(s:popup_id) | endif

  " Create popup
  call skyrg#ui#style#init()
  let s:popup_id = popup_create(s:render(), {
    \ 'line': l:line,
    \ 'col': l:col,
    \ 'pos': l:anchor,
    \ 'minwidth': 40,
    \ 'maxwidth': 60,
    \ 'padding': [0, 1, 0, 1],
    \ 'border': [1, 1, 1, 1],
    \ 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    \ 'borderhighlight': ['Title'],
    \ 'highlight': 'Normal',
    \ 'title': s:render_title(),
    \ 'filter': function('s:on_key'),
    \ 'mapping': 0,
    \ 'callback': function('s:on_close'),
    \ 'zindex': 300,
    \ })
endfunction

"==============================================================================
" Page loading
"==============================================================================

" Load actions for the current page and reset selection.
function! s:load_page() abort
  let l:page = skyrg#backend#context_pages#current()
  let s:page_actions = skyrg#backend#context_pages#actions_for_page(
    \ l:page, s:all_actions, s:ctx)
  let s:selected = 0
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

  " Backtick: toggle history page
  if a:key ==# '`'
    let s:history_mode = !s:history_mode
    let s:selected = 0
    if !s:history_mode
      call s:load_page()
    endif
    call s:refresh_popup(a:winid)
    return 1
  endif

  " Left/Right: navigate pages (exit history mode)
  if a:key ==# "\<Left>"
    let s:history_mode = 0
    call skyrg#backend#context_pages#navigate(-1, s:all_actions, s:ctx)
    call s:load_page()
    call s:refresh_popup(a:winid)
    return 1
  endif
  if a:key ==# "\<Right>"
    let s:history_mode = 0
    call skyrg#backend#context_pages#navigate(1, s:all_actions, s:ctx)
    call s:load_page()
    call s:refresh_popup(a:winid)
    return 1
  endif

  " Number keys: jump to page (exit history mode)
  if a:key =~# '[0-9]'
    let s:history_mode = 0
    let l:idx = str2nr(a:key)
    call skyrg#backend#context_pages#jump(l:idx, s:all_actions, s:ctx)
    call s:load_page()
    call s:refresh_popup(a:winid)
    return 1
  endif

  " History mode: Up/Down navigate entries, Enter replays
  if s:history_mode
    let l:hcount = skyrg#backend#context_history#count()
    if a:key ==# "\<Up>" || a:key ==# 'k'
      let s:selected = max([0, s:selected - 1])
      call popup_settext(a:winid, s:render())
      return 1
    endif
    if a:key ==# "\<Down>" || a:key ==# 'j'
      let s:selected = min([l:hcount - 1, s:selected + 1])
      call popup_settext(a:winid, s:render())
      return 1
    endif
    if a:key ==# "\<CR>"
      if l:hcount > 0
        call popup_close(a:winid)
        call skyrg#backend#context_history#replay(s:selected)
      endif
      return 1
    endif
    return 1
  endif

  " Up/Down: navigate actions within page
  if a:key ==# "\<Up>" || a:key ==# 'k'
    let s:selected = max([0, s:selected - 1])
    call popup_settext(a:winid, s:render())
    return 1
  endif
  if a:key ==# "\<Down>" || a:key ==# 'j'
    let s:selected = min([len(s:page_actions) - 1, s:selected + 1])
    call popup_settext(a:winid, s:render())
    return 1
  endif

  " Enter: execute selected action
  if a:key ==# "\<CR>"
    if empty(s:page_actions) | return 1 | endif
    let l:action = s:page_actions[s:selected]
    call skyrg#log#info('views/context', 'execute "%s"', l:action.name)
    call popup_close(a:winid)
    call skyrg#backend#context#execute(l:action, s:ctx)
    return 1
  endif

  " Shortcut: find action by key within current page
  if len(a:key) == 1 && a:key =~# '[a-zA-Z!@#$%^&*]'
    for l:i in range(len(s:page_actions))
      if get(s:page_actions[l:i], 'key', '') ==# a:key
        let l:action = s:page_actions[l:i]
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
" Popup refresh (page change)
"==============================================================================

function! s:refresh_popup(winid) abort
  call popup_settext(a:winid, s:render())
  call popup_setoptions(a:winid, {'title': s:render_title()})
endfunction

"==============================================================================
" Rendering
"==============================================================================

" Render the popup title as a tab bar showing visible pages.
function! s:render_title() abort
  if s:history_mode
    return ' [`:History]  ← → back '
  endif
  let l:visible = skyrg#backend#context_pages#visible_pages(s:all_actions, s:ctx)
  let l:cur = skyrg#backend#context_pages#current()
  let l:parts = []
  for l:idx in l:visible
    let l:page = skyrg#backend#context_pages#get_page(l:idx)
    let l:name = get(l:page, 'name', string(l:idx))
    if l:idx == l:cur
      call add(l:parts, printf('[%d:%s]', l:idx, l:name))
    else
      call add(l:parts, printf(' %d:%s ', l:idx, l:name))
    endif
  endfor
  return ' ' . join(l:parts, '') . '  `:Hist '
endfunction

" Render the action list for the current page.
function! s:render() abort
  if s:history_mode
    return s:render_history()
  endif

  let l:lines = []

  if empty(s:page_actions)
    call add(l:lines, {'text': '  (no actions on this page)'})
    return l:lines
  endif

  let l:prev_group = ''
  for l:i in range(len(s:page_actions))
    let l:a = s:page_actions[l:i]
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

  " Footer hint
  call add(l:lines, {'text': ''})
  call add(l:lines, {'text': '  ← → page  0-9 jump  ` hist  Esc close'})

  return l:lines
endfunction

" Render the history page.
function! s:render_history() abort
  let l:lines = []
  let l:entries = skyrg#backend#context_history#entries()

  if empty(l:entries)
    call add(l:lines, {'text': '  (no history yet)'})
    call add(l:lines, {'text': ''})
    call add(l:lines, {'text': '  ` back  Esc close'})
    return l:lines
  endif

  for l:i in range(len(l:entries))
    let l:e = l:entries[l:i]
    let l:time = skyrg#backend#context_history#relative_time(l:e.timestamp)
    let l:text = printf('  %s  %s', l:e.label, l:time)
    if l:i == s:selected
      call add(l:lines, skyrg#ui#util#hl_line(l:text, 'skyrg_sel'))
    else
      " Dim the time portion
      let l:time_col = len(l:text) - len(l:time) + 1
      call add(l:lines, {
        \ 'text': l:text,
        \ 'props': [{'col': l:time_col, 'length': len(l:time), 'type': 'skyrg_dim'}],
        \ })
    endif
  endfor

  call add(l:lines, {'text': ''})
  call add(l:lines, {'text': '  Enter replay  ` back  Esc close'})

  return l:lines
endfunction
