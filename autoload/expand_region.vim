vim9script

# ==============================================================================
# File: expand_region.vim
# Author: Alex Lebedev (original Terry Ma)
# Last Modified: June 13, 2025
# ==============================================================================

# ==============================================================================
# Settings
# ==============================================================================

# Init global vars
export def Init()
  if exists('g:expand_region_init') && g:expand_region_init
    return
  endif
  g:expand_region_init = 1

  # Dictionary of text objects that are supported by default. Note that some of
  # the text objects are not available in vanilla vim. '1' indicates that the
  # text object is recursive (think of nested parens or brackets)
  g:expand_region_text_objects = get(g:, 'expand_region_text_objects', {
          'iw': 0,
          'iW': 0,
          'i"': 0,
          "i'": 0,
          'i]': 1,
          'ib': 1,
          'iB': 1,
          'il': 0,
          'ip': 0,
          'ie': 0,
          })

  # Option to default to the select mode when selecting a new region
  g:expand_region_use_select_mode = get(g:, 'expand_region_use_select_mode', 0)
enddef
Init()

# ==============================================================================
# Global Functions
# ==============================================================================

# Returns whether we should perform the region highlighting use visual mode or
# select mode
export def UseSelectMode(): bool
  return g:expand_region_use_select_mode || saved_selectmode->split(',')->index('cmd') != -1
enddef

# Main function
export def Next(mode: string, direction: string)
  ExpandRegion(mode, direction)
enddef

# ==============================================================================
# Variables
# ==============================================================================

# The saved cursor position when user initiates expand. This is the position we
# use to calcuate the region for all of our text objects. This is also used to
# restore the original cursor position when the region is completely shrinked.
var saved_pos: list<any> = []

# Index into the list of filtered text objects(candidates), the text object
# this points to is the currently selected region.
var cur_index = -1

# The list of filtered text objects used to expand/shrink the visual selection.
# This is computed when expand-region is called the first time.
# Each item is a dictionary containing the following:
# text_object: The actual text object string
# start_pos: The result of getpos() on the starting position of the text object
# end_pos: The result of getpos() on the ending position of the text object
# length: The number of characters for the text object
var candidates: list<dict<any>> = []

# This is used to save the user's selectmode setting. If the user's selectmode
# contains 'cmd', then our expansion should result in the region selected under
# select mode.
var saved_selectmode = &selectmode

# ==============================================================================
# Functions
# ==============================================================================

# Sort the text object by length in ascending order
def SortTextObject(l: dict<any>, r: dict<any>): number
  return l.length - r.length
enddef

# Compare two position arrays. Each input is the result of getpos(). Return a
# negative value if lhs occurs before rhs, positive value if after, and 0 if
# they are the same.
def ComparePos(l: list<any>, r: list<any>): number
  # If number lines are the same, compare columns
  return l[1] == r[1] ? l[2] - r[2] : l[1] - r[1]
enddef

# Boundary check on the cursor position to make sure it's inside the text object
# region. Return 1 if the cursor is within range, 0 otherwise.
def IsCursorInside(pos: list<any>, region: dict<any>): bool
  if ComparePos(pos, region.start_pos) < 0
    return false
  endif
  if ComparePos(pos, region.end_pos) > 0
    return false
  endif
  return true
enddef

# Remove duplicates from the candidate list. Two candidates are duplicates if
# they cover the exact same region (same length and same starting position)
def RemoveDuplicate(input: list<dict<any>>)
  var i = input->len() - 1
  while i >= 1
    if input[i].length == input[i - 1].length &&
          input[i].start_pos == input[i - 1].start_pos
      input->remove(i)
    endif
    i -= 1
  endwhile
enddef

# Return a single candidate dictionary. Each dictionary contains the following:
# text_object: The actual text object string
# start_pos: The result of getpos() on the starting position of the text object
# end_pos: The result of getpos() on the ending position of the text object
# length: The number of characters for the text object
def GetCandidateDict(text_object: string): dict<any>
  # Store the current view so we can restore it at the end
  var curpos = getcursorcharpos()

  # Use ! as much as possible
  # The double quote is important
  execute 'silent! normal! v' .. text_object .. "\<Esc>"

  var selection = GetVisualSelection()

  # Restore peace
  # winrestview(winview)
  setcursorcharpos(curpos[1], curpos[2])

  return {
        text_object: text_object,
        start_pos: selection.start_pos,
        end_pos: selection.end_pos,
        length: selection.length,
        }
enddef

# Return dictionary of text objects that are to be used for the current
# filetype. Filetype-specific dictionaries will be loaded if they exist
# and the global dictionary will be used as a fallback.
def GetConfiguration(): dict<any>
  var configuration: dict<any> = {}
  for ft in &ft->split('\.')
    var ft_dict = $"g:expand_region_text_objects_{ft}"
    if exists(ft_dict)
      extend(configuration, eval(ft_dict))
    endif
  endfor

  if empty(configuration)
    extend(configuration, g:expand_region_text_objects)
  endif

  return configuration
enddef

# Return list of candidate dictionary. Each dictionary contains the following:
# text_object: The actual text object string
# start_pos: The result of getpos() on the starting position of the text object
# length: The number of characters for the text object
def GetCandidateList(): list<dict<any>>
  var winview = winsaveview()
  # Turn off wrap to allow recursive search to work without triggering errors
  var save_wrapscan = &wrapscan
  set nowrapscan

  var config = GetConfiguration()

  # Generate the candidate list for every defined text object
  var cands = keys(config)->map((_, val) => GetCandidateDict(val))

  # For the ones that are recursive, generate them until they no longer match
  # any region
  var recursive_candidates: list<dict<any>> = []
  for cand in cands
    var text_obj = cand.text_object
    # Continue if not recursive
    if !config[text_obj] || cand.length == 0
      continue
    endif
    var count = 2
    var previous = cand.length
    while true
      var test = count .. text_obj
      var candidate = GetCandidateDict(test)
      if candidate.length == 0
        break
      endif
      # If we're not producing larger regions, end early
      if candidate.length == previous
        break
      endif
      recursive_candidates += [candidate]
      count += 1
      previous = candidate.length
    endwhile
  endfor

  # Restore wrapscan
  &wrapscan = save_wrapscan

  winrestview(winview)
  return extend(cands, recursive_candidates)
enddef

# Return a dictionary containing the start position, end position and length of
# the current visual selection.
def GetVisualSelection(): dict<any>
  var start_pos = getpos("'<")
  var end_pos = getpos("'>")
  var [lnum1, col1] = start_pos[1 : 2]
  var [lnum2, col2] = end_pos[1 : 2]
  var lines = getline(lnum1, lnum2)
  lines[-1] = lines[-1][: col2 - 1]
  lines[0] = lines[0][col1 - 1 :]
  return {
        start_pos: start_pos,
        end_pos: end_pos,
        length: lines->join("\n")->len()
        }
enddef

# Figure out whether we should compute the candidate text objects, or we're in
# the middle of an expand/shrink.
def ShouldComputeCandidates(mode: string): bool
  if mode == 'v'
    # Check that current visual selection is idential to our last expanded
    # region
    if cur_index >= 0
      var selection = GetVisualSelection()
      if candidates[cur_index].start_pos == selection.start_pos
            && candidates[cur_index].length == selection.length
        return false
      endif
    endif
  endif
  return true
enddef

# Computes the list of text object candidates to be used given the current
# cursor position.
def ComputeCandidates(cursor_pos: list<any>)
  # Reset index into the candidates list
  cur_index = -1

  # Save the current cursor position so we can restore it later
  saved_pos = cursor_pos

  # Compute a list of candidate regions
  candidates = GetCandidateList()

  # Sort them and remove the ones with 0 or 1 length
  candidates->sort(SortTextObject)->filter((_, val) => val.length > 1)

  # Filter out the ones where the cursor falls outside of its region. i" and i'
  # can start after the cursor position, and ib can start before, so both checks
  # are needed
  candidates->filter((_, val) => IsCursorInside(saved_pos, val))

  # Remove duplicates
  RemoveDuplicate(candidates)
enddef

# Perform the visual selection at the end. If the user wants to be left in
# select mode, do so
def SelectRegion()
  execute 'normal! v' .. candidates[cur_index].text_object .. (UseSelectMode() ? "normal! \<C-g>" : '') 
enddef

# Expand or shrink the visual selection to the next candidate in the text object
# list.
def ExpandRegion(mode: string, direction: string)
  # Save the selectmode setting, and remove the setting so our 'v' command do
  # not get interfered
  saved_selectmode = &selectmode
  &selectmode = ""

  if ShouldComputeCandidates(mode)
    ComputeCandidates(getpos('.'))
  else
    setpos('.', saved_pos)
  endif

  if direction == '+'
    # Expanding
    if cur_index == candidates->len() - 1
      normal! gv
    else
      cur_index += 1
      SelectRegion()
    endif
  else
    #Shrinking
    if cur_index <= 0
      # In visual mode, doing nothing here will return us to normal mode. For
      # select mode, the following is needed.
      if UseSelectMode()
        normal! gV
      endif
    else
      cur_index -= 1
      SelectRegion()
    endif
  endif

  # Restore the selectmode setting
  &selectmode = saved_selectmode
enddef
