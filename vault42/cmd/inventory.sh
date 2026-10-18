# shellcheck shell=bash
# inventory.sh — `vault42 list`, `diff` and `find`: read-only views of the vault. Defines functions
# only; sourced by vault42.sh.
#
# Caveat: `diff` compares sizes, so a same-size edit is invisible to it; `push FILE` and the
# post-push verify compare bytes. Caveat: `find` matches the pattern as a shell glob over the vault's
# paths, or as a substring when it holds no glob character.

# _inv_fixes TABLE: the restore command for every path the vault has and this checkout lacks or
# differs on. Always --only: a bare `pull --apply` would overwrite everything (C5).
_inv_fixes() {
  local line path shown=0
  while IFS= read -r line; do
    [ "${line:0:2}" != "+ " ] || continue
    path="$(v42_diff_row_path "$line")" || continue
    shown=$((shown + 1))
    if [ "$shown" -gt 20 ]; then
      echo "  … and more"
      break
    fi
    printf '  vault42 pull --apply --only %q\n' "$path"
  done <<<"$1"
}

cmd_list() {
  local t rows size priv path
  v42_cred_require passphrase || return 5
  v42_scoped_targets || return 2
  for t in "${V42_SEL[@]}"; do
    rows="$(v42_remote_listing "$t")" || return 1
    printf '[%s]\n' "$t"
    while read -r size priv path; do
      printf '%10s %-7s %s\n' "$size" "$([ "$priv" = true ] && echo private || echo shared)" "$path"
    done <<<"$rows"
  done
}

cmd_diff() {
  local t table
  v42_cred_require passphrase || return 5
  v42_scoped_targets || return 2
  for t in "${V42_SEL[@]}"; do
    table="$(v42_diff_table "$t" "${V42_KINDS[@]}")" || return 1
    printf '[%s] %s\n' "$t" "$(v42_diff_counts "$table")"
    [ -z "$table" ] || printf '%s\n' "$table"
    if grep -qE '^(-|~) ' <<<"$table"; then
      echo "restore with:"
      _inv_fixes "$table"
    fi
  done
}

cmd_find() {
  local pattern="${1:-}" t rows path
  [ -n "$pattern" ] || {
    usage_error "usage: vault42 find PATTERN"
    return 2
  }
  [[ "$pattern" == *[*?[]* ]] || pattern="*$pattern*"
  v42_cred_require passphrase || return 5
  v42_scoped_targets || return 2
  for t in "${V42_SEL[@]}"; do
    rows="$(v42_remote_sizes "$t")" || return 1
    while IFS=$'\t' read -r _ path; do
      [ -z "$path" ] || ! vault42_glob_match "$path" "$pattern" || printf '%s\t%s\n' "$t" "$path"
    done <<<"$rows"
  done
}
