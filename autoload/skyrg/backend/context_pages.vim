" autoload/skyrg/backend/context_pages.vim — Page definitions for context popup
"
" Manages paginated domains for the context popup.  Each page has:
"   - An index (0-9) mapped to a keyboard key
"   - A name shown in the tab bar
"   - An optional page-level predicate (hide page when false)
"   - An optional 'auto' flag (auto-switch when predicate matches)
"
" Pages are configured via g:skyrg_pages and g:skyrg_group_pages.
" Actions are assigned to pages through their 'group' field.
"
" Keyboard ordering (left to right): 1 2 3 4 5 6 7 8 9 0
" This matches the physical key layout for arrow navigation.

" Keyboard order for left/right navigation
let s:key_order = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]

" Last opened page index (persists across popup opens)
let s:current_page = -1

"==============================================================================
" Configuration
"==============================================================================

" Returns the page definitions dict. { index: {name, predicate?, auto?} }
function! skyrg#backend#context_pages#get_pages() abort
  return get(g:, 'skyrg_pages', {})
endfunction

" Returns the group-to-page mapping dict. { group_name: page_index }
function! skyrg#backend#context_pages#get_group_map() abort
  return get(g:, 'skyrg_group_pages', {})
endfunction

"==============================================================================
" Page resolution
"==============================================================================

" Determine which page an action belongs to based on its group.
" Returns -1 if unmapped (action won't appear on any page).
function! skyrg#backend#context_pages#page_for_action(action) abort
  let l:group = get(a:action, 'group', '')
  if empty(l:group) | return -1 | endif
  let l:map = skyrg#backend#context_pages#get_group_map()
  return get(l:map, l:group, -1)
endfunction

" Get actions for a specific page, filtered by their predicates.
function! skyrg#backend#context_pages#actions_for_page(page_idx, all_actions, ctx) abort
  let l:result = []
  for l:a in a:all_actions
    if skyrg#backend#context_pages#page_for_action(l:a) == a:page_idx
      if !has_key(l:a, 'predicate') || l:a.predicate(a:ctx)
        call add(l:result, l:a)
      endif
    endif
  endfor
  return l:result
endfunction

"==============================================================================
" Page visibility — which pages have content right now
"==============================================================================

" Returns a list of page indices (in keyboard order) that are visible:
" i.e., the page is defined, its page-level predicate passes, and it has
" at least one visible action.
function! skyrg#backend#context_pages#visible_pages(all_actions, ctx) abort
  let l:pages = skyrg#backend#context_pages#get_pages()
  let l:visible = []
  for l:idx in s:key_order
    let l:sidx = string(l:idx)
    if !has_key(l:pages, l:sidx) && !has_key(l:pages, l:idx)
      continue
    endif
    let l:page = has_key(l:pages, l:idx) ? l:pages[l:idx] : l:pages[l:sidx]
    " Page-level predicate
    if has_key(l:page, 'predicate') && !l:page.predicate()
      continue
    endif
    " Must have at least one visible action
    if !empty(skyrg#backend#context_pages#actions_for_page(l:idx, a:all_actions, a:ctx))
      call add(l:visible, l:idx)
    endif
  endfor
  return l:visible
endfunction

"==============================================================================
" Navigation state
"==============================================================================

" Get the current page index. Returns -1 if unset.
function! skyrg#backend#context_pages#current() abort
  return s:current_page
endfunction

" Set the current page index.
function! skyrg#backend#context_pages#set_current(idx) abort
  let s:current_page = a:idx
endfunction

" Determine which page to open to.
" Priority: auto-page (if matched) > last-opened > first visible page.
function! skyrg#backend#context_pages#resolve_open_page(all_actions, ctx) abort
  let l:visible = skyrg#backend#context_pages#visible_pages(a:all_actions, a:ctx)
  if empty(l:visible) | return -1 | endif
  let l:pages = skyrg#backend#context_pages#get_pages()

  " Check for auto-switch pages
  for l:idx in l:visible
    let l:sidx = string(l:idx)
    let l:page = has_key(l:pages, l:idx) ? l:pages[l:idx] : l:pages[l:sidx]
    if get(l:page, 'auto', 0)
      return l:idx
    endif
  endfor

  " Last opened, if still visible
  if s:current_page >= 0 && index(l:visible, s:current_page) >= 0
    return s:current_page
  endif

  " Default: first visible
  return l:visible[0]
endfunction

" Navigate to the next visible page (wrapping). dir = 1 (right) or -1 (left).
function! skyrg#backend#context_pages#navigate(dir, all_actions, ctx) abort
  let l:visible = skyrg#backend#context_pages#visible_pages(a:all_actions, a:ctx)
  if len(l:visible) <= 1 | return s:current_page | endif

  let l:cur_pos = index(l:visible, s:current_page)
  if l:cur_pos < 0
    let s:current_page = l:visible[0]
    return s:current_page
  endif

  let l:new_pos = (l:cur_pos + a:dir) % len(l:visible)
  if l:new_pos < 0 | let l:new_pos += len(l:visible) | endif
  let s:current_page = l:visible[l:new_pos]
  return s:current_page
endfunction

" Jump to a specific page index. No-op if page is not visible.
function! skyrg#backend#context_pages#jump(idx, all_actions, ctx) abort
  let l:visible = skyrg#backend#context_pages#visible_pages(a:all_actions, a:ctx)
  if index(l:visible, a:idx) >= 0
    let s:current_page = a:idx
  endif
  return s:current_page
endfunction

" Return the keyboard ordering constant for external use.
function! skyrg#backend#context_pages#key_order() abort
  return copy(s:key_order)
endfunction

" Get page definition by index. Returns {} if not defined.
function! skyrg#backend#context_pages#get_page(idx) abort
  let l:pages = skyrg#backend#context_pages#get_pages()
  let l:sidx = string(a:idx)
  if has_key(l:pages, a:idx) | return l:pages[a:idx] | endif
  if has_key(l:pages, l:sidx) | return l:pages[l:sidx] | endif
  return {}
endfunction
