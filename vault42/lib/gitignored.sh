# shellcheck shell=bash
# gitignored.sh — would git pick a file up? A secret written into a checkout must not be one
# `git add -A` away from a commit. Sourced; sets no shell options.
#
#   git_owner_of PATH     the top level of the repository owning PATH (nearest existing directory)
#   is_git_ignored PATH   status 0 when that repository ignores PATH, and when there is no git or no
#                         repository to ask
#
# Caveat: a path under a submodule that is not checked out is judged by the parent repository's
# rules; no repository at all reads as "ignored", because nothing can commit it either.

git_owner_of() {
  local dir
  dir="$(dirname "$1")"
  while [ ! -d "$dir" ]; do dir="$(dirname "$dir")"; done
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null
}

is_git_ignored() {
  local top
  command -v git >/dev/null || return 0
  top="$(git_owner_of "$1")" || return 0
  git -C "$top" check-ignore -q "$1"
}
