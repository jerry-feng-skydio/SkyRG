# Backend Protocol

> **Status**: Proposal

## Overview

A **backend** is a headless data producer. It accepts parameters, does work
(possibly async), and delivers results via callbacks. Backends have zero UI
knowledge — they never import from `ui/`.

This separation means the same rg backend can power both the search view and
a hypothetical "search and replace" view, and the same list pane can display
rg results, history entries, or build errors.

## Protocol

Every backend is a dict (or set of autoload functions) with:

```vim
" Minimal backend interface
let backend = {
  \ 'run':    function('s:run'),     " (params, callbacks) → void
  \ 'cancel': function('s:cancel'),  " () → void
  \ }
```

### `run(params, callbacks)`

- `params`: dict with backend-specific query parameters
- `callbacks`: dict with standard hooks:
  - `on_result(item)` — called per result (streaming)
  - `on_done(results)` — called when complete, with all results
  - `on_error(msg)` — called on failure
- Must be **re-entrant**: calling `run()` again cancels the previous operation.

### `cancel()`

Abort any in-progress operation. Idempotent.

## Backend Specifications

### `rg.vim` — Ripgrep Search

Extracted from current `panel/search.vim`.

```vim
" Params:
let params = {
  \ 'query':       'search term',
  \ 'types':       'py,cpp',       " comma-separated, .ext for raw extensions
  \ 'dirs':        'src/,lib/',     " comma-separated
  \ 'preset':      'my_preset',    " SkyFilter preset name
  \ 'gitignore':   1,              " respect .gitignore
  \ 'max_results': 500,
  \ }

" Result item shape:
let item = {
  \ 'file': '/abs/path/to/file.py',
  \ 'line': 42,
  \ 'col':  7,
  \ 'text': 'the matched line content',
  \ }
```

Internals:
- Builds `rg` command from params (including SkyFilter globbing args)
- Uses `job_start()` with `out_cb`/`close_cb`
- Generation counter to discard stale results
- Debounced scheduling (300ms default) exposed as `schedule(params, callbacks)`

### `history.vim` — Query Persistence

```vim
" Storage: ~/.local/share/skyrg/<project_hash>.jsonl
" One JSON object per line, append-only.

" Entry shape:
let entry = {
  \ 'query':     'search term',
  \ 'types':     'py,cpp',
  \ 'dirs':      'src/',
  \ 'preset':    'my_preset',
  \ 'gitignore': 1,
  \ 'timestamp': 1716249600,       " unix epoch
  \ 'cwd':       '/home/user/project',
  \ }

" API:
function! skyrg#backend#history#save(entry) abort       " append to file
function! skyrg#backend#history#load_all(cwd) abort     " → [entry, ...] (newest first)
function! skyrg#backend#history#load_last(cwd) abort    " → entry or {}
function! skyrg#backend#history#search(cwd, filter) abort " → [entry, ...]
```

Project scoping:
- Project root = `git rev-parse --show-toplevel` if available, else cwd.
- File path = `~/.local/share/skyrg/` + SHA256(project_root)[0:12] + `.jsonl`
- Avoids writing into the project tree.

What gets saved:
- Only "committed" searches: user pressed Enter to view results, or jumped
  to a match. Intermediate keystrokes are not persisted.
- Deduplication: if the most recent entry has identical query fields (ignoring
  timestamp), skip the save.

### `favorites.vim` — Bookmarked Queries

```vim
" Storage: ~/.local/share/skyrg/favorites.jsonl
" Same entry shape as history, plus:
let entry.label = 'Find TODO comments'  " user-provided label

" API:
function! skyrg#backend#favorites#save(entry) abort
function! skyrg#backend#favorites#remove(idx) abort
function! skyrg#backend#favorites#load_all() abort     " → [entry, ...]
```

Favorites are global (not project-scoped) since users may want cross-project
bookmarks.

### `context.vim` — Context Action Registry

```vim
" Action shape:
let action = {
  \ 'label':    'Find callers',
  \ 'when':     {ctx -> ctx.filetype =~# '^\(cpp\|c\)$'},
  \ 'run':      {ctx -> skyrg#views#search#open({'query': ctx.word})},
  \ 'priority': 10,
  \ }

" Context shape (computed once per invocation):
let context = {
  \ 'word':     expand('<cword>'),
  \ 'WORD':     expand('<cWORD>'),
  \ 'line':     getline('.'),
  \ 'lnum':     line('.'),
  \ 'col':      col('.'),
  \ 'file':     expand('%:p'),
  \ 'filetype': &filetype,
  \ 'visual':   '',              " visual selection if from visual mode
  \ 'git_root': s:git_root(),
  \ 'cwd':      getcwd(),
  \ }

" API:
function! skyrg#backend#context#register(action) abort  " add action
function! skyrg#backend#context#get(context) abort      " → [action, ...] filtered + sorted
function! skyrg#backend#context#execute(action, context) abort
```

Registration sources:
1. Built-in actions (shipped with SkyRG, registered on load)
2. User actions via `g:skyrg_context_actions` list
3. Filetype-specific actions via `g:skyrg_context_{ft}` lists

Helper predicates for common patterns:
```vim
function! skyrg#backend#context#ft(pattern)   " → when-lambda matching filetype
function! skyrg#backend#context#has_cmd(cmd)  " → when-lambda checking executable()
function! skyrg#backend#context#always()      " → when-lambda returning 1
```

See [context-popup.md](context-popup.md) for the full context system spec.
