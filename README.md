# SkyRG
Small vimscript wrapper for fzf + rg search to allow for some search option configuration

# Installation
Note: Requires the vim plugin `'junngunn/fzf'` and the ripgrep (`rg`) command installed on your system.

Then you can install it like any basic plugin:

```
Plug 'jerry-feng-skydio/SkyRG'
```

etc etc

# Quick start
## Create a search function for yourself:
Here's mine as an example:
```
" Calls SkyRG normally (arguments following 'RG' are passed in as <f-args>
command! -nargs=* -bang RG call SkyRG(<f-args>)

" Calls SkyRG and assumes the everything after 'RGN' is the query
command! -nargs=* -bang RGN call SkyRG('--', <f-args>)
```

## Using the search function
You can pass flags into the function call to modify your search scope.
Read `docs/skyrg.txt` for more details.

High level, you can use the following flags
```
-- ) everything after this is part of the query.
-f ) include filetypes (comma-delimited list)
-Nf) ignore filetypes (comma-delimited list)
-d ) include directories (comma-delimited list)
-Nd) ignore directories (comma-delimited list)
```
The function passes the args 1 word at a time. The moment it can't parse a flag and its option, it assumes the query has started.
Many of these flags take a comma-delimited list, for example `cc,h,lcm,proto` or `build,**/node_modules`.

So for instance, with my command above, I can search for only c++ files in the `tools/` directory
```
:RG -f cc,cpp,h -d tools cool thing I'm looking for
```

If your query happens to start with something that could be read as a flag, use `--`
For instance, if I wanted to search for the part of the function call above in this repo:
```
:RG -f md -- -f cc,cpp,h
```

Ordering matters, the following search would actually ignore cc files, despite it being included earlier.
```
:RG -f cc -nF cc -- shared_from_this()
```

You can change the base search filter to pre-made presets on the fly. For more about presets see below.
```
:RG -p ios_dev CoolSwiftClass
```

# Creating filter presets
Generally, you will set up filters with the `g:SkyFilter.new` function.
```
call g:SkyFilter.new("my_awesome_filter")
```

You don't really have to keep track of this filter, it's registered into a singleton filter dict that the SkyRG function uses to find defaults/presets you pass in through the command.

Once you have a filter, you can call:
`.include_filetypes([])`
`.ignore_filetypes([])`
`.include_dirs([])`
`.ignore_dirs([])`

These all take a list of strings, and return the filter, so that you can chain filter methods:
```
call g:SkyFilter.new("my_awesome_filter")
              \ .include_filetypes(['cpp', 'h'])
              \ .include_dirs(['my_cool_project'])
              \ .ignore_filetypes(['idk'])
              \ .ignore_dirs(['my_cool_project/lame_submodule'])
```
Note that `include_filetypes` inherently hides `ignore_filetypes` based on how rg actually works (for example if we specifically included the types `['cc', 'h']` and ignored `['py', 'js']`, the ignores technically don't matter since they normally wouldn't match the include filetypes specifications anyways. Now I know you could probably break/abuse this if you took a look at the code and thought about it a bit, but ¯\\_(ツ)_/¯

Once you have some filter presets, you can set the base preset that will RG will "default" to.
```
call g:SkyFilter.new("my_awesome_filter")
              \ .include_filetypes(['cpp', 'h'])
              \ .include_dirs(['my_cool_project'])
              \ .ignore_filetypes(['idk'])
              \ .ignore_dirs(['my_cool_project/lame_submodule'])
let g:SkyFilter.default = "my_awesome_filter"
```

The intended experience is that you can specify presets you use frequently, but have the flexibility to be more granular with one-off search flags.

## Applying command line filters to defaults
Applying a filter on top of a set of defaults is not as straightfoward logically as overwriting all the default values with our new filter.

Therefore, when you supply command-buffer-time filter options on top of a filter preset, there are a few interesting behaviors to note:
### Include collisions
If any specific `includes` are specified in our command, the preset's includes are ignored. This prevents us from simply adding filetypes, which would actually widen the scope of the search.

### Ignore collisions
If the preset has any `ignores` those are always applied unless the command specifically includes that ignore. Generally files you go out of your way to ignore are files that you always wish to ignore, unless specified explicitly.

### Consequences of my actions
Say you have this set up in your vimrc
```
call g:SkyFilter.new("empty")
call g:SkyFilter.new("my_awesome_filter")
              \ .include_filetypes(['cpp', 'h'])
              \ .include_dirs(['my_cool_project'])
              \ .ignore_dirs(['my_cool_project/lame_submodule'])
let g:SkyFilter.default = "empty"
```

Then later you call
```
:RG -p my_awesome_filter -f py,js -- where is this code anyways
```
ripgrep will only search in .py and .js files, but will still ignore `lame_submodule`

Likewise, with `-Nf`
```
:RG -p my_awesome_filter -Nf cc -- where is this code anyways
```
ripgrep will only search in .h files, and will still ignore `lame_submodule`

Another example
```
:RG -p my_awesome_filter -d my_cool_project/lame_submodule -- where is this code anyways
```
ripgrep will only search in the `lame_submodule`, but still only in c++ files.

Lastly:
```
:RG -p my_awesome_filter -Nd my_cool_project/other_submodule -- where is this code anyways
```
ripgrep will also exclude `other_submodule`, and only c++ files.

Generally, the intent is that each action of manually specifying something will make the search more specific.

## Example .vimrc filters
Here's mine from my .vimrc for an example. I've even got a little check to see what my current working directory is, and sets up the presets depending on where I'm working.
```
" Default configurations
let s:ac_types = ['py', 'cc', 'h', 'lcm', 'proto', 'djinni', 'mm', 'm', 'swift', 'java', 'kt', 'cmake']
let s:ac_ignore_types = []

" NOTE: All directory paths are relative.
" Also, if search dirs is empty, rg will search where vim was executed.
let s:ac_search_dirs = []
let s:ac_ignore_dirs = [
    \ 'build',
    \ 'third_party_modules',
    \ 'third_party',
    \ 'bazel-out',
    \ '**/node_modules',
    \ ]

let s:cwd = getcwd()
if (stridx(s:cwd, 'aircam') != -1)
    echom "Setting RG filter to default to aircam!"

    call g:SkyFilter.new("aircam")
          \ .include_filetypes(s:ac_types)
          \ .include_dirs(s:ac_search_dirs)
          \ .ignore_filetypes(s:ac_ignore_types)
          \ .ignore_dirs(s:ac_ignore_dirs)

    call g:SkyFilter.new("ios")
          \ .include_filetypes(['djinni', 'mm', 'm', 'swift'])
          \ .include_dirs(['mobile'])
          \ .ignore_filetypes(s:ac_ignore_types)
          \ .ignore_dirs(s:ac_ignore_dirs)

    call g:SkyFilter.new("android")
          \ .include_filetypes(['djinni', 'java', 'kt'])
          \ .include_dirs(['mobile'])
          \ .ignore_filetypes(s:ac_ignore_types)
          \ .ignore_dirs(s:ac_ignore_dirs)

    call g:SkyFilter.new("mcore")
          \ .include_filetypes(['djinni', 'cc', 'h'])
          \ .include_dirs(['mobile/shared'])
          \ .ignore_filetypes(s:ac_ignore_types)
          \ .ignore_dirs(s:ac_ignore_dirs)

    call g:SkyFilter.new("lcm")
          \ .include_filetypes(['lcm', 'proto'])
          \ .include_dirs(s:ac_search_dirs)
          \ .ignore_filetypes(s:ac_ignore_types)
          \ .ignore_dirs(s:ac_ignore_dirs)

    let g:SkyFilter.default = 'aircam'
endif
```

# Debugging with logs (AI-aided)

SkyRG has structured logging that makes it easy to diagnose bugs — especially
with an AI assistant. The workflow is:

1. **Enable debug logging** in your `.vimrc`:
   ```vim
   let g:skyrg_log_level = 'DEBUG'   " DEBUG|INFO|WARN|ERROR|OFF (default: INFO)
   ```

2. **Reproduce the bug**, then open the log:
   ```vim
   :SkyRGLog        " opens ~/.local/share/skyrg/skyrg.log in a split
   ```

3. **Copy the relevant section** and paste it to your AI assistant along with
   a description of what went wrong.

## Log location

| Setting | Default |
|---|---|
| `g:skyrg_log_level` | `'INFO'` — set to `'DEBUG'` for maximum detail |
| `g:skyrg_log_file` | `~/.local/share/skyrg/skyrg.log` |
| `g:skyrg_log_echo` | `0` — set to `1` to also echo to `:messages` |
| `g:skyrg_log_max` | `5000` — auto-rotates when exceeded |

## What gets logged

Every log line has a timestamp, level, and source module tag:

```
2026-05-20 18:02:00 [INFO] [panel] open mode=search
2026-05-20 18:02:00 [DEBUG] [panel] open params: {"query":"TODO","types":"py"}
2026-05-20 18:02:02 [INFO] [search] run gen=1 query="CaptureSettings"
2026-05-20 18:02:02 [DEBUG] [search] cmd: rg --column --line-number ... -- CaptureSettings .
2026-05-20 18:02:02 [INFO] [search] done gen=1 results=500 (620.6ms)
2026-05-20 18:02:08 [INFO] [results] jump ./vehicle/mavlink/mavlink_camera.cc:810:15
2026-05-20 18:02:08 [INFO] [views/search] commit_to_history query="CaptureSettings"
2026-05-20 18:02:08 [INFO] [panel] close
```

Key module tags to grep for:
- **`[panel]`** — open/close, pane switching, key dispatch, reposition
- **`[panel/key]`** — every keypress (DEBUG only)
- **`[search]`** — rg command, results, errors, timing
- **`[form]`** — field value changes
- **`[preview]`** — syntax highlighting, file display
- **`[tree]`** — directory tree toggle/rebuild
- **`[events]`** — event bus emissions
- **`[history]`** — save/load/compact
- **`[views/search]`** — open, history commit, history navigation
- **`[views/context]`** — context popup open, action execution
- **`[backend/rg]`** — generic rg backend timing

Timing traces (with `(NNms)` or `(N.NNs)` suffix) are on all slow paths:
search execution, syntax highlighting, tree rebuild, history loading, and
panel creation.

## Commands

| Command | Description |
|---|---|
| `:SkyRG [args]` | Open the search panel (see Quick Start) |
| `:SkyRGHistory` | Browse past searches |
| `:SkyRGTasks` | View active/recent tasks with live output |
| `:SkyRGActionLog` | Open most recent task log in a split |
| `:SkyRGLog` | Open the SkyRG event log |
| `:SkyRGLogClear` | Clear the event log |
| `:SkyRGDebugHistory` | View raw history entries (debug popup) |

# Context popup

The context popup is a cursor-relative action menu. Press your context key
and pick an action:

```
╭─────────────────────────────────╮
│ [w] Search "CaptureSettings"    │
│ [D] Search "CaptureSettings" in │
│     vehicle/                    │
│ [d] Search in this directory    │
│ [t] Search this filetype        │
│                                 │
│ [o] Open SkyRG                  │
│ [h] History browser             │
╰─────────────────────────────────╯
```

## Setup

Set a trigger key in your `.vimrc`:
```vim
let g:skyrg_context_key = '<Leader>a'
```

Keys inside the popup: `j`/`k` navigate, `Enter` execute, letter shortcuts,
`Esc` close.

# Custom actions

Register actions in your `.vimrc` via `g:skyrg_context_actions`. Actions
can be pure Vim, synchronous shell, or async jobs.

## Vim action (instant)

```vim
let g:skyrg_context_actions = [
  \ {
  \   'name':      'Go to definition',
  \   'key':       'g',
  \   'group':     'lsp',
  \   'priority':  5,
  \   'predicate': {ctx -> !empty(ctx.word)},
  \   'execute':   {ctx -> execute('YcmCompleter GoToDefinition')},
  \ },
  \ ]
```

## Shell action (synchronous, <1s)

```vim
let g:skyrg_context_actions = [
  \ {
  \   'name':    'Copy file path',
  \   'key':     'p',
  \   'shell':   {ctx -> 'echo ' . shellescape(ctx.file) . ' | xclip -sel c'},
  \   'job_opts': {'title': 'Copy path'},
  \ },
  \ ]
```

## Job action (async, for long-running tasks)

```vim
let g:skyrg_context_actions = [
  \ {
  \   'name':    'Example: echo word',
  \   'key':     'e',
  \   'group':   'example',
  \   'priority': 200,
  \   'job':     {ctx -> '~/.dotfiles/scripts/skyrg_example_action.sh ' . shellescape(ctx.word)},
  \   'job_opts': {
  \     'title':  'Echo example',
  \     'notify': 1,
  \   },
  \ },
  \ ]
```

## Action shape reference

| Key | Type | Description |
|---|---|---|
| `name` | string | Display name (required) |
| `label_fn` | funcref | Dynamic label: `{ctx -> printf('Search "%s"', ctx.word)}` |
| `key` | string | Single letter shortcut in the popup |
| `group` | string | Visual grouping (separator between groups) |
| `priority` | number | Sort order (lower = higher in list, default: 100) |
| `predicate` | funcref | Show only when `predicate(ctx)` is truthy |
| `execute` | funcref | Vim action: `{ctx -> ...}` |
| `shell` | string/funcref | Sync shell command (string or `{ctx -> cmd}`) |
| `job` | string/funcref | Async shell command |
| `job_opts` | dict | Options for shell/job (see below) |

### `job_opts`

| Key | Default | Description |
|---|---|---|
| `title` | action name | Display name in task list |
| `cwd` | project root | Working directory |
| `env` | `{}` | Extra environment variables |
| `notify` | `1` | Show completion notification |
| `on_success` | `[]` | Followup actions on exit 0 |
| `on_failure` | `[]` | Followup actions on non-zero exit |

### Context dict

Every predicate and execute/shell/job funcref receives a `ctx` dict:

| Key | Description |
|---|---|
| `word` | `expand('<cword>')` |
| `WORD` | `expand('<cWORD>')` |
| `line` | Current line text |
| `col` | Cursor column |
| `filetype` | Buffer filetype |
| `mode` | `'n'` or `'v'` |
| `file` | Full file path |
| `dir` | File's directory |
| `visual` | Selected text (visual mode only) |

### String interpolation

Shell/job strings support `{ctx.*}` placeholders (auto-shell-escaped):
```vim
'shell': 'grep {ctx.word} {ctx.file}'
" Becomes: grep 'CaptureSettings' '/path/to/file.cpp'
```

For full control, use a funcref instead.

# Async tasks

Actions dispatched with `job` run asynchronously. You can continue editing
while they execute.

## Statusline

Add a task progress indicator to your statusline:
```vim
set statusline+=%{skyrg#backend#tasks#statusline()}
```

This shows:
- `⟳ Build firmware (12s)` while running
- `✓ Build firmware` for 5s after success
- `✗ Build firmware` for 5s after failure
- Empty when idle (zero visual cost)

## Task viewer (`:SkyRGTasks`)

Opens a two-pane popup showing all active/recent tasks with live output:
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
└─────────────────────────────────────────────┘
```

Keys: `j`/`k` navigate, `Enter` open full log, `c` cancel, `q` close.

## Followup actions

If an action defines `on_success` or `on_failure`, a small popup appears
when the task completes offering next steps:
```vim
'job_opts': {
  'on_success': [{
    'name': 'Deploy to drone',
    'key':  'd',
    'job':  'deploy.sh',
    'job_opts': {'title': 'Deploy'},
  }],
  'on_failure': [{
    'name': 'View errors',
    'key':  'e',
    'execute': {ctx -> execute('split ' . ctx.task_log)},
  }],
}
```

## Action logs

Every dispatched action's stdout/stderr is logged to
`~/.local/share/skyrg/actions/`. Use `:SkyRGActionLog` to open the most
recent log, or `:SkyRGTasks` → `Enter` to view any task's log.

Retention is configurable:
```vim
let g:skyrg_action_log_keep_days = 7       " keep all logs (default: 7)
let g:skyrg_action_log_keep_failed = 30    " keep failed logs (default: 30)
```
