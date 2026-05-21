# History System

> **Status**: Proposal

## Overview

The history system gives SkyRG a memory across sessions. It persists
committed searches, scoped by project, and surfaces them via:

1. **Auto-restore**: opening SkyRG shows the last search for this project
2. **In-search navigation**: PageUp/Down cycles through past queries
3. **History browser**: a dedicated view for searching and re-running past queries

## Storage

### Location

```
~/.local/share/skyrg/
├── history/
│   ├── a1b2c3d4e5f6.jsonl    ← project hash → search history
│   ├── f7e8d9c0b1a2.jsonl
│   └── ...
├── favorites.jsonl             ← global favorites
└── meta.json                   ← project hash → project root mapping (for debugging)
```

- XDG-compliant: `$XDG_DATA_HOME/skyrg/` or `~/.local/share/skyrg/`.
- Never writes into the project tree.
- The directory is created on first write.

### Project scoping

```vim
function! s:project_root() abort
  " Prefer git root for consistency across subdirectories
  let root = system('git rev-parse --show-toplevel 2>/dev/null')
  if v:shell_error == 0
    return trim(root)
  endif
  " Fall back to the cwd Vim was launched with
  return getcwd()
endfunction

function! s:project_hash(root) abort
  " 12-char SHA256 prefix — short, collision-resistant
  return sha256(a:root)[:11]
endfunction
```

A user working in `~/aircam` gets a different history file than one in
`~/.dotfiles`, even if they `cd` into a subdirectory.

### File format: JSON Lines

Each line is one JSON object. Append-only writes (no full-file rewrites
except for compaction).

```json
{"query":"TODO","types":"py","dirs":"src/","preset":"","gitignore":1,"timestamp":1716249600,"result_count":42}
{"query":"import os","types":"py","dirs":"","preset":"python","gitignore":1,"timestamp":1716250200,"result_count":7}
```

### Entry shape

```vim
let entry = {
  \ 'query':        'search term',
  \ 'types':        'py,cpp',
  \ 'dirs':         'src/',
  \ 'preset':       'my_preset',
  \ 'gitignore':    1,
  \ 'timestamp':    localtime(),
  \ 'result_count': 42,
  \ }
```

`result_count` is informational (shown in history browser), not required.

## What gets saved

A search is **committed** when:
1. The user presses Enter in the results pane (jumps to a match), OR
2. The user presses Enter in the form pane to move to results (meaning they
   actively chose to view results), OR
3. The user closes the search window and there was a non-empty query with
   results.

A search is **NOT** committed when:
- The user is still typing (intermediate auto-search results)
- The query is empty
- The search produced zero results

### Deduplication

Before saving, compare the new entry (ignoring `timestamp` and
`result_count`) to the most recent entry. If all query fields are identical,
skip the save. This prevents "typed a char, deleted it" from creating
duplicate entries.

## In-Search History Navigation

### Behavior

When the search window is open and the form pane is active:

| Key | Action |
|---|---|
| `PageUp` | Fill form with the previous query in history |
| `PageDown` | Fill form with the next query in history |

### State machine

```
[current query]  ← user is here initially
       │
  PageUp │
       ▼
[history[-1]]    ← most recent different query
       │
  PageUp │
       ▼
[history[-2]]    ← second most recent
       │
  PageDown │
       ▼
[history[-1]]    ← back to most recent
       │
  PageDown │
       ▼
[current query]  ← back to what user had before navigating
```

Implementation:
```vim
" In the search view:
let s:history_state = {
  \ 'entries':     [],     " loaded history (newest first)
  \ 'nav_idx':     -1,     " -1 = "current" (not navigating)
  \ 'saved_query': {},     " snapshot of form before navigation started
  \ }
```

- `PageUp`: if `nav_idx == -1`, snapshot current form into `saved_query`
  and load `entries[0]`. Otherwise, load `entries[nav_idx + 1]` if it
  exists. If at the end of history, do nothing.
- `PageDown`: if `nav_idx > 0`, load `entries[nav_idx - 1]`. If
  `nav_idx == 0`, restore `saved_query` and set `nav_idx = -1`. If
  `nav_idx == -1`, do nothing.
- Any form edit resets `nav_idx = -1` (the user is now composing a new
  query; the snapshot is discarded).
- Navigation does **not** wrap.

## History Browser View

A dedicated view (`:SkyRGHistory`) for browsing and filtering all past
searches.

### Layout

```
┌── History (47 entries) ─────┬── Preview ──────────────┐
│ > [2h ago]  TODO (py, src/) │   src/foo.py:42: # TODO │
│   [5h ago]  my_func (cpp)   │   src/bar.py:17: # TODO │
│   [1d ago]  import os       │   ...                   │
│   [3d ago]  class Foo       │                         │
│                             │                         │
│ Filter: ___                 │                         │
└─────────────────────────────┴─────────────────────────┘
```

### Formatting

Each entry is displayed as:
```
  [relative_time]  query  (types, dirs)
```

Relative time:
- < 1 hour: "Nm ago"
- < 24 hours: "Nh ago"
- < 7 days: "Nd ago"
- Otherwise: "YYYY-MM-DD"

### Filter bar

The bottom of the list pane has a filter input. Typing filters entries by
substring match on the query field. This uses the same text-input machinery
as the form pane's fields.

### Actions

| Key | Action |
|---|---|
| `Up`/`Down` | Navigate entries |
| `Enter` | Open search view pre-filled with selected query |
| `d` | Delete entry from history |
| `/` | Focus filter bar |
| `Esc` | Close (or unfocus filter bar) |
| `f` | Add to favorites |

### Preview

When navigating history entries, the preview pane shows a summary:
- The query parameters (formatted like the info pane)
- If the search is cheap to re-run, show first few results
- If not, show "Press Enter to search"

## Compaction

Over time, history files grow. Compaction runs automatically on load if the
file exceeds a threshold (e.g., 10,000 entries):

1. Deduplicate (keep newest of identical queries)
2. Keep all entries from last 30 days
3. Keep at most 5,000 older entries (drop oldest)
4. Rewrite the file atomically (write to `.tmp`, rename)

Compaction is transparent to the user.

## API Summary

```vim
" Backend API (autoload/skyrg/backend/history.vim):
function! skyrg#backend#history#save(entry) abort
function! skyrg#backend#history#load_all(project_root) abort  " → [entry, ...] newest first
function! skyrg#backend#history#load_last(project_root) abort " → entry or {}
function! skyrg#backend#history#search(project_root, filter_str) abort " → [entry, ...]
function! skyrg#backend#history#delete(project_root, timestamp) abort
function! skyrg#backend#history#project_root() abort          " → string

" View API (autoload/skyrg/views/history.vim):
function! skyrg#views#history#open() abort
```
