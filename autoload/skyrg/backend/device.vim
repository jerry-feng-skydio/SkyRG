" autoload/skyrg/backend/device.vim — Device detection via SSH probing
"
" Detects connected Skydio devices (R47, C38, etc.) by probing SSH host
" aliases defined in ~/.ssh/config. Probes run in parallel via job_start().
"
" Usage:
"   call skyrg#backend#device#detect(Callback)   " async detect
"   let vehicles = skyrg#backend#device#cached()  " last result
"   call skyrg#backend#device#refresh(Callback)   " force re-probe
"   let ok = skyrg#backend#device#is_connected()  " quick check
"
" Detected vehicle shape:
"   {'type': 'R47', 'boards': [{'name': 'NVU', 'host': 'nvu'}, ...]}

"==============================================================================
" Vehicle definitions — override with g:skyrg_device_defs
"==============================================================================

function! s:get_vehicle_defs() abort
  if exists('g:skyrg_device_defs')
    return g:skyrg_device_defs
  endif
  let l:r47_probes = [
    \ {'board': 'NVU',        'host': 'nvu',       'platform': 'linux'},
    \ {'board': 'QCU',        'host': 'qcu',       'platform': 'linux'},
    \ {'board': 'NVU (wifi)', 'host': 'nvu-wifi',  'platform': 'linux'},
    \ {'board': 'QCU (wifi)', 'host': 'qcu-wifi',  'platform': 'linux'},
    \ ]
  let l:c38_probes = [
    \ {'board': 'SOC',   'host': 'c38',       'platform': 'android'},
    \ {'board': 'Radio', 'host': 'c38-radio', 'platform': 'linux'},
    \ ]
  return [
    \ {'type': 'R47', 'probes': l:r47_probes},
    \ {'type': 'C38', 'probes': l:c38_probes},
    \ ]
endfunction

"==============================================================================
" State
"==============================================================================

let s:cached_vehicles = []   " list of detected vehicles
let s:detecting = 0          " 1 while detection is in-flight
let s:pending_probes = 0     " number of probes still running
let s:probe_results = {}     " host -> 0/1

"==============================================================================
" Public API
"==============================================================================

" Return cached detection results (empty list if never probed).
function! skyrg#backend#device#cached() abort
  return s:cached_vehicles
endfunction

" Return 1 if any device was detected in the last probe.
function! skyrg#backend#device#is_connected() abort
  return !empty(s:cached_vehicles)
endfunction

" Statusline-friendly string.
"   No devices:  '[No Connected Devices]'
"   One device:  '[🔗 C38]'
"   Multiple:    '[🔗 R47 C38]'
function! skyrg#backend#device#statusline() abort
  if empty(s:cached_vehicles)
    return '[No Connected Devices]'
  endif
  let l:parts = []
  for l:v in s:cached_vehicles
    let l:name = l:v.type
    if has_key(l:v, 'hostname') && !empty(l:v.hostname)
      let l:name .= ' ' . l:v.hostname
    endif
    call add(l:parts, l:name)
  endfor
  return '[🔗 ' . join(l:parts, ' | ') . ']'
endfunction

" Start async detection. Callback receives the vehicle list when done.
"   Callback signature: function(vehicles)
function! skyrg#backend#device#detect(Callback) abort
  if s:detecting
    call skyrg#log#info('device', 'detection already in-flight, skipping')
    return
  endif
  call s:probe_all(a:Callback)
endfunction

" Force re-probe (clears cache first).
function! skyrg#backend#device#refresh(Callback) abort
  let s:cached_vehicles = []
  let s:detecting = 0
  call s:probe_all(a:Callback)
endfunction

"==============================================================================
" Probing internals
"==============================================================================

function! s:probe_all(Callback) abort
  let s:detecting = 1
  let s:probe_results = {}
  let s:pending_probes = 0
  let l:Callback = a:Callback

  " Collect all unique hosts to probe
  let l:hosts = []
  for l:vdef in s:get_vehicle_defs()
    for l:p in l:vdef.probes
      if index(l:hosts, l:p.host) < 0
        call add(l:hosts, l:p.host)
      endif
    endfor
  endfor

  if empty(l:hosts)
    let s:detecting = 0
    call skyrg#log#warn('device', 'no hosts to probe')
    call l:Callback(s:cached_vehicles)
    return
  endif

  let s:pending_probes = len(l:hosts)
  call skyrg#log#info('device', 'probing %d hosts: %s', len(l:hosts), join(l:hosts, ', '))

  " Launch all probes in parallel
  for l:host in l:hosts
    let l:cmd = printf(
      \ 'ssh -o ConnectTimeout=1 -o BatchMode=yes -o StrictHostKeyChecking=no %s true',
      \ shellescape(l:host))
    call job_start(['/bin/sh', '-c', l:cmd], {
      \ 'exit_cb': function('s:on_probe_exit', [l:host, l:Callback]),
      \ })
  endfor
endfunction

function! s:on_probe_exit(host, Callback, job, exit_code) abort
  let s:probe_results[a:host] = (a:exit_code == 0) ? 1 : 0
  let s:pending_probes -= 1

  call skyrg#log#info('device', 'probe %s: %s (%d remaining)',
    \ a:host, a:exit_code == 0 ? 'UP' : 'down', s:pending_probes)

  if s:pending_probes > 0
    return
  endif

  " All probes done — group into vehicles, then fetch hostnames
  let s:cached_vehicles = s:group_vehicles()

  call skyrg#log#info('device', 'detected %d vehicle(s): %s',
    \ len(s:cached_vehicles),
    \ join(map(copy(s:cached_vehicles), 'v:val.type'), ', '))

  " Fetch device hostnames (async) before signalling completion
  call s:fetch_hostnames(a:Callback)
endfunction

" Fetch the human-readable hostname for each detected vehicle via SSH.
" Picks the first reachable board per vehicle.  When all done, marks
" detection finished and calls the Callback.
function! s:fetch_hostnames(Callback) abort
  let s:hostname_pending = 0
  for l:v in s:cached_vehicles
    if empty(l:v.boards) | continue | endif
    let l:host = l:v.boards[0].host
    let s:hostname_pending += 1
    let l:cmd = printf(
      \ 'ssh -o ConnectTimeout=1 -o BatchMode=yes %s hostname',
      \ shellescape(l:host))
    call job_start(['/bin/sh', '-c', l:cmd], {
      \ 'out_cb': function('s:on_hostname_out', [l:v]),
      \ 'exit_cb': function('s:on_hostname_exit', [a:Callback]),
      \ 'out_mode': 'nl',
      \ })
  endfor
  " No vehicles — finish immediately
  if s:hostname_pending == 0
    let s:detecting = 0
    call a:Callback(s:cached_vehicles)
  endif
endfunction

function! s:on_hostname_out(vehicle, ch, msg) abort
  " Store the first line of output as the device name
  if !has_key(a:vehicle, 'hostname') || empty(a:vehicle.hostname)
    let a:vehicle.hostname = trim(a:msg)
  endif
endfunction

function! s:on_hostname_exit(Callback, job, exit_code) abort
  let s:hostname_pending -= 1
  if s:hostname_pending > 0 | return | endif
  " All hostnames fetched — fill in blanks
  for l:v in s:cached_vehicles
    if !has_key(l:v, 'hostname') || empty(l:v.hostname)
      let l:v.hostname = ''
    endif
  endfor
  let s:detecting = 0
  call a:Callback(s:cached_vehicles)
endfunction

"==============================================================================
" USB event watcher — auto-detect on plug/unplug
"==============================================================================

let s:usb_watch_job = v:null
let s:usb_debounce_timer = 0

" Start watching for USB events. Triggers device detection on plug/unplug.
" Safe to call multiple times — only one watcher runs at a time.
function! skyrg#backend#device#watch_usb() abort
  if s:usb_watch_job != v:null && job_status(s:usb_watch_job) ==# 'run'
    call skyrg#log#info('device', 'USB watcher already running')
    return
  endif
  if !executable('udevadm')
    call skyrg#log#warn('device', 'udevadm not found, USB watch unavailable')
    return
  endif
  let s:usb_watch_job = job_start(
    \ ['/bin/sh', '-c', 'stdbuf -oL udevadm monitor --subsystem-match=usb --property'],
    \ {
    \   'out_cb': function('s:on_usb_event'),
    \   'err_cb': {ch, msg -> 0},
    \   'exit_cb': function('s:on_usb_watch_exit'),
    \   'out_mode': 'nl',
    \ })
  call skyrg#log#info('device', 'USB watcher started')

  " Initial probe so devices are detected at Vim startup
  call skyrg#backend#device#detect({vehicles -> s:on_usb_detect_done(vehicles)})
endfunction

" Stop watching for USB events.
function! skyrg#backend#device#unwatch_usb() abort
  if s:usb_watch_job != v:null && job_status(s:usb_watch_job) ==# 'run'
    call job_stop(s:usb_watch_job)
    let s:usb_watch_job = v:null
    call skyrg#log#info('device', 'USB watcher stopped')
  endif
  if s:usb_debounce_timer
    call timer_stop(s:usb_debounce_timer)
    let s:usb_debounce_timer = 0
  endif
endfunction

function! s:on_usb_event(ch, msg) abort
  " udevadm emits many lines per event; debounce to a single detection.
  " Only trigger on ACTION lines (add/remove/bind/unbind).
  if a:msg !~# '^ACTION='
    return
  endif
  call skyrg#log#info('device', 'USB event: %s', a:msg)
  " Reset debounce timer — wait 2s after last event before probing
  if s:usb_debounce_timer
    call timer_stop(s:usb_debounce_timer)
  endif
  let s:usb_debounce_timer = timer_start(2000, function('s:on_usb_debounce'))
endfunction

function! s:on_usb_debounce(timer) abort
  let s:usb_debounce_timer = 0
  call skyrg#log#info('device', 'USB debounce fired, re-detecting devices')
  call skyrg#backend#device#detect({vehicles -> s:on_usb_detect_done(vehicles)})
endfunction

function! s:on_usb_detect_done(vehicles) abort
  let l:status = skyrg#backend#device#statusline()
  if empty(l:status)
    echom '[SkyRG] Devices: none detected'
  else
    echom printf('[SkyRG] Devices: %s', l:status)
  endif
endfunction

function! s:on_usb_watch_exit(job, exit_code) abort
  let s:usb_watch_job = v:null
  call skyrg#log#info('device', 'USB watcher exited (%d)', a:exit_code)
endfunction

"==============================================================================
" Vehicle grouping
"==============================================================================

function! s:group_vehicles() abort
  let l:vehicles = []
  for l:vdef in s:get_vehicle_defs()
    let l:boards = []
    for l:p in l:vdef.probes
      if get(s:probe_results, l:p.host, 0)
        call add(l:boards, {
          \ 'name': l:p.board,
          \ 'host': l:p.host,
          \ 'platform': get(l:p, 'platform', 'linux'),
          \ })
      endif
    endfor
    if !empty(l:boards)
      call add(l:vehicles, {'type': l:vdef.type, 'boards': l:boards})
    endif
  endfor
  return l:vehicles
endfunction
