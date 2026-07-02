" autoload/skyrg/views/analytics.vim — Analytics Event Viewer
"
" Multi-pane window for browsing, filtering, and exporting analytics events
" from a connected C38 device.
"
" Layout:
"   ┌─ Event Types ─┬─ Event Timeline ──────┬─ Event Details ─────┐
"   │ [x] skycat_…  │ 17:59:39 skycat_event │ timestamp: ...      │
"   │ [ ] kernel_…  │ 17:59:40 analytics    │ name: ...           │
"   │               │                       │ key: value          │
"   └───────────────┴───────────────────────┴─────────────────────┘
"
" Usage:
"   call skyrg#views#analytics#open(txtlog_path, vehicle_id)

"==============================================================================
" State
"==============================================================================

let s:handle = {}
let s:state = {}

"==============================================================================
" Open
"==============================================================================

function! skyrg#views#analytics#open(txtlog_path, vehicle_id) abort
  " Parse events
  let l:all_events = skyrg#backend#analytics#parse(a:txtlog_path)
  if empty(l:all_events)
    echohl WarningMsg | echo '[SkyRG] No analytics events found' | echohl None
    return
  endif

  " Get event types with counts
  let l:type_counts = skyrg#backend#analytics#event_types(l:all_events)

  " Load persisted filter or default to all enabled
  let l:saved = skyrg#backend#analytics#load_filter()
  let l:enabled = {}
  for l:t in keys(l:type_counts)
    let l:enabled[l:t] = has_key(l:saved, l:t) ? l:saved[l:t] : 1
  endfor

  " Build state
  let s:state = {
    \ 'all_events': l:all_events,
    \ 'type_counts': l:type_counts,
    \ 'enabled': l:enabled,
    \ 'filtered': [],
    \ 'vehicle_id': a:vehicle_id,
    \ 'txtlog_path': a:txtlog_path,
    \ 'search_query': '',
    \ 'types_visible': 1,
    \ 'focus': 'timeline',
    \ }

  call skyrg#backend#analytics#clear_ignore_stack()
  call s:apply_filter()

  " Build panes
  let l:timeline_pane = skyrg#ui#panes#list#new({
    \ 'format_item': function('s:format_timeline_item'),
    \ 'on_select': function('s:on_timeline_select'),
    \ 'empty_text': 'No matching events',
    \ })
  call l:timeline_pane.set_items(s:state.filtered)

  let l:details_pane = skyrg#ui#panes#info#new({'title': 'Details'})

  let l:types_pane = skyrg#ui#panes#list#new({
    \ 'format_item': function('s:format_type_item'),
    \ 'on_select': function('s:on_type_select'),
    \ 'empty_text': 'No event types',
    \ 'actions': {
    \   'up': 'analytics_types_up',
    \   'down': 'analytics_types_down',
    \   'page_up': 'analytics_types_page_up',
    \   'page_down': 'analytics_types_page_down',
    \   'accept': 'analytics_types_noop',
    \ },
    \ })
  call l:types_pane.set_items(s:build_type_items())

  " Store pane references
  let s:state.timeline_pane = l:timeline_pane
  let s:state.details_pane = l:details_pane
  let s:state.types_pane = l:types_pane

  " Show details for first event
  if !empty(s:state.filtered)
    call s:update_details(s:state.filtered[0])
  endif

  " Open window
  let s:handle = skyrg#ui#window#open({
    \ 'title': 'Analytics — ' . a:vehicle_id,
    \ 'panes': [
    \   {'name': 'timeline', 'pane': l:timeline_pane, 'region': 'top-left', 'flex': 0.50},
    \   {'name': 'details',  'pane': l:details_pane,  'region': 'top-right', 'flex': 0.50},
    \ ],
    \ 'sidepanes': [
    \   {'name': 'types', 'pane': l:types_pane, 'side': 'left', 'width': 44, 'hidden': 0},
    \ ],
    \ 'top_height': &lines - 4,
    \ 'initial_pane': 'timeline',
    \ 'global_keys': function('s:global_keys'),
    \ 'on_close': function('s:on_close'),
    \ })

  " Sync pane geometry so list panes render at full height
  call s:handle.reposition()

  call skyrg#log#info('views/analytics', 'opened %d events, %d types',
    \ len(l:all_events), len(l:type_counts))
endfunction

"==============================================================================
" Filter logic
"==============================================================================

function! s:apply_filter() abort
  let l:filtered = skyrg#backend#analytics#filter(
    \ s:state.all_events, s:state.enabled)

  " Apply search query if any
  if !empty(s:state.search_query)
    let l:query = tolower(s:state.search_query)
    let l:matched = []
    for l:e in l:filtered
      if stridx(tolower(l:e.raw), l:query) >= 0
        call add(l:matched, l:e)
      endif
    endfor
    let l:filtered = l:matched
  endif

  let s:state.filtered = l:filtered
endfunction

function! s:refresh_timeline() abort
  call s:apply_filter()
  call s:state.timeline_pane.set_items(s:state.filtered)
  if !empty(s:state.filtered)
    call s:update_details(s:state.filtered[0])
  else
    call s:state.details_pane.set_lines([
      \ skyrg#ui#util#hl_line('  No matching events', 'skyrg_dim')])
  endif
  call s:redraw_all()
endfunction

function! s:redraw_all() abort
  if empty(s:handle) | return | endif
  call s:handle.redraw_pane('timeline')
  call s:handle.redraw_pane('details')
  " Redraw types sidepane
  let l:types_popup = s:handle.get_popup('types')
  if l:types_popup
    call popup_settext(l:types_popup, s:state.types_pane.render())
  endif
endfunction

"==============================================================================
" Formatting
"==============================================================================

function! s:format_timeline_item(item, idx, is_sel) abort
  " Extract short time from timestamp (HH:MM:SS portion)
  let l:ts = a:item.timestamp
  let l:short_ts = matchstr(l:ts, '\d\d:\d\d:\d\d')
  if empty(l:short_ts)
    let l:short_ts = l:ts[:18]
  endif

  let l:text = printf(' %s  %s', l:short_ts, a:item.name)
  if a:is_sel
    return skyrg#ui#util#hl_line(l:text, 'skyrg_sel')
  endif
  " Dim the timestamp
  let l:ts_len = len(l:short_ts) + 1
  return skyrg#ui#util#line(l:text, [
    \ {'col': 1, 'length': l:ts_len, 'type': 'skyrg_dim'},
    \ ])
endfunction

function! s:format_type_item(item, idx, is_sel) abort
  let l:check = a:item.enabled ? '✓' : ' '
  let l:text = printf(' [%s] %s (%d)', l:check, a:item.name, a:item.count)
  if a:is_sel
    return skyrg#ui#util#hl_line(l:text, 'skyrg_sel')
  endif
  if !a:item.enabled
    return skyrg#ui#util#hl_line(l:text, 'skyrg_dim')
  endif
  return {'text': l:text}
endfunction

function! s:build_type_items() abort
  let l:items = []
  for l:name in sort(keys(s:state.type_counts))
    call add(l:items, {
      \ 'name': l:name,
      \ 'count': s:state.type_counts[l:name],
      \ 'enabled': get(s:state.enabled, l:name, 1),
      \ })
  endfor
  return l:items
endfunction

"==============================================================================
" Details pane
"==============================================================================

" Break text into chunks of at most max_w characters.
" Tries to split at path separators (/) or hyphens (-) when possible.
function! s:wrap_text(text, max_w) abort
  let l:chunks = []
  let l:remaining = a:text
  while len(l:remaining) > a:max_w
    " Try to find a good break point (/ or -) near the end of the chunk
    let l:break_at = a:max_w
    let l:best = -1
    for l:i in range(a:max_w - 1, a:max_w / 2, -1)
      if l:remaining[l:i] ==# '/' || l:remaining[l:i] ==# '-'
        let l:best = l:i + 1
        break
      endif
    endfor
    if l:best > 0
      let l:break_at = l:best
    endif
    call add(l:chunks, l:remaining[:l:break_at - 1])
    let l:remaining = l:remaining[l:break_at:]
  endwhile
  if !empty(l:remaining)
    call add(l:chunks, l:remaining)
  endif
  return l:chunks
endfunction

function! s:update_details(event) abort
  let l:fields = skyrg#backend#analytics#detail_fields(a:event)
  let l:lines = []
  let l:max_key = 0
  for [l:k, l:v] in l:fields
    if len(l:k) > l:max_key
      let l:max_key = len(l:k)
    endif
  endfor

  " Available width for value text (pane width minus border, indent, key col)
  let l:val_col = l:max_key + 4
  let l:pane_w = max([s:state.details_pane._geo.width - 2, 20])
  let l:val_w = l:pane_w - l:val_col

  for [l:k, l:v] in l:fields
    let l:pad = repeat(' ', l:max_key - len(l:k))
    let l:indent = repeat(' ', l:val_col)

    if l:val_w > 0 && len(l:v) > l:val_w
      " Wrap: first chunk on key line, rest on indented continuation lines
      let l:chunks = s:wrap_text(l:v, l:val_w)
      let l:text = printf('  %s%s  %s', l:k, l:pad, l:chunks[0])
      let l:props = [{'col': 3, 'length': len(l:k), 'type': 'skyrg_dim'}]
      call add(l:lines, skyrg#ui#util#line(l:text, l:props))
      for l:ci in range(1, len(l:chunks) - 1)
        call add(l:lines, {'text': l:indent . l:chunks[l:ci]})
      endfor
    else
      let l:text = printf('  %s%s  %s', l:k, l:pad, l:v)
      let l:props = [{'col': 3, 'length': len(l:k), 'type': 'skyrg_dim'}]
      call add(l:lines, skyrg#ui#util#line(l:text, l:props))
    endif
  endfor

  " Pin shortcut hints to bottom of pane
  let l:hint_lines = [
    \ skyrg#ui#util#hl_line(
    \   '  ↑↓ navigate  i ignore  u undo  / search  e export', 'skyrg_dim'),
    \ skyrg#ui#util#hl_line(
    \   '  a all  n none  t types  ^L clear  Esc close', 'skyrg_dim'),
    \ ]
  let l:visible = max([s:state.details_pane._geo.height - 2, 6])
  let l:pad = l:visible - len(l:lines) - len(l:hint_lines)
  while l:pad > 0
    call add(l:lines, {'text': ''})
    let l:pad -= 1
  endwhile
  call extend(l:lines, l:hint_lines)

  call s:state.details_pane.set_lines(l:lines)
endfunction

"==============================================================================
" Callbacks
"==============================================================================

function! s:on_timeline_select(item, idx) abort
  call s:update_details(a:item)
  if !empty(s:handle)
    call s:handle.redraw_pane('details')
  endif
endfunction

function! s:on_type_select(item, idx) abort
endfunction

function! s:on_close() abort
  " Save filter state on close
  call skyrg#backend#analytics#save_filter(s:state.enabled)
  let s:handle = {}
  let s:state = {}
endfunction

"==============================================================================
" Key routing
"==============================================================================

function! s:global_keys(key, K, handle) abort
  " Escape closes
  if a:K(a:key, 'close')
    call a:handle.close()
    return 1
  endif

  " Toggle types sidepane
  if a:key ==# 't'
    let s:state.types_visible = !s:state.types_visible
    call a:handle.toggle_sidepane('types', s:state.types_visible)
    return 1
  endif

  " Select all event types
  if a:key ==# 'a'
    for l:t in keys(s:state.enabled)
      let s:state.enabled[l:t] = 1
    endfor
    call s:state.types_pane.set_items(s:build_type_items())
    call s:refresh_timeline()
    return 1
  endif

  " Deselect all event types
  if a:key ==# 'n'
    for l:t in keys(s:state.enabled)
      let s:state.enabled[l:t] = 0
    endfor
    call s:state.types_pane.set_items(s:build_type_items())
    call s:refresh_timeline()
    return 1
  endif

  " Export visible events
  if a:key ==# 'e'
    let l:path = skyrg#backend#analytics#export(
      \ s:state.all_events, s:state.enabled, s:state.vehicle_id)
    if !empty(l:path)
      echom printf('[SkyRG] Exported to %s', l:path)
    endif
    return 1
  endif

  " Search / filter
  if a:key ==# '/'
    let l:query = input('[SkyRG] Filter events: ', s:state.search_query)
    let s:state.search_query = l:query
    call s:refresh_timeline()
    return 1
  endif

  " Clear search
  if a:key ==# "\<C-l>"
    let s:state.search_query = ''
    call s:refresh_timeline()
    return 1
  endif

  " Pane navigation
  if a:key ==# "\<C-Up>" || a:key ==# "\<C-Left>"
    call s:set_focus('types', a:handle)
    return 1
  endif
  if a:key ==# "\<C-Down>" || a:key ==# "\<C-Right>"
    call s:set_focus('timeline', a:handle)
    return 1
  endif

  " --- Route keys to focused pane ---
  let l:active = s:state.focus

  if l:active ==# 'timeline'
    " Ignore current event type
    if a:key ==# 'i'
      let l:sel = s:state.timeline_pane.selected()
      if !empty(l:sel)
        let s:state.enabled[l:sel.name] = 0
        call skyrg#backend#analytics#push_ignore(l:sel.name)
        call s:state.types_pane.set_items(s:build_type_items())
        call s:refresh_timeline()
      endif
      return 1
    endif

    " Undo last ignore
    if a:key ==# 'u'
      let l:restored = skyrg#backend#analytics#pop_ignore()
      if !empty(l:restored)
        let s:state.enabled[l:restored] = 1
        call s:state.types_pane.set_items(s:build_type_items())
        call s:refresh_timeline()
        echom printf('[SkyRG] Restored: %s', l:restored)
      endif
      return 1
    endif
  endif

  " --- Types pane keys ---
  if l:active ==# 'types'
    " Route arrow keys to types pane
    if s:state.types_pane.on_key(a:key, a:K)
      let l:types_popup = a:handle.get_popup('types')
      if l:types_popup
        call popup_settext(l:types_popup, s:state.types_pane.render())
      endif
      return 1
    endif

    " Space toggles the selected event type
    if a:key ==# ' '
      let l:sel = s:state.types_pane.selected()
      if !empty(l:sel)
        let l:saved_idx = s:state.types_pane.state.idx
        let s:state.enabled[l:sel.name] = !get(s:state.enabled, l:sel.name, 1)
        call s:state.types_pane.set_items(s:build_type_items())
        let s:state.types_pane.state.idx = min([l:saved_idx, len(s:state.types_pane.state.items) - 1])
        call s:refresh_timeline()
      endif
      return 1
    endif

    " Enter switches to timeline
    if a:key ==# "\<CR>"
      call s:set_focus('timeline', a:handle)
      return 1
    endif
  endif

  return 0
endfunction

" Switch logical focus between timeline and types sidepane.
function! s:set_focus(target, handle) abort
  let l:old = s:state.focus
  let s:state.focus = a:target

  " Update border highlights
  if l:old ==# 'types'
    let l:tp = a:handle.get_popup('types')
    if l:tp | call popup_setoptions(l:tp, {'borderhighlight': ['Comment']}) | endif
  elseif l:old ==# 'timeline'
    let l:tp = a:handle.get_popup('timeline')
    if l:tp | call popup_setoptions(l:tp, {'borderhighlight': ['Comment']}) | endif
  endif

  if a:target ==# 'types'
    let l:tp = a:handle.get_popup('types')
    if l:tp | call popup_setoptions(l:tp, {'borderhighlight': ['Title']}) | endif
  elseif a:target ==# 'timeline'
    let l:tp = a:handle.get_popup('timeline')
    if l:tp | call popup_setoptions(l:tp, {'borderhighlight': ['Title']}) | endif
  endif
endfunction
