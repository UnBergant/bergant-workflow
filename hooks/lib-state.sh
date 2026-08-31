#!/bin/bash
# Shared by all three enforcement hooks: locate .lifecycle-state.json.
#
# The hooks used to look at a bare relative path, so launching Claude in a subdirectory of the
# project made an active lifecycle look absent — and an absent lifecycle means every hook
# allows everything. The state file belongs to the repository, not to the current directory,
# so walk up from the hook's cwd and stop at the repository root.
#
# Prints the path and returns 0 when found; returns 1 otherwise.

find_state_file() {
  local dir
  dir="${1:-$PWD}"
  [ -d "$dir" ] || return 1
  dir="$(cd "$dir" 2>/dev/null && pwd)" || return 1

  while :; do
    # Check the boundary before the file: a state file sitting directly in $HOME must not
    # govern every project underneath it.
    if [ -n "$HOME" ] && [ "$dir" = "$HOME" ]; then
      return 1
    fi
    if [ -f "$dir/.lifecycle-state.json" ]; then
      printf '%s\n' "$dir/.lifecycle-state.json"
      return 0
    fi
    # A .git entry marks the repository root — a file in the worktree case, hence -e.
    [ -e "$dir/.git" ] && return 1
    [ "$dir" = "/" ] && return 1
    dir="$(dirname "$dir")"
  done
}
