" skyrg/filter.vim - Search filter presets
"
" Provides g:SkyFilter, a prototype-based class for building rg search
" filters with chainable include/ignore methods for filetypes and dirs.
"
" Usage (in your .vimrc, typically in a VimEnter autocmd):
"   call g:SkyFilter.new("my_project")
"         \ .include_filetypes(['cc', 'h', 'py'])
"         \ .ignore_dirs(['build', '**/node_modules'])
"   let g:SkyFilter.default = 'my_project'

" Bucket keys for the internal filter dict
let s:TYPE = 'type'
let s:DIR = 'dir'

" Instance method prototype — copied into every new filter
let s:proto = {}

"==============================================================================
" Initialization
"==============================================================================

" Set up the global g:SkyFilter namespace. Called once from plugin/skyrg.vim.
function! skyrg#filter#init() abort
  if exists('g:SkyFilter') && has_key(g:SkyFilter, '_loaded')
    return
  endif

  let g:SkyFilter = {
    \ 'presets': {},
    \ 'default': 'DEFAULT_FILTER',
    \ '_loaded': 1,
    \ }

  " Bind the public constructor to the global dict
  function! g:SkyFilter.new(name) abort dict
    return skyrg#filter#new(a:name)
  endfunction
endfunction

"==============================================================================
" Constructor
"==============================================================================

" Create a new filter and register it in g:SkyFilter.presets.
function! skyrg#filter#new(name) abort
  let l:f = copy(s:proto)
  let l:f.name = a:name
  let l:f[s:TYPE] = {}
  let l:f[s:DIR] = {}

  if has_key(g:SkyFilter.presets, a:name)
    call skyrg#log#debug('[SkyFilter] Redefining filter "%s"', a:name)
  endif
  let g:SkyFilter.presets[a:name] = l:f

  return l:f
endfunction

"==============================================================================
" Private helpers
"==============================================================================

" Batch-set keys in a filter bucket.
"   value: 1 = include, 0 = ignore
"   overwrite: if 0, existing entries are preserved
function! s:set_entries(filter, bucket, keys, value, overwrite) abort
  for l:key in a:keys
    if !a:overwrite && has_key(a:filter[a:bucket], l:key)
      call skyrg#log#debug('[SkyFilter] Keeping [%s]=%s (skip %s)',
            \ l:key, a:filter[a:bucket][l:key], a:value)
      continue
    endif
    let a:filter[a:bucket][l:key] = a:value
  endfor
endfunction

" Return the list of keys in a bucket whose value matches.
function! s:get_entries(filter, bucket, value) abort
  let l:result = []
  for [l:key, l:val] in items(a:filter[a:bucket])
    if l:val == a:value
      call add(l:result, l:key)
    endif
  endfor
  return l:result
endfunction

"==============================================================================
" Chainable setters
"==============================================================================

function! s:proto.include_filetypes(list) abort dict
  call s:set_entries(self, s:TYPE, a:list, 1, 1)
  let g:SkyFilter.presets[self.name] = self
  return self
endfunction

function! s:proto.ignore_filetypes(list) abort dict
  call s:set_entries(self, s:TYPE, a:list, 0, 1)
  let g:SkyFilter.presets[self.name] = self
  return self
endfunction

function! s:proto.include_dirs(list) abort dict
  call s:set_entries(self, s:DIR, a:list, 1, 1)
  let g:SkyFilter.presets[self.name] = self
  return self
endfunction

function! s:proto.ignore_dirs(list) abort dict
  call s:set_entries(self, s:DIR, a:list, 0, 1)
  let g:SkyFilter.presets[self.name] = self
  return self
endfunction

"==============================================================================
" Composition
"==============================================================================

" Merge another filter into this one. On collision, self's values win.
function! s:proto.merge(other) abort dict
  let l:ow = 0
  call s:set_entries(self, s:TYPE, s:get_entries(a:other, s:TYPE, 1), 1, l:ow)
  call s:set_entries(self, s:TYPE, s:get_entries(a:other, s:TYPE, 0), 0, l:ow)
  call s:set_entries(self, s:DIR,  s:get_entries(a:other, s:DIR,  1), 1, l:ow)
  call s:set_entries(self, s:DIR,  s:get_entries(a:other, s:DIR,  0), 0, l:ow)
  return self
endfunction

" Apply a base preset's defaults, respecting explicit overrides in self.
"
" Include behavior:
"   Only applied if self has NO includes of that type. This enables
"   specificity — when the user explicitly passes -f or -d flags, the
"   base preset's includes are skipped entirely.
"
" Ignore behavior:
"   Always applied (unless self already has an entry for that key).
"   Base ignores act as project-wide safety nets.
function! s:proto.apply_base(base) abort dict
  let l:ow = 0

  if empty(s:get_entries(self, s:TYPE, 1))
    call s:set_entries(self, s:TYPE, s:get_entries(a:base, s:TYPE, 1), 1, l:ow)
  endif
  if empty(s:get_entries(self, s:DIR, 1))
    call s:set_entries(self, s:DIR, s:get_entries(a:base, s:DIR, 1), 1, l:ow)
  endif

  call s:set_entries(self, s:TYPE, s:get_entries(a:base, s:TYPE, 0), 0, l:ow)
  call s:set_entries(self, s:DIR,  s:get_entries(a:base, s:DIR,  0), 0, l:ow)

  return self
endfunction

"==============================================================================
" Query builders — produce rg command fragments
"==============================================================================

" Build the glob flags string for rg (file type includes/excludes + dir excludes).
function! s:proto.get_globbing_flags() abort dict
  let l:out = ''

  " File type includes
  let l:inc = join(s:get_entries(self, s:TYPE, 1), ',')
  if l:inc !=# ''
    let l:out .= printf("-g '*.{%s}' ", l:inc)
  endif

  " File type excludes
  let l:exc = join(s:get_entries(self, s:TYPE, 0), ',')
  if l:exc !=# ''
    let l:out .= printf("-g '!*.{%s}' ", l:exc)
  endif

  " Directory excludes
  for l:dir in s:get_entries(self, s:DIR, 0)
    if len(l:dir) > 1 && l:dir[-1:] ==# '/'
      let l:dir = l:dir[:-2]
    endif
    let l:out .= printf("-g '!%s/**' ", l:dir)
  endfor

  return l:out
endfunction

" Build a list of rg glob arguments (for job_start — no shell quoting).
function! s:proto.get_globbing_args() abort dict
  let l:out = []

  let l:inc = join(s:get_entries(self, s:TYPE, 1), ',')
  if l:inc !=# ''
    call extend(l:out, ['-g', '*.{' . l:inc . '}'])
  endif

  let l:exc = join(s:get_entries(self, s:TYPE, 0), ',')
  if l:exc !=# ''
    call extend(l:out, ['-g', '!*.{' . l:exc . '}'])
  endif

  for l:dir in s:get_entries(self, s:DIR, 0)
    if len(l:dir) > 1 && l:dir[-1:] ==# '/'
      let l:dir = l:dir[:-2]
    endif
    call extend(l:out, ['-g', '!' . l:dir . '/**'])
  endfor

  return l:out
endfunction

" Build the search directories string for rg.
function! s:proto.get_search_directories() abort dict
  return join(s:get_entries(self, s:DIR, 1), ' ')
endfunction

" Return the list of included search directories.
function! s:proto.get_search_dirs_list() abort dict
  return s:get_entries(self, s:DIR, 1)
endfunction

"==============================================================================
" Debug
"==============================================================================

function! s:proto.print() abort dict
  call skyrg#log#status('Filter: %s', self.name)
  call skyrg#log#status('  include types: [%s]', join(s:get_entries(self, s:TYPE, 1), ', '))
  call skyrg#log#status('  ignore types:  [%s]', join(s:get_entries(self, s:TYPE, 0), ', '))
  call skyrg#log#status('  include dirs:  [%s]', join(s:get_entries(self, s:DIR,  1), ', '))
  call skyrg#log#status('  ignore dirs:   [%s]', join(s:get_entries(self, s:DIR,  0), ', '))
endfunction
