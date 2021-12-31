" initially written by jerry.feng, modified by... you?
" Dec 30, 2021 -- version 1.0

" ==================================================================================================
" Util methods 
" ==================================================================================================
let g:Report={}
let g:sky_verbose=0

" Echo 'Status'
function g:Report.s(...)
    if (a:0 == 1)
        echom a:1
    elseif (a:0 > 1)
        let l:fmt_str = a:1
        let l:subs = a:000[1:len(a:000)]
        echom call(function('printf'), a:000)
    else
        echom a:000
    endif
endfunction

" Echo 'Debug'
function g:Report.d(...)
    if (g:sky_verbose)
        if (a:0 == 1)
            echom a:1
        elseif (a:0 > 1)
            let l:fmt_str = a:1
            let l:subs = a:000[1:len(a:000)]
            echom call(function('printf'), a:000)
        else
            echom a:000
        endif
    endif
endfunction

" Echo 'Error'
function g:Report.e(...)
    if (a:0 == 1)
        echoe a:1
    elseif (a:0 > 1)
        let l:fmt_str = a:1
        let l:subs = a:000[1:len(a:000)]
        echoe call(function('printf'), a:000)
    else
        echoe a:000
    endif
endfunction

function g:ListToDelimitedString(list, delimiter)
  let l:output = ''
  for value in a:list
    if (len(l:output) == 0)
      let l:output = value
    else 
      let l:output = l:output . a:delimiter . value
    endif
  endfor

  return l:output
endfunction

" ==================================================================================================
" Search preset implementation
" ==================================================================================================
let g:SkyFilter={}
let g:TypeKey='type'
let g:DirKey='dir'

" Global state =====================================================================================
" all filters created are registered in this dict
let g:SkyFilter.presets = {}
" Key for the default base filter used in the search. If no such key exists, an empty filter will
" be constructed for use
let g:SkyFilter.default = 'DEFAULT_FILTER' 

" Init =============================================================================================
function g:SkyFilter.new(name)
    let l:new_preset = copy(self)

    let l:new_preset.name = a:name

      " In these dicts:
      " - if an entry has a value of 1, it is specifically included in the globbing options
      " - if an entry has a value of 0, it is specifically ignored in the globbing options
    let l:new_preset[g:DirKey] = {}
    let l:new_preset[g:TypeKey] = {}

    " Register filter into global presets 
    if (has_key(g:SkyFilter.presets, a:name))
      call g:Report.d("New filter supercedes pre-existing filter with same name!")
    endif
    let g:SkyFilter.presets[a:name] = l:new_preset

    return l:new_preset 
endfunction

" TODO: Do I still even want this?
function g:SkyFilter.new_from(name, desired_types, ignored_types, desired_dirs, ignored_dirs)
    let l:new_preset = g:SkyFilter.new(a:name)

    let l:allow_overwrites = 1
    call l:new_preset._set_filetypes(a:desired_types, 1, l:allow_overwrites)
    call l:new_preset._set_filetypes(a:ignored_types, 0, l:allow_overwrites)
    call l:new_preset._set_dirs(a:desired_dirs, 1, l:allow_overwrites)
    call l:new_preset._set_dirs(a:ignored_dirs, 0, l:allow_overwrites)

    return l:new_preset
endfunction

" Private methods ==================================================================================
function g:SkyFilter._set(bucket, key, value, overrides_existing)
    if (!has_key(self, a:bucket))
        call g:Report.d("Ignoring set call, no bucket [%s]", a:bucket)
        return
    endif

    if (has_key(self[a:bucket], a:key) && !a:overrides_existing)
        call g:Report.d("Ignoring override for [%s]: %s -> %s", a:key, self[a:bucket][a:key], a:value)
        return
    endif

    let self[a:bucket][a:key] = a:value
    call g:Report.d("Set %s [%s]: %s", a:bucket, a:key, a:value)
endfunction

function g:SkyFilter._set_filetype(filetype, is_desired, overrides_existing)
    call self._set(g:TypeKey, a:filetype, a:is_desired, a:overrides_existing)
endfunction

function g:SkyFilter._set_filetypes(filetypes, is_desired, overrides_existing)
    for filetype in a:filetypes
        call self._set_filetype(filetype, a:is_desired, a:overrides_existing)
    endfor
endfunction

function g:SkyFilter._set_dir(dir, is_desired, overrides_existing)
    call self._set(g:DirKey, a:dir, a:is_desired, a:overrides_existing)
endfunction

function g:SkyFilter._set_dirs(dirs, is_desired, overrides_existing)
    for dir in a:dirs
        call self._set_dir(dir, a:is_desired, a:overrides_existing)
    endfor
endfunction

function g:SkyFilter._get(bucket, with_value) 
    let output = [] 
    if (!has_key(self, a:bucket))
        call g:Report.d("Returning empty list, no bucket [%s]", a:bucket)
        return output
    endif

    for key in keys(self[a:bucket])
        if (self[a:bucket][key] == a:with_value)
            call add(output, key)
        endif
    endfor

    return output
endfunction

function g:SkyFilter._get_desired_types()
    return self._get(g:TypeKey, 1)
endfunction

function g:SkyFilter._get_ignored_types()
    return self._get(g:TypeKey, 0)
endfunction

function g:SkyFilter._get_desired_dirs()
    return self._get(g:DirKey, 1)
endfunction

function g:SkyFilter._get_ignored_dirs()
    return self._get(g:DirKey, 0)
endfunction

function g:SkyFilter._print()
    call g:Report.s("Search preset: %s", self.name)
    call g:Report.s("  desired_types: %s", self._get_desired_types())
    call g:Report.s("  ignored_types: %s", self._get_ignored_types())
    call g:Report.s("  desired_dirs: %s", self._get_desired_dirs())
    call g:Report.s("  ignored_dirs: %s", self._get_ignored_dirs())
endfunction

" Public interface +================================================================================
function g:SkyFilter.include_filetypes(filetypes)
    let l:allow_overwrites = 1
    call self._set_filetypes(a:filetypes, 1, l:allow_overwrites)
    let g:SkyFilter.presets[self.name] = self
    return self
endfunction

function g:SkyFilter.ignore_filetypes(filetypes)
    let l:allow_overwrites = 1
    call self._set_filetypes(a:filetypes, 0, l:allow_overwrites)
    let g:SkyFilter.presets[self.name] = self
    return self
endfunction

function g:SkyFilter.include_dirs(dirs)
    let l:allow_overwrites = 1
    call self._set_dirs(a:dirs, 1, l:allow_overwrites)
    let g:SkyFilter.presets[self.name] = self
    return self
endfunction

function g:SkyFilter.ignore_dirs(dirs)
    let l:allow_overwrites = 1
    call self._set_dirs(a:dirs, 0, l:allow_overwrites)
    let g:SkyFilter.presets[self.name] = self
    return self
endfunction

function g:SkyFilter.merge(other_preset)
    " Merge another preset into this preset. If there are collisions, this filter trumps
    if (has_key(a:other_preset, g:TypeKey) && has_key(a:other_preset, g:DirKey))
        let l:allow_overwrites = 0
        call self._set_filetypes(a:other_preset._get_desired_types(), 1, l:allow_overwrites)
        call self._set_filetypes(a:other_preset._get_ignored_types(), 0, l:allow_overwrites)
        call self._set_dirs(a:other_preset._get_desired_dirs(), 1, l:allow_overwrites)
        call self._set_dirs(a:other_preset._get_ignored_dirs(), 1, l:allow_overwrites)
    endif
endfunction

function g:SkyFilter.apply_base(base)
    " Works kind of like merge, but does what the 'user would expect':
    " - If any specifically included types or directories are specified in base_preset, we do not
    "   apply the other preset's 'desired' value. For example, if we specified '-f vimrc', we do not
    "   want the filter to apply the default 'cc,h,...' we usually have.
    " - Applies any unspecified ignores, e.g. if I didn't specify 'build' in the this filter's
    "   ignored directories dict, I want to apply base's rule on 'build'. Otherwise respects what
    "   was already in this 
    " Note that you lose information across calls to 'apply base'. Good enough for now.
    if (has_key(a:base, g:TypeKey) && has_key(a:base, g:DirKey))
        let l:allow_overwrites = 0
        if (len(self._get_desired_types()) == 0)
            call self._set_filetypes(a:base._get_desired_types(), 1, l:allow_overwrites)
        endif
        if (len(self._get_desired_dirs()) == 0) 
            call self._set_dirs(a:base._get_desired_dirs(), 1, l:allow_overwrites)
        endif

        call self._set_filetypes(a:base._get_ignored_types(), 0, l:allow_overwrites)
        call self._set_dirs(a:base._get_ignored_dirs(), 0, l:allow_overwrites)
    endif
endfunction

function g:SkyFilter.get_globbing_flags()
  let l:output = ''

  let l:desired_types = g:ListToDelimitedString(self._get_desired_types(), ',')
  let l:ignored_types = g:ListToDelimitedString(self._get_ignored_types(), ',')
  
  if (len(l:desired_types) > 0)
    let l:output = l:output . printf("-g '*.{%s}' ", l:desired_types)
  endif
  if (len(l:ignored_types) > 0)
    let l:output = l:output . printf("-g '!*.{%s}' ", l:ignored_types)
  endif

  let l:ignored_dirs = self._get_ignored_dirs()
  for dir in l:ignored_dirs

    if (len(dir) > 1 && dir[-2] == '/')
      let dir = dir[:-2]
    endif
    let l:output = l:output . printf("-g '!%s/**' ", dir)
  endfor

  return l:output
endfunction

function g:SkyFilter.get_search_directories()
  " Returns the 'string representation' of all the directories we wish to search in, empty string if
  " nothing specified (searches current directory)
  " TODO(jfeng): Maybe have it 'intelligently' find git root of project?
  let l:output = ''
  let l:desired_dirs = self._get_desired_dirs()

  for dir in l:desired_dirs
    let l:output = l:output . ' ' . dir
  endfor

  return l:output
endfunction

function! SkyRG( ... )
  " Usage:
  "   SkyRG([-f|-Nf file_extensions] [-d|Nd directories] [-p preset_name] [-n] query)
  "
  " Passes in some filtering options for rg, note that all options must come before the query.
  " Anything that is not parsed as an option (and potential following argument).
  "
  " Additionally, arguments that can 'be a list' are comma delimited.
  "
  " An example using the RG command I've set up below:
  "     :RG -f cc,lcm -d mobile/shared/mvvm,infrastructure/ar_video_shaders prism_t
  "
  " Options:
  "  --) Everything after this flag is considered part of the query. Useful if part of your query
  "      would have been interpreted as a flag
  "
  "  -f) Specifically search within the filetypes listed in the next argument.
  "      For example, ':RG -f cc,h,lcm <QUERY>' will only search in *.cc *.h and *.lcm files
  "      Can be specified multiple times, for instance ':RG -f cc -f h -f lcm <QUERY>'
  "
  "  -Nf) Specifically ignore filetypes listed in the next argument. Works like '-f'
  "
  "  -d) Specifically search within the directories listed in the next argument.
  "      For example, ':RG -d mobile/shared/appcore,mobile/shared/mvvm' will change the 'root
  "      search' directories to look within 'appcore' and 'mvvm' and will not include the 'cwd'
  "      those relative directories.
  "      Note that for 'proper' search filtering to work, you should pass in directories without the
  "      trailing slash.
  "
  "  -Nf) Specifically ignore directories listed in the next argument. Should be passed in like a
  "      '-d' argument, but does not effect the 'root directories' being searched.
  "
  "  -p) Base off preset defined in your vimrc. This has some interesting behavior to discuss:
  "      - If any specific includes are specified, the specified preset's includes are ignored. 
  "      - The preset's ignores are always applied, unless already explicitly specified in the
  "        command.
  "      This allows us to set some general base preset for a project, i.e.
  "         let my_preset = g:SkyFilter.new("base_preset")
  "                                  \ .include_filetypes(['cc', 'h', 'py'])
  "                                  \ .include_dirs(['some_submodule'])
  "                                  \ .ignore_filetypes(['vim', 'sh'])
  "                                  \ .ignore_dirs(['**/node_modules'])
  "
  "       but also allows us to search outside of the predefined include scope, for example:
  "         :RG -f vim,vimrc,yaml -d other_submodule <QUERY>
  "
  "       should allow us to search within *only* those filetypes (including 'vim' we previously
  "       ignored from the base) in the other_submodule given, while continuing to filter out '.sh'
  "       files and any and all 'node_modules' directories we may find along the way.
  "
  " Current Limitations:
  "  - Would love to have tab-completion for directory searching
  "
  "  - Can't change the filtering parameters once FZF's popup comes up
  "
  "  - Upon closer inspection, -Nd is very close just generic glob patterns. Should set up
  "    an option for generic regex and a 'directories' flag. Maybe the main difference is how
  "    autocomplete will work with it.
  "
  "  - My vimscript is bad and it should feel bad. Lots of repeated code because I don't know a
  "    better way at the moment
  "=================================================================================================

  let rg_filter = g:SkyFilter.new("ACTIVE RG QUERY")
  let preset_name = ''
  let query=''
  let query_started=0

  " Parse arguments, then build query.
  let num_args = len(a:000)
  let curr_idx = 0
  while curr_idx < num_args
    let arg = a:000[curr_idx]
    if (!query_started)
        if (arg == '--') " Ignore all subsequent possible flags
            call g:Report.d("Ignoring all future flags")
            let query_started = 1
            let curr_idx = curr_idx + 1
            continue " Don't append this to the query
        elseif (arg == '-f' || arg == '-Nf' || arg == '-d' || arg == '-Nd')
            " Process all non-optional following list argument together
            if (curr_idx + 1 < num_args)
                let curr_idx = curr_idx + 1
                let option = a:000[curr_idx]
                let split = split(option, ',') 
                if (arg == '-f')
                    call rg_filter._set_filetypes(split, 1, 1)
                elseif (arg == '-Nf')
                    call rg_filter._set_filetypes(split, 0, 1)
                elseif (arg == '-d')
                    call rg_filter._set_dirs(split, 1, 1)
                elseif (arg == '-Nd')
                    call rg_filter._set_dirs(split, 0, 1)
                endif
            else
                g:Report.e("No argument for %s flag?", arg)
            endif
        elseif (arg == '-p')
            " Process all with a non-optional following single argument together, for DRY
            if (curr_idx + 1 < num_args)
                let curr_idx = curr_idx + 1
                let preset_name = a:000[curr_idx]
                call g:Report.d("Got base preset " . preset_name)
            else
                g:Report.e("No argument for %s flag?", arg)
            endif " next argument is valid
        else
          " Not a flag, starting query concatenation
          let query_started = 1
        endif 
    endif " !query_started

    if (query_started)
      if (len(query) == 0)
        let query = arg 
      else
        let query = printf('%s %s', query, arg) 
      endif
    endif " query_started

    let curr_idx = curr_idx + 1
  endwhile
  
  " Get, then rebase on preset filter. Fall back to default if necessary
  let base_preset_name = g:SkyFilter.default
  if (preset_name != '' && has_key(g:SkyFilter.presets, preset_name))
    let base_preset_name = preset_name
  else
    if (!has_key(g:SkyFilter.presets, g:SkyFilter.default))
      call g:SkyFilter.new(g:SkyFilter.default)
    endif
    let base_preset_name = g:SkyFilter.default
  endif

  let base_preset = g:SkyFilter.presets[base_preset_name]
  call rg_filter.apply_base(base_preset)

  " Construct ripgrep command
  let l:globbing_flags = rg_filter.get_globbing_flags()
  let l:search_dirs = rg_filter.get_search_directories()
  let command_fmt = 'rg --column --line-number --no-heading --color=always --smart-case
              \ %s -- %s  %s || true
              \'

  let initial_command = printf(command_fmt, l:globbing_flags, shellescape(query), l:search_dirs)
  let reload_command = printf(command_fmt, l:globbing_flags, '{q}', l:search_dirs)

  call g:Report.d("Got initial command " . initial_command)
  call g:Report.d("Got reload command " . reload_command)

  let spec = {'options': ['--phony', '--query', query, '--bind', 'change:reload:'.reload_command]}
  call fzf#vim#grep(initial_command, 1, fzf#vim#with_preview(spec), 0)
endfunction

