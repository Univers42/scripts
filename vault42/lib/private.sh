# shellcheck shell=bash
# private.sh — which stored paths 42ctl seals to the pusher alone, computed before a push so the
# vault can be checked against it afterwards. Sourced; sets no shell options.
#
#   vault42_glob_match PATH PATTERN   42ctl's matcher: `*` is the only wildcard and crosses `/`
#   vault42_filter_private PATTERNS   stdin paths that any pattern (newline list) selects, plus `*.local`
#   vault42_undecided PRIVATE SHARED  stdin paths with a secrets/ or .secrets/ directory component (as
#                                     scan.sh takes them) that no private pattern selects and no
#                                     shared pattern (newline list) names: the ones nobody classified
#
# Caveat: `*.local` is repeated from 42ctl's scope_private.rs (DEFAULT_PRIVATE). A 42ctl that forces
# other names private makes the expected set smaller than the real one, and the post-push comparison
# then refuses on the extra paths: a refusal, never a silent pass.

vault42_glob_match() {
  local escaped="$2"
  escaped="${escaped//\\/\\\\}"
  escaped="${escaped//\?/\\?}"
  escaped="${escaped//\[/\\[}"
  # shellcheck disable=SC2254 # the pattern is the point: only `*` survives the escaping above
  case "$1" in $escaped) return 0 ;; esac
  return 1
}

vault42_filter_private() {
  local path pattern
  local -a patterns=('*.local')
  while IFS= read -r pattern; do
    [ -z "$pattern" ] || patterns+=("$pattern")
  done <<<"$1"
  while IFS= read -r path; do
    for pattern in "${patterns[@]}"; do
      if vault42_glob_match "$path" "$pattern"; then
        printf '%s\n' "$path"
        break
      fi
    done
  done
}

vault42_undecided() {
  local path pattern shared
  while IFS= read -r path; do
    [[ "/$path" == */secrets/* || "/$path" == */.secrets/* ]] || continue
    [ -z "$(printf '%s\n' "$path" | vault42_filter_private "$1")" ] || continue
    shared=0
    while IFS= read -r pattern; do
      [ -n "$pattern" ] && vault42_glob_match "$path" "$pattern" && shared=1
    done <<<"$2"
    [ "$shared" = 1 ] || printf '%s\n' "$path"
  done
}
