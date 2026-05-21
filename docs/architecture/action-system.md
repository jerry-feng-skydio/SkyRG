# Action System — Architecture Proposal

> **Status**: All phases implemented (Phase 1–4 complete)  
> **Scope**: External action dispatch, async execution, action logging, user configuration

## Motivation

The context popup already works for pure-Vim actions (search, history, YCM).
This proposal extends it to **external processes** — shell scripts, build
systems, CLI tools — while keeping the architecture general enough for
complex multi-step workflows.

---

## 1. Search Shortcut (already works, minor fix needed)

### Current state
The built-in action `"Search word under cursor"` calls:
```vim
skyrg#views#search#open({'query': ctx.word})
```

This passes **only** `query` — so `apply_params()` fills the query field but
the other fields (types, dirs, preset) start blank, because `panel#open()`
always resets state to empty before applying params.

### What the user wants
"The other fields remain how any previous search may have left it."

### Fix: merge-with-last semantics
When `views/search#open()` receives partial params (has `query` but not all
fields), merge them on top of the last history entry:

```vim
" In views/search#open():
if !empty(l:params) && !has_key(l:params, '_complete')
  let l:last = skyrg#backend#history#load_last()
  if !empty(l:last)
    let l:params = extend(copy(l:last), l:params)
  endif
endif
```

This means: "Search for this word, but keep my previous filter context."
If the user explicitly passes `{'query': 'foo', 'types': 'py'}`, the
explicit types win. The `_complete` flag lets callers (like history restore)
opt out of merging.

**Ergonomics verdict**: Your UI description is good. The merge-with-last
behavior is what VS Code's "search in files" does — it keeps your previous
scope when you change the query. This feels natural.

---

## 2. Action Types

Today actions are Vim lambdas. We need to support three execution modes:

| Type | Key | Runs as | Example |
|---|---|---|---|
| **vim** | `execute` | Vimscript funcref/lambda | Search, go-to-def |
| **shell** | `shell` | Synchronous `system()` | Quick scripts < 1s |
| **job** | `job` | Async `job_start()` | Builds, deploys, long scripts |

### Action shape (extended)

```vim
{
  'name':      'Build drone firmware',
  'key':       'b',
  'group':     'build',
  'priority':  50,
  'predicate': {ctx -> ctx.filetype =~# '^\(cpp\|c\)$'},

  " --- Execution (exactly one of these) ---
  'execute':   {ctx -> ...},              " vim action (existing)
  'shell':     'bazel build //vehicle',   " sync shell (string or funcref→string)
  'job':       'bazel build //vehicle',   " async job (string or funcref→string)

  " --- Job options (only for 'job' type) ---
  'job_opts': {
    'title':       'Build firmware',      " display name in task list
    'cwd':         '/path/to/repo',       " working directory (default: project root)
    'env':         {'CC': 'clang'},       " extra env vars
    'interactive': 0,                     " if 1, opens a terminal (for sudo, OTP, etc.)
    'on_success':  [...],                 " followup actions (see §5)
    'on_failure':  [...],                 " followup actions on non-zero exit
    'notify':      1,                     " show completion notification (default: 1)
  },
}
```

### String interpolation in shell/job commands

Commands can contain `{ctx.*}` placeholders:
```vim
'job': 'bazel build //vehicle:{ctx.word}',
'shell': 'echo {ctx.word}',
```

Or a funcref for full control:
```vim
'job': {ctx -> 'deploy.sh --target=' . ctx.word},
```

---

## 3. Dummy Action (proving the concept)

### Script
`~/.dotfiles/scripts/skyrg_example_action.sh`:
```bash
#!/usr/bin/env bash
sleep 10
echo "$1"
```

### Registration in .vimrc
```vim
let g:skyrg_context_actions = [
  \ {
  \   'name':    'Example: echo word',
  \   'key':     'e',
  \   'group':   'example',
  \   'priority': 200,
  \   'job':     {ctx -> '~/.dotfiles/scripts/skyrg_example_action.sh ' . shellescape(ctx.word)},
  \   'job_opts': {'title': 'Echo example'},
  \ },
  \ ]
```

---

## 4. Action Execution Engine

New module: `autoload/skyrg/backend/action.vim`

### Responsibilities
1. Resolve action type (vim / shell / job)
2. Interpolate command string
3. Launch job or call system()
4. Capture stdout/stderr
5. Manage lifecycle (running → done/failed)
6. Log everything
7. Trigger followup actions or notifications

### Execution flow

```
context popup → backend/context#execute()
                    │
                    ├─ 'execute' key? → call funcref directly (existing path)
                    │
                    ├─ 'shell' key?   → action#run_shell(cmd, ctx)
                    │                     └─ system() + capture output
                    │                     └─ log result
                    │
                    └─ 'job' key?     → action#run_job(cmd, opts, ctx)
                                          └─ job_start() with callbacks
                                          └─ register in task list
                                          └─ stream output to log
                                          └─ on exit: notify + followup
```

### Interactive mode

For actions that need user input (sudo password, OTP, menu selection):

```vim
'job_opts': {'interactive': 1}
```

This opens a **terminal buffer** via `term_start()` instead of a headless
job. The terminal gets its own popup or split. When the terminal exits, the
normal completion flow runs (log, notify, followup).

This cleanly separates:
- **Headless jobs** — user continues working, output captured silently
- **Interactive jobs** — Vim's terminal takes over, user interacts directly

---

## 5. Async Task Manager

New module: `autoload/skyrg/backend/tasks.vim`

### Task state

```vim
let s:tasks = []    " list of active/recent tasks

" Task shape:
{
  'id':         1,
  'title':      'Build firmware',
  'cmd':        'bazel build //vehicle',
  'status':     'running',          " running | done | failed
  'job':        <job>,              " Vim job handle
  'pid':        12345,
  'start_time': 1716300000,
  'end_time':   0,
  'exit_code':  -1,
  'stdout':     [],                 " ring buffer, last N lines
  'stderr':     [],
  'log_file':   '~/.local/share/skyrg/actions/task_1_1716300000.log',
  'context':    { ... },            " frozen ctx from when action was dispatched
  'action':     { ... },            " frozen action definition
  'on_success': [...],
  'on_failure': [...],
}
```

### Progress indicator

A persistent, unobtrusive status shown in Vim's statusline or tabline:

```vim
" Option A: statusline component (preferred — zero visual footprint when idle)
set statusline+=%{skyrg#backend#tasks#statusline()}
" Returns: '' when no tasks, '⟳ Build firmware (12s)' when running,
"          '✓ Build firmware' for 5s after completion

" Option B: floating indicator (top-right corner popup, auto-hides)
" Small popup that appears only while a task is running.
```

I'd recommend **Option A** (statusline) as the default since it's zero-cost
and doesn't steal focus. Option B can be a `g:skyrg_task_indicator` setting.

### Task viewer popup

`:SkyRGTasks` or a context action — opens a popup listing all active/recent
tasks with live output preview:

```
┌─────────────────────────────────────────────┐
│ Tasks                                       │
├─────────────────────────────────────────────┤
│ ⟳ Build firmware           12s  [running]   │
│ ✓ Deploy to drone          3m   [done]      │
│ ✗ Run tests               45s   [failed]    │
└─────────────────────────────────────────────┘
┌─────────────────────────────────────────────┐
│ Output: Build firmware                      │
├─────────────────────────────────────────────┤
│ [1234/5678] Compiling vehicle/main.cc       │
│ [1235/5678] Compiling vehicle/sensors.cc    │
│ ...                                         │
└─────────────────────────────────────────────┘
```

Keys: `j/k` select task, `Enter` to view full log, `c` to cancel running
task, `q` to close, `f` to trigger followup action chooser.

### Completion notification

When a task finishes:
1. Update statusline component
2. `echom '[SkyRG] ✓ Build firmware (45s)'` (or `✗` on failure)
3. If `on_success` or `on_failure` actions are defined, show a small
   **followup popup** near the cursor:

```
╭─────────────────────────────╮
│ Build firmware succeeded    │
│                             │
│ [d] Deploy to drone         │
│ [l] View build log          │
│ [q] Dismiss                 │
╰─────────────────────────────╯
```

This is just the context popup with a filtered action set. No new UI needed.

---

## 6. Action Logging + Retention

New module: `autoload/skyrg/backend/action_log.vim`

### Storage

```
~/.local/share/skyrg/actions/
  ├── index.jsonl                     # append-only task metadata
  └── task_<id>_<timestamp>.log       # combined stdout+stderr per task
```

### Log format (per-task file)

```
=== SkyRG Action Log ===
Action:    Build firmware
Command:   bazel build //vehicle
CWD:       /home/jerry/aircam
Started:   2026-05-21 02:15:00
Context:   {"word":"CaptureSettings","file":"vehicle/main.cc","filetype":"cpp",...}
Exit code: 1
Duration:  45.2s
============================================================

[stdout] [1234/5678] Compiling vehicle/main.cc
[stderr] ERROR: vehicle/main.cc:42: undefined reference to 'foo'
[stdout] [1235/5678] Compiling vehicle/sensors.cc
...
```

The header preserves enough context for AI-driven debugging: you can paste
the whole file and I'll have the command, working directory, file context,
and full output.

### Index file (index.jsonl)

One JSON line per task, for quick listing without reading every log file:
```json
{"id":1,"title":"Build firmware","cmd":"bazel build //vehicle","status":"failed","exit_code":1,"start_time":1716300000,"end_time":1716300045,"log_file":"task_1_1716300000.log"}
```

### Retention strategy

| Approach | Pros | Cons |
|---|---|---|
| `/tmp` | Auto-cleaned | Lost on reboot — bad for debugging |
| `~/.local/share/skyrg/actions/` | Survives reboot, colocated with history | Grows unbounded |
| **Tiered** (recommended) | Best of both | Slightly more complex |

**Recommended: tiered retention**

1. **Hot** (last 7 days): Keep everything in `~/.local/share/skyrg/actions/`
2. **Warm** (7–30 days): Keep only failed tasks and their logs
3. **Cold** (30+ days): Delete log files, keep index.jsonl entries (for stats)

Compaction runs on plugin load (same pattern as history compaction).

Configurable:
```vim
let g:skyrg_action_log_keep_days = 7       " keep all logs for N days
let g:skyrg_action_log_keep_failed = 30    " keep failed logs for N days
```

### `:SkyRGActionLog` command

Opens the log file for the most recent (or selected) task in a split,
similar to `:SkyRGLog`.

### AI context preservation

The log header + SkyRG's main log together give me everything I need:
- **What was attempted**: action name, command, CWD
- **What the user was doing**: context dict (word, file, filetype, visual)
- **What happened**: stdout/stderr interleaved with timestamps
- **Plugin state**: SkyRG's main log shows the event flow leading up to the action

For a debugging session, the user workflow is:
```
:SkyRGLog           → shows the SkyRG event flow
:SkyRGActionLog     → shows the specific task output
```
Then paste both to the AI.

---

## 7. Responding to Complex Outcomes

Your examples reveal four patterns for how actions dispatch results:

### Pattern A: Fire-and-forget
Script runs, output is logged, done.
*Example: `echo <word>`*

### Pattern B: Success/failure branching
Exit code determines which followup actions are offered.
*Example: Build → deploy on success, error analysis on failure*

Implementation: `on_success` / `on_failure` in `job_opts` — each is a list
of action defs. On completion, SkyRG shows a followup popup.

### Pattern C: Structured output → SkyRG view
Script outputs data that SkyRG can render (error list, file list, etc.).

```vim
'job_opts': {
  'output_format': 'matches',    " parse stdout as file:line:col:text
  'on_success': [{
    'name': 'Browse results',
    'execute': {ctx -> skyrg#panel#browse(ctx.task_output, 'Build Errors')},
  }],
}
```

The action engine parses stdout based on `output_format` and makes it
available as `ctx.task_output` in followup actions. Supported formats:
- `'matches'` — `file:line:col:text` (same as rg output)
- `'json'` — parsed JSON
- `'lines'` — raw string list
- `'none'` (default) — no parsing

*Example: Build fails → parse errors → browse in SkyRG error list*

### Pattern D: Interactive (terminal takeover)
User needs to type input (password, OTP, menu selection).

```vim
'job_opts': {'interactive': 1}
```

Opens `term_start()`. When terminal exits, normal completion flow resumes.

*Example: `sudo deploy.sh`, revup interactive prompts*

### Pattern E: Dispatch to external tool (AI, etc.)
Action sends context to an external process and receives a response that
gets applied to the buffer.

```vim
{
  'name':    'Ask Claude',
  'predicate': {ctx -> ctx.mode ==# 'v'},
  'job':     {ctx -> 'claude --pipe'},
  'job_opts': {
    'stdin': {ctx -> ctx.visual},     " pipe selection as stdin
    'output_format': 'lines',
    'on_success': [{
      'name': 'Replace selection',
      'execute': {ctx -> s:replace_visual(ctx.task_output)},
    }],
  },
}
```

This covers your "Ask Claude" example cleanly.

---

## 8. Implementation Plan

### Phase 1: Action engine basics ✓
1. ✓ `backend/action.vim` — shell and job execution with logging
2. ✓ `backend/action_log.vim` — log storage and retention
3. ✓ `backend/tasks.vim` — task registry and lifecycle
4. ✓ Extend `backend/context#execute()` to detect `shell`/`job` keys

### Phase 2: Task UI ✓
5. ✓ Statusline component for progress
6. ✓ `:SkyRGTasks` popup (task list + live output)
7. ✓ On-demand followup popup (awaiting status, `f` key, `<Leader>f`)

### Phase 3: Interactive + advanced ✓
8. ✓ Interactive mode (`term_start()`)
9. ✓ Structured output parsing (`output_format`)
10. ✓ Stdin piping for AI-style workflows

### Phase 4: Polish ✓
11. ✓ `:SkyRGActionLog` command
12. ✓ Retention compaction
13. ✓ Quickstart guide

### Dummy actions (shipped in Phase 1, expanded in Phase 3) ✓
- ✓ `skyrg_example_action.sh` — fake build (matches output format)
- ✓ `skyrg_example_stdin.sh` — selection analysis (stdin piping)
- ✓ `skyrg_example_interactive.sh` — deploy prompt (interactive terminal)

---

## 9. Open Questions (Resolved)

1. **Followup popup timing**: ~~Immediate popup vs CursorHold.~~
   **Resolved**: Neither. Followups are stored on the task with `awaiting`
   status. User invokes them on-demand via `f` in task viewer or `<Leader>f`
   globally. Statusline shows `❗` indicator. No surprise popups.

2. **Task concurrency**: ~~Configurable cap?~~
   **Resolved**: Yes, multiple tasks run simultaneously. No cap enforced yet;
   task registry tracks all. Can add `g:skyrg_max_tasks` later if needed.

3. **Task cancellation**: ~~Global "cancel all"?~~
   **Resolved**: `c` in task viewer cancels selected task via `job_stop()`.
   No global cancel-all yet.

4. **Terminal popup vs split**: ~~Popup terminal vs regular split?~~
   **Resolved**: Regular split via `term_start()`. Configurable height with
   `term_rows` (default: min(lines/3, 15)). Auto-closes on exit.
