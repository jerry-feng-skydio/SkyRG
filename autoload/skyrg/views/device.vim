" autoload/skyrg/views/device.vim — Device interaction popups
"
" Provides sub-menus for board selection, log browsing, and device actions.
" Called from context actions registered in backend/context.vim.
"
" Flow:
"   detect → vehicle picker (if >1) → action → board picker (if >1) → execute

let s:popup_id = 0
let s:items = []
let s:selected = 0
let s:on_select = v:null   " funcref called with selected item

"==============================================================================
" Generic picker popup
"==============================================================================

" Show a picker popup.  items = [{'label': '...', 'value': ...}, ...]
" on_select = {item -> ...} called when user picks one.
function! s:show_picker(title, items, On_select) abort
  if empty(a:items)
    echohl WarningMsg | echo '[SkyRG] No items to pick' | echohl None
    return
  endif

  " Single item — skip popup
  if len(a:items) == 1
    call a:On_select(a:items[0])
    return
  endif

  let s:items = a:items
  let s:on_select = a:On_select
  let s:selected = 0

  let l:lines = s:render_picker()
  let l:max_w = 0
  for l:item in a:items
    let l:w = len(l:item.label) + 4
    if l:w > l:max_w | let l:max_w = l:w | endif
  endfor

  if s:popup_id | silent! call popup_close(s:popup_id) | endif
  call skyrg#ui#style#init()
  let s:popup_id = popup_create(l:lines, {
    \ 'line': 'cursor+1',
    \ 'col': 'cursor',
    \ 'pos': 'topleft',
    \ 'width': l:max_w,
    \ 'padding': [0, 1, 0, 1],
    \ 'border': [1, 1, 1, 1],
    \ 'borderchars': ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
    \ 'borderhighlight': ['Title'],
    \ 'highlight': 'Normal',
    \ 'title': ' ' . a:title . ' ',
    \ 'filter': function('s:picker_key'),
    \ 'mapping': 0,
    \ 'callback': function('s:picker_close'),
    \ 'zindex': 310,
    \ })
endfunction

function! s:render_picker() abort
  let l:lines = []
  for l:i in range(len(s:items))
    let l:text = '  ' . s:items[l:i].label
    if l:i == s:selected
      call add(l:lines, skyrg#ui#util#hl_line(l:text, 'skyrg_sel'))
    else
      call add(l:lines, {'text': l:text})
    endif
  endfor
  return l:lines
endfunction

function! s:picker_key(winid, key) abort
  if a:key ==# "\<Esc>" || a:key ==# "\<C-c>"
    call popup_close(a:winid)
    return 1
  endif
  if a:key ==# "\<Up>" || a:key ==# 'k'
    let s:selected = max([0, s:selected - 1])
    call popup_settext(a:winid, s:render_picker())
    return 1
  endif
  if a:key ==# "\<Down>" || a:key ==# 'j'
    let s:selected = min([len(s:items) - 1, s:selected + 1])
    call popup_settext(a:winid, s:render_picker())
    return 1
  endif
  if a:key ==# "\<CR>"
    let l:item = s:items[s:selected]
    call popup_close(a:winid)
    call s:on_select(l:item)
    return 1
  endif
  return 1
endfunction

function! s:picker_close(id, result) abort
  let s:popup_id = 0
endfunction

"==============================================================================
" Board picker — choose a board from a detected vehicle
"==============================================================================

" Pick a board, then call Callback({'name': 'NVU', 'host': 'nvu'}).
" If only one board, skip the picker.
function! skyrg#views#device#pick_board(vehicle, Callback) abort
  let l:items = []
  for l:b in a:vehicle.boards
    call add(l:items, {
      \ 'label': printf('%s  (%s)', l:b.name, l:b.host),
      \ 'value': l:b,
      \ })
  endfor
  call s:show_picker(a:vehicle.type . ' — Select Board', l:items,
    \ {item -> a:Callback(item.value)})
endfunction

"==============================================================================
" Vehicle picker — choose a vehicle if multiple detected
"==============================================================================

function! skyrg#views#device#pick_vehicle(vehicles, Callback) abort
  let l:items = []
  for l:v in a:vehicles
    let l:board_names = join(map(copy(l:v.boards), 'v:val.name'), ', ')
    call add(l:items, {
      \ 'label': printf('%s  [%s]', l:v.type, l:board_names),
      \ 'value': l:v,
      \ })
  endfor
  call s:show_picker('Select Vehicle', l:items,
    \ {item -> a:Callback(item.value)})
endfunction

"==============================================================================
" High-level device actions
"==============================================================================

" Open an interactive SSH shell to a device board.
function! skyrg#views#device#ssh(ctx) abort
  call s:with_board(a:ctx, function('s:do_ssh'))
endfunction

function! s:do_ssh(board) abort
  let l:dirs = s:ssh_directories(a:board)
  if len(l:dirs) <= 1
    " No picker needed — just connect
    let l:dir = empty(l:dirs) ? '' : l:dirs[0].value
    call s:ssh_connect(a:board, l:dir)
    return
  endif
  call s:show_picker(a:board.name . ' — SSH directory', l:dirs,
    \ {item -> s:ssh_connect(a:board, item.value)})
endfunction

function! s:ssh_connect(board, dir) abort
  let l:platform = get(a:board, 'platform', 'linux')
  if empty(a:dir)
    let l:cmd = 'ssh ' . a:board.host
  elseif l:platform ==# 'android'
    " Android: no /bin/bash, use sh directly
    let l:cmd = printf('ssh -t %s "cd %s && exec sh"', a:board.host, shellescape(a:dir))
  else
    let l:cmd = printf('ssh -t %s "cd %s && exec \\$SHELL -l"', a:board.host, shellescape(a:dir))
  endif
  call skyrg#backend#action#dispatch({
    \ 'name': 'SSH ' . a:board.name,
    \ 'job': l:cmd,
    \ 'job_opts': {'interactive': 1, 'title': 'SSH ' . a:board.host},
    \ }, {})
endfunction

" SSH directory options, keyed by board.platform ('android' or 'linux').
" First entry is the default landing spot (double-tap Enter to connect).
" Paths derived from util/path_util/BUILD.bazel:
"   android: SKYDIO_DIR_PATH=/odm, SEMI_PERSISTENT_OVERRIDE_PATH=/data/vendor
"   linux:   SKYDIO_DIR_PATH=/home/skydio, semi_persistent under HomeSkydioPath
function! s:ssh_directories(board) abort
  let l:platform = get(a:board, 'platform', 'linux')

  if l:platform ==# 'android'
    return [
      \ {'label': '/  (root)',                                    'value': '/'},
      \ {'label': '/data/vendor/logs/process_logs/latest/',       'value': '/data/vendor/logs/process_logs/latest'},
      \ {'label': '/data/vendor/analytics/',                      'value': '/data/vendor/analytics'},
      \ {'label': '/data/vendor/syslog/',                         'value': '/data/vendor/syslog'},
      \ {'label': '/data/vendor/',                                'value': '/data/vendor'},
      \ {'label': '/odm/',                                        'value': '/odm'},
      \ ]
  endif

  " linux — /home/skydio is HomeSkydioPath for all linux boards
  return [
    \ {'label': '~/  (home)',                                   'value': '~'},
    \ {'label': '~/semi_persistent/process_logs/latest/',       'value': '~/semi_persistent/process_logs/latest'},
    \ {'label': '~/semi_persistent/analytics/',                 'value': '~/semi_persistent/analytics'},
    \ {'label': '~/semi_persistent/syslog/',                    'value': '~/semi_persistent/syslog'},
    \ {'label': '~/emmc_logs/',                                 'value': '~/emmc_logs'},
    \ {'label': '~/semi_persistent/',                           'value': '~/semi_persistent'},
    \ ]
endfunction

" View analytics events from a C38 device.
function! skyrg#views#device#view_analytics(ctx) abort
  call s:with_vehicle(a:ctx, function('s:do_view_analytics'))
endfunction

function! s:do_view_analytics(vehicle) abort
  if a:vehicle.type !=# 'C38'
    echohl WarningMsg | echo '[SkyRG] Analytics viewer only supported for C38' | echohl None
    return
  endif

  " Get SOC board
  let l:soc = {}
  for l:b in a:vehicle.boards
    if l:b.name ==# 'SOC'
      let l:soc = l:b
      break
    endif
  endfor
  if empty(l:soc)
    echohl WarningMsg | echo '[SkyRG] No SOC board found on C38' | echohl None
    return
  endif

  " Create temp directory for analytics
  let l:timestamp = strftime('%Y%m%d_%H%M%S')
  let l:local_dir = '/tmp/c38_analytics_' . l:timestamp
  call mkdir(l:local_dir, 'p')

  " Build a shell script that copies + converts + prints the txtlog path
  let l:aircam_dir = '/home/skydio/aircam'
  let l:cmd = join([
    \ printf('scp -r %s:/data/vendor/analytics/ %s/', l:soc.host, l:local_dir),
    \ printf('cd %s && bazel run tools/analytics_tools/executables:analytics_to_file -- --dir %s --skip-error-reports >&2',
    \   l:aircam_dir, l:local_dir),
    \ printf('echo ANALYTICS_DIR=%s', l:local_dir),
    \ ], ' && ')

  " Dispatch as async job with followup
  let l:action = {
    \ 'name': 'Fetch analytics',
    \ 'job': l:cmd,
    \ 'job_opts': {
    \   'title': 'Fetch analytics from ' . l:soc.host,
    \   'on_success': [
    \     {
    \       'name': 'Open analytics viewer',
    \       'key': 'o',
    \       'execute': function('s:open_analytics_from_task'),
    \     },
    \   ],
    \ },
    \ }

  call skyrg#backend#action#dispatch(l:action, {
    \ 'local_dir': l:local_dir,
    \ 'host': l:soc.host,
    \ })
endfunction

" Followup: find the txtlog in the task output dir and open the viewer.
function! s:open_analytics_from_task(ctx) abort
  " Extract ANALYTICS_DIR from task stdout
  let l:local_dir = ''
  for l:line in get(a:ctx, 'task_stdout', [])
    if l:line =~# '^ANALYTICS_DIR='
      let l:local_dir = substitute(l:line, '^ANALYTICS_DIR=', '', '')
      break
    endif
  endfor
  if empty(l:local_dir)
    let l:local_dir = get(a:ctx, 'local_dir', '')
  endif
  if empty(l:local_dir)
    echohl WarningMsg | echo '[SkyRG] Cannot find analytics directory' | echohl None
    return
  endif

  let l:txtlog_files = glob(l:local_dir . '/*/*.txtlog', 0, 1)
  if empty(l:txtlog_files)
    echohl WarningMsg | echo '[SkyRG] No txtlog files found after conversion' | echohl None
    return
  endif

  let l:vehicle_id = fnamemodify(l:txtlog_files[0], ':h:t')
  call skyrg#views#analytics#open(l:txtlog_files[0], l:vehicle_id)
endfunction

" Tail logs on a device board.
function! skyrg#views#device#tail_logs(ctx) abort
  call s:with_vehicle(a:ctx, function('s:do_tail_vehicle'))
endfunction

function! s:do_tail_vehicle(vehicle) abort
  if a:vehicle.type ==# 'C38'
    " C38: pick a logcat filter, then tail on SOC board
    let l:soc = {}
    for l:b in a:vehicle.boards
      if l:b.name ==# 'SOC'
        let l:soc = l:b
        break
      endif
    endfor
    if empty(l:soc)
      let l:soc = a:vehicle.boards[0]
    endif
    call s:show_picker('C38 — Tail', [
      \ {'label': 'Tail ucon',         'value': 'ucon'},
      \ {'label': 'Tail AVC denials',  'value': 'avc'},
      \ ], function('s:on_c38_tail_picked', [l:soc, a:vehicle]))
    return
  endif

  " R47 and others: pick board, then browse logs
  call skyrg#views#device#pick_board(a:vehicle, function('s:do_tail_r47_board'))
endfunction

let s:c38_tail_filters = {
  \ 'ucon': {'title': 'C38 tail ucon',         'grep': 'ucon'},
  \ 'avc':  {'title': 'C38 tail AVC denials',  'grep': 'avc: denied'},
  \ }

function! s:on_c38_tail_picked(board, vehicle, item) abort
  let l:f = s:c38_tail_filters[a:item.value]
  let l:meta = s:device_meta(a:board, a:vehicle)
  let l:meta['Filter'] = l:f.grep
  call skyrg#ui#live_split#open({
    \ 'title': l:f.title,
    \ 'source': 'job',
    \ 'cmd': printf('ssh %s logcat | grep --line-buffered "%s"', a:board.host, l:f.grep),
    \ 'meta': l:meta,
    \ })
endfunction

function! s:do_tail_r47_board(board) abort
  " List runmode directories, then pick one
  let l:host = a:board.host
  call skyrg#log#info('views/device', 'listing runmode dirs on %s', l:host)
  let l:cmd = printf(
    \ 'ssh -o ConnectTimeout=2 -o BatchMode=yes %s ls /home/skydio/semi_persistent/process_logs/latest/',
    \ l:host)
  let l:output = system(l:cmd)
  if v:shell_error
    echohl ErrorMsg
    echo printf('[SkyRG] Failed to list logs on %s (exit %d)', l:host, v:shell_error)
    echohl None
    return
  endif

  let l:dirs = filter(split(l:output, "\n"), '!empty(v:val)')
  if empty(l:dirs)
    echohl WarningMsg | echo '[SkyRG] No runmode directories found' | echohl None
    return
  endif

  let l:items = []
  for l:d in l:dirs
    call add(l:items, {'label': l:d, 'value': l:d})
  endfor
  call s:show_picker(a:board.name . ' — Runmode', l:items,
    \ function('s:on_runmode_picked', [a:board]))
endfunction

function! s:on_runmode_picked(board, item) abort
  " List log files in the chosen runmode dir
  let l:dir = '/home/skydio/semi_persistent/process_logs/latest/' . a:item.value
  let l:cmd = printf(
    \ 'ssh -o ConnectTimeout=2 -o BatchMode=yes %s ls %s',
    \ a:board.host, shellescape(l:dir))
  let l:output = system(l:cmd)
  if v:shell_error
    echohl ErrorMsg
    echo printf('[SkyRG] Failed to list files in %s', l:dir)
    echohl None
    return
  endif

  let l:files = filter(split(l:output, "\n"), '!empty(v:val)')
  if empty(l:files)
    echohl WarningMsg | echo '[SkyRG] No log files found' | echohl None
    return
  endif

  let l:items = []
  for l:f in l:files
    call add(l:items, {'label': l:f, 'value': l:dir . '/' . l:f})
  endfor
  call s:show_picker(a:board.name . ' — Log File', l:items,
    \ function('s:on_logfile_picked', [a:board]))
endfunction

function! s:on_logfile_picked(board, item) abort
  call skyrg#ui#live_split#open({
    \ 'title': a:board.name . ': ' . a:item.label,
    \ 'source': 'job',
    \ 'cmd': printf('ssh %s tail -f %s', a:board.host, shellescape(a:item.value)),
    \ })
endfunction

" View a remote file via Vim's built-in scp:// netrw support.
function! skyrg#views#device#view_file(ctx) abort
  call s:with_board(a:ctx, function('s:do_view_file'))
endfunction

function! s:do_view_file(board) abort
  " List hot paths, or let user type a path
  let l:hot_paths = s:get_hot_paths(a:board)
  if empty(l:hot_paths)
    " Fallback: prompt for path
    let l:path = skyrg#ui#input#prompt('remote_path', '[SkyRG] Remote path: ')
    if empty(l:path) | return | endif
    execute 'edit scp://' . a:board.host . '/' . l:path
    return
  endif

  let l:items = []
  for l:hp in l:hot_paths
    call add(l:items, {'label': l:hp.label, 'value': l:hp.path})
  endfor
  call s:show_picker(a:board.name . ' — Remote File', l:items,
    \ function('s:on_hot_path_picked', [a:board]))
endfunction

function! s:on_hot_path_picked(board, item) abort
  execute 'edit scp://' . a:board.host . '/' . a:item.value
endfunction

function! s:get_hot_paths(board) abort
  " Check user-defined hot paths first
  let l:user_paths = get(g:, 'skyrg_device_hot_paths', {})
  " Try board name, then fall through to defaults
  if has_key(l:user_paths, a:board.name)
    return l:user_paths[a:board.name]
  endif
  " Defaults
  return [
    \ {'label': 'process_logs/latest/', 'path': '/home/skydio/semi_persistent/process_logs/latest/'},
    \ {'label': 'crash_reports/',       'path': '/home/skydio/semi_persistent/crash_reports/'},
    \ ]
endfunction

" Build flashpack — runs in aircam repo.
function! skyrg#views#device#build_flashpack(ctx) abort
  call s:with_vehicle(a:ctx, function('s:do_build_flashpack'))
endfunction

function! s:do_build_flashpack(vehicle) abort
  let l:platform = s:vehicle_to_platform(a:vehicle.type)
  let l:cmd = printf('./skybuild --platform=%s CreateFlashPack', l:platform)

  " Let user edit the command before running
  let l:cmd = skyrg#ui#input#prompt('build_cmd', '[SkyRG] Build command: ', l:cmd)
  if empty(l:cmd) | return | endif

  " Determine aircam root
  let l:aircam = s:find_aircam_root()
  if empty(l:aircam)
    echohl ErrorMsg | echo '[SkyRG] Cannot find aircam root' | echohl None
    return
  endif

  call skyrg#backend#action#dispatch({
    \ 'name': 'Build flashpack (' . a:vehicle.type . ')',
    \ 'job': l:cmd,
    \ 'job_opts': {
    \   'interactive': 1,
    \   'title': 'Build ' . a:vehicle.type . ' flashpack',
    \   'cwd': l:aircam,
    \ },
    \ }, {})
endfunction

function! s:vehicle_to_platform(vtype) abort
  let l:map = get(g:, 'skyrg_device_platforms', {
    \ 'R47': 'r47',
    \ 'C38': 'c38',
    \ })
  return get(l:map, a:vtype, tolower(a:vtype))
endfunction

function! s:find_aircam_root() abort
  " Check common paths
  for l:p in [expand('~/aircam'), '/home/skydio/aircam']
    if isdirectory(l:p)
      return l:p
    endif
  endfor
  " Fall back to cwd if it looks like aircam
  if filereadable(getcwd() . '/skybuild')
    return getcwd()
  endif
  return ''
endfunction

"==============================================================================
" Search device logs
"==============================================================================

" C38 log sources — each entry defines a label, the remote directory, and a
" file glob.  Add new sources here as needed.
let s:c38_log_sources = [
  \ {'label': 'logcat',  'dir': '/data/vendor/logs/process_logs/latest', 'glob': 'logcat*'},
  \ ]

" Entry point: search device logs for a user-provided term.
function! skyrg#views#device#search_logs(ctx) abort
  call s:with_vehicle(a:ctx, function('s:do_search_logs'))
endfunction

function! s:do_search_logs(vehicle) abort
  if a:vehicle.type !=# 'C38'
    echohl WarningMsg | echo '[SkyRG] Log search is only supported on C38' | echohl None
    return
  endif
  let l:soc = {}
  for l:b in a:vehicle.boards
    if l:b.name ==# 'SOC'
      let l:soc = l:b
      break
    endif
  endfor
  if empty(l:soc)
    let l:soc = a:vehicle.boards[0]
  endif

  " If multiple sources, let user pick; otherwise go straight to search
  if len(s:c38_log_sources) == 1
    call s:do_search_logs_prompt(l:soc, a:vehicle, s:c38_log_sources[0])
  else
    let l:items = []
    for l:src in s:c38_log_sources
      call add(l:items, {'label': l:src.label, 'value': l:src})
    endfor
    call s:show_picker('C38 — Search Logs', l:items,
      \ function('s:on_log_source_picked', [l:soc, a:vehicle]))
  endif
endfunction

function! s:on_log_source_picked(board, vehicle, item) abort
  call s:do_search_logs_prompt(a:board, a:vehicle, a:item.value)
endfunction

function! s:do_search_logs_prompt(board, vehicle, source) abort
  let l:term = skyrg#ui#input#prompt('search_term',
    \ printf('[SkyRG] Search %s for (empty=all): ', a:source.label))
  " Merge all matching files and sort by timestamp.
  " logcat format: MM-DD HH:MM:SS.mmm  — sort -t' ' -k1,2 gives time order.
  " Filter out logcat buffer-switch headers (--------- switch to <buf>)
  " before sorting, since they have no timestamp and sort to the top.
  let l:strip = 'grep -hv ''^---------'' %s/%s'
  if empty(l:term)
    let l:cmd = printf(
      \ 'ssh %s "' . l:strip . ' | sort -t'' '' -k1,2 -s"',
      \ a:board.host, a:source.dir, a:source.glob)
    let l:title = printf('C38 %s (all)', a:source.label)
  else
    let l:cmd = printf(
      \ 'ssh %s "' . l:strip . ' | grep ''%s'' | sort -t'' '' -k1,2 -s"',
      \ a:board.host, a:source.dir, a:source.glob, escape(l:term, "'"))
    let l:title = printf('C38 %s grep: %s', a:source.label, l:term)
  endif
  let l:meta = s:device_meta(a:board, a:vehicle)
  let l:meta['Source'] = a:source.dir . '/' . a:source.glob
  if !empty(l:term)
    let l:meta['Search'] = l:term
  endif
  call skyrg#ui#live_split#open({
    \ 'title': l:title,
    \ 'source': 'job',
    \ 'cmd': l:cmd,
    \ 'meta': l:meta,
    \ })
endfunction

" Refresh device detection — re-probe and report.
function! skyrg#views#device#refresh(ctx) abort
  echo '[SkyRG] Probing devices...'
  call skyrg#backend#device#refresh(function('s:on_refresh_done'))
endfunction

function! s:on_refresh_done(vehicles) abort
  if empty(a:vehicles)
    echohl WarningMsg | echo '[SkyRG] No devices detected' | echohl None
  else
    let l:names = join(map(copy(a:vehicles), {_, v ->
      \ v.type . ' [' . join(map(copy(v.boards), 'v:val.name'), ', ') . ']'}), ', ')
    echo '[SkyRG] Detected: ' . l:names
  endif
endfunction

"==============================================================================
" Helpers — resolve vehicle/board from cache with pickers
"==============================================================================

" Resolve a vehicle from cache, showing picker if needed, then call Callback.
function! s:with_vehicle(ctx, Callback) abort
  let l:vehicles = skyrg#backend#device#cached()
  if empty(l:vehicles)
    " Try detecting first
    echo '[SkyRG] Probing devices...'
    call skyrg#backend#device#detect(
      \ function('s:with_vehicle_after_detect', [a:Callback]))
    return
  endif
  call skyrg#views#device#pick_vehicle(l:vehicles, a:Callback)
endfunction

function! s:with_vehicle_after_detect(Callback, vehicles) abort
  if empty(a:vehicles)
    echohl WarningMsg | echo '[SkyRG] No devices detected' | echohl None
    return
  endif
  call skyrg#views#device#pick_vehicle(a:vehicles, a:Callback)
endfunction

" Resolve a board: pick vehicle if needed, then pick board.
function! s:with_board(ctx, Callback) abort
  call s:with_vehicle(a:ctx, function('s:with_board_pick', [a:Callback]))
endfunction

function! s:with_board_pick(Callback, vehicle) abort
  call skyrg#views#device#pick_board(a:vehicle, a:Callback)
endfunction

" Build a standard meta dict for device-related live_splits.
" Includes Device (hostname), Type, Host, and Board.
function! s:device_meta(board, vehicle) abort
  let l:meta = {}
  if has_key(a:vehicle, 'hostname') && !empty(a:vehicle.hostname)
    let l:meta['Device'] = a:vehicle.hostname
  endif
  let l:meta['Type'] = a:vehicle.type
  let l:meta['Host'] = a:board.host
  let l:meta['Board'] = a:board.name
  return l:meta
endfunction
