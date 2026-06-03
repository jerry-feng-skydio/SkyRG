# SkyRG Plugin

Personal Vim plugin for Skydio development. Vim 8.2+ only (no Neovim-only features).

## Two Repos, Two Roles

| Directory | Repo | Role |
|-----------|------|------|
| `skyrg-plugin/` | SkyRG (submodule) | **Plugin code** — UI, backend, views |
| `skyrg/` | dotfiles | **User config** — actions, project settings, global.vim |

The plugin loads user config from `~/.dotfiles/skyrg/` at runtime. Never put
personal actions or project-specific settings in `skyrg-plugin/`.

## Architecture

```
autoload/skyrg/
├── backend/
│   ├── action.vim      # Action dispatch engine (execute/shell/job/interactive)
│   ├── action_log.vim  # Persistent action history (file-backed)
│   ├── context.vim     # Context action registry + predicate filtering
│   ├── device.vim      # Device detection via SSH probing (R47, C38)
│   ├── favorites.vim   # Starred search results
│   ├── history.vim     # Search history
│   ├── rg.vim          # Ripgrep integration
│   └── tasks.vim       # Task lifecycle (add, update, complete, status)
├── ui/
│   ├── live_split.vim  # Reusable tailing scratch splits (file + job sources)
│   ├── popup.vim       # Popup factory (Vim 8 popup_create wrappers)
│   ├── style.vim       # Highlight groups, log styling
│   ├── window.vim      # Multi-pane window management
│   ├── keymap.vim      # Key binding helpers
│   ├── events.vim      # Event dispatch
│   └── util.vim        # Misc UI utilities
├── views/
│   ├── context.vim     # Context popup (cursor-aware action picker)
│   ├── device.vim      # Device interaction popups (SSH, logs, file browsing)
│   ├── search.vim      # Search panel
│   ├── tasks.vim       # Task viewer + log display + monitor API
│   ├── history.vim     # History browser
│   └── debug.vim       # Debug info panel
├── filter.vim          # Result filtering
├── log.vim             # Internal logging (g:skyrg_log_level)
├── panel.vim           # Legacy multi-pane search UI
└── revup.vim           # Revup integration
```

## Action Dispatch Flow

```
skyrg#backend#action#dispatch(action, ctx)
  ├── action.execute(ctx)           → Vimscript funcref (synchronous)
  ├── s:run_shell(action, ctx)      → system() call (< 1s scripts)
  ├── s:run_interactive(action, ctx) → terminal split (needs user input)
  └── s:run_job(action, ctx)        → job_start() (async builds, deploys)
        ├── registers task in backend/tasks
        ├── optionally opens monitor (live_split with source=file)
        ├── on_out/on_err → appends to task log
        └── s:on_exit → parse output, notify, run followups
```

### Action shape (registered via `g:skyrg_context_actions` or `context#register`)

```vim
{
  'name':      'Build project',
  'key':       'b',
  'group':     'build',       " optional, visual grouping in popup
  'priority':  100,           " optional, lower = higher in list
  'predicate': {ctx -> &ft ==# 'cpp'},
  'job':       {ctx -> 'make -C ' . ctx.dir},
  'job_opts':  { ... },       " see below
}
```

### `job_opts` dictionary keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `title` | string | action.name | Display name in task viewer |
| `cwd` | string or funcref | getcwd() | Working directory (funcref receives ctx) |
| `interactive` | 0/1 | 0 | Open in terminal split instead of background job |
| `term_rows` | number | — | Terminal height (interactive only) |
| `stdin` | string/funcref | — | Pipe text to job stdin (funcref receives ctx) |
| `env` | dict | — | Environment variables |
| `output_format` | string | 'none' | Parse output: 'none', 'matches', 'lines' |
| `notify` | 0/1 | 1 | Show completion message |
| `monitor` | 0/1 | 0 | Auto-open live_split log viewer on start |
| `monitor_on_success` | string | 'keep' | 'close' or 'keep' — what to do with monitor on clean exit |
| `on_success` | list | [] | Followup actions offered on exit 0 |
| `on_failure` | list | [] | Followup actions offered on non-zero exit |

### Context shape (built by `views/context.vim`)

```vim
{
  'word':     expand('<cword>'),
  'WORD':     expand('<cWORD>'),
  'line':     getline('.'),
  'col':      col('.'),
  'filetype': &filetype,
  'visual':   'selected text or empty',
  'mode':     'n' or 'v',
  'file':     expand('%:p'),
  'dir':      expand('%:p:h'),
}
```

## Live Split Module (`ui/live_split.vim`)

Reusable styled scratch splits with two data sources:

| Source | Mechanism | Use case |
|--------|-----------|----------|
| `'file'` | Timer re-reads file every 1s | Task log files |
| `'job'` | `job_start` streams stdout line-by-line | `ssh tail -f`, `logcat` |

Both get: full-width at bottom (`botright`), configurable height (`g:skyrg_log_height`,
default 10), smart scroll (only follows if cursor at bottom), styled.

```vim
let id = skyrg#ui#live_split#open({'title': '...', 'source': 'job', 'cmd': '...'})
call skyrg#ui#live_split#stop(id)   " stop source, keep split
call skyrg#ui#live_split#close(id)  " close split entirely
```

## Device Detection (`backend/device.vim`)

Probes SSH hosts defined in `~/.ssh/config` to detect connected Skydio devices.

| Vehicle | Boards | SSH hosts |
|---------|--------|-----------|
| R47 | NVU, QCU | `nvu`, `qcu`, `nvu-wifi`, `qcu-wifi` |
| C38 | SOC, Radio | `c38`, `c38-radio` |

Detection is async (parallel `ssh -o ConnectTimeout=2`). Results cached
until `device#refresh()`.

## Compatibility Rules

- **Vim 8.2+ only** — never use Neovim-only features (`winhl`, `nvim_*` API, lua)
- Use `popup_create()` not floating windows
- Use `job_start()` not `jobstart()`
- Test with `has('patch-8.2.XXXX')` if using newer Vim features
