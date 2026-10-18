# shellcheck shell=bash
# diffs.sh — compare a checkout with the vault. Sourced; sets no shell options; needs config.sh,
# scan.sh, kinds.sh, remote.sh, state.sh and common.sh.
#
#   v42_local_sizes ROOT          "SIZE<TAB>PATH" for each file the scan takes
#   v42_diff_table TARGET KIND…   fast diff by size: "+ path" local only, "- path" vault only,
#                                 "~ path L->R bytes" sizes differ; status 1 when the vault cannot be read
#   v42_diff_exact TARGET KIND…   the same markers, but BYTES and MODE: the vault tree is restored
#                                 into a mode-700 scratch dir under the git common dir and every file
#                                 compared with cmp and stat
#   v42_diff_counts TABLE         "N added, N dropped, N changed"
#
# KIND… limits both sides to those kinds' paths when the target has more kinds than selected.
# `~` lines say what differs: "bytes" or "mode A->B".
#
# Caveat: the size diff cannot see a same-size edit, and a vault that reports a sealed size for
# private files shows them as `~`; v42_diff_exact exists for the cases where that matters (file-mode
# push). Caveat: files another member pushed private are invisible to both, so neither can tell
# whether a push keeps them (assumption A2, README). Caveat: v42_diff_exact assumes 42ctl restores
# the mode it stored; if it applied a umask, every file would read `~ mode` and the push be refused.

v42_local_sizes() {
  local path
  vault42_scan "$1" | while IFS= read -r path; do
    printf '%s\t%s\n' "$(stat -c %s "$1/$path")" "$path"
  done
}

# _v42_keep_kinds TARGET KIND… : stdin lines "…<TAB>PATH" -> only PATHs the selection covers.
_v42_keep_kinds() {
  local target="$1" line path
  local -a covered
  shift
  if [ "$(v42_kind_scope "$target" "$@")" != partial ]; then
    cat
    return 0
  fi
  read -ra covered <<<"$(_v42_kind_common "$target" "$@")"
  while IFS= read -r line; do
    path="${line#*$'\t'}"
    ! v42_path_in_kinds "$path" "${covered[@]}" || printf '%s\n' "$line"
  done
}

_v42_size_table() {
  awk -F'\t' -v lf="$1" '
    FILENAME == lf { l[$2] = $1; next }
    { r[$2] = $1 }
    END {
      for (p in l) {
        if (!(p in r)) print p "\t+ " p
        else if (l[p] != r[p]) print p "\t~ " p " " l[p] "->" r[p] " bytes"
      }
      for (p in r) if (!(p in l)) print p "\t- " p
    }' "$1" "$2" | LC_ALL=C sort -t "$(printf '\t')" -k1,1 | cut -f2-
}

v42_diff_table() {
  local target="$1" local_f remote_f rc=0
  shift
  local_f="$(mktemp)"
  remote_f="$(mktemp)"
  v42_local_sizes "$(v42_cfg "$target" root)" | _v42_keep_kinds "$target" "$@" >"$local_f"
  v42_remote_sizes "$target" | _v42_keep_kinds "$target" "$@" >"$remote_f"
  [ "${PIPESTATUS[0]}" -eq 0 ] || rc=1
  [ "$rc" -ne 0 ] || _v42_size_table "$local_f" "$remote_f"
  rm -f "$local_f" "$remote_f"
  return "$rc"
}

# v42_diff_row_path ROW: the path of a `+`, `-` or `~` row; status 1 for anything else.
v42_diff_row_path() {
  local re
  # One suffix per pattern, tried in turn: a single alternation lets the greedy path group swallow
  # the "L->R" of a size row and leave only "bytes" as the suffix.
  for re in '^~ (.*) [0-9]+->[0-9]+ bytes$' '^~ (.*) mode [0-9]+->[0-9]+$' '^~ (.*) bytes$'; do
    if [[ "$1" =~ $re ]]; then
      printf '%s' "${BASH_REMATCH[1]}"
      return 0
    fi
  done
  if [[ "$1" == "+ "* || "$1" == "- "* ]]; then
    printf '%s' "${1:2}"
  else
    return 1
  fi
}

v42_diff_counts() {
  printf '%s added, %s dropped, %s changed\n' "$(count_lines "$(grep '^+ ' <<<"$1")")" \
    "$(count_lines "$(grep '^- ' <<<"$1")")" "$(count_lines "$(grep '^~ ' <<<"$1")")"
}

# _v42_restore_vault TARGET: restore the vault tree into $V42_TMP/restore (cwd of an --apply pull).
# A vault holding no tree restores nothing, which is an empty restore and not a failure.
_v42_restore_vault() {
  local target="$1" dest errf
  v42_mktmp "$(v42_cfg "$target" root)" || return 1
  dest="$V42_TMP/restore"
  mkdir -p "$dest"
  v42_envargs "$target"
  errf="$V42_TMP/err"
  if ! (cd "$dest" && v42_ctl keystore env pull "${V42_ENVARGS[@]}" --apply) >"$V42_TMP/out" 2>"$errf"; then
    grep -q "holds no tree" "$errf" "$V42_TMP/out" && return 0
    note "restoring the vault to compare bytes failed: $(cat "$errf") — run: 42ctl env pull ${V42_ENVARGS[*]}"
    return 1
  fi
}

_v42_exact_row() {
  local root="$1" dest="$2" path="$3" lm rm
  if [ ! -e "$dest/$path" ]; then
    printf '+ %s\n' "$path"
  elif [ ! -e "$root/$path" ]; then
    printf -- '- %s\n' "$path"
  elif ! cmp -s "$root/$path" "$dest/$path"; then
    printf '~ %s bytes\n' "$path"
  else
    lm="$(stat -c %a "$root/$path")"
    rm="$(stat -c %a "$dest/$path")"
    [ "$lm" = "$rm" ] || printf '~ %s mode %s->%s\n' "$path" "$rm" "$lm"
  fi
}

v42_diff_exact() {
  local target="$1" root dest path
  shift
  root="$(v42_cfg "$target" root)"
  _v42_restore_vault "$target" || return 1
  dest="$V42_TMP/restore"
  {
    vault42_scan "$root"
    (cd "$dest" && find . -type f | sed 's|^\./||')
  } | LC_ALL=C sort -u | awk '{ print "x\t" $0 }' | _v42_keep_kinds "$target" "$@" | cut -f2- |
    while IFS= read -r path; do _v42_exact_row "$root" "$dest" "$path"; done
}
