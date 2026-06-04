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

" Check if currently recording.
function! skyrg#backend#workflow#is_recording() abort
  return s:recording
endfunction

" Get the current workflow name (for statusline, etc.).
function! skyrg#backend#workflow#name() abort
  return s:recording ? s:name : ''
endfunction

"==============================================================================
" Step capture — called from action#dispatch hook
"==============================================================================

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

  let l:lines = s:render_workflow(a:name, a:steps, a:mode)
  call writefile(l:lines, l:path)

  call skyrg#log#info('workflow', 'exported %d steps to %s', len(a:steps), l:path)
  echom printf('[SkyRG] Workflow exported: %s (%d steps)', l:path, len(a:steps))

  " Open the file for review/editing
  execute 'split' fnameescape(l:path)
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

  " Steps
  let l:step_num = 0
  for l:s in a:steps
    let l:step_num += 1

    if l:s.type ==# 'shell'
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
