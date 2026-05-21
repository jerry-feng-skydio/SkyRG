# SkyRG Architecture Proposal

> **Status**: Proposal (not yet implemented)
> **Author**: Jerry Feng + Cascade
> **Date**: 2026-05-20

## Purpose

SkyRG started as a ripgrep search UI. This proposal refactors it into a
**general-purpose popup windowing system** with a **pluggable backend
architecture**, so it can power search, history browsing, favorites, context
actions, build-error navigation, and future features — all reusing the same
UI primitives.

## Reading Guide

| Document | What it covers |
|---|---|
| [layers.md](layers.md) | The 4-layer architecture overview |
| [pane-protocol.md](pane-protocol.md) | Pane interface contract |
| [window-system.md](window-system.md) | Window lifecycle, layout engine, key dispatch |
| [backends.md](backends.md) | Backend protocol for data sources |
| [views.md](views.md) | View composition: how panes + backends wire together |
| [context-popup.md](context-popup.md) | Context-action popup system (detailed spec) |
| [history.md](history.md) | Query history persistence and navigation |
| [refactor-plan.md](refactor-plan.md) | Phase-by-phase implementation plan with checklists |

## Key Principles

1. **Layers don't reach down.** Views depend on the window system; the window
   system depends on UI primitives; UI primitives depend on nothing. Never the
   reverse.
2. **Panes are dumb.** A pane knows how to render data and handle keys. It
   does not know where its data comes from. Views wire panes to backends.
3. **Backends are headless.** A backend knows how to produce data (run rg, read
   history, fetch LSP results). It does not know about popups.
4. **Views are glue.** A view creates a window spec, instantiates panes,
   connects them to a backend, and handles cross-pane coordination.
5. **Backward compatibility.** All existing public APIs (`skyrg#panel#open()`,
   `skyrg#panel#state()`, `:SkyRG`) continue to work as thin wrappers during
   and after the refactor.

## Target File Tree

```
autoload/skyrg/
├── ui/                          ← Layer 0+1: Generic UI system
│   ├── popup.vim                ← Popup factory (from panel/popup.vim)
│   ├── style.vim                ← Highlight/prop registry (from panel/style.vim)
│   ├── events.vim               ← Event bus (from panel/events.vim)
│   ├── util.vim                 ← Line builders (from panel/util.vim)
│   ├── keymap.vim               ← Keymap merge engine (from panel/keymap.vim)
│   ├── window.vim               ← Window lifecycle (from panel.vim)
│   └── panes/                   ← Generic pane implementations
│       ├── list.vim             ← Scrollable list (from panel/results.vim)
│       ├── form.vim             ← Field-editor form (from panel/form.vim)
│       ├── preview.vim          ← File preview (from panel/preview.vim)
│       ├── info.vim             ← Read-only info display
│       └── tree.vim             ← Directory tree (from panel/tree.vim)
│
├── backend/                     ← Layer 2: Domain-specific backends
│   ├── rg.vim                   ← Async ripgrep runner (from panel/search.vim)
│   ├── history.vim              ← Query persistence
│   ├── favorites.vim            ← Bookmarked queries
│   └── context.vim              ← Context-action registry
│
├── views/                       ← Layer 3: View compositions
│   ├── search.vim               ← Search window (current SkyRG)
│   ├── history.vim              ← History browser
│   ├── favorites.vim            ← Favorites browser
│   ├── context.vim              ← Context popup
│   └── build.vim                ← Build-error navigator
│
├── filter.vim                   ← SkyFilter presets (unchanged)
├── log.vim                      ← Logging (unchanged)
│
├── panel.vim                    ← COMPAT SHIM: delegates to views/search.vim
└── panel/                       ← DEPRECATED: originals kept during transition
    └── ...
```
