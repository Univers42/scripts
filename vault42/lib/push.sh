# shellcheck shell=bash
# push.sh — the guards around a push: the lock, the confirm, the route, the drop guard, the object-
# store gate and the summary. Sourced; sets no shell options; needs config.sh, creds.sh, ctl.sh,
# remote.sh, lock.sh, state.sh and common.sh. The flow that orders them is cmd/transfer.sh.
#
#   v42_locked ROOT FN…        run FN… holding the target's lock; status 4 when another run holds it
#   v42_confirm PROMPT         status 0 on `y` typed at $VAULT42_TTY (default /dev/tty); never reads stdin
#   v42_push_route TARGET      V42_ROUTE = team | personal | fallback; status 1 when the key is not held
#   v42_push_drops TABLE       status 1 naming every `- path` not listed in V42_PUSH_DROPS
#   v42_push_s3_gate TARGET    make sure a file over the private ceiling can travel, or status 1
#   v42_push_summary TARGET TABLE   the review printed before the confirm (A2 and the key holders)
#
# Caveat: the route reads the key state once, before the diff; a key revoked between that read and the
# push surfaces as the push failing, not as a different route. Caveat: the TTY seam means a harness
# that provides a terminal answers `y` for the user; --yes is the only unattended path.

declare -ga V42_PUSH_DROPS=()
V42_ROUTE=team
V42_HOLDERS=""
V42_PUSH_PERSONAL=0

# v42_push_allow_personal [0]: record --personal (or clear it with 0).
v42_push_allow_personal() { V42_PUSH_PERSONAL="${1:-1}"; }

v42_locked() {
  local root="$1" rc
  shift
  vault42_lock "$root" || return 4
  "$@"
  rc=$?
  vault42_unlock_lock
  return "$rc"
}

v42_confirm() {
  local tty="${VAULT42_TTY:-/dev/tty}" answer=""
  { : <"$tty"; } 2>/dev/null || return 1
  printf '%s [y/N] ' "$1" >&2
  read -r answer <"$tty" || return 1
  [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]]
}

# The personal vault reaches only the pusher, so it is never the quiet outcome of a failed key check
# (C13): it needs `personal_fallback = yes` in the config AND --personal on the command line.
v42_push_route() {
  local target="$1" rows me state
  V42_ROUTE=team
  V42_HOLDERS=""
  [ "$(v42_cfg "$target" mode)" != personal ] || {
    V42_ROUTE=personal
    return 0
  }
  v42_envargs "$target"
  rows="$(v42_keys_rows "$target")" || return 1
  me="$(v42_my_account)" || {
    note "cannot tell who you are (42ctl auth me failed), so not whether you hold the $(v42_cfg "$target" env) key: no personal fallback on a failed read"
    return 1
  }
  V42_HOLDERS="$(v42_holders "$rows" | paste -sd' ')"
  state="$(v42_my_state "$rows" "$me")"
  [ "$state" != active ] || return 0
  if [ "$(v42_cfg "$target" personal_fallback)" = yes ] && [ "${V42_PUSH_PERSONAL:-0}" -eq 1 ]; then
    V42_ROUTE=fallback
    return 0
  fi
  note "you do not hold the $(v42_cfg "$target" env) key of $target (state: $state; holders: ${V42_HOLDERS:-none}); a holder runs: 42ctl env keys sync ${V42_ENVARGS[*]}. A push to your personal vault needs personal_fallback = yes in the config and --personal"
  return 1
}

v42_push_drops() {
  local line path bad="" hint=""
  while IFS= read -r line; do
    [ "${line:0:2}" = "- " ] || continue
    path="${line:2}"
    printf '%s\n' ${V42_PUSH_DROPS[@]+"${V42_PUSH_DROPS[@]}"} | grep -qxF -- "$path" && continue
    bad="$bad $path"
    hint="$hint
  vault42 pull --apply --only $(printf '%q' "$path")   (keep it) or rerun with --drop $(printf '%q' "$path")   (drop it)"
  done <<<"$1"
  [ -z "$bad" ] || {
    note "this push would DROP from the vault's newest tree (history keeps them):$bad$hint"
    return 1
  }
}

# A file over the ceiling travels through the object store, which needs infra/S3_KEY and
# infra/S3_SECRET. They are fetched from the vault's own secrets into this process's environment.
v42_push_s3_gate() {
  local root big key secret
  root="$(v42_cfg "$1" root)"
  big="$(v42_local_sizes "$root" | awk -F'\t' -v m="$V42_PRIVATE_CEILING" '$1 > m { print $2 }' | paste -sd' ')"
  [ -n "$big" ] || return 0
  [ -z "${FT_S3_KEY:-}" ] || return 0
  v42_envargs "$1"
  key="$(_v42_in_root "$1" keystore env secret get "${V42_ENVARGS[@]}" infra/S3_KEY 2>/dev/null)" || key=""
  secret="$(_v42_in_root "$1" keystore env secret get "${V42_ENVARGS[@]}" infra/S3_SECRET 2>/dev/null)" || secret=""
  if [ -z "$key" ] || [ -z "$secret" ]; then
    note "these files are above $V42_PRIVATE_CEILING bytes and the object-store key is not in the vault: $big; store infra/S3_KEY and infra/S3_SECRET with vault42 secret set"
    return 1
  fi
  export FT_S3_KEY="$key" FT_S3_SECRET="$secret"
}

v42_push_summary() {
  local target="$1" table="$2"
  if [ "$V42_ROUTE" = team ]; then
    note "push $target -> $(v42_cfg "$target" org)/$(v42_cfg "$target" project)/$(v42_cfg "$target" env)"
  else
    note "push $target -> your PERSONAL vault, project $(v42_cfg "$target" project): this reaches only YOU. Key holders: ${V42_HOLDERS:-none}"
  fi
  if [ -n "$table" ]; then
    printf '%s\n' "$table" >&2
    note "$(v42_diff_counts "$table")"
  fi
  note "files another member pushed private are invisible to you; whether the server keeps them across your push is UNVERIFIED"
  [ "$V42_ROUTE" != team ] || note "active key holders who will read this tree: ${V42_HOLDERS:-none}"
}
