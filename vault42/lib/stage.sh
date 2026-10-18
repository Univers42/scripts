# shellcheck shell=bash
# stage.sh — turn the git-ignored files 42ctl's scan leaves behind into one private archive the push
# then carries. Sourced; sets no shell options; needs config.sh, scan.sh, creds.sh, gitignored.sh and
# common.sh.
#
#   v42_stage_stale ROOT        status 1 naming any unfinished `.NAME.stale` under secrets/ (a stage or
#                               capture that was killed)
#   v42_stage_paths TARGET      the archive paths (relative to the root) the target stages, one per line
#   v42_stage TARGET            build every archive the target configures; status 1 on the first failure
#
# stage_unscanned_as archives vault42_unscanned (the git-ignored files outside the scan); stage_dir
# with stage_dir_as archives the files of that directory. The archive is written to `.NAME.stale`,
# checked with gzip -t and size-checked, then moved to NAME at mode 600, so a killed run leaves a name
# the next push refuses instead of a half archive. The archive path must be git-ignored.
#
# Caveat: the ceiling (4128768 bytes) is 42ctl's private-file limit as measured on 0.1.16; a larger
# archive is refused here rather than pushed with S3. Caveat: tar archives file contents only as
# they are at that moment; a file written during the run can be torn.

V42_PRIVATE_CEILING=4128768

v42_stage_stale() {
  local found
  found="$(find "$1" \( -path '*/secrets/.*.stale' -o -path '*/.secrets/.*.stale' \) -type f 2>/dev/null | LC_ALL=C sort)"
  [ -n "$found" ] || return 0
  note "unfinished temp files under the secrets directory (a capture or stage was killed): $(paste -sd' ' - <<<"$found") — remove them: rm -f $(paste -sd' ' - <<<"$found")"
  return 1
}

v42_stage_paths() {
  local as
  for as in stage_unscanned_as stage_dir_as; do
    [ -z "$(v42_cfg "$1" "$as")" ] || printf '%s\n' "$(v42_cfg "$1" "$as")"
  done
}

_v42_biggest() {
  (cd "$2" && tr '\n' '\0' <"$1" | xargs -0 stat -c '%s %n' | sort -rn | head -5) 2>/dev/null || true
}

# _v42_archive ROOT FINAL LIST: tar the paths in LIST into FINAL.
_v42_archive() {
  local root="$1" final="$2" list="$3" tmp size
  tmp="$(dirname "$final")/.$(basename "$final").stale"
  mkdir -p "$(dirname "$final")"
  rm -f "$tmp"
  if ! v42_with_creds none tar --numeric-owner -C "$root" -czf "$tmp" -T "$list"; then
    rm -f "$tmp"
    note "tar failed for $final; nothing staged"
    return 1
  fi
  v42_with_creds none gzip -t "$tmp" || {
    rm -f "$tmp"
    note "the archive for $final is not valid gzip; nothing staged"
    return 1
  }
  size="$(stat -c %s "$tmp")"
  if [ "$size" -gt "$V42_PRIVATE_CEILING" ]; then
    rm -f "$tmp"
    note "$final would be $size bytes, above the $V42_PRIVATE_CEILING-byte ceiling for a private file; the biggest entries:"
    _v42_biggest "$list" "$root" >&2
    return 1
  fi
  chmod 600 "$tmp"
  mv -f "$tmp" "$final"
  note "staged $final ($size bytes)"
}

# _v42_stage_one ROOT AS GENERATOR [DIR]: archive what GENERATOR prints, to ROOT/AS.
_v42_stage_one() {
  local root="$1" as="$2" generator="$3" dir="${4:-}" list rc=0
  if ! is_git_ignored "$root/$as"; then
    note "refusing to stage $as: git would take it (not ignored); add it to .gitignore first"
    return 1
  fi
  list="$(mktemp)"
  "$generator" "$root" "$dir" >"$list"
  if [ ! -s "$list" ]; then
    note "nothing to archive for $as"
  else
    _v42_archive "$root" "$root/$as" "$list" || rc=1
  fi
  rm -f "$list"
  return "$rc"
}

_v42_gen_unscanned() { vault42_unscanned "$1"; }
_v42_gen_dir() {
  [ -d "$2" ] || return 0
  find "$2" -type f | LC_ALL=C sort | while IFS= read -r f; do realpath --relative-to="$1" "$f"; done
}

v42_stage() {
  local target="$1" root as dir
  root="$(v42_cfg "$target" root)"
  as="$(v42_cfg "$target" stage_unscanned_as)"
  if [ -n "$as" ]; then _v42_stage_one "$root" "$as" _v42_gen_unscanned || return 1; fi
  as="$(v42_cfg "$target" stage_dir_as)"
  dir="$(v42_cfg "$target" stage_dir)"
  if [ -n "$as" ] && [ -n "$dir" ]; then
    _v42_stage_one "$root" "$as" _v42_gen_dir "$dir" || return 1
  fi
}
