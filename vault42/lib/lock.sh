# shellcheck shell=bash
# lock.sh — one vault42 run per checkout at a time: a pull replaces files with mv -f, and a second
# session in the same tree would read half of it. Sourced; sets no shell options. Needs `flock`.
#
#   vault42_lock ROOT     take an exclusive, non-blocking flock on <state dir of ROOT>/lock and hold
#                         it on $VAULT42_LOCK_FD until the process exits. Status 1 when taken or
#                         flock is absent.
#   vault42_unlock_lock   release it.
#
# Caveat: flock is advisory, so a tool that does not take it (42ctl itself, a hand mv) is not excluded.
# Caveat: the pid in the lock file is written after locking and is only a hint for the message;
# a holder killed between the two shows no pid, and a stale pid is never checked for liveness.

vault42_lock() {
  local root="$1" dir file holder
  command -v flock >/dev/null || {
    printf 'vault42_lock: flock (util-linux) is not installed; cannot guard %s\n' "$root" >&2
    return 1
  }
  dir="$(v42_state_dir "$root")" || return 1
  file="$dir/lock"
  exec {VAULT42_LOCK_FD}>>"$file" || return 1
  if ! flock -n "$VAULT42_LOCK_FD"; then
    holder="$(cat "$file" 2>/dev/null)"
    printf 'locked: another vault42 run holds %s%s\n' "$file" "${holder:+ (pid $holder)}" >&2
    exec {VAULT42_LOCK_FD}>&-
    return 1
  fi
  printf '%s\n' "$$" >"$file"
}

vault42_unlock_lock() {
  [ -z "${VAULT42_LOCK_FD:-}" ] || exec {VAULT42_LOCK_FD}>&-
}
