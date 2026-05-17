" autoload/skyrg/panel/preset.vim — Preset management

function! skyrg#panel#preset#names() abort
  let l:names = {}
  if exists('g:skyrg_presets')
    for l:k in keys(g:skyrg_presets) | let l:names[l:k] = 1 | endfor
  endif
  if exists('g:SkyFilter') && has_key(g:SkyFilter, 'presets')
    for l:k in keys(g:SkyFilter.presets) | let l:names[l:k] = 1 | endfor
  endif
  return sort(keys(l:names))
endfunction

function! skyrg#panel#preset#get_sky_filter(name) abort
  if exists('g:SkyFilter') && has_key(g:SkyFilter, 'presets') && has_key(g:SkyFilter.presets, a:name)
    return g:SkyFilter.presets[a:name]
  endif
  return {}
endfunction

function! skyrg#panel#preset#cycle(dir) abort
  let l:fm = skyrg#panel#state().form
  let l:c = skyrg#panel#const()
  let l:n = skyrg#panel#preset#names()
  if empty(l:n) | return | endif
  let l:idx = index(l:n, l:fm.fields[l:c.PRESET].value)
  let l:idx = l:idx < 0 ? 0 : (l:idx + a:dir + len(l:n)) % len(l:n)
  let l:name = l:n[l:idx]
  let l:fm.fields[l:c.PRESET].value = l:name
  let l:fm.fields[l:c.PRESET].pos = len(l:name)
  call skyrg#panel#preset#apply(l:name)
endfunction

function! skyrg#panel#preset#apply(name) abort
  let l:fm = skyrg#panel#state().form
  let l:c = skyrg#panel#const()
  if !exists('g:skyrg_presets') || !has_key(g:skyrg_presets, a:name) | return | endif
  let l:p = g:skyrg_presets[a:name]
  if empty(l:fm.fields[l:c.TYPES].value) && has_key(l:p, 'desired_types')
    let l:v = join(l:p.desired_types, ',')
    let l:fm.fields[l:c.TYPES].value = l:v | let l:fm.fields[l:c.TYPES].pos = len(l:v)
  endif
  if empty(l:fm.fields[l:c.DIRS].value) && has_key(l:p, 'desired_dirs')
    let l:v = join(l:p.desired_dirs, ',')
    let l:fm.fields[l:c.DIRS].value = l:v | let l:fm.fields[l:c.DIRS].pos = len(l:v)
  endif
endfunction
