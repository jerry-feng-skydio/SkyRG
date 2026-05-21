" autoload/skyrg/ui/panes/info.vim — Read-only information display pane
"
" A simple pane that displays line dicts set by the view. No key handling.
" Conforms to the pane protocol.
"
" Usage:
"   let pane = skyrg#ui#panes#info#new({'title': 'Info'})
"   call pane.set_lines([skyrg#ui#util#line('Hello')])

"==============================================================================
" Constructor
"==============================================================================

function! skyrg#ui#panes#info#new(config) abort
  let l:pane = {
    \ 'name':   '',
    \ 'config': a:config,
    \ 'state':  {'lines': [{'text': ''}]},
    \ '_geo':   {'height': 7, 'width': 30},
    \ }

  function! l:pane.render() dict abort
    return self.state.lines
  endfunction

  function! l:pane.on_key(key, K) dict abort
    return 0
  endfunction

  function! l:pane.on_focus() dict abort
  endfunction

  function! l:pane.on_blur() dict abort
  endfunction

  function! l:pane.on_resize(geo) dict abort
    let self._geo = a:geo
  endfunction

  function! l:pane.cleanup() dict abort
  endfunction

  " --- Public helpers ---

  function! l:pane.set_lines(lines) dict abort
    let self.state.lines = a:lines
  endfunction

  function! l:pane.clear() dict abort
    let self.state.lines = [{'text': ''}]
  endfunction

  return l:pane
endfunction
