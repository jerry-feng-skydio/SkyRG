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
    \ {'board': 'NVU',        'host': 'nvu'},
    \ {'board': 'QCU',        'host': 'qcu'},
    \ {'board': 'NVU (wifi)', 'host': 'nvu-wifi'},
    \ {'board': 'QCU (wifi)', 'host': 'qcu-wifi'},
    \ ]
  let l:c38_probes = [
    \ {'board': 'SOC',   'host': 'c38'},
    \ {'board': 'Radio', 'host': 'c38-radio'},
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

" Statusline-friendly string.  Returns '' when nothing is connected,
" otherwise e.g. 'R47[NVU,QCU] C38[SOC]'.
function! skyrg#backend#device#statusline() abort
  if empty(s:cached_vehicles) | return '' | endif
  let l:parts = []
  for l:v in s:cached_vehicles
    let l:boards = join(map(copy(l:v.boards), 'v:val.name'), ',')
    call add(l:parts, l:v.type . '[' . l:boards . ']')
  endfor
  return join(l:parts, ' ')
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

  " All probes done — group into vehicles
  let s:cached_vehicles = s:group_vehicles()
  let s:detecting = 0

  call skyrg#log#info('device', 'detected %d vehicle(s): %s',
    \ len(s:cached_vehicles),
    \ join(map(copy(s:cached_vehicles), 'v:val.type'), ', '))

  call a:Callback(s:cached_vehicles)
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
        call add(l:boards, {'name': l:p.board, 'host': l:p.host})
      endif
    endfor
    if !empty(l:boards)
      call add(l:vehicles, {'type': l:vdef.type, 'boards': l:boards})
    endif
  endfor
  return l:vehicles
endfunction
