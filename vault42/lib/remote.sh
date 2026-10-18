# shellcheck shell=bash
# remote.sh — read a target's environment from the vault through 42ctl. Sourced; sets no shell
# options; needs config.sh, creds.sh, ctl.sh and common.sh. Every function takes the TARGET name.
#
#   v42_envargs TARGET          set V42_ENVARGS to --org O --project P --env E
#   v42_remote_sizes TARGET     "SIZE<TAB>PATH" per stored file; status 1 + message when 42ctl fails or
#                               returns a row with a blank field (C14)
#   v42_remote_listing TARGET   "SIZE PRIVATE PATH" per file, PRIVATE being true|false
#   v42_remote_private TARGET   the paths stored private, sorted
#   v42_keys_rows TARGET        "MEMBER STATE" per key holder
#   v42_my_account              the first account id `42ctl auth me` prints
#   v42_my_state ROWS ACCOUNT   ACCOUNT's key state, or "absent"
#   v42_holders ROWS            the members whose state is active
#
# A row with an empty field is refused, never read as a value: awk-style splitting would shift the
# columns left and turn a blank size into the path.
#
# Caveat: the `--format` templates and the Private column spelling (true|false) are taken from
# `42ctl env files --help` and the born2root repair script, not captured from a live run; a different
# spelling fails the row check (a refusal), it is never accepted as data. Caveat: "holds no tree"
# is matched as text and means an empty listing; another wording makes a first push look like a failure.

V42_OUT=""
V42_ERR=""
declare -ga V42_ENVARGS=()

v42_envargs() {
  V42_ENVARGS=(--org "$(v42_cfg "$1" org)" --project "$(v42_cfg "$1" project)" --env "$(v42_cfg "$1" env)")
}

# 42ctl roots its scan at the working directory, so calls about a target run in its root.
_v42_in_root() {
  local target="$1" root
  shift
  root="$(v42_cfg "$target" root)"
  [ -d "$root" ] || root=.
  (cd "$root" && v42_ctl "$@")
}

# Sets V42_OUT (stdout) and V42_ERR (stderr) apart, so a 42ctl warning never reads as a row.
_v42_call() {
  local errf rc
  errf="$(mktemp)"
  V42_OUT="$(_v42_in_root "$@" 2>"$errf")"
  rc=$?
  V42_ERR="$(cat "$errf")"
  rm -f "$errf"
  return "$rc"
}

_v42_remote_fail() {
  note "listing the vault failed: ${V42_ERR:-$V42_OUT} — run: 42ctl $1 ${V42_ENVARGS[*]}"
  return 1
}

_v42_rows_valid() {
  local what="$1" regex="$2" row
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    [[ "$row" =~ $regex ]] || {
      note "refusing: '42ctl $what' returned a row with a blank or malformed field: '$row'"
      return 1
    }
  done <<<"$V42_OUT"
}

v42_remote_sizes() {
  v42_envargs "$1"
  if ! _v42_call "$1" keystore env files "${V42_ENVARGS[@]}" --format '{{.Size}} {{.Path}}'; then
    [[ "$V42_ERR$V42_OUT" == *"holds no tree"* ]] && return 0
    _v42_remote_fail "env files"
    return 1
  fi
  _v42_rows_valid "env files" '^[0-9]+ [^[:space:]].*$' || return 1
  [ -z "$V42_OUT" ] || awk '{ size = $1; sub(/^[^ ]+ /, ""); print size "\t" $0 }' <<<"$V42_OUT"
}

v42_remote_listing() {
  v42_envargs "$1"
  if ! _v42_call "$1" keystore env files "${V42_ENVARGS[@]}" --format '{{.Size}} {{.Private}} {{.Path}}'; then
    [[ "$V42_ERR$V42_OUT" == *"holds no tree"* ]] && return 0
    _v42_remote_fail "env files"
    return 1
  fi
  _v42_rows_valid "env files" '^[0-9]+ (true|false) [^[:space:]].*$' || return 1
  [ -z "$V42_OUT" ] || printf '%s\n' "$V42_OUT"
}

# 42ctl bails with "no row matches" when nothing is private; that is an empty set, not a failure.
v42_remote_private() {
  v42_envargs "$1"
  if ! _v42_call "$1" keystore env files "${V42_ENVARGS[@]}" --filter Private=true --format '{{.Path}}'; then
    [[ "$V42_ERR$V42_OUT" == *"no row matches"* || "$V42_ERR$V42_OUT" == *"holds no tree"* ]] && return 0
    _v42_remote_fail "env files --filter Private=true"
    return 1
  fi
  _v42_rows_valid "env files --filter" '^[^[:space:]].*$' || return 1
  [ -z "$V42_OUT" ] || LC_ALL=C sort -u <<<"$V42_OUT"
}

v42_keys_rows() {
  v42_envargs "$1"
  if ! _v42_call "$1" keystore env keys ls "${V42_ENVARGS[@]}" --format '{{.Member}} {{.State}}'; then
    _v42_remote_fail "env keys ls"
    return 1
  fi
  _v42_rows_valid "env keys ls" '^[^[:space:]]+ [^[:space:]]+$' || return 1
  [ -z "$V42_OUT" ] || printf '%s\n' "$V42_OUT"
}

v42_my_account() {
  local out
  out="$(v42_ctl none auth me 2>/dev/null)" || return 1
  [[ "$out" =~ ([0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}) ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

v42_my_state() {
  awk -v me="$2" '$1 == me { print $2; found = 1; exit } END { if (!found) print "absent" }' <<<"$1"
}

v42_holders() { awk '$2 == "active" { print $1 }' <<<"$1"; }
