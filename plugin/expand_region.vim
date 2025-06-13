vim9script

# ==============================================================================
# File: expand_region.vim
# Author: Alex Lebedev (original Terry Ma)
# Description: Incrementally select larger regions of text in visual mode by
# repeating the same key combination
# Last Modified: June 13, 2025
# ==============================================================================

import autoload '../autoload/expand_region.vim'

# Init global vars
expand_region.Init()

# ==============================================================================
# Mappings
# ==============================================================================
if !hasmapto('<Plug>(expand_region_expand)')
  nmap + <Plug>(expand_region_expand)
  vmap + <Plug>(expand_region_expand)
endif
if !hasmapto('<Plug>(expand_region_shrink)')
  vmap _ <Plug>(expand_region_shrink)
  nmap _ <Plug>(expand_region_shrink)
endif

def Next(mode: string, direction: string)
  expand_region.Next(mode, direction)
enddef

nnoremap <silent> <Plug>(expand_region_expand)
      \ :<C-U>call <sid>Next('n', '+')<CR>
# Map keys differently depending on which mode is desired
if expand_region.UseSelectMode()
  snoremap <silent> <Plug>(expand_region_expand)
        \ :<C-U>call <sid>Next('v', '+')<CR>
  snoremap <silent> <Plug>(expand_region_shrink)
        \ :<C-U>call <sid>Next('v', '-')<CR>
else
  xnoremap <silent> <Plug>(expand_region_expand)
        \ :<C-U>call <sid>Next('v', '+')<CR>
  xnoremap <silent> <Plug>(expand_region_shrink)
        \ :<C-U>call <sid>Next('v', '-')<CR>
endif

# Allow user to customize the global dictionary, or the per file type dictionary
def g:CustomTextObjects(...args: list<any>)
  if len(args) == 1
    extend(g:expand_region_text_objects, args[0])
  elseif len(args) == 2
    var ft_dict = $"g:expand_region_text_objects_{args[0]}"
    if !exists(ft_dict)
      execute $"{ft_dict} = {{}}"
      extend(eval(ft_dict), g:expand_region_text_objects)
    endif
    extend(eval(ft_dict), args[1])
  endif
enddef
