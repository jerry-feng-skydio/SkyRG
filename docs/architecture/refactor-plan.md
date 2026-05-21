# Refactor Plan

> **Status**: Proposal — checklists track implementation progress

## Guiding Rules

1. **Tests stay green at every step.** Run `vim -u NONE -N --not-a-term --cmd 'set rtp+=.' -S test/run.vim` after each phase.
2. **Existing public API preserved.** `skyrg#panel#open()`, `skyrg#panel#state()`, `:SkyRG`, etc. continue to work via shims.
3. **One phase at a time.** Complete and commit each phase before starting the next.
4. **No feature work during refactor.** The refactor changes structure, not behavior. New features come after Phase 3.

## Phase 1 — Extract Generic UI Primitives

**Goal**: Move existing generic modules into `autoload/skyrg/ui/` without
changing behavior. Old paths become one-line shims.

**Risk**: Low — mechanical file moves + autoload function renames.

### Checklist

- [x] Create `autoload/skyrg/ui/` directory
- [x] Move `panel/popup.vim` → `ui/popup.vim`
  - Rename functions: `skyrg#panel#popup#*` → `skyrg#ui#popup#*`
  - Add shim in `panel/popup.vim`: forward calls to new location
- [x] Move `panel/style.vim` → `ui/style.vim`
  - Rename: `skyrg#panel#style#*` → `skyrg#ui#style#*`
  - Add shim
- [x] Move `panel/events.vim` → `ui/events.vim`
  - Rename: `skyrg#panel#events#*` → `skyrg#ui#events#*`
  - Add shim
- [x] Move `panel/util.vim` → `ui/util.vim`
  - Rename: `skyrg#panel#util#*` → `skyrg#ui#util#*`
  - Add shim
- [x] Move `panel/keymap.vim` → `ui/keymap.vim`
  - Rename: `skyrg#panel#keymap#*` → `skyrg#ui#keymap#*`
  - Add shim
  - Note: action names stay search-specific for now; will be generalized in Phase 2
- [x] Update all `panel/*.vim` imports to use `ui/` paths (via shims — callers unchanged)
- [x] Update `panel.vim` to use `ui/` paths (via shims — callers unchanged)
- [x] Run tests — all 83 pass
- [x] Commit: `refactor: extract generic UI primitives into skyrg/ui/` (2ae79f1)

### Shim pattern

```vim
" autoload/skyrg/panel/popup.vim (shim)
" DEPRECATED: Use skyrg#ui#popup#* directly. This shim exists for
" backward compatibility during the transition.
function! skyrg#panel#popup#create(content, opts) abort
  return skyrg#ui#popup#create(a:content, a:opts)
endfunction
function! skyrg#panel#popup#move(id, opts) abort
  call skyrg#ui#popup#move(a:id, a:opts)
endfunction
```

## Phase 2 — Window System + Pane Protocol

**Goal**: Create `ui/window.vim` with the declarative spec-based lifecycle,
and create generic pane implementations in `ui/panes/`. The search view
still lives in `panel.vim` but starts using the new pane protocol internally.

**Risk**: Medium — need to decouple panes from `skyrg#panel#state()`.

### Checklist

- [x] Create `ui/window.vim`
  - [x] `skyrg#ui#window#open(spec)` — create popups from spec, register filter + VimResized
  - [x] `skyrg#ui#window#close(handle)` — close all popups, cleanup
  - [x] Key dispatch: global_keys → active pane → ignore
  - [x] `set_active(name)` — pane switching with border highlights
  - [x] `reposition(handle)` — recompute layout, call pane.on_resize
  - [x] Layout engine: compute geometry from region + flex specs
- [x] Define pane protocol (as a documented dict shape — all panes implement render/on_key/on_focus/on_blur/on_resize/cleanup)
- [x] Create `ui/panes/list.vim` — generic scrollable list
  - [x] Parameterized by `format_item`, `on_select`, `on_accept`, `empty_text`
  - [x] Supports: Up/Down, PageUp/PageDown, Enter
  - [x] Scroll management (current `results.vim` logic, generalized)
- [x] Create `ui/panes/form.vim` — generic field editor
  - [x] Parameterized by field definitions (label, type, initial value)
  - [x] Supports: field navigation, text editing, cursor movement
  - [x] Field types: text, toggle, select, readonly
  - [x] Hint line support via `hint_fn` callback
- [x] Create `ui/panes/preview.vim` — generic file preview
  - [x] show_file(path, line) + show_file_with_syntax() + toggle_syntax()
  - [x] Syntax highlighting via hidden window (extracted from panel/preview.vim)
  - [x] Dynamic height (uses popup geometry, not fixed constant)
- [x] Create `ui/panes/info.vim` — read-only display
  - [x] Simple: set_lines/clear, renders them
  - [x] No key handling
- [x] Create `ui/panes/tree.vim` — generic directory tree
  - [x] Expand/collapse, scroll, configurable list_fn + on_select
- [x] Write unit tests: 76 new tests (test_ui_panes.vim + test_ui_window.vim)
- [x] Run full test suite — 159 pass, 0 fail
- [x] Commit: `refactor: window system + generic pane implementations` (15eb768)

## Phase 3 — Search View Extraction

**Goal**: Create `views/search.vim` that composes the generic panes with the
rg backend. `panel.vim` becomes a thin compatibility shim.

**Risk**: Medium — must preserve all existing behavior exactly.

### Checklist

**Approach**: Incremental. views/search.vim delegates to panel.vim for popup
lifecycle while adding query-loading capability. Panel modules continue using
`skyrg#panel#state()`. Full migration to generic window system deferred to
a future phase to avoid a risky big-bang rewrite.

- [x] Create `autoload/skyrg/views/search.vim`
  - [x] `skyrg#views#search#open(params)` — main entry point
  - [x] `skyrg#views#search#load_query(params)` — fill fields on open panel
  - [x] `skyrg#views#search#get_query()` — snapshot for history saving
  - [x] `skyrg#views#search#browse(matches, title)` — browse mode wrapper
  - [x] Support `params` dict for pre-filling fields (query loading)
  - [ ] Construct generic panes + `skyrg#ui#window#open(spec)` (future: full migration)
- [x] Extract rg backend: `backend/rg.vim`
  - [x] Conform to backend protocol: `run(params, callbacks)`, `cancel()`
  - [x] Generation counter for stale result rejection
  - [x] `schedule(params, callbacks, delay)` for debounced search
  - [x] Command builder extracted from panel/search.vim
  - [ ] Wire panel/search.vim to delegate to backend (future)
- [x] Modify `panel.vim` to accept params:
  - [x] `skyrg#panel#open(params)` — accepts optional params dict
  - [x] `s:apply_params()` — pre-fills form fields from params
  - [x] `skyrg#panel#state()`, `skyrg#panel#const()` — unchanged
  - [x] `skyrg#panel#browse()` — unchanged
- [x] Add `:SkyRG` command in plugin/skyrg.vim → routes to views/search
- [x] Add context key mapping support via `g:skyrg_context_key`
- [ ] Migrate `panel/complete.vim` and `panel/preset.vim` (keep in `panel/` for now)
- [x] Run full test suite — 168 pass, 0 fail
- [x] Commit: `refactor: search view + rg backend extraction` (ea23d0e)

## Phase 4 — Backend Extraction + History

**Goal**: Extract remaining backends, implement history persistence, wire
history into the search view.

**Risk**: Low-medium — new code, but additive.

### Checklist

- [ ] Create `backend/history.vim`
  - [ ] `save(entry)` — append to JSONL file
  - [ ] `load_all(project_root)` — read + parse + sort
  - [ ] `load_last(project_root)` — return newest entry
  - [ ] `search(project_root, filter)` — substring filter
  - [ ] `delete(project_root, timestamp)` — remove entry
  - [ ] `project_root()` — git root or cwd
  - [ ] Deduplication on save
  - [ ] Compaction on load (if > threshold)
- [ ] Wire history into search view:
  - [ ] On open: `load_last()` → pre-fill form (Feature 3)
  - [ ] On commit (Enter to results or jump): `save()` current query
  - [ ] Ctrl+Backspace: clear all fields (Feature 3a)
  - [ ] PageUp/PageDown: history navigation (Feature 4)
- [ ] Create `backend/favorites.vim`
  - [ ] `save(entry)`, `remove(idx)`, `load_all()`
- [ ] Run tests
- [ ] Commit: `feat: history persistence + in-search history navigation`

## Phase 5 — New Views

**Goal**: Build the history browser, favorites browser, context popup, and
build-error navigator using the generic pane system.

**Risk**: Low — purely additive, uses established patterns.

### Checklist

- [ ] Create `views/history.vim` — history browser
  - [ ] List pane with formatted history entries
  - [ ] Preview pane showing query details
  - [ ] Filter bar
  - [ ] Enter to open search with selected query
  - [ ] `d` to delete, `f` to favorite
- [ ] Create `views/favorites.vim` — favorites browser
  - [ ] Same pattern as history view
  - [ ] `e` to edit label
- [ ] Create `backend/context.vim` — action registry
  - [ ] `register(action)`, `get(context)`, `execute(action, context)`
  - [ ] Built-in actions (search word, search dir, search filetype)
  - [ ] User action registration via `g:skyrg_context_actions`
  - [ ] Filetype-specific actions via `g:skyrg_context_{ft}`
  - [ ] Helper predicates: `ft()`, `has_cmd()`, `always()`
- [ ] Create `views/context.vim` — context popup
  - [ ] Cursor-relative positioning
  - [ ] List pane with filtered actions
  - [ ] Number quick-select, letter filtering
  - [ ] Normal mode + visual mode support
- [ ] Create `views/build.vim` — build error navigator (basic)
  - [ ] Accept `{cmd, parser}` config
  - [ ] List pane (same shape as search results) + preview
- [ ] Add commands to `plugin/skyrg.vim`:
  - [ ] `:SkyRGHistory`, `:SkyRGFav`, `:SkyCtx`
  - [ ] Context key mapping via `g:skyrg_context_key`
- [ ] Write tests for new views
- [ ] Commit: `feat: history browser, favorites, context popup, build errors`

## Migration Timeline

```
Phase 1 ──→ Phase 2 ──→ Phase 3 ──→ Phase 4 ──→ Phase 5
  (safe)     (medium)    (medium)     (easy)      (easy)
  ~1 session ~2 sessions ~2 sessions  ~1 session  ~2 sessions
```

After Phase 3, the old `panel/` directory can be deleted (all functionality
lives in `ui/`, `views/`, and `backend/`). Keep shims in `panel.vim` for
any external callers.

## Rollback Strategy

At any phase, if things go wrong:
- `git stash` or `git checkout` to the last green commit.
- Each phase is a single logical commit, so reverting is one `git revert`.
- The shim pattern means old call sites never break during transition.
