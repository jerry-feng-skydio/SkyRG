# Layer Architecture

> **Status**: Proposal

## Overview

```
┌─────────────────────────────────────────────────────┐
│  Layer 4 — Plugin (plugin/skyrg.vim)                │
│  User-facing commands: :SkyRG, :SkyRGHistory, etc.  │
├─────────────────────────────────────────────────────┤
│  Layer 3 — Views (autoload/skyrg/views/)            │
│  Compositions: search, history, context, build      │
│  Each view wires panes to a backend.                │
├─────────────────────────────────────────────────────┤
│  Layer 2 — Backends (autoload/skyrg/backend/)       │
│  Data sources: rg, history, favorites, context      │
│  Headless, async, no UI knowledge.                  │
├─────────────────────────────────────────────────────┤
│  Layer 1 — Window System (autoload/skyrg/ui/)       │
│  window.vim: lifecycle, layout, key dispatch         │
│  panes/: generic list, form, preview, info, tree    │
├─────────────────────────────────────────────────────┤
│  Layer 0 — Primitives (autoload/skyrg/ui/)          │
│  popup.vim, style.vim, events.vim, util.vim,        │
│  keymap.vim                                          │
└─────────────────────────────────────────────────────┘
```

## Dependency Rules

- **Layer N may only depend on layers < N.** No upward or lateral deps.
- Within a layer, modules should not depend on siblings (prefer events).
- Backends (layer 2) never import from `ui/`. They return data; views push
  it into panes.
- Views (layer 3) may import from `ui/` and `backend/` but not from other views.

## Layer 0 — Primitives

Pure utilities with zero domain knowledge. Could be extracted into a
standalone Vim library.

| Module | Responsibility |
|---|---|
| `popup.vim` | `popup_create`/`popup_move` wrapper with SkyRG defaults |
| `style.vim` | Highlight groups + `prop_type_add`/`prop_type_delete` registry |
| `events.vim` | `on(event, Fn)`, `emit(event, ...)`, `reset()` |
| `util.vim` | `line()`, `hl_line()`, `short()`, `del_word()` |
| `keymap.vim` | Merge engine: default keymap + user overrides via `g:skyrg_keymap` |

## Layer 1 — Window System

The window system manages popup lifecycles, computes layouts from declarative
specs, routes keystrokes to the active pane, and handles terminal resizes.

| Module | Responsibility |
|---|---|
| `window.vim` | `open(spec)`, `close()`, `reposition()`, key dispatch loop |
| `panes/list.vim` | Scrollable list with selection, search, page up/down |
| `panes/form.vim` | Multi-field editor with cursor, editing, field navigation |
| `panes/preview.vim` | File preview with optional syntax highlighting |
| `panes/info.vim` | Read-only text display (for preset details, metadata) |
| `panes/tree.vim` | Expandable tree browser with search/filter |

See [pane-protocol.md](pane-protocol.md) and
[window-system.md](window-system.md) for specs.

## Layer 2 — Backends

Headless data producers. They accept query parameters and call back with
results. They own persistence (history files), external process management
(rg jobs), and domain logic (action registries).

| Module | Responsibility |
|---|---|
| `rg.vim` | Build rg command from query dict, manage async job, parse output |
| `history.vim` | Save/load/search query history, scoped by project root |
| `favorites.vim` | Persist/retrieve bookmarked queries |
| `context.vim` | Action registry: register, filter by context, execute |

See [backends.md](backends.md) for the protocol spec.

## Layer 3 — Views

Each view is a function that creates a window spec (layout + panes + keymap),
opens it, and manages the data flow between its panes and its backend(s).

| View | Panes used | Backend(s) |
|---|---|---|
| `search.vim` | form, list, preview, info, tree | rg, filter |
| `history.vim` | list, preview | history |
| `favorites.vim` | list, preview | favorites |
| `context.vim` | list | context |
| `build.vim` | list, preview | (shell command + parser) |

See [views.md](views.md) for the composition spec.

## Layer 4 — Plugin

User-facing Vim commands defined in `plugin/skyrg.vim`. Each command is a
one-liner that calls a view:

```vim
command! -nargs=* SkyRG      call skyrg#views#search#open(<f-args>)
command! -nargs=0 SkyRGHistory call skyrg#views#history#open()
command! -nargs=0 SkyRGFav   call skyrg#views#favorites#open()
command! -nargs=0 SkyCtx     call skyrg#views#context#open()
```
