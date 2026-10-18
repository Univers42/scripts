# shellcheck shell=bash
# seedsums.sh — the SHA256SUMS file next to a set of archives. Sourced; sets no shell options.
#
#   seed_sha256 FILE         the hex digest of FILE.
#   seed_names SUMS          every name a SHA256SUMS file lists.
#   seed_sums_put DIR NAME…  rewrite the SHA256SUMS lines of exactly those NAMEs (files in DIR), every
#                            other line untouched, sorted by name; status 1 on a non-file or a name
#                            42ctl never uploads (SHA256SUMS*, .bak, .stale, dotfiles). Lines already
#                            naming SHA256SUMS* are dropped.

seed_sha256() {
  local out
  if command -v sha256sum >/dev/null; then out="$(sha256sum <"$1")"; else out="$(shasum -a 256 <"$1")"; fi
  printf '%s' "${out%% *}"
}

seed_names() { awk '{ n = $2; sub(/^\*/, "", n) } n != "" { print n }' "$1"; }

# 42ctl never uploads .bak/.stale/symlink names (4ee32f6 src/core/project.rs skip_file) and
# SHA256SUMS cannot vouch for itself, so a line naming one makes every later push guard report it
# "absent".
_seed_sums_unlistable() {
  case "$1" in
    SHA256SUMS* | *.bak* | *.stale | .*) return 0 ;;
  esac
  return 1
}

# The sort is on the name column so a line a pusher wrote with a "*" binary marker keeps its
# bytes. Every NAME is checked before anything is written.
seed_sums_put() {
  local dir="$1" name tmp sums="$1/SHA256SUMS"
  shift
  for name in "$@"; do
    if _seed_sums_unlistable "$name"; then
      printf 'seed_sums_put: %s is never uploaded by 42ctl (SHA256SUMS*, .bak, .stale or dotfile name); not listed\n' "$name" >&2
      return 1
    fi
    [ -f "$dir/$name" ] || {
      printf 'seed_sums_put: %s is not a file in %s\n' "$name" "$dir" >&2
      return 1
    }
  done
  tmp="$(mktemp "$dir/.SHA256SUMS.XXXXXX")" || return 1
  {
    [ ! -f "$sums" ] || awk -v names="$(printf '%s\n' "$@")" '
      BEGIN { n = split(names, a, "\n"); for (i = 1; i <= n; i++) drop[a[i]] = 1 }
      { f = $2; sub(/^\*/, "", f); if (!(f in drop) && f !~ /^SHA256SUMS/) print f "\t" $0 }' "$sums"
    for name in "$@"; do printf '%s\t%s  %s\n' "$name" "$(seed_sha256 "$dir/$name")" "$name"; done
  } | LC_ALL=C sort -t "$(printf '\t')" -k1,1 | cut -f2- >"$tmp" || {
    rm -f "$tmp"
    return 1
  }
  chmod 600 "$tmp"
  mv -f "$tmp" "$sums"
}
