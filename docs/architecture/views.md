# View Composition

> **Status**: Proposal

## Overview

A **view** is a function that wires panes to backends and opens a window.
Views are the "glue" layer — they contain all the domain-specific
orchestration that doesn't belong in generic panes or headless backends.

Each view:
1. Creates and configures pane instances
2. Constructs a window spec (layout, keymap, callbacks)
3. Registers event listeners for cross-pane coordination
4. Opens the window
5. Handles lifecycle events (close, save-to-history, etc.)

## View Catalog

### `search.vim` — Main Search Window

The current SkyRG experience, refactored into the new architecture.

```
┌── Form ──────────────┬── Info ──────────────┐
│ > Query:  my_search  │ Preset: cpp_only     │
│   Dirs:   src/       │ +types: cpp, h       │
│   Types:  py,cpp     │ -dirs:  third_party/ │
│   Preset: ◀ cpp ▶   │                      │
│   .gitignore [x]     │ cpp | [py] | all     │
├── Results (3/47) ────┼── Preview ───────────┤
│ > src/foo.cpp:42: .. │   40  int bar() {    │
│   src/bar.py:17: ... │   41    // ...       │
│   lib/baz.h:9: ...   │ > 42    my_search(); │
│                      │   43    return 0;    │
│                      │   44  }              │
└──────────────────────┴──────────────────────┘
```

**Panes**: form, info, list (results), preview
**Sidepane**: tree (directory browser, togglable)
**Backend**: rg
**Keymap context**: query_*, results_*, tree_*

**Cross-pane wiring**:
```vim
" View setup pseudocode:
events#on('form_changed',    → rg.schedule(form.get_query()))
events#on('results_changed', → preview.show(results.selected_item()))
events#on('results_changed', → results_pane.render())
events#on('pane_changed',    → update border highlights)
```

**Query loading**: The view exposes `open(params)` where `params` is an
optional dict that pre-fills form fields:
```vim
call skyrg#views#search#open({
  \ 'query': 'TODO',
  \ 'types': 'py',
  \ 'dirs':  'src/',
  \ })
```
This is used by:
- History restore (load last query on open)
- History navigation (PageUp/Down fills from history)
- Context actions (pre-fill query with word under cursor)
- Favorites (load bookmarked query)

### `history.vim` — History Browser

```
┌── History ──────────────────┬── Preview ──────────────┐
│   [2h ago]  TODO (py, src/) │   src/foo.py:42: # TODO │
│ > [5h ago]  my_func (cpp)   │   src/bar.py:17: # TODO │
│   [1d ago]  import os       │   ...                   │
│   [3d ago]  class Foo       │                         │
│                             │                         │
│ Filter: ___                 │                         │
└─────────────────────────────┴─────────────────────────┘
```

**Panes**: list (history entries), preview (shows first few results of
selected query, or re-runs the search)
**Backend**: history
**Entry point**: `:SkyRGHistory`

**Actions**:
- Enter: open search view pre-filled with selected query
- `d`: delete entry from history
- `/`: focus filter bar
- Esc: close

### `favorites.vim` — Favorites Browser

Same layout as history. Entries have user-provided labels instead of
timestamps.

**Actions**:
- Enter: open search view pre-filled with selected query
- `d`: remove from favorites
- `e`: edit label

### `context.vim` — Context Popup

```
╭─────────────────────────╮
│ Find callers             │
│ Find definition          │
│ Search in this directory │
│ Run build                │
╰─────────────────────────╯
   ^ appears near cursor
```

**Panes**: list (filtered actions)
**Backend**: context
**Position**: cursor-relative (not centered)
**Entry point**: user-configured mapping (e.g., `<Leader>a`)

**Actions**:
- Enter: execute selected action
- Typing: filter action list
- Esc: close
- `1`-`9`: quick-select by number

See [context-popup.md](context-popup.md) for the full spec.

### `build.vim` — Build Error Navigator

```
┌── Errors (3) ──────────────┬── Preview ──────────────┐
│ > foo.cpp:42: undeclared.. │   40  int bar() {       │
│   bar.cpp:17: type misma.. │   41    // ...          │
│   baz.h:9: missing semi..  │ > 42    unk_var = 1;   │
│                            │   43    return 0;       │
└────────────────────────────┴─────────────────────────┘
```

**Panes**: list (parsed errors), preview (file at error location)
**Backend**: shell command output + user-provided parser function
**Entry point**: context action ("Run build") or direct command

The error list uses the **same `{file, line, col, text}` shape** as search
results, so the list pane and preview pane work unmodified.

## View Registration Pattern

Views register themselves so other parts of the system can open them:

```vim
" In views/search.vim:
function! skyrg#views#search#open(...) abort
  let l:params = a:0 > 0 ? a:1 : {}
  " ... create panes, build spec, open window
endfunction

" In views/context.vim, an action can open any view:
let action = {
  \ 'label': 'Search for word',
  \ 'run': {ctx -> skyrg#views#search#open({'query': ctx.word})},
  \ }
```

## State Serialization

Views that support history need to serialize/deserialize their state:

```vim
" Save: extract query dict from form pane
function! s:get_query_dict() abort
  let form_state = self.form_pane.state
  return {
    \ 'query':     form_state.fields[0].value,
    \ 'dirs':      form_state.fields[1].value,
    \ 'types':     form_state.fields[2].value,
    \ 'preset':    form_state.fields[3].value,
    \ 'gitignore': form_state.fields[4].value ==# 'on',
    \ }
endfunction

" Restore: push query dict into form pane
function! s:load_query_dict(d) abort
  let form_state = self.form_pane.state
  let form_state.fields[0].value = a:d.query
  " ... etc
  call self.form_pane.render()
endfunction
```

This is how history restore, PageUp/Down navigation, and favorite loading
all work — they call `load_query_dict()` with different sources.
