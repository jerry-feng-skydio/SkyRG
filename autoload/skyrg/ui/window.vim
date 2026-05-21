" autoload/skyrg/ui/window.vim — Generic window lifecycle manager
"
" Opens a popup-based window from a declarative spec, routes keystrokes,
" handles resizing, and manages pane focus. No domain knowledge.
"
" Usage:
"   let handle = skyrg#ui#window#open(spec)
"   call handle.set_active('results')
"   call handle.close()
"
" See docs/architecture/window-system.md for the full spec.

"==============================================================================
" Open
"==============================================================================

" Open a window from a declarative spec dict.
"
" Spec fields:
"   title        — string, shown on the primary pane border
"   panes        — list of {name, pane, region, flex, ...}
"                  region: 'top-left','top-right','bot-left','bot-right','full'
"                  flex: 0.0-1.0 horizontal proportion within row
"   top_height   — int, fixed height for top row (default: 7)
"   initial_pane — string, name of the pane to focus on open
"   global_keys  — Funcref(key, K, handle) → 0/1, handles keys before pane routing
"   on_close     — Funcref(), called after window closes
"   sidepanes    — list of {name, pane, side, width, hidden}
"
" Returns a handle dict with methods: set_active, close, get_pane, get_popup,
" reposition, get_layout, toggle_sidepane.
function! skyrg#ui#window#open(spec) abort
  call skyrg#ui#style#init()
  call skyrg#ui#events#reset()

  let l:win = {
    \ 'spec':       a:spec,
    \ 'panes':      {},
    \ 'popups':     {},
    \ 'sidepanes':  {},
    \ 'side_popups': {},
    \ 'active':     '',
    \ 'closing':    0,
    \ }

  " Index panes by name
  for l:p in a:spec.panes
    let l:win.panes[l:p.name] = l:p.pane
  endfor
  for l:sp in get(a:spec, 'sidepanes', [])
    let l:win.sidepanes[l:sp.name] = l:sp
  endfor

  " Compute layout and create popups
  let l:geo = s:compute_layout(l:win)
  let l:primary = get(a:spec, 'initial_pane', a:spec.panes[0].name)

  for l:p in a:spec.panes
    let l:pane = l:p.pane
    let l:g = l:geo[l:p.name]
    let l:opts = extend(copy(l:g), {
      \ 'title': l:p.name ==# l:primary ? ' ' . get(a:spec, 'title', 'SkyRG') . ' ' : ' ' . l:p.name . ' ',
      \ 'borderhighlight': [l:p.name ==# l:primary ? 'Title' : 'Comment'],
      \ })
    if l:p.name ==# l:primary
      let l:opts.filter = function('s:on_key', [l:win])
      let l:opts.mapping = 0
      let l:opts.zindex = 200
      let l:opts.callback = function('s:on_popup_close', [l:win])
    endif
    let l:content = has_key(l:pane, 'render') ? l:pane.render() : [{'text': ''}]
    let l:win.popups[l:p.name] = skyrg#ui#popup#create(l:content, l:opts)
  endfor

  " Create sidepanes (hidden by default if specified)
  for l:sp in get(a:spec, 'sidepanes', [])
    let l:pane = l:sp.pane
    let l:g = l:geo[l:sp.name]
    let l:opts = extend(copy(l:g), {
      \ 'title': ' ' . l:sp.name . ' ',
      \ 'borderhighlight': ['Comment'],
      \ })
    if get(l:sp, 'hidden', 0)
      let l:opts.hidden = 1
    endif
    let l:content = has_key(l:pane, 'render') ? l:pane.render() : [{'text': ''}]
    let l:win.side_popups[l:sp.name] = skyrg#ui#popup#create(l:content, l:opts)
  endfor

  " Set active pane
  let l:win.active = l:primary
  if has_key(l:win.panes[l:primary], 'on_focus')
    call l:win.panes[l:primary].on_focus()
  endif

  " Register VimResized autocmd
  let s:active_window = l:win
  augroup SkyRGUIResize
    autocmd!
    autocmd VimResized * call s:on_vim_resized()
  augroup END

  " Build and return handle
  let l:handle = {
    \ '_win':           l:win,
    \ 'set_active':     function('s:handle_set_active', [l:win]),
    \ 'close':          function('s:handle_close', [l:win]),
    \ 'get_pane':       function('s:handle_get_pane', [l:win]),
    \ 'get_popup':      function('s:handle_get_popup', [l:win]),
    \ 'reposition':     function('s:handle_reposition', [l:win]),
    \ 'get_layout':     function('s:handle_get_layout', [l:win]),
    \ 'toggle_sidepane': function('s:handle_toggle_sidepane', [l:win]),
    \ 'redraw_pane':    function('s:handle_redraw_pane', [l:win]),
    \ }
  let l:win.handle = l:handle
  return l:handle
endfunction

"==============================================================================
" Layout engine
"==============================================================================

" Compute per-pane geometry from the spec.
" Returns a dict: {pane_name: {line, col, width, height}, ...}
function! s:compute_layout(win) abort
  let l:W = &columns
  let l:H = &lines
  let l:spec = a:win.spec
  let l:margin = 3
  let l:total_w = max([l:W - 2 * l:margin, 40])

  " Account for visible sidepanes
  let l:side_offset = 0
  for l:sp in get(l:spec, 'sidepanes', [])
    if !get(l:sp, 'hidden', 0)
      let l:side_offset += l:sp.width + 2
    endif
  endfor
  let l:main_w = max([l:total_w - l:side_offset, 40])

  " Top/bottom row heights
  let l:top_h = get(l:spec, 'top_height', 7)
  let l:bot_h = max([l:H - l:top_h - 6, 6])

  " Collect panes by row
  let l:top = []
  let l:bot = []
  let l:full = []
  for l:p in l:spec.panes
    let l:r = get(l:p, 'region', 'full')
    if l:r =~# '^top'   | call add(l:top, l:p)
    elseif l:r =~# '^bot' | call add(l:bot, l:p)
    else                  | call add(l:full, l:p)
    endif
  endfor

  let l:geo = {}
  let l:fc = l:margin + l:side_offset

  " Layout top row
  call s:layout_row(l:geo, l:top, l:fc, 2, l:main_w, l:top_h)

  " Layout bottom row
  call s:layout_row(l:geo, l:bot, l:fc, l:top_h + 4, l:main_w, l:bot_h)

  " Layout full-width panes (take entire area)
  for l:p in l:full
    let l:geo[l:p.name] = {
      \ 'line': 2, 'col': l:fc,
      \ 'width': l:main_w, 'height': l:H - 4,
      \ }
  endfor

  " Layout sidepanes
  let l:sc = l:margin
  for l:sp in get(l:spec, 'sidepanes', [])
    let l:geo[l:sp.name] = {
      \ 'line': 2, 'col': l:sc,
      \ 'width': l:sp.width, 'height': l:H - 4,
      \ }
    if !get(l:sp, 'hidden', 0)
      let l:sc += l:sp.width + 2
    endif
  endfor

  return l:geo
endfunction

" Layout a row of panes horizontally, splitting by flex ratios.
function! s:layout_row(geo, panes, col, row, total_w, height) abort
  if empty(a:panes) | return | endif
  if len(a:panes) == 1
    let a:geo[a:panes[0].name] = {
      \ 'line': a:row, 'col': a:col,
      \ 'width': a:total_w, 'height': a:height,
      \ }
    return
  endif
  " Distribute width by flex ratios
  let l:total_flex = 0.0
  for l:p in a:panes
    let l:total_flex += get(l:p, 'flex', 1.0 / len(a:panes))
  endfor
  let l:c = a:col
  for l:i in range(len(a:panes))
    let l:p = a:panes[l:i]
    let l:flex = get(l:p, 'flex', 1.0 / len(a:panes))
    if l:i == len(a:panes) - 1
      " Last pane gets remaining width to avoid rounding gaps
      let l:w = a:total_w - (l:c - a:col)
    else
      let l:w = float2nr(a:total_w * l:flex / l:total_flex)
    endif
    let l:w = max([l:w - 2, 10])
    let a:geo[l:p.name] = {
      \ 'line': a:row, 'col': l:c,
      \ 'width': l:w, 'height': a:height,
      \ }
    let l:c += l:w + 2
  endfor
endfunction

"==============================================================================
" Key dispatch
"==============================================================================

function! s:on_key(win, winid, key) abort
  let l:K = function('skyrg#ui#keymap#is')

  " Global: close
  if l:K(a:key, 'close')
    call s:do_close(a:win)
    return 1
  endif

  " Global keys handler (view-specific routing, pane switching, etc.)
  if has_key(a:win.spec, 'global_keys')
    let l:consumed = a:win.spec.global_keys(a:key, l:K, a:win.handle)
    if l:consumed | return 1 | endif
  endif

  " Route to active pane
  let l:pane = get(a:win.panes, a:win.active, {})
  if !empty(l:pane) && has_key(l:pane, 'on_key')
    let l:consumed = l:pane.on_key(a:key, l:K)
    if l:consumed
      " Re-render the active pane after key handling
      call s:redraw_pane(a:win, a:win.active)
      return 1
    endif
  endif

  return 1
endfunction

"==============================================================================
" Close
"==============================================================================

function! s:on_popup_close(win, id, result) abort
  call s:do_close(a:win)
endfunction

function! s:do_close(win) abort
  if a:win.closing | return | endif
  let a:win.closing = 1

  " Cleanup panes
  for [l:name, l:pane] in items(a:win.panes)
    if has_key(l:pane, 'cleanup')
      call l:pane.cleanup()
    endif
  endfor
  for [l:name, l:sp] in items(a:win.sidepanes)
    if has_key(l:sp, 'pane') && has_key(l:sp.pane, 'cleanup')
      call l:sp.pane.cleanup()
    endif
  endfor

  " Close all popups
  for l:id in values(a:win.popups)
    silent! call popup_close(l:id)
  endfor
  for l:id in values(a:win.side_popups)
    silent! call popup_close(l:id)
  endfor

  " Cleanup
  call skyrg#ui#events#reset()
  call skyrg#ui#style#cleanup()
  silent! autocmd! SkyRGUIResize

  if has_key(a:win.spec, 'on_close')
    call a:win.spec.on_close()
  endif
endfunction

"==============================================================================
" Pane management
"==============================================================================

function! s:set_active(win, name) abort
  if a:win.active ==# a:name | return | endif

  " Blur old pane
  let l:old = get(a:win.panes, a:win.active, {})
  if !empty(l:old) && has_key(l:old, 'on_blur')
    call l:old.on_blur()
  endif
  if has_key(a:win.popups, a:win.active)
    call popup_setoptions(a:win.popups[a:win.active], {'borderhighlight': ['Comment']})
  endif

  " Focus new pane
  let a:win.active = a:name
  let l:new = get(a:win.panes, a:name, {})
  if !empty(l:new) && has_key(l:new, 'on_focus')
    call l:new.on_focus()
  endif
  if has_key(a:win.popups, a:name)
    call popup_setoptions(a:win.popups[a:name], {'borderhighlight': ['Title']})
  endif

  " Re-render both panes
  call s:redraw_pane(a:win, a:win.active)
endfunction

function! s:redraw_pane(win, name) abort
  let l:pane = get(a:win.panes, a:name, {})
  let l:popup = get(a:win.popups, a:name, 0)
  if !empty(l:pane) && l:popup && has_key(l:pane, 'render')
    call popup_settext(l:popup, l:pane.render())
  endif
endfunction

"==============================================================================
" Resize
"==============================================================================

function! s:on_vim_resized() abort
  if !exists('s:active_window') || s:active_window.closing | return | endif
  call s:reposition(s:active_window)
endfunction

function! s:reposition(win) abort
  let l:geo = s:compute_layout(a:win)

  " Move main panes
  for l:p in a:win.spec.panes
    if has_key(a:win.popups, l:p.name) && has_key(l:geo, l:p.name)
      call skyrg#ui#popup#move(a:win.popups[l:p.name], l:geo[l:p.name])
      let l:pane = a:win.panes[l:p.name]
      if has_key(l:pane, 'on_resize')
        call l:pane.on_resize(l:geo[l:p.name])
      endif
      call s:redraw_pane(a:win, l:p.name)
    endif
  endfor

  " Move sidepanes
  for l:sp in get(a:win.spec, 'sidepanes', [])
    if has_key(a:win.side_popups, l:sp.name) && has_key(l:geo, l:sp.name)
      call skyrg#ui#popup#move(a:win.side_popups[l:sp.name], l:geo[l:sp.name])
      if has_key(l:sp.pane, 'on_resize')
        call l:sp.pane.on_resize(l:geo[l:sp.name])
      endif
      if has_key(l:sp.pane, 'render')
        call popup_settext(a:win.side_popups[l:sp.name], l:sp.pane.render())
      endif
    endif
  endfor
endfunction

"==============================================================================
" Sidepane toggle
"==============================================================================

function! s:toggle_sidepane(win, name, visible) abort
  let l:found = 0
  for l:sp in get(a:win.spec, 'sidepanes', [])
    if l:sp.name ==# a:name
      let l:sp.hidden = !a:visible
      let l:found = 1
      break
    endif
  endfor
  if !l:found | return | endif

  let l:popup = get(a:win.side_popups, a:name, 0)
  if l:popup
    if a:visible
      call popup_show(l:popup)
    else
      call popup_hide(l:popup)
    endif
  endif

  " Reposition everything (main panes shift when sidepane toggles)
  call s:reposition(a:win)
endfunction

"==============================================================================
" Handle methods (bound to a specific window instance)
"==============================================================================

function! s:handle_set_active(win, name) abort
  call s:set_active(a:win, a:name)
endfunction

function! s:handle_close(win) abort
  call s:do_close(a:win)
endfunction

function! s:handle_get_pane(win, name) abort
  return get(a:win.panes, a:name, {})
endfunction

function! s:handle_get_popup(win, name) abort
  let l:id = get(a:win.popups, a:name, 0)
  if l:id | return l:id | endif
  return get(a:win.side_popups, a:name, 0)
endfunction

function! s:handle_reposition(win) abort
  call s:reposition(a:win)
endfunction

function! s:handle_get_layout(win) abort
  return s:compute_layout(a:win)
endfunction

function! s:handle_toggle_sidepane(win, name, visible) abort
  call s:toggle_sidepane(a:win, a:name, a:visible)
endfunction

function! s:handle_redraw_pane(win, name) abort
  call s:redraw_pane(a:win, a:name)
endfunction
