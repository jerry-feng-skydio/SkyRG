# SkyRG
Small vimscript wrapper for fzf + rg search to allow for some search option configuration

# Installation
Note: Requires the vim plugin `'junngunn/fzf'` and the ripgrep (`rg`) command installed on your system.

Then you can install it like any basic plugin:

```
Plug 'jerry-feng-skydio/SkyRG'
```

etc etc

# Quick start
## Create a search function for yourself:
Here's mine as an example:
```
" Calls SkyRG normally (arguments following 'RG' are passed in as <f-args>
command! -nargs=* -bang RG call SkyRG(<f-args>)

" Calls SkyRG and assumes the everything after 'RGN' is the query
command! -nargs=* -bang RGN call SkyRG('--', <f-args>)
```

## Using the search function
You can pass flags into the function call to modify your search scope.
Read `docs/skyrg.txt` for more details.

High level, you can use the following flags
```
-- ) everything after this is part of the query.
-f ) include filetypes (comma-delimited list)
-Nf) ignore filetypes (comma-delimited list)
-d ) include directories (comma-delimited list)
-Nd) ignore directories (comma-delimited list)
```
The function passes the args 1 word at a time. The moment it can't parse a flag and its option, it assumes the query has started.
Many of these flags take a comma-delimited list, for example `cc,h,lcm,proto` or `build,**/node_modules`.

So for instance, with my command above, I can search for only c++ files in the `tools/` directory
```
:RG -f cc,cpp,h -d tools cool thing I'm looking for
```

If your query happens to start with something that could be read as a flag, use `--`
For instance, if I wanted to search for the part of the function call above in this repo:
```
:RG -f md -- -f cc,cpp,h
```

Ordering matters, the following search would actually ignore cc files, despite it being included earlier.
```
:RG -f cc -nF cc -- shared_from_this()
```

You can change the base search filter to pre-made presets on the fly. For more about presets see below.
```
:RG -p ios_dev CoolSwiftClass
```

# Creating filter presets
Generally, you will set up filters with the `g:SkyFilter.new` function.
```
call g:SkyFilter.new("my_awesome_filter")
```

You don't really have to keep track of this filter, it's registered into a singleton filter dict that the SkyRG function uses to find defaults/presets you pass in through the command.

Once you have a filter, you can call:
`.include_filetypes([])`
`.ignore_filetypes([])`
`.include_dirs([])`
`.ignore_dirs([])`

These all take a list of strings, and return the filter, so that you can chain filter methods:
```
call g:SkyFilter.new("my_awesome_filter")
              \ .include_filetypes(['cpp', 'h'])
              \ .include_dirs(['my_cool_project'])
              \ .ignore_filetypes(['idk'])
              \ .ignore_dirs(['my_cool_project/lame_submodule'])
```
Note that `include_filetypes` inherently hides `ignore_filetypes` based on how rg actually works (for example if we specifically included the types `['cc', 'h']` and ignored `['py', 'js']`, the ignores technically don't matter since they normally wouldn't match the include filetypes specifications anyways. Now I know you could probably break/abuse this if you took a look at the code and thought about it a bit, but ¯\\_(ツ)_/¯

Once you have some filter presets, you can set the base preset that will RG will "default" to.
```
call g:SkyFilter.new("my_awesome_filter")
              \ .include_filetypes(['cpp', 'h'])
              \ .include_dirs(['my_cool_project'])
              \ .ignore_filetypes(['idk'])
              \ .ignore_dirs(['my_cool_project/lame_submodule'])
let g:SkyFilter.default = "my_awesome_filter"
```

The intended experience is that you can specify presets you use frequently, but have the flexibility to be more granular with one-off search flags.

## Applying command line filters to defaults
Applying a filter on top of a set of defaults is not as straightfoward logically as overwriting all the default values with our new filter.

Therefore, when you supply command-buffer-time filter options on top of a filter preset, there are a few interesting behaviors to note:
### Include collisions
If any specific `includes` are specified in our command, the preset's includes are ignored. This prevents us from simply adding filetypes, which would actually widen the scope of the search.

### Ignore collisions
If the preset has any `ignores` those are always applied unless the command specifically includes that ignore. Generally files you go out of your way to ignore are files that you always wish to ignore, unless specified explicitly.

### Consequences of my actions
Say you have this set up in your vimrc
```
call g:SkyFilter.new("empty")
call g:SkyFilter.new("my_awesome_filter")
              \ .include_filetypes(['cpp', 'h'])
              \ .include_dirs(['my_cool_project'])
              \ .ignore_dirs(['my_cool_project/lame_submodule'])
let g:SkyFilter.default = "empty"
```

Then later you call
```
:RG -p my_awesome_filter -f py,js -- where is this code anyways
```
ripgrep will only search in .py and .js files, but will still ignore `lame_submodule`

Likewise, with `-Nf`
```
:RG -p my_awesome_filter -Nf cc -- where is this code anyways
```
ripgrep will only search in .h files, and will still ignore `lame_submodule`

Another example
```
:RG -p my_awesome_filter -d my_cool_project/lame_submodule -- where is this code anyways
```
ripgrep will only search in the `lame_submodule`, but still only in c++ files.

Lastly:
```
:RG -p my_awesome_filter -Nd my_cool_project/other_submodule -- where is this code anyways
```
ripgrep will also exclude `other_submodule`, and only c++ files.

Generally, the intent is that each action of manually specifying something will make the search more specific.

## Example .vimrc filters
Here's mine from my .vimrc for an example. I've even got a little check to see what my current working directory is, and sets up the presets depending on where I'm working.
```
" Default configurations
let s:ac_types = ['py', 'cc', 'h', 'lcm', 'proto', 'djinni', 'mm', 'm', 'swift', 'java', 'kt', 'cmake']
let s:ac_ignore_types = []

" NOTE: All directory paths are relative.
" Also, if search dirs is empty, rg will search where vim was executed.
let s:ac_search_dirs = []
let s:ac_ignore_dirs = [
    \ 'build',
    \ 'third_party_modules',
    \ 'third_party',
    \ 'bazel-out',
    \ '**/node_modules',
    \ ]

let s:cwd = getcwd()
if (stridx(s:cwd, 'aircam') != -1)
    echom "Setting RG filter to default to aircam!"

    call g:SkyFilter.new("aircam")
          \ .include_filetypes(s:ac_types)
          \ .include_dirs(s:ac_search_dirs)
          \ .ignore_filetypes(s:ac_ignore_types)
          \ .ignore_dirs(s:ac_ignore_dirs)

    call g:SkyFilter.new("ios")
          \ .include_filetypes(['djinni', 'mm', 'm', 'swift'])
          \ .include_dirs(['mobile'])
          \ .ignore_filetypes(s:ac_ignore_types)
          \ .ignore_dirs(s:ac_ignore_dirs)

    call g:SkyFilter.new("android")
          \ .include_filetypes(['djinni', 'java', 'kt'])
          \ .include_dirs(['mobile'])
          \ .ignore_filetypes(s:ac_ignore_types)
          \ .ignore_dirs(s:ac_ignore_dirs)

    call g:SkyFilter.new("mcore")
          \ .include_filetypes(['djinni', 'cc', 'h'])
          \ .include_dirs(['mobile/shared'])
          \ .ignore_filetypes(s:ac_ignore_types)
          \ .ignore_dirs(s:ac_ignore_dirs)

    call g:SkyFilter.new("lcm")
          \ .include_filetypes(['lcm', 'proto'])
          \ .include_dirs(s:ac_search_dirs)
          \ .ignore_filetypes(s:ac_ignore_types)
          \ .ignore_dirs(s:ac_ignore_dirs)

    let g:SkyFilter.default = 'aircam'
endif
```
