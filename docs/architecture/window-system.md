# Window System

> **Status**: Proposal

## Overview

`skyrg#ui#window` manages the lifecycle of a popup-based window composed of
multiple panes. It owns:

- Popup creation and destruction
- Layout computation from a declarative spec
- Keystroke routing to the active pane
- Terminal resize handling (`VimResized`)
- Active pane switching with border highlight updates

The window does **not** know what's inside its panes. It treats them as
opaque objects conforming to the [pane protocol](pane-protocol.md).

## Window Spec

A view creates a window by passing a **spec dict**:

```vim
let spec = {
  \ 'title': 'SkyRG',
  \ 'panes': [
  \   {'name': 'form',    'pane': form_pane,    'region': 'top-left',  'flex': 0.55},
  \   {'name': 'info',    'pane': info_pane,    'region': 'top-right', 'flex': 0.45},
  \   {'name': 'results', 'pane': results_pane, 'region': 'bot-left',  'flex': 0.45},
  \   {'name': 'preview', 'pane': preview_pane, 'region': 'bot-right', 'flex': 0.55},
  \ ],
  \ 'initial_pane': 'form',
  \ 'keymap': { ... },
  \ 'global_keys': function('s:global_key_handler'),
  \ 'on_close': function('s:on_close_callback'),
  \ 'sidepanes': [
  \   {'name': 'tree', 'pane': tree_pane, 'side': 'left', 'width': 30, 'hidden': 1},
  \ ],
  \ }
```

### Spec Fields

| Field | Type | Description |
|---|---|---|
| `title` | string | Window title (shown on the primary pane's border) |
| `panes` | list | Main panes with region placement |
| `initial_pane` | string | Name of the pane that starts focused |
| `keymap` | dict | Action → key list mappings (merged with defaults) |
| `global_keys` | Funcref | `(key, K) → 0/1` — handles keys before pane routing |
| `on_close` | Funcref | Called when the window closes |
| `sidepanes` | list | Optional togglable side panels |

### Region Model

The layout uses a **2-row, 2-column grid** for main panes:

```
┌─────────────────┬──────────────────┐
│   top-left      │   top-right      │
│   (flex: 0.55)  │   (flex: 0.45)   │
├─────────────────┼──────────────────┤
│   bot-left      │   bot-right      │
│   (flex: 0.45)  │   (flex: 0.55)   │
└─────────────────┴──────────────────┘
```

If only one pane occupies a row, it takes full width. The `flex` ratio
controls the horizontal split within a row. The top row height is fixed
(derived from the top panes' content needs); the bottom row fills remaining
space.

Side panes attach to the left or right edge and push the main grid inward
when visible.

### Positioning Modes

Most windows use the default centered layout. The context popup uses a
**cursor-relative** mode:

```vim
let spec = {
  \ 'position': 'cursor',    " 'center' (default) or 'cursor'
  \ 'panes': [
  \   {'name': 'actions', 'pane': list_pane, 'region': 'full'},
  \ ],
  \ }
```

In cursor mode, the popup appears near `screenrow()`/`screencol()` and is
sized to its content (up to a max).

## Lifecycle

```
open(spec)
  │
  ├─ compute_layout(spec, &columns, &lines)
  ├─ for each pane: popup_create(pane.render(), geo)
  ├─ focus initial_pane (set border highlight)
  ├─ register VimResized autocmd
  └─ return window_handle
  
on_key(winid, key)
  │
  ├─ global_keys(key, K) → consumed? stop
  ├─ check close action → close()
  ├─ active_pane.on_key(key, K) → consumed? stop
  └─ unhandled: ignore
  
VimResized
  │
  ├─ recompute_layout()
  ├─ for each pane: popup_move(id, new_geo)
  ├─ for each pane: pane.on_resize(new_geo)
  └─ for each pane: popup_settext(id, pane.render())

close()
  │
  ├─ for each pane: pane.cleanup()
  ├─ for each popup: popup_close(id)
  ├─ remove VimResized autocmd
  ├─ events#reset()
  ├─ style#cleanup()
  └─ call spec.on_close()
```

## Pane Switching

The window provides a function to switch the active pane:

```vim
call window.set_active('results')
```

This:
1. Calls `old_pane.on_blur()`
2. Updates border highlights (active = `Title`, inactive = `Comment`)
3. Calls `new_pane.on_focus()`
4. Updates the form's hint line (if applicable)

Pane switching keys are defined in the keymap and handled by `global_keys`
or individual pane `on_key` handlers. The view decides the navigation graph
(e.g., "from form, Ctrl+Down goes to results").

## Window Handle

`open()` returns a handle dict that views hold onto:

```vim
let handle = {
  \ 'set_active': function('s:set_active'),
  \ 'close':      function('s:close'),
  \ 'get_pane':   function('s:get_pane'),    " (name) → pane dict
  \ 'get_popup':  function('s:get_popup'),   " (name) → popup ID
  \ 'reposition': function('s:reposition'),
  \ 'get_layout': function('s:get_layout'),  " () → layout dict
  \ }
```

Views use the handle for cross-pane coordination. They never access window
internals directly.

## Migration from panel.vim

During the transition:

1. `panel.vim` becomes a thin wrapper that constructs a search-view spec
   and calls `skyrg#ui#window#open(spec)`.
2. Existing `skyrg#panel#state()` returns a compat shim that maps old
   state keys to the new pane states.
3. Old `panel/` submodules continue to work but are gradually replaced by
   `ui/panes/` implementations.

The test suite runs green at every step.
