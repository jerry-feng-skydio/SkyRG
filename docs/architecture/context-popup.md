# Context Popup System

> **Status**: Proposal

## Concept

The context popup is a **cursor-relative action menu** that shows only
actions relevant to the current editing context (filetype, word under cursor,
project structure, etc.). It is the universal dispatch point — every SkyRG
feature becomes accessible through contextually filtered actions.

## User Experience

1. User is in normal mode, cursor on a function name in a `.cpp` file.
2. User presses the context key (e.g., `<Leader>a`).
3. A small popup appears near the cursor:
   ```
   ╭──────────────────────────────╮
   │ 1  Find callers              │
   │ 2  Go to definition          │
   │ 3  Search in this directory  │
   │ 4  Run build                 │
   ╰──────────────────────────────╯
   ```
4. User presses `1` or navigates with Up/Down and presses Enter.
5. The selected action runs (e.g., opens SkyRG search with the function
   name pre-filled).

### Interaction model

| Key | Action |
|---|---|
| `Up`/`Down` | Navigate action list |
| `Enter` | Execute selected action |
| `1`-`9` | Quick-select by number |
| `Esc` | Close popup |
| Any letter | Filter actions by label (fuzzy or prefix) |

### From visual mode

If triggered from visual mode, the context includes the selected text.
Actions can use `context.visual` instead of `context.word`:

```
╭──────────────────────────────╮
│ 1  Search for "my_function"  │
│ 2  Search in all files       │
│ 3  Add to favorites          │
╰──────────────────────────────╯
```

## Architecture

### Components

```
┌──────────────┐     ┌──────────────────┐     ┌────────────────┐
│ User trigger │ ──→ │ context backend   │ ──→ │ context view   │
│ (mapping)    │     │ (filter + sort    │     │ (list pane +   │
│              │     │  actions by ctx)  │     │  cursor popup) │
└──────────────┘     └──────────────────┘     └────────────────┘
                             │
                     ┌───────┴────────┐
                     │                │
              ┌──────┴──────┐  ┌─────┴──────┐
              │ Built-in    │  │ User-      │
              │ actions     │  │ defined    │
              │             │  │ actions    │
              └─────────────┘  └────────────┘
```

### Context dict

Computed once when the popup is triggered, passed to all `when` predicates
and `run` handlers:

```vim
function! s:build_context(visual) abort
  let ctx = {
    \ 'word':       expand('<cword>'),
    \ 'WORD':       expand('<cWORD>'),
    \ 'line':       getline('.'),
    \ 'lnum':       line('.'),
    \ 'col':        col('.'),
    \ 'file':       expand('%:p'),
    \ 'filetype':   &filetype,
    \ 'bufnr':      bufnr('%'),
    \ 'visual':     a:visual,
    \ 'git_root':   s:git_root(),
    \ 'cwd':        getcwd(),
    \ 'has_lsp':    s:has_lsp(),
    \ }
  return ctx
endfunction
```

### Action registration

#### Built-in actions

Shipped with SkyRG. Registered on plugin load:

```vim
" In autoload/skyrg/backend/context.vim

let s:builtins = [
  \ {
  \   'label': 'Search for "%s"',
  \   'label_fn': {ctx -> printf('Search for "%s"', ctx.word)},
  \   'when': {ctx -> !empty(ctx.word)},
  \   'run': {ctx -> skyrg#views#search#open({'query': ctx.word})},
  \   'priority': 10,
  \ },
  \ {
  \   'label': 'Search in this directory',
  \   'when': {ctx -> !empty(ctx.file)},
  \   'run': {ctx -> skyrg#views#search#open({
  \     'dirs': fnamemodify(ctx.file, ':h')
  \   })},
  \   'priority': 20,
  \ },
  \ {
  \   'label': 'Search this filetype',
  \   'when': {ctx -> !empty(ctx.filetype)},
  \   'run': {ctx -> skyrg#views#search#open({
  \     'query': ctx.word, 'types': ctx.filetype
  \   })},
  \   'priority': 30,
  \ },
  \ {
  \   'label': 'Go to definition',
  \   'when': {ctx -> ctx.has_lsp && !empty(ctx.word)},
  \   'run': {ctx -> execute('YcmCompleter GoToDefinition')},
  \   'priority': 5,
  \ },
  \ {
  \   'label': 'Find references',
  \   'when': {ctx -> ctx.has_lsp && !empty(ctx.word)},
  \   'run': {ctx -> skyrg#panel#ycm_refs()},
  \   'priority': 6,
  \ },
  \ ]
```

#### User-defined actions

In `.vimrc`:

```vim
let g:skyrg_context_actions = [
  \ {
  \   'label': 'Run bazel build',
  \   'when': skyrg#backend#context#ft('cpp'),
  \   'run': function('MyBazelBuild'),
  \   'priority': 50,
  \ },
  \ {
  \   'label': 'Open header/source',
  \   'when': {ctx -> ctx.filetype =~# '^\(c\|cpp\)$'},
  \   'run': {ctx -> execute('edit ' . s:swap_h_cpp(ctx.file))},
  \   'priority': 15,
  \ },
  \ ]
```

#### Filetype-specific actions

For cleaner organization:

```vim
let g:skyrg_context_cpp = [
  \ {'label': 'View AST', 'run': function('MyViewAST'), 'priority': 60},
  \ ]
let g:skyrg_context_python = [
  \ {'label': 'Run pytest', 'run': function('MyRunPytest'), 'priority': 60},
  \ ]
```

These are automatically registered with `when` = filetype match.

### Action filtering and sorting

```vim
function! skyrg#backend#context#get(context) abort
  let all_actions = s:builtins
    \ + get(g:, 'skyrg_context_actions', [])
    \ + s:filetype_actions(a:context.filetype)
  
  " Filter: keep only actions where when(context) is true
  let filtered = filter(copy(all_actions),
    \ {_, a -> !has_key(a, 'when') || a.when(a:context)})
  
  " Sort by priority (lower = higher in list)
  call sort(filtered, {a, b -> get(a, 'priority', 50) - get(b, 'priority', 50)})
  
  return filtered
endfunction
```

### Action execution

```vim
function! skyrg#backend#context#execute(action, context) abort
  " Close the context popup first
  call skyrg#views#context#close()
  
  " Resolve dynamic label if present
  " Then call the run handler
  call a:action.run(a:context)
endfunction
```

## Popup positioning

The context popup appears near the cursor, not centered like other windows.
Placement logic:

```vim
function! s:cursor_position() abort
  let row = screenrow()
  let col = screencol()
  let lines_below = &lines - row
  let lines_above = row - 1
  
  " Prefer below cursor, fall back to above if not enough room
  if lines_below >= 6
    return {'line': row + 1, 'col': col}
  else
    return {'line': row - s:popup_height, 'col': col}
  endif
endfunction
```

The popup width auto-sizes to the longest label (with a min/max).
Height = number of visible actions (capped at 12).

## Edge Cases

### No matching actions

If no actions pass the `when` filter, either:
- Don't show the popup at all (preferred — less intrusive)
- Show a single dim line: "No actions available"

### Slow `when` predicates

- `when` functions must be synchronous and fast (< 1ms each).
- Document this requirement clearly.
- The context dict is computed once and reused for all predicates.
- If a user needs an async check (e.g., "is there a BUILD file?"), they
  should cache the result in a buffer-local variable.

### Action opens another SkyRG window

When an action calls `skyrg#views#search#open(...)`, the context popup
closes first, then the search window opens. No nested popup conflicts.

### Rapid re-triggering

If the user opens the context popup, closes it, and immediately re-opens:
- The context dict is recomputed (cursor may have moved).
- No stale state leaks.

## Integration with other features

### Search → Context

From the results pane, a future key binding could open the context popup
for the selected match's file/line, enabling "drill-down" workflows.

### History → Context

"Re-run this search" is naturally a context action on history entries.

### Build → Context

"Run build" is a context action. Build errors are displayed in a build
view (list + preview, same `{file, line, col, text}` shape as search
results). From the build error list, the context popup could offer
"Search for this symbol" or "Go to definition."

## Configuration

```vim
" Trigger key (default: none — user must set this)
" We don't ship a default because we don't want to clobber user mappings.
let g:skyrg_context_key = '<Leader>a'

" In plugin/skyrg.vim:
if exists('g:skyrg_context_key')
  execute 'nnoremap' g:skyrg_context_key ':call skyrg#views#context#open("n")<CR>'
  execute 'vnoremap' g:skyrg_context_key ':<C-u>call skyrg#views#context#open("v")<CR>'
endif
```
