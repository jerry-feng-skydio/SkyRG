" autoload/skyrg/panel/complete.vim — Dir and Types tab-completion

"==============================================================================
" Unified dispatcher
"==============================================================================
function! skyrg#panel#complete#field(...) abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  let l:dir = get(a:, 1, 1)
  if l:s.field == l:c.DIRS
    call s:complete_dirs(l:dir)
  elseif l:s.field == l:c.TYPES
    call s:complete_types(l:dir)
  endif
endfunction

function! skyrg#panel#complete#jump_letter(dir) abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  if !get(l:s, 'tab_cycling', 0) || empty(get(l:s, 'tab_candidates', []))
    call skyrg#panel#complete#field(a:dir)
    return
  endif
  let l:cands = l:s.tab_candidates
  let l:n = len(l:cands)
  let l:cur_letter = l:cands[l:s.tab_idx][0]
  let l:idx = l:s.tab_idx
  while 1
    let l:idx = (l:idx + a:dir + l:n) % l:n
    if l:cands[l:idx][0] !=# l:cur_letter || l:idx == l:s.tab_idx
      break
    endif
  endwhile
  let l:s.tab_idx = l:idx
  let l:f = l:s.fields[l:s.field]
  if l:s.field == l:c.DIRS
    let l:parts = split(l:f.value, ',', 1)
    let l:prev_len = 0
    for l:i in range(len(l:parts) - 1)
      let l:prev_len += len(l:parts[l:i]) + 1
    endfor
    let l:parts[-1] = l:cands[l:idx]
    let l:s.dir_candidates = l:cands
    let l:f.value = join(l:parts, ',')
    let l:f.pos = l:prev_len + len(l:parts[-1]) - 1
  elseif l:s.field == l:c.TYPES
    let l:val = l:f.value
    if len(l:val) > 0 && l:val[-1:] ==# ',' | let l:val = l:val[:-2] | endif
    let l:parts = split(l:val, ',', 1)
    let l:parts[-1] = l:cands[l:idx]
    let l:s.type_candidates = l:cands
    let l:f.value = join(l:parts, ',') . ','
    let l:f.pos = len(l:f.value)
  endif
endfunction

function! skyrg#panel#complete#reset_tab_cycle() abort
  let l:s = skyrg#panel#state()
  let l:s.tab_cycling = 0
  let l:s.tab_candidates = []
  let l:s.tab_suffix = ''
  " Keep tab_idx so the hint highlight persists on the last selection
endfunction

"==============================================================================
" Dirs completion
"==============================================================================
function! s:complete_dirs(dir) abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  let l:f = l:s.fields[l:c.DIRS]
  let l:parts = split(l:f.value, ',', 1)

  let l:prev_len = 0
  for l:i in range(len(l:parts) - 1)
    let l:prev_len += len(l:parts[l:i]) + 1
  endfor
  let l:cur = l:parts[-1]
  let l:cpos = l:f.pos - l:prev_len
  let l:n_cands = len(get(l:s, 'tab_candidates', []))

  " --- Cycling ---
  if get(l:s, 'tab_cycling', 0) && l:n_cands > 0
    let l:cands = l:s.tab_candidates
    let l:s.tab_idx = (l:s.tab_idx + a:dir + l:n_cands) % l:n_cands
    let l:parts[-1] = l:cands[l:s.tab_idx]
    let l:s.dir_candidates = l:cands
    let l:f.value = join(l:parts, ',')
    let l:f.pos = l:prev_len + len(l:parts[-1]) - 1
    return
  endif

  " --- Determine mode: drill-in vs sibling ---
  let l:drill = (l:cpos >= len(l:cur)) && l:cur[-1:] ==# '/'

  if l:drill
    let l:prefix = l:cur
    let l:candidates = s:glob_entries(l:prefix)
  else
    let l:stripped = l:cur
    if l:stripped[-1:] ==# '/'
      let l:stripped = l:stripped[:-2]
    endif
    let l:slash = strridx(l:stripped, '/')
    let l:parent = l:slash >= 0 ? l:stripped[:l:slash] : ''
    let l:candidates = s:glob_entries(l:parent)
  endif

  if empty(l:candidates)
    let l:s.dir_candidates = []
    call skyrg#panel#complete#reset_tab_cycle()
    return
  endif

  let l:exact = index(l:candidates, l:cur)
  if l:exact >= 0
    let l:next = (l:exact + a:dir + len(l:candidates)) % len(l:candidates)
    let l:parts[-1] = l:candidates[l:next]
    call s:dir_start_cycle(l:candidates, l:next)
  elseif len(l:candidates) == 1
    let l:parts[-1] = l:candidates[0]
    call s:dir_start_cycle(l:candidates, 0)
  else
    let l:pick = a:dir >= 0 ? 0 : len(l:candidates) - 1
    let l:parts[-1] = l:candidates[l:pick]
    call s:dir_start_cycle(l:candidates, l:pick)
  endif

  let l:f.value = join(l:parts, ',')
  let l:f.pos = l:prev_len + len(l:parts[-1]) - 1
endfunction

function! s:dir_start_cycle(cands, idx) abort
  let l:s = skyrg#panel#state()
  let l:s.dir_candidates = a:cands
  let l:s.tab_cycling = 1
  let l:s.tab_candidates = a:cands
  let l:s.tab_idx = a:idx
  let l:s.tab_suffix = ''
endfunction

function! s:glob_entries(prefix) abort
  let l:entries = filter(glob(a:prefix . '*', 0, 1), 'isdirectory(v:val)')
  return map(l:entries, 'v:val . "/"')
endfunction

"==============================================================================
" Types completion
"==============================================================================
function! s:complete_types(dir) abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  let l:f = l:s.fields[l:c.TYPES]
  let l:parts = split(l:f.value, ',', 1)

  let l:prev_len = 0
  for l:i in range(len(l:parts) - 1)
    let l:prev_len += len(l:parts[l:i]) + 1
  endfor
  let l:cur = trim(l:parts[-1])
  let l:cpos = l:f.pos - l:prev_len
  let l:n_cands = len(get(l:s, 'tab_candidates', []))

  " --- Cycling ---
  if get(l:s, 'tab_cycling', 0) && l:n_cands > 0
    let l:cands = l:s.tab_candidates
    let l:s.tab_idx = (l:s.tab_idx + a:dir + l:n_cands) % l:n_cands
    let l:parts[-1] = l:cands[l:s.tab_idx]
    let l:s.type_candidates = l:cands
    let l:f.value = join(l:parts, ',')
    let l:f.pos = l:prev_len + len(l:parts[-1]) - 1
    return
  endif

  let l:drill = (l:cpos >= len(l:parts[-1])) && !empty(l:cur)

  if l:drill
    let l:parts = l:parts + ['']
    let l:prev_len += len(l:cur) + 1
    let l:cur = ''
    let l:candidates = s:match_types('')
  else
    let l:candidates = s:match_types(l:cur)
  endif

  if empty(l:candidates)
    let l:s.type_candidates = []
    call skyrg#panel#complete#reset_tab_cycle()
    return
  endif

  let l:exact = index(l:candidates, l:cur)
  if l:exact >= 0
    let l:next = (l:exact + a:dir + len(l:candidates)) % len(l:candidates)
    let l:parts[-1] = l:candidates[l:next]
    call s:type_start_cycle(l:candidates, l:next)
  elseif len(l:candidates) == 1
    let l:parts[-1] = l:candidates[0]
    call s:type_start_cycle(l:candidates, 0)
  else
    let l:pick = a:dir >= 0 ? 0 : len(l:candidates) - 1
    let l:parts[-1] = l:candidates[l:pick]
    call s:type_start_cycle(l:candidates, l:pick)
  endif

  let l:f.value = join(l:parts, ',')
  let l:f.pos = l:prev_len + len(l:parts[-1]) - 1
endfunction

function! s:type_start_cycle(cands, idx) abort
  let l:s = skyrg#panel#state()
  let l:s.type_candidates = a:cands
  let l:s.tab_cycling = 1
  let l:s.tab_candidates = a:cands
  let l:s.tab_idx = a:idx
  let l:s.tab_suffix = ''
endfunction

function! s:match_types(partial) abort
  let l:s = skyrg#panel#state()
  let l:c = skyrg#panel#const()
  let l:all = s:rg_type_names()
  let l:val = l:s.fields[l:c.TYPES].value
  if l:val[-1:] ==# ',' | let l:val = l:val[:-2] | endif
  let l:chosen = map(split(l:val, ','), 'trim(v:val)')
  if !empty(l:chosen)
    call remove(l:chosen, -1)
    let l:all = filter(copy(l:all), 'index(l:chosen, v:val) < 0')
  endif
  if l:s.fields[l:c.GITIGN].value ==# 'on'
    let l:gi_exts = s:gitignore_extensions()
    if !empty(l:gi_exts)
      let l:type_exts = s:rg_type_extensions()
      let l:all = filter(l:all, '!s:type_fully_ignored(v:val, l:type_exts, l:gi_exts)')
    endif
  endif
  if empty(a:partial)
    return l:all
  endif
  return filter(l:all, 'v:val[:len(a:partial)-1] ==# a:partial')
endfunction

"==============================================================================
" rg type list cache
"==============================================================================
let s:rg_types_cache = []
function! s:rg_type_names() abort
  if !empty(s:rg_types_cache)
    return s:rg_types_cache
  endif
  call s:parse_rg_type_list()
  return s:rg_types_cache
endfunction

let s:rg_type_ext_cache = {}
function! s:rg_type_extensions() abort
  if !empty(s:rg_type_ext_cache)
    return s:rg_type_ext_cache
  endif
  call s:parse_rg_type_list()
  return s:rg_type_ext_cache
endfunction

function! s:parse_rg_type_list() abort
  if !empty(s:rg_types_cache) | return | endif
  let l:raw = systemlist('rg --type-list 2>/dev/null')
  for l:line in l:raw
    let l:name = matchstr(l:line, '^[^:]*')
    if empty(l:name) | continue | endif
    call add(s:rg_types_cache, l:name)
    let l:ext_str = matchstr(l:line, ':\s*\zs.*')
    let s:rg_type_ext_cache[l:name] = map(split(l:ext_str, ',\s*'), 'substitute(v:val, "^\\*\\.", "", "")')
  endfor
endfunction

let s:gitignore_ext_cache = v:null
function! s:gitignore_extensions() abort
  if s:gitignore_ext_cache isnot v:null
    return s:gitignore_ext_cache
  endif
  let s:gitignore_ext_cache = {}
  let l:gi = findfile('.gitignore', '.;')
  if empty(l:gi) | return s:gitignore_ext_cache | endif
  for l:line in readfile(l:gi)
    let l:line = trim(l:line)
    if empty(l:line) || l:line[0] ==# '#' | continue | endif
    if l:line[0] ==# '!' | continue | endif
    let l:ext = matchstr(l:line, '^\%(\*\*/\)\?\*\.\zs[a-zA-Z0-9_+]\+$')
    if !empty(l:ext)
      let s:gitignore_ext_cache[l:ext] = 1
    endif
  endfor
  return s:gitignore_ext_cache
endfunction

function! s:type_fully_ignored(type_name, type_exts, gi_exts) abort
  let l:exts = get(a:type_exts, a:type_name, [])
  if empty(l:exts) | return 0 | endif
  for l:ext in l:exts
    if !has_key(a:gi_exts, l:ext) | return 0 | endif
  endfor
  return 1
endfunction
