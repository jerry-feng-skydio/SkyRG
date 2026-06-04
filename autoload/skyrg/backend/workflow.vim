" autoload/skyrg/backend/workflow.vim — Workflow recorder + exporter
"
" Records dispatched actions as workflow steps, then exports them as
" .windsurf/workflows/*.md files that agentic assistants can follow.
"
" Usage:
"   call skyrg#backend#workflow#start('selinux-iteration')
"   ... use SkyRG normally, actions are captured as steps ...
"   call skyrg#backend#workflow#stop()        " prompts for mode + exports
"   call skyrg#backend#workflow#is_recording() " check state
"
" Iteration modes (expressed in workflow frontmatter):
"   cautious   — Run until error, wait for user input
"   balanced   — Auto-resolve trivial issues, discuss complex ones
"   autonomous — Run until complete, workaround as needed

let s:recording = 0
let s:name = ''
let s:steps = []
let s:start_time = 0
let s:preview_bufnr = -1

"==============================================================================
" Public API
"==============================================================================

" Start recording a workflow.
function! skyrg#backend#workflow#start(name) abort
  if s:recording
    echohl WarningMsg | echom '[SkyRG] Already recording workflow: ' . s:name | echohl None
    return
  endif
  let s:recording = 1
  let s:name = a:name
  let s:steps = []
  let s:start_time = localtime()
  call skyrg#log#info('workflow', 'started recording "%s"', a:name)
  echom printf('[SkyRG] 🔴 Recording workflow: %s', a:name)
  call s:open_preview()
endfunction

" Stop recording and export.
function! skyrg#backend#workflow#stop() abort
  if !s:recording
    echohl WarningMsg | echom '[SkyRG] Not recording a workflow' | echohl None
    return
  endif
  let s:recording = 0

  if empty(s:steps)
    echohl WarningMsg | echom '[SkyRG] No steps recorded, nothing to export' | echohl None
    return
  endif

  call skyrg#log#info('workflow', 'stopped recording "%s" (%d steps)', s:name, len(s:steps))

  " Prompt for iteration mode
  let l:modes = ['cautious', 'balanced', 'autonomous']
  let l:choice = confirm(
    \ '[SkyRG] Workflow mode?',
    \ "&Cautious (stop on error)\n&Balanced (auto-fix trivial)\n&Autonomous (run to completion)",
    \ 2)
  if l:choice == 0 | return | endif
  let l:mode = l:modes[l:choice - 1]

  call s:export(s:name, s:steps, l:mode)
endfunction

" Discard current recording without exporting.
function! skyrg#backend#workflow#discard() abort
  if !s:recording
    echohl WarningMsg | echom '[SkyRG] Not recording a workflow' | echohl None
    return
  endif
  call skyrg#log#info('workflow', 'discarded recording "%s" (%d steps)', s:name, len(s:steps))
  let s:recording = 0
  let s:steps = []
  call s:close_preview()
  echom printf('[SkyRG] Workflow discarded: %s', s:name)
  let s:name = ''
endfunction

" Check if currently recording.
function! skyrg#backend#workflow#is_recording() abort
  return s:recording
endfunction

" Get the current workflow name (for statusline, etc.).
function! skyrg#backend#workflow#name() abort
  return s:recording ? s:name : ''
endfunction

" Get the number of steps captured so far.
function! skyrg#backend#workflow#step_count() abort
  return len(s:steps)
endfunction

" Add a free-text description step (no action executed).
" Used for heavy steps the user doesn't want to run during recording.
function! skyrg#backend#workflow#describe(title, body) abort
  if !s:recording
    echohl WarningMsg | echom '[SkyRG] Not recording a workflow' | echohl None
    return
  endif
  let l:step = {
    \ 'name': a:title,
    \ 'type': 'describe',
    \ 'description': a:body,
    \ 'agent_hint': '',
    \ 'group': '',
    \ 'timestamp': localtime(),
    \ 'inputs': {},
    \ }
  call add(s:steps, l:step)
  call s:append_step_to_preview(l:step)
  call skyrg#log#info('workflow', 'described step %d: %s', len(s:steps), a:title)
  echom printf('[SkyRG] Step added: %s', a:title)
endfunction

"==============================================================================
" Preview buffer
"==============================================================================

" Open the live preview split.
function! s:open_preview() abort
  " Reuse existing preview if still open
  if s:preview_bufnr >= 0 && bufexists(s:preview_bufnr)
    let l:win = bufwinnr(s:preview_bufnr)
    if l:win != -1
      execute l:win . 'wincmd w'
      return
    endif
  endif

  " Open a vertical split on the right
  let l:saved_win = winnr()
  execute 'vertical botright new'
  execute 'vertical resize 60'
  setlocal buftype=nofile bufhidden=hide noswapfile
  setlocal filetype=markdown
  execute 'file' fnameescape('[Workflow] ' . s:name)
  let s:preview_bufnr = bufnr('%')

  " Write initial preamble (without mode — that's chosen at export)
  let l:header = [
    \ '---',
    \ printf('description: %s', s:name),
    \ '---',
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
  call setline(1, l:header)

  " Return focus to the previous window
  execute l:saved_win . 'wincmd w'
endfunction

" Close the preview buffer.
function! s:close_preview() abort
  if s:preview_bufnr >= 0 && bufexists(s:preview_bufnr)
    let l:win = bufwinnr(s:preview_bufnr)
    if l:win != -1
      execute l:win . 'wincmd c'
    endif
    execute 'bwipeout' s:preview_bufnr
  endif
  let s:preview_bufnr = -1
endfunction

" Reopen (or focus) the preview split. Called from context popup.
function! skyrg#backend#workflow#show_preview() abort
  if !s:recording
    echohl WarningMsg | echom '[SkyRG] Not recording a workflow' | echohl None
    return
  endif
  if s:preview_bufnr >= 0 && bufexists(s:preview_bufnr)
    let l:win = bufwinnr(s:preview_bufnr)
    if l:win != -1
      execute l:win . 'wincmd w'
      return
    endif
    " Buffer exists but no window — reopen the split
    let l:saved_win = winnr()
    execute 'vertical botright sbuffer' s:preview_bufnr
    execute 'vertical resize 60'
    execute l:saved_win . 'wincmd w'
  else
    " Buffer was wiped — recreate and re-render all existing steps
    call s:open_preview()
    for l:s in s:steps
      call s:append_step_to_preview(l:s)
    endfor
  endif
endfunction

" Render a single step to a list of lines.
function! s:render_step_lines(step, step_num) abort
  let l:lines = []
  let l:s = a:step

  if l:s.type ==# 'describe'
    call add(l:lines, printf('## %d. %s', a:step_num, l:s.name))
    call add(l:lines, '')
    call add(l:lines, l:s.description)
  elseif l:s.type ==# 'shell'
    call add(l:lines, printf('## %d. %s', a:step_num, l:s.name))
    call add(l:lines, '')
    if !empty(get(l:s, 'cwd', ''))
      call add(l:lines, printf('Working directory: `%s`', l:s.cwd))
      call add(l:lines, '')
    endif
    if get(l:s, 'interactive', 0)
      call add(l:lines, '> **Interactive** — This command opens a terminal session.')
      call add(l:lines, '')
    endif
    call add(l:lines, '```bash')
    call add(l:lines, l:s.cmd)
    call add(l:lines, '```')
  else
    call add(l:lines, printf('## %d. %s', a:step_num, l:s.name))
    call add(l:lines, '')
    if has_key(l:s, 'description')
      call add(l:lines, l:s.description)
    else
      call add(l:lines, '*Manual step — describe what to do here.*')
    endif
  endif

  let l:hint = get(l:s, 'agent_hint', '')
  if !empty(l:hint)
    call add(l:lines, '')
    call add(l:lines, s:render_agent_hint(l:hint))
  endif

  if !empty(get(l:s, 'inputs', {}))
    call add(l:lines, '')
    call add(l:lines, '**Inputs provided:**')
    for [l:k, l:v] in items(l:s.inputs)
      call add(l:lines, printf('- `%s`: `%s`', l:k, l:v))
    endfor
  endif

  call add(l:lines, '')
  return l:lines
endfunction

" Append a rendered step to the preview buffer.
function! s:append_step_to_preview(step) abort
  if s:preview_bufnr < 0 || !bufexists(s:preview_bufnr) | return | endif
  let l:lines = s:render_step_lines(a:step, len(s:steps))
  call appendbufline(s:preview_bufnr, '$', l:lines)
endfunction

" Replace the last step in the preview buffer (used when upgrading
" a vim placeholder to a shell step via capture_raw).
function! s:replace_last_step_in_preview(step) abort
  if s:preview_bufnr < 0 || !bufexists(s:preview_bufnr) | return | endif

  " Find the last ## heading and delete from there to end
  let l:buf_lines = getbufline(s:preview_bufnr, 1, '$')
  let l:last_heading = -1
  for l:i in range(len(l:buf_lines) - 1, 0, -1)
    if l:buf_lines[l:i] =~# '^## \d\+\.'
      let l:last_heading = l:i
      break
    endif
  endfor

  if l:last_heading >= 0
    " Delete from last heading to end of buffer (1-indexed for deletebufline)
    call deletebufline(s:preview_bufnr, l:last_heading + 1, '$')
  endif

  " Append the replacement
  let l:lines = s:render_step_lines(a:step, len(s:steps))
  call appendbufline(s:preview_bufnr, '$', l:lines)
endfunction

"==============================================================================
" Step capture
"==============================================================================

" Capture a raw command as a workflow step.
" Used by subsystems that bypass action#dispatch (e.g. live_split).
" If there is already a vim-type step with the same name (captured by the
" top-level dispatch), replace it with this concrete command version.
function! skyrg#backend#workflow#capture_raw(name, cmd, agent_hint) abort
  if !s:recording | return | endif

  " Check if the last step is a vim-type placeholder — if so, replace it
  " with this concrete command. This handles the common pattern where a
  " top-level vim action (e.g. "Tail device logs") dispatches a job
  " through a subsystem (e.g. live_split) with a more specific title.
  if !empty(s:steps)
    let l:last = s:steps[-1]
    if l:last.type ==# 'vim'
      let l:last.name = a:name
      let l:last.type = 'shell'
      let l:last.cmd = a:cmd
      let l:last.agent_hint = a:agent_hint
      let l:last.interactive = 0
      call s:replace_last_step_in_preview(l:last)
      call skyrg#log#info('workflow', 'upgraded step %d to shell: %s', len(s:steps), a:name)
      return
    endif
  endif

  let l:step = {
    \ 'name': a:name,
    \ 'type': 'shell',
    \ 'cmd': a:cmd,
    \ 'agent_hint': a:agent_hint,
    \ 'group': '',
    \ 'interactive': 0,
    \ 'cwd': '',
    \ 'timestamp': localtime(),
    \ 'inputs': {},
    \ }
  call add(s:steps, l:step)
  call s:append_step_to_preview(l:step)
  call skyrg#log#info('workflow', 'captured raw step %d: %s', len(s:steps), a:name)
endfunction

" Capture a dispatched action as a workflow step.
" Called after action dispatch with the resolved command.
function! skyrg#backend#workflow#capture(action, ctx, resolved_cmd) abort
  if !s:recording | return | endif

  let l:step = {
    \ 'name': a:action.name,
    \ 'group': get(a:action, 'group', ''),
    \ 'agent_hint': get(a:action, 'agent_hint', ''),
    \ 'timestamp': localtime(),
    \ 'inputs': skyrg#ui#input#harvest(),
    \ }

  " Skip workflow control actions (Record, Describe, etc.)
  if get(a:action, 'no_history', 0)
    call skyrg#log#info('workflow', 'skipped control action: %s', a:action.name)
    return
  endif

  " Skip steps the agent should ignore (e.g. 'Close live split')
  if l:step.agent_hint ==# 'skip'
    call skyrg#log#info('workflow', 'skipped step (agent_hint=skip): %s', a:action.name)
    return
  endif

  " Determine step type and content
  if !empty(a:resolved_cmd)
    " Shell/job action — capture the resolved command
    let l:step.type = 'shell'
    let l:step.cmd = a:resolved_cmd
    let l:opts = get(a:action, 'job_opts', {})
    let l:step.interactive = get(l:opts, 'interactive', 0)
    let l:step.cwd = get(l:opts, 'cwd', '')
    if type(l:step.cwd) == v:t_func
      let l:step.cwd = l:step.cwd(a:ctx)
    endif
  else
    " Vim-only action (execute funcref) — describe it
    let l:step.type = 'vim'
    let l:label = has_key(a:action, 'label_fn')
      \ ? a:action.label_fn(a:ctx) : a:action.name
    let l:step.description = l:label
  endif

  call add(s:steps, l:step)
  call s:append_step_to_preview(l:step)
  call skyrg#log#info('workflow', 'captured step %d: %s', len(s:steps), l:step.name)
endfunction

"==============================================================================
" Export
"==============================================================================

function! s:export(name, steps, mode) abort
  " Find or create .windsurf/workflows/ directory
  let l:ws_dir = s:find_workflows_dir()
  if empty(l:ws_dir)
    echohl ErrorMsg | echom '[SkyRG] Could not find or create .windsurf/workflows/' | echohl None
    return
  endif

  let l:slug = substitute(tolower(a:name), '[^a-z0-9]', '-', 'g')
  let l:slug = substitute(l:slug, '-\+', '-', 'g')
  let l:slug = substitute(l:slug, '^-\|-$', '', 'g')
  let l:path = l:ws_dir . '/' . l:slug . '.md'

  " Use preview buffer contents if it exists (preserves user edits)
  if s:preview_bufnr >= 0 && bufexists(s:preview_bufnr)
    let l:lines = getbufline(s:preview_bufnr, 1, '$')
    " Inject mode into frontmatter if not already present
    if len(l:lines) >= 3 && l:lines[0] ==# '---'
      let l:has_mode = 0
      for l:i in range(1, min([len(l:lines) - 1, 10]))
        if l:lines[l:i] =~# '^mode:'
          let l:lines[l:i] = 'mode: ' . a:mode
          let l:has_mode = 1
          break
        endif
        if l:lines[l:i] ==# '---' | break | endif
      endfor
      if !l:has_mode
        call insert(l:lines, 'mode: ' . a:mode, 2)
      endif
    endif
  else
    let l:lines = s:render_workflow(a:name, a:steps, a:mode)
  endif

  call writefile(l:lines, l:path)
  call s:close_preview()

  call skyrg#log#info('workflow', 'exported %d steps to %s', len(a:steps), l:path)
  echom printf('[SkyRG] Workflow exported: %s (%d steps)', l:path, len(a:steps))

  " Open the exported file
  execute 'edit' fnameescape(l:path)
endfunction

function! s:render_workflow(name, steps, mode) abort
  let l:lines = []

  " Frontmatter
  call extend(l:lines, [
    \ '---',
    \ printf('description: %s', a:name),
    \ printf('mode: %s', a:mode),
    \ '---',
    \ '',
    \ ])

  " Mode explanation
  if a:mode ==# 'cautious'
    call add(l:lines, '> **Mode: Cautious** — Stop on any error and wait for user input.')
  elseif a:mode ==# 'balanced'
    call add(l:lines, '> **Mode: Balanced** — Auto-resolve trivial issues. Document complex issues and discuss strategies with the user.')
  else
    call add(l:lines, '> **Mode: Autonomous** — Run until complete. Use whatever workarounds are necessary.')
  endif
  call add(l:lines, '')

  " Q&A preamble
  call extend(l:lines, [
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
    \ ])

  " Steps
  let l:step_num = 0
  for l:s in a:steps
    let l:step_num += 1

    if l:s.type ==# 'describe'
      " Free-text step — user-authored instruction for the agent
      call add(l:lines, printf('## %d. %s', l:step_num, l:s.name))
      call add(l:lines, '')
      call add(l:lines, l:s.description)
    elseif l:s.type ==# 'shell'
      call add(l:lines, printf('## %d. %s', l:step_num, l:s.name))
      call add(l:lines, '')
      if !empty(get(l:s, 'cwd', ''))
        call add(l:lines, printf('Working directory: `%s`', l:s.cwd))
        call add(l:lines, '')
      endif
      if get(l:s, 'interactive', 0)
        call add(l:lines, '> **Interactive** — This command opens a terminal session. Capture relevant output before closing.')
        call add(l:lines, '')
      endif
      call add(l:lines, '```bash')
      call add(l:lines, l:s.cmd)
      call add(l:lines, '```')
    else
      " Vim/manual step
      call add(l:lines, printf('## %d. %s', l:step_num, l:s.name))
      call add(l:lines, '')
      if has_key(l:s, 'description')
        call add(l:lines, l:s.description)
      else
        call add(l:lines, '*Manual step — describe what to do here.*')
      endif
    endif

    " Agent hint annotation
    let l:hint = get(l:s, 'agent_hint', '')
    if !empty(l:hint)
      call add(l:lines, '')
      call add(l:lines, s:render_agent_hint(l:hint))
    endif

    " Show user inputs if any
    if !empty(get(l:s, 'inputs', {}))
      call add(l:lines, '')
      call add(l:lines, '**Inputs provided:**')
      for [l:k, l:v] in items(l:s.inputs)
        call add(l:lines, printf('- `%s`: `%s`', l:k, l:v))
      endfor
    endif

    call add(l:lines, '')
  endfor

  " Footer
  call extend(l:lines, [
    \ '---',
    \ '',
    \ printf('*Recorded by SkyRG on %s (%d steps)*',
    \   strftime('%Y-%m-%d %H:%M'), len(a:steps)),
    \ '*Review and edit this workflow before passing to an agent.*',
    \ ])

  return l:lines
endfunction

" Translate agent_hint codes into clear instructions for agentic assistants.
function! s:render_agent_hint(hint) abort
  let l:hints = {
    \ 'capture_output': '> **Agent:** Run this command and capture its stdout. The output is needed for the next step.',
    \ 'read_output':    '> **Agent:** Read and analyze the output from the previous command. This replaces the human step of copying to clipboard.',
    \ 'read_file':      '> **Agent:** Read the file produced or referenced by this step.',
    \ 'run_command':    '> **Agent:** Run this command non-interactively. If it requires a shell, use `ssh <host> "<command>"` instead of an interactive session.',
    \ 'wait_ready':     '> **Agent:** Poll until this condition is met before proceeding (e.g. `ssh -o ConnectTimeout=5 <host> true`).',
    \ }
  return get(l:hints, a:hint, printf('> **Agent:** (%s)', a:hint))
endfunction

" Find .windsurf/workflows/ relative to the current project root.
function! s:find_workflows_dir() abort
  " Walk up from cwd looking for .windsurf/
  let l:dir = getcwd()
  let l:prev = ''
  while l:dir !=# l:prev
    let l:candidate = l:dir . '/.windsurf/workflows'
    if isdirectory(l:candidate)
      return l:candidate
    endif
    " Check for .windsurf/ (create workflows/ inside it)
    if isdirectory(l:dir . '/.windsurf')
      call mkdir(l:candidate, 'p')
      return l:candidate
    endif
    let l:prev = l:dir
    let l:dir = fnamemodify(l:dir, ':h')
  endwhile

  " Fallback: create in cwd
  let l:fallback = getcwd() . '/.windsurf/workflows'
  call mkdir(l:fallback, 'p')
  return l:fallback
endfunction
