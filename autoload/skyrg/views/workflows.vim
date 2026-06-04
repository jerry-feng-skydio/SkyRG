" autoload/skyrg/views/workflows.vim — Workflow file management
"
" CRUD operations for .windsurf/workflows/*.md files.
" Accessed via context popup (key 2: Workflows).

"==============================================================================
" Helpers
"==============================================================================

" Find the .windsurf/workflows/ directory.
function! s:find_workflows_dir() abort
  let l:dir = getcwd()
  let l:prev = ''
  while l:dir !=# l:prev
    let l:candidate = l:dir . '/.windsurf/workflows'
    if isdirectory(l:candidate)
      return l:candidate
    endif
    let l:prev = l:dir
    let l:dir = fnamemodify(l:dir, ':h')
  endwhile
  return ''
endfunction

" Get all workflow files with metadata.
function! s:list_workflows() abort
  let l:dir = s:find_workflows_dir()
  if empty(l:dir)
    return []
  endif
  let l:files = glob(l:dir . '/*.md', 0, 1)
  let l:result = []
  for l:f in l:files
    let l:stat = getftime(l:f)
    call add(l:result, {
      \ 'path': l:f,
      \ 'name': fnamemodify(l:f, ':t'),
      \ 'mtime': l:stat,
      \ 'relative': fnamemodify(l:f, ':.'),
      \ })
  endfor
  return l:result
endfunction

"==============================================================================
" Public API
"==============================================================================

" Open a workflow via fzf picker.
function! skyrg#views#workflows#open(ctx) abort
  let l:workflows = s:list_workflows()
  if empty(l:workflows)
    echohl WarningMsg | echom '[SkyRG] No workflows found in .windsurf/workflows/' | echohl None
    return
  endif

  let l:idx = s:show_picker('Open workflow', l:workflows)
  if l:idx < 0 | return | endif

  let l:selected = l:workflows[l:idx]
  execute 'edit' fnameescape(l:selected.path)
endfunction

" Create a new workflow with template.
function! skyrg#views#workflows#create(ctx) abort
  let l:dir = s:find_workflows_dir()
  if empty(l:dir)
    echohl ErrorMsg | echom '[SkyRG] Could not find .windsurf/workflows/' | echohl None
    return
  endif

  let l:name = input('[SkyRG] Workflow name: ')
  if empty(l:name) | return | endif

  let l:slug = substitute(tolower(l:name), '[^a-z0-9]', '-', 'g')
  let l:slug = substitute(l:slug, '-\+', '-', 'g')
  let l:slug = substitute(l:slug, '^-\|-$', '', 'g')
  let l:path = l:dir . '/' . l:slug . '.md'

  if filereadable(l:path)
    echohl WarningMsg | echom printf('[SkyRG] Workflow already exists: %s', l:path) | echohl None
    return
  endif

  let l:template = [
    \ '---',
    \ printf('description: %s', l:name),
    \ 'mode: balanced',
    \ '---',
    \ '',
    \ '> **Mode: Balanced** — Auto-resolve trivial issues. Document complex issues and discuss strategies with the user.',
    \ '',
    \ '## 0. Clarify requirements',
    \ '',
    \ 'Before executing, review this workflow and confirm with the user:',
    \ '',
    \ '1. Do you understand each step and its expected outcome?',
    \ '2. Are there any steps that need adjustment for the current situation?',
    \ '3. Are there environment prerequisites (device connected, build clean, etc.)?',
    \ '',
    \ 'Proceed only after the user confirms.',
    \ '',
    \ ]

  call writefile(l:template, l:path)
  execute 'edit' fnameescape(l:path)
  echom printf('[SkyRG] Created workflow: %s', l:path)
endfunction

" Delete a workflow with confirmation.
function! skyrg#views#workflows#delete(ctx) abort
  let l:workflows = s:list_workflows()
  if empty(l:workflows)
    echohl WarningMsg | echom '[SkyRG] No workflows found' | echohl None
    return
  endif

  let l:idx = s:show_picker('Delete workflow', l:workflows)
  if l:idx < 0 | return | endif

  let l:selected = l:workflows[l:idx]
  let l:confirm = confirm(
    \ printf('[SkyRG] Delete "%s"?', l:selected.name),
    \ "&Yes\n&No", 2)
  if l:confirm != 1 | return | endif

  call delete(l:selected.path)
  echom printf('[SkyRG] Deleted: %s', l:selected.name)
endfunction

" Rename a workflow.
function! skyrg#views#workflows#rename(ctx) abort
  let l:workflows = s:list_workflows()
  if empty(l:workflows)
    echohl WarningMsg | echom '[SkyRG] No workflows found' | echohl None
    return
  endif

  let l:idx = s:show_picker('Rename workflow', l:workflows)
  if l:idx < 0 | return | endif

  let l:selected = l:workflows[l:idx]
  let l:new_name = input('[SkyRG] New name: ', l:selected.name)
  if empty(l:new_name) || l:new_name ==# l:selected.name | return | endif

  let l:slug = substitute(tolower(l:new_name), '[^a-z0-9]', '-', 'g')
  let l:slug = substitute(l:slug, '-\+', '-', 'g')
  let l:slug = substitute(l:slug, '^-\|-$', '', 'g')
  let l:dir = fnamemodify(l:selected.path, ':h')
  let l:new_path = l:dir . '/' . l:slug . '.md'

  if filereadable(l:new_path) && l:new_path !=# l:selected.path
    echohl WarningMsg | echom '[SkyRG] Target already exists' | echohl None
    return
  endif

  call rename(l:selected.path, l:new_path)
  echom printf('[SkyRG] Renamed to: %s', l:new_name)
endfunction

" Copy/duplicate a workflow.
function! skyrg#views#workflows#copy(ctx) abort
  let l:workflows = s:list_workflows()
  if empty(l:workflows)
    echohl WarningMsg | echom '[SkyRG] No workflows found' | echohl None
    return
  endif

  let l:idx = s:show_picker('Copy workflow', l:workflows)
  if l:idx < 0 | return | endif

  let l:selected = l:workflows[l:idx]
  let l:new_name = input('[SkyRG] Copy as: ', l:selected.name . '-copy')
  if empty(l:new_name) | return | endif

  let l:slug = substitute(tolower(l:new_name), '[^a-z0-9]', '-', 'g')
  let l:slug = substitute(l:slug, '-\+', '-', 'g')
  let l:slug = substitute(l:slug, '^-\|-$', '', 'g')
  let l:dir = fnamemodify(l:selected.path, ':h')
  let l:new_path = l:dir . '/' . l:slug . '.md'

  if filereadable(l:new_path)
    echohl WarningMsg | echom '[SkyRG] Target already exists' | echohl None
    return
  endif

  call writefile(readfile(l:selected.path), l:new_path)
  execute 'edit' fnameescape(l:new_path)
  echom printf('[SkyRG] Copied to: %s', l:new_name)
endfunction

" Grep across all workflow files.
function! skyrg#views#workflows#grep(ctx) abort
  let l:dir = s:find_workflows_dir()
  if empty(l:dir)
    echohl WarningMsg | echom '[SkyRG] No workflows directory found' | echohl None
    return
  endif

  let l:pattern = input('[SkyRG] Search pattern: ')
  if empty(l:pattern) | return | endif

  let l:cmd = printf('rg --column --line-number --no-heading --color=always %s %s',
    \ shellescape(l:pattern), shellescape(l:dir))

  if exists('*fzf#run')
    call fzf#run(fzf#wrap({
      \ 'source': l:cmd,
      \ 'sink': function('s:grep_sink'),
      \ 'options': '--delimiter=: --nth=3..',
      \ }))
  else
    echohl WarningMsg | echom '[SkyRG] fzf not available, using grep' | echohl None
    let l:output = system(l:cmd)
    echo l:output
  endif
endfunction

" Open the most recently modified workflow.
function! skyrg#views#workflows#edit_recent(ctx) abort
  let l:workflows = s:list_workflows()
  if empty(l:workflows)
    echohl WarningMsg | echom '[SkyRG] No workflows found' | echohl None
    return
  endif

  " Sort by mtime descending
  call sort(l:workflows, {a, b -> b.mtime - a.mtime})
  let l:most_recent = l:workflows[0]

  execute 'edit' fnameescape(l:most_recent.path)
  echom printf('[SkyRG] Opened most recent: %s', l:most_recent.name)
endfunction

" Open the workflows directory in file explorer.
function! skyrg#views#workflows#open_dir(ctx) abort
  let l:dir = s:find_workflows_dir()
  if empty(l:dir)
    echohl ErrorMsg | echom '[SkyRG] Could not find .windsurf/workflows/' | echohl None
    return
  endif
  execute 'edit' fnameescape(l:dir)
endfunction

"==============================================================================
" Picker
"==============================================================================

" Pick a workflow using fzf if available, otherwise numeric picker.
" title: prompt text
" workflows: list of workflow dicts with {name, path, mtime}
" Returns: index into workflows array, or -1 if cancelled
function! s:show_picker(title, workflows) abort
  if empty(a:workflows)
    return -1
  endif

  " Try fzf first
  if exists('*fzf#run')
    return s:fzf_picker(a:title, a:workflows)
  endif

  " Fallback to numeric picker
  return s:numeric_picker(a:title, a:workflows)
endfunction

" Fzf picker for workflows.
function! s:fzf_picker(title, workflows) abort
  let l:lines = []
  for l:i in range(len(a:workflows))
    let l:w = a:workflows[l:i]
    call add(l:lines, printf('%s %s', l:w.name, strftime('%Y-%m-%d %H:%M', l:w.mtime)))
  endfor

  let s:selected_idx = -1
  call fzf#run(fzf#wrap({
    \ 'source': l:lines,
    \ 'sink': {line -> s:fzf_sink(line, a:workflows)},
    \ 'down': 15,
    \ 'options': '--with-nth=1',
    \ }))
  return s:selected_idx
endfunction

" Sink for fzf picker: maps selected line back to workflow index.
function! s:fzf_sink(line, workflows) abort
  let l:parts = split(a:line)
  if empty(l:parts) | return | endif
  let l:name = l:parts[0]
  for l:i in range(len(a:workflows))
    if a:workflows[l:i].name ==# l:name
      let s:selected_idx = l:i
      return
    endif
  endfor
endfunction

" Numeric picker (fallback when fzf not available).
function! s:numeric_picker(title, workflows) abort
  echo printf('[SkyRG] %s', a:title)
  for l:i in range(len(a:workflows))
    let l:w = a:workflows[l:i]
    echo printf('  %d. %s (%s)', l:i + 1, l:w.name, strftime('%Y-%m-%d %H:%M', l:w.mtime))
  endfor

  let l:choice = input('[SkyRG] Select (1-' . len(a:workflows) . '): ')
  if empty(l:choice) | return -1 | endif

  let l:idx = str2nr(l:choice) - 1
  if l:idx < 0 || l:idx >= len(a:workflows)
    echohl WarningMsg | echom '[SkyRG] Invalid selection' | echohl None
    return -1
  endif

  return l:idx
endfunction

" Sink for grep results (file:line:col:content).
function! s:grep_sink(line) abort
  let l:parts = split(a:line, ':')
  if len(l:parts) >= 3
    let l:path = l:parts[0]
    let l:line = str2nr(l:parts[1])
    execute 'edit' fnameescape(l:path)
    execute l:line
  endif
endfunction
