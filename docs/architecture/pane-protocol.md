# Pane Protocol

> **Status**: Proposal

## Overview

A **pane** is a dict that conforms to a duck-typed interface. The window
system calls pane methods generically — it never inspects pane internals.

This is the central abstraction that makes the UI reusable: the window
system doesn't know if it's rendering search results, history entries, or
build errors. It just calls `pane.render()` and gets back popup line dicts.

## Interface

```vim
" Every pane is a dict with these keys:
let pane = {
  \ 'name':      'results',              " String — unique within a window
  \ 'render':    function('s:render'),    " () → [line_dict, ...]
  \ 'on_key':    function('s:on_key'),    " (key, keymap_is_fn) → 0/1
  \ 'on_focus':  function('s:on_focus'),  " () → void (called when pane becomes active)
  \ 'on_blur':   function('s:on_blur'),   " () → void (called when pane loses focus)
  \ 'on_resize': function('s:on_resize'), " (geo_dict) → void
  \ 'cleanup':   function('s:cleanup'),   " () → void (called on window close)
  \ 'state':     {},                      " Dict — pane-private state
  \ 'config':    {},                      " Dict — creation-time configuration
  \ }
```

### Method contracts

#### `render() → [line_dict, ...]`

Returns a list of popup line dicts suitable for `popup_settext()`. Each dict
has the form `{'text': '...', 'props': [...]}` (see `util#line()`).

- Called by the window after any state change that might affect display.
- Must be **idempotent** and **side-effect-free** (no popup calls inside).
- The window owns `popup_settext(popup_id, pane.render())`.

#### `on_key(key, K) → 0/1`

Handles a keypress routed by the window's key dispatch. `K` is the
`keymap#is` function for checking action bindings.

- Returns `1` if the key was consumed, `0` to let the window handle it.
- May mutate `self.state` and call `self.emit(event, ...)` to signal
  other panes via the event bus.

#### `on_focus()` / `on_blur()`

Called when the window switches the active pane. Use for visual updates
(e.g., showing/hiding cursor highlights).

#### `on_resize(geo)`

Called after a `VimResized` event with the new geometry dict
`{'line': N, 'col': N, 'width': N, 'height': N}`. The pane may adjust
internal scroll state.

#### `cleanup()`

Called when the window closes. Free resources (e.g., close syntax analysis
windows, stop timers).

## Pane Configuration

Panes are configured at creation time via a `config` dict. This allows
the same pane implementation to serve different views:

```vim
" A list pane for search results:
let results_pane = skyrg#ui#panes#list#new({
  \ 'format_item': function('s:format_match'),
  \ 'on_select':   function('s:on_match_selected'),
  \ 'on_accept':   function('s:on_match_accepted'),
  \ 'empty_text':  'No results',
  \ })

" The same list pane for history entries:
let history_pane = skyrg#ui#panes#list#new({
  \ 'format_item': function('s:format_history_entry'),
  \ 'on_select':   function('s:on_history_selected'),
  \ 'on_accept':   function('s:on_history_accepted'),
  \ 'empty_text':  'No history',
  \ })
```

## Pane ↔ Window Communication

Panes communicate with the window and other panes via two mechanisms:

1. **Return values**: `on_key()` returns 0/1 to signal consumption.
2. **Event bus**: Panes call `skyrg#ui#events#emit(event, ...)` for cross-
   pane coordination. The view registers listeners in its setup phase.

Panes do **not** call `popup_settext()` or `popup_setoptions()` directly.
They mutate their own state and return render data. The window orchestrates
actual popup updates.

Exception: during the transition period, existing panes may still call popup
functions directly. These will be migrated incrementally.

## Built-in Pane Types

### `list` — Scrollable list with selection

State: `{items: [...], idx: 0, scroll: 0}`

Config callbacks:
- `format_item(item, idx, is_selected) → line_dict`
- `on_select(item, idx)` — called on cursor movement
- `on_accept(item, idx)` — called on Enter

### `form` — Multi-field editor

State: `{fields: [{label, value, pos, type}, ...], field_idx: 0}`

Field types: `'text'`, `'toggle'`, `'select'` (for preset-like cycling),
`'readonly'`.

Config callbacks:
- `on_change(field_idx, old_value, new_value)` — called after edits
- `on_submit(fields_snapshot)` — called on Enter
- `hint_fn(field_idx) → line_dict` — dynamic hint line

### `preview` — File preview

State: `{file: '', line: 0, syn_mode: 0}`

Config:
- `context_provider()` — returns `{file, line, col}` for what to preview
- `syntax_enabled` — whether to support syntax toggle

### `info` — Read-only text

State: `{lines: [line_dict, ...]}`

No key handling. Pure display. Views set content directly.

### `tree` — Directory tree browser

State: `{nodes: [...], idx: 0, expanded: {}, filter: ''}`

Config callbacks:
- `on_select(node)` — called on Enter
- `root_fn()` — returns the tree root path
