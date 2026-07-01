" autoload/skyrg/backend/analytics.vim — Analytics event parsing, filtering, export
"
" Parses txtlog files produced by analytics_to_file, maintains filter state
" (which event types are visible), persists selections, and exports filtered
" events to a readable text file.
"
" Usage:
"   let events = skyrg#backend#analytics#parse(txtlog_path)
"   let types  = skyrg#backend#analytics#event_types(events)
"   let filtered = skyrg#backend#analytics#filter(events, enabled_types)
"   call skyrg#backend#analytics#export(events, enabled_types)
"   call skyrg#backend#analytics#save_filter(enabled_types)
"   let enabled = skyrg#backend#analytics#load_filter()

" Super properties that are redundant in the detail view — stripped to reduce
" noise and let the interesting fields stand out.
let s:super_props = [
  \ 'vehicle_id', 'vehicle_name', 'reset_id', 'boot_num', 'boot_id',
  \ 'log_num', 'release_key', 'soc', 'vehicle_type',
  \ ]

let s:filter_path = expand('~/.local/share/skyrg/analytics_filter.json')

" Undo stack for ignore actions (list of event type names)
let s:ignore_undo_stack = []

"==============================================================================
" Parse
"==============================================================================

" Parse a txtlog file into a list of event dicts.
" Each dict: {timestamp, name, fields: {k: v, ...}, raw}
function! skyrg#backend#analytics#parse(path) abort
  if !filereadable(a:path)
    call skyrg#log#info('backend/analytics', 'file not readable: %s', a:path)
    return []
  endif

  let l:lines = readfile(a:path)
  let l:events = []

  for l:line in l:lines
    " Only parse lines starting with [timestamp]
    if l:line !~# '^\['
      continue
    endif

    let l:event = s:parse_line(l:line)
    if !empty(l:event)
      call add(l:events, l:event)
    endif
  endfor

  call skyrg#log#info('backend/analytics', 'parsed %d events from %s',
    \ len(l:events), fnamemodify(a:path, ':t'))
  return l:events
endfunction

" Parse a single txtlog line into an event dict.
function! s:parse_line(line) abort
  " Extract timestamp: [2026-06-30 17:59:39-07:00]
  let l:ts_match = matchlist(a:line, '^\[\([^\]]*\)\]\s*')
  if empty(l:ts_match)
    return {}
  endif
  let l:timestamp = l:ts_match[1]
  let l:rest = a:line[len(l:ts_match[0]):]

  " Extract event name (first word)
  let l:name_match = matchlist(l:rest, '^\(\S\+\)\s*')
  if empty(l:name_match)
    return {}
  endif
  let l:name = l:name_match[1]
  let l:props_str = l:rest[len(l:name_match[0]):]

  " Parse key=value pairs
  let l:fields = s:parse_fields(l:props_str)

  return {
    \ 'timestamp': l:timestamp,
    \ 'name': l:name,
    \ 'fields': l:fields,
    \ 'raw': a:line,
    \ }
endfunction

" Parse a string of key=value pairs into a dict.
" Handles quoted values like ssid="skydio-guest".
function! s:parse_fields(str) abort
  let l:fields = {}
  let l:s = a:str
  while !empty(l:s)
    " Skip whitespace
    let l:s = substitute(l:s, '^\s\+', '', '')
    if empty(l:s) | break | endif

    " Match key=value
    let l:m = matchlist(l:s, '^\(\w\+\)=\("\([^"]*\)"\|\(\S*\)\)\s*')
    if empty(l:m)
      break
    endif
    let l:key = l:m[1]
    " Quoted value in group 3, unquoted in group 4
    let l:val = !empty(l:m[3]) ? l:m[3] : l:m[4]
    let l:fields[l:key] = l:val
    let l:s = l:s[len(l:m[0]):]
  endwhile
  return l:fields
endfunction

"==============================================================================
" Event types
"==============================================================================

" Return sorted list of unique event type names from parsed events.
function! skyrg#backend#analytics#event_types(events) abort
  let l:types = {}
  for l:e in a:events
    let l:types[l:e.name] = get(l:types, l:e.name, 0) + 1
  endfor
  return l:types
endfunction

"==============================================================================
" Filter
"==============================================================================

" Filter events to only those whose name is in enabled_types dict.
function! skyrg#backend#analytics#filter(events, enabled_types) abort
  let l:result = []
  for l:e in a:events
    if get(a:enabled_types, l:e.name, 0)
      call add(l:result, l:e)
    endif
  endfor
  return l:result
endfunction

"==============================================================================
" Ignore undo stack
"==============================================================================

function! skyrg#backend#analytics#push_ignore(event_type) abort
  call add(s:ignore_undo_stack, a:event_type)
endfunction

function! skyrg#backend#analytics#pop_ignore() abort
  if empty(s:ignore_undo_stack) | return '' | endif
  return remove(s:ignore_undo_stack, -1)
endfunction

function! skyrg#backend#analytics#clear_ignore_stack() abort
  let s:ignore_undo_stack = []
endfunction

"==============================================================================
" Filter persistence
"==============================================================================

" Save enabled event types to disk.
function! skyrg#backend#analytics#save_filter(enabled_types) abort
  let l:dir = fnamemodify(s:filter_path, ':h')
  if !isdirectory(l:dir)
    call mkdir(l:dir, 'p')
  endif
  let l:data = json_encode(a:enabled_types)
  call writefile([l:data], s:filter_path)
  call skyrg#log#info('backend/analytics', 'saved filter to %s', s:filter_path)
endfunction

" Load enabled event types from disk. Returns {} if no saved state.
function! skyrg#backend#analytics#load_filter() abort
  if !filereadable(s:filter_path)
    return {}
  endif
  try
    let l:lines = readfile(s:filter_path)
    if empty(l:lines) | return {} | endif
    return json_decode(l:lines[0])
  catch
    call skyrg#log#info('backend/analytics', 'failed to load filter: %s', v:exception)
    return {}
  endtry
endfunction

"==============================================================================
" Detail fields (for Event Details pane)
"==============================================================================

" Return a list of [key, value] pairs for the detail view, stripping super
" properties to reduce noise.
function! skyrg#backend#analytics#detail_fields(event) abort
  let l:result = []
  " Always show timestamp and name first
  call add(l:result, ['timestamp', a:event.timestamp])
  call add(l:result, ['name', a:event.name])

  " Show event_type early if present
  if has_key(a:event.fields, 'event_type')
    call add(l:result, ['event_type', a:event.fields.event_type])
  endif

  " Add remaining fields, skipping super props and event_type (already shown)
  let l:skip = copy(s:super_props)
  call add(l:skip, 'event_type')
  for [l:k, l:v] in sort(items(a:event.fields))
    if index(l:skip, l:k) < 0
      call add(l:result, [l:k, l:v])
    endif
  endfor

  return l:result
endfunction

"==============================================================================
" Export
"==============================================================================

" Export filtered events to a readable text file.
" Returns the output file path.
function! skyrg#backend#analytics#export(events, enabled_types, vehicle_id) abort
  let l:filtered = skyrg#backend#analytics#filter(a:events, a:enabled_types)
  if empty(l:filtered)
    echohl WarningMsg | echo '[SkyRG] No events to export' | echohl None
    return ''
  endif

  let l:export_dir = get(g:, 'skyrg_analytics_export_dir', expand('~/analytics_dumps'))
  if !isdirectory(l:export_dir)
    call mkdir(l:export_dir, 'p')
  endif

  let l:timestamp = strftime('%Y%m%d_%H%M%S')
  let l:filename = printf('analytics_%s_%s.txt', a:vehicle_id, l:timestamp)
  let l:path = l:export_dir . '/' . l:filename

  let l:lines = []
  call add(l:lines, printf('Analytics Export — %s', strftime('%Y-%m-%d %H:%M:%S')))
  call add(l:lines, printf('Vehicle: %s', a:vehicle_id))
  call add(l:lines, printf('Events: %d (of %d total)', len(l:filtered), len(a:events)))
  call add(l:lines, repeat('─', 60))
  call add(l:lines, '')

  for l:e in l:filtered
    let l:detail = skyrg#backend#analytics#detail_fields(l:e)
    for [l:k, l:v] in l:detail
      call add(l:lines, printf('  %-20s %s', l:k, l:v))
    endfor
    call add(l:lines, '')
  endfor

  call writefile(l:lines, l:path)
  call skyrg#log#info('backend/analytics', 'exported %d events to %s',
    \ len(l:filtered), l:path)
  return l:path
endfunction
